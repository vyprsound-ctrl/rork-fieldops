-- =============================================================================
-- 0014 - COMMUNICATIONS & MULTI-TENANT SMS
--        One Twilio subaccount, Messaging Service and dedicated number per
--        company · segment-based credits · two-way SMS · opt-outs · templates ·
--        automations · scheduled messages · number billing and retention
-- =============================================================================
--
-- ADDITIVE ONLY. No table, column, row, ledger entry, message, photo, payment,
-- subscription or Stripe record is dropped or deleted. Existing functions that
-- change (`consume_sms_credit`) keep their signature and their callers.
--
-- ARCHITECTURE
--   Harbour South master Twilio account (platform, never closed by this code)
--     -> one subaccount per company         company_messaging_accounts
--        -> one Messaging Service           (inbound + status callbacks carry
--                                            a random per-company callback_key)
--        -> one dedicated US local number   company_phone_numbers
--        -> the company's OWN A2P brand/campaign, registered from the business
--           details the owner submits (never Harbour South's identity)
--
-- TRUST MODEL
--   * Company is always derived server-side: current_company_id() for app
--     callers, the callback_key + subaccount SID match for Twilio callbacks.
--   * Twilio credentials never live in a table. A subaccount token is stored in
--     Supabase Vault; only service-role functions can read it.
--   * Every send is reserved in ONE transaction that checks subscription,
--     messaging status, opt-out, segments and balance under the company lock,
--     before any provider call.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. Rate card (configurable; nothing below hard-codes a price)
-- -----------------------------------------------------------------------------
insert into public.platform_settings (key, value, description) values
  ('sms_credits_per_segment', to_jsonb(1),
   'Credits consumed per outbound SMS segment. 1 credit = 1 segment.'),
  ('sms_cost_basis_micros_per_segment', to_jsonb(13300),
   'INTERNAL. Harbour South underlying cost per outbound US SMS segment in millionths of a dollar (Twilio segment price + blended carrier fee + failed-message allowance). Never shown to customers.'),
  ('sms_margin_bps', to_jsonb(5000),
   'INTERNAL. Target retail margin over the cost basis, in basis points. 5000 = 50%.'),
  ('sms_number_monthly_fee_cents', to_jsonb(299),
   'Retail monthly fee for a company''s dedicated SMS number, in cents.'),
  ('sms_fee_credit_value_cents', to_jsonb(16),
   'Value of one SMS credit, in cents, used to convert the monthly number fee into credits (fee credits = ceil(fee cents / this)).'),
  ('sms_setup_fee_cents', to_jsonb(0),
   'One-time SMS setup fee, in cents. 0 = no setup fee.'),
  ('sms_number_retention_days', to_jsonb(60),
   'Days a number is kept after SMS is paused for non-payment or the company closes, before it may be released.'),
  ('sms_number_grace_days', to_jsonb(7),
   'Days of grace after a missed monthly number fee before sending is paused.'),
  ('sms_max_numbers_per_company', to_jsonb(1),
   'Maximum dedicated numbers per company.'),
  ('sms_max_body_chars', to_jsonb(640),
   'Longest customer SMS accepted, in characters.')
on conflict (key) do nothing;

create or replace function public.sms_setting_int(p_key text, p_default integer)
returns integer language sql stable security definer set search_path = public as $$
  select coalesce((select (value #>> '{}')::integer from public.platform_settings where key = p_key), p_default)
$$;

create or replace function public.sms_credits_per_segment()
returns integer language sql stable security definer set search_path = public as $$
  select greatest(public.sms_setting_int('sms_credits_per_segment', 1), 1)
$$;

create or replace function public.sms_number_monthly_fee_credits()
returns integer language sql stable security definer set search_path = public as $$
  select case when public.sms_setting_int('sms_number_monthly_fee_cents', 299) <= 0 then 0
    else ceil(public.sms_setting_int('sms_number_monthly_fee_cents', 299)::numeric
              / greatest(public.sms_setting_int('sms_fee_credit_value_cents', 16), 1))::integer end
$$;

-- Full rate card including the internal cost basis. Service role only.
create or replace function public.sms_rate_card()
returns table(credits_per_segment integer, cost_basis_micros_per_segment integer, margin_bps integer,
              target_retail_micros_per_segment integer, number_monthly_fee_cents integer,
              number_monthly_fee_credits integer, setup_fee_cents integer, retention_days integer,
              grace_days integer, max_numbers integer)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.push_caller_is_service_role() then
    raise exception 'The internal SMS rate card is service-role only' using errcode = 'TD403';
  end if;
  credits_per_segment := public.sms_credits_per_segment();
  cost_basis_micros_per_segment := public.sms_setting_int('sms_cost_basis_micros_per_segment', 13300);
  margin_bps := public.sms_setting_int('sms_margin_bps', 5000);
  target_retail_micros_per_segment := ceil(cost_basis_micros_per_segment * (1 + margin_bps / 10000.0))::integer;
  number_monthly_fee_cents := public.sms_setting_int('sms_number_monthly_fee_cents', 299);
  number_monthly_fee_credits := public.sms_number_monthly_fee_credits();
  setup_fee_cents := public.sms_setting_int('sms_setup_fee_cents', 0);
  retention_days := public.sms_setting_int('sms_number_retention_days', 60);
  grace_days := public.sms_setting_int('sms_number_grace_days', 7);
  max_numbers := public.sms_setting_int('sms_max_numbers_per_company', 1);
  return next;
end $$;

-- -----------------------------------------------------------------------------
-- 2. Phone and segment helpers
-- -----------------------------------------------------------------------------
create or replace function public.sms_normalise_phone(p text)
returns text language plpgsql immutable as $$
declare
  t text := btrim(coalesce(p, ''));
  d text;
begin
  if t = '' then return null; end if;
  d := regexp_replace(t, '[^0-9]', '', 'g');
  if left(t, 1) = '+' then
    return case when length(d) between 8 and 15 then '+' || d end;
  end if;
  if length(d) = 10 then return '+1' || d; end if;
  if length(d) = 11 and left(d, 1) = '1' then return '+' || d; end if;
  return null;
end $$;

-- Segments exactly as carriers bill them: GSM-7 (160 single / 153 per part,
-- extension characters count twice and are never split) or UCS-2 (70 single /
-- 67 per part, characters outside the BMP count twice and are never split).
create or replace function public.sms_segment_info(p_body text)
returns table(segments integer, encoding text, units integer)
language plpgsql immutable as $$
declare
  basic constant text := '@£$¥èéùìòÇ' || chr(10) || 'ØøÅå' || chr(13)
    || 'Δ_ΦΓΛΩΠΨΣΘΞÆæßÉ !"#¤%&''()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà';
  ext constant text := '^{}\[~]|€' || chr(12);
  n integer := char_length(coalesce(p_body, ''));
  ch text;
  is_gsm boolean := true;
  w integer;
  total integer := 0;
  seg integer := 1;
  cur integer := 0;
  single_cap integer;
  part_cap integer;
begin
  if n = 0 then
    segments := 0; encoding := 'GSM-7'; units := 0; return next; return;
  end if;
  for i in 1..n loop
    ch := substr(p_body, i, 1);
    if position(ch in basic) = 0 and position(ch in ext) = 0 then
      is_gsm := false; exit;
    end if;
  end loop;

  if is_gsm then single_cap := 160; part_cap := 153; encoding := 'GSM-7';
  else single_cap := 70; part_cap := 67; encoding := 'UCS-2'; end if;

  for i in 1..n loop
    ch := substr(p_body, i, 1);
    if is_gsm then w := case when position(ch in ext) > 0 then 2 else 1 end;
    else w := case when ascii(ch) > 65535 then 2 else 1 end; end if;
    total := total + w;
    if cur + w > part_cap then seg := seg + 1; cur := 0; end if;
    cur := cur + w;
  end loop;

  units := total;
  segments := case when total <= single_cap then 1 else seg end;
  return next;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Tables
-- -----------------------------------------------------------------------------
create table if not exists public.company_messaging_accounts (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null unique references public.companies(id) on delete restrict,
  status text not null default 'not_started'
    check (status in ('not_started','provisioning','awaiting_registration','active','suspended','closing','closed','failed')),
  registration_route text check (registration_route in ('standard','low_volume','sole_proprietor')),
  twilio_subaccount_sid text unique,
  auth_token_secret_id uuid,
  messaging_service_sid text unique,
  callback_key text not null unique default encode(extensions.gen_random_bytes(24), 'hex'),
  customer_profile_sid text,
  business_end_user_sid text,
  representative_end_user_sid text,
  address_sid text,
  supporting_document_sid text,
  trust_product_sid text,
  trust_end_user_sid text,
  brand_sid text,
  brand_status text,
  brand_identity_status text,
  campaign_sid text,
  campaign_status text,
  registration_status text not null default 'not_submitted'
    check (registration_status in ('not_submitted','submitted','brand_pending','needs_verification',
                                   'brand_approved','campaign_pending','approved','rejected')),
  registration_error text,
  business_details jsonb not null default '{}'::jsonb,
  requested_number text,
  requested_area_code text,
  provisioning_step text not null default 'none',
  last_error text,
  last_error_at timestamptz,
  retry_count integer not null default 0,
  next_attempt_at timestamptz,
  billing_state text not null default 'current' check (billing_state in ('current','grace','paused')),
  grace_started_at timestamptz,
  suspended_reason text,
  suspended_at timestamptz,
  closing_started_at timestamptz,
  retention_until timestamptz,
  closed_at timestamptz,
  created_by_user_id uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.company_phone_numbers (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  messaging_account_id uuid not null references public.company_messaging_accounts(id) on delete restrict,
  phone_number_sid text unique,
  e164 text not null,
  area_code text,
  locality text,
  region text,
  status text not null default 'active' check (status in ('pending','active','releasing','released')),
  is_primary boolean not null default true,
  monthly_fee_credits integer not null default 0,
  next_fee_due_at timestamptz,
  last_fee_charged_at timestamptz,
  purchased_at timestamptz,
  release_confirmed_at timestamptz,
  release_confirmed_by uuid references public.app_users(id) on delete set null,
  released_at timestamptz,
  release_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists company_phone_numbers_one_live_primary
  on public.company_phone_numbers (company_id)
  where is_primary and status in ('pending','active','releasing');
create unique index if not exists company_phone_numbers_live_e164
  on public.company_phone_numbers (e164) where status <> 'released';

create table if not exists public.messaging_provisioning_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  messaging_account_id uuid references public.company_messaging_accounts(id) on delete restrict,
  operation text not null,
  stage text not null,
  outcome text not null check (outcome in ('started','succeeded','failed','skipped')),
  provider_reference text,
  idempotency_key text unique,
  error_code text,
  error_message text,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists messaging_provisioning_events_company on public.messaging_provisioning_events (company_id, created_at desc);

create table if not exists public.sms_opt_outs (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  phone_e164 text not null,
  customer_id uuid references public.customers(id) on delete set null,
  contact_id uuid references public.customer_contacts(id) on delete set null,
  opted_out boolean not null default true,
  source text not null check (source in ('keyword','provider','manual')),
  keyword text,
  messaging_service_sid text,
  twilio_account_sid text,
  last_message_sid text,
  opted_out_at timestamptz,
  opted_in_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (company_id, phone_e164)
);

create table if not exists public.sms_template_defaults (
  template_key text primary key,
  category text not null check (category in ('appointment','engineer','job','quote','invoice','general')),
  title text not null,
  body text not null,
  context text not null check (context in ('customer','job','quote','invoice')),
  allowed_variables text[] not null,
  is_automatable boolean not null default false,
  automation_default boolean not null default false,
  automation_description text,
  sort_order integer not null
);

create table if not exists public.sms_templates (
  company_id uuid not null references public.companies(id) on delete restrict,
  template_key text not null references public.sms_template_defaults(template_key),
  body text not null,
  updated_by_user_id uuid references public.app_users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (company_id, template_key)
);

create table if not exists public.sms_automation_settings (
  company_id uuid not null references public.companies(id) on delete restrict,
  template_key text not null references public.sms_template_defaults(template_key),
  enabled boolean not null,
  updated_by_user_id uuid references public.app_users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (company_id, template_key)
);

create table if not exists public.sms_conversations (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  phone_e164 text not null,
  customer_id uuid references public.customers(id) on delete set null,
  contact_id uuid references public.customer_contacts(id) on delete set null,
  last_job_id uuid references public.jobs(id) on delete set null,
  last_message_at timestamptz not null default now(),
  last_preview text not null default '',
  last_direction text not null default 'outbound' check (last_direction in ('inbound','outbound')),
  created_at timestamptz not null default now(),
  unique (company_id, phone_e164)
);
create index if not exists sms_conversations_recent on public.sms_conversations (company_id, last_message_at desc);

create table if not exists public.sms_conversation_reads (
  conversation_id uuid not null references public.sms_conversations(id) on delete cascade,
  user_id uuid not null references public.app_users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete restrict,
  last_read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create table if not exists public.sms_inbound_messages (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  conversation_id uuid not null references public.sms_conversations(id) on delete restrict,
  messaging_account_id uuid not null references public.company_messaging_accounts(id) on delete restrict,
  customer_id uuid references public.customers(id) on delete set null,
  job_id uuid references public.jobs(id) on delete set null,
  from_number text not null,
  to_number text not null,
  body text not null default '',
  provider_reference text not null unique,
  keyword_type text check (keyword_type in ('stop','start','help')),
  received_at timestamptz not null default clock_timestamp()
);
create index if not exists sms_inbound_messages_conversation on public.sms_inbound_messages (conversation_id, received_at);
create index if not exists sms_inbound_messages_customer on public.sms_inbound_messages (company_id, customer_id, received_at desc);

create table if not exists public.scheduled_messages (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  customer_id uuid not null references public.customers(id) on delete restrict,
  job_id uuid references public.jobs(id) on delete set null,
  quote_id uuid references public.quotes(id) on delete set null,
  invoice_id uuid references public.invoices(id) on delete set null,
  template_key text not null references public.sms_template_defaults(template_key),
  body text,
  to_number text,
  eta_text text,
  scheduled_for timestamptz not null,
  status text not null default 'scheduled'
    check (status in ('scheduled','sending','sent','cancelled','failed','skipped')),
  source text not null check (source in ('manual','automation')),
  dedupe_key text unique,
  created_by_user_id uuid references public.app_users(id) on delete set null,
  notification_id uuid references public.notifications(id) on delete set null,
  attempts integer not null default 0,
  claimed_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by_user_id uuid references public.app_users(id) on delete set null,
  failure_reason text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists scheduled_messages_due on public.scheduled_messages (scheduled_for) where status = 'scheduled';
create index if not exists scheduled_messages_company on public.scheduled_messages (company_id, scheduled_for);

create table if not exists public.quote_share_tokens (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete restrict,
  quote_id uuid not null references public.quotes(id) on delete restrict,
  token text not null unique,
  created_by_user_id uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  last_viewed_at timestamptz,
  view_count integer not null default 0
);

alter table public.notifications add column if not exists messaging_account_id uuid references public.company_messaging_accounts(id) on delete set null;
alter table public.notifications add column if not exists twilio_account_sid text;
alter table public.notifications add column if not exists provider_price_micros bigint;
alter table public.notifications add column if not exists conversation_id uuid references public.sms_conversations(id) on delete set null;
alter table public.notifications add column if not exists quote_id uuid references public.quotes(id) on delete set null;
alter table public.notifications add column if not exists sent_by_user_id uuid references public.app_users(id) on delete set null;
alter table public.notifications add column if not exists scheduled_message_id uuid references public.scheduled_messages(id) on delete set null;
alter table public.notifications add column if not exists encoding text;
create index if not exists notifications_sms_conversation on public.notifications (conversation_id, created_at) where channel = 'sms';

-- Monthly number fees are idempotent per number per period.
create unique index if not exists sms_credit_ledger_number_fee_once
  on public.sms_credit_ledger (company_id, purchase_reference)
  where purchase_reference like 'number-fee:%';

-- -----------------------------------------------------------------------------
-- 4. Row level security
-- -----------------------------------------------------------------------------
alter table public.company_messaging_accounts enable row level security;
alter table public.company_phone_numbers enable row level security;
alter table public.messaging_provisioning_events enable row level security;
alter table public.sms_opt_outs enable row level security;
alter table public.sms_template_defaults enable row level security;
alter table public.sms_templates enable row level security;
alter table public.sms_automation_settings enable row level security;
alter table public.sms_conversations enable row level security;
alter table public.sms_conversation_reads enable row level security;
alter table public.sms_inbound_messages enable row level security;
alter table public.scheduled_messages enable row level security;
alter table public.quote_share_tokens enable row level security;

-- Writes to every table below happen only through SECURITY DEFINER functions
-- or the service role.
revoke insert, update, delete, truncate on
  public.company_messaging_accounts, public.company_phone_numbers, public.messaging_provisioning_events,
  public.sms_opt_outs, public.sms_template_defaults, public.sms_templates, public.sms_automation_settings,
  public.sms_conversations, public.sms_conversation_reads, public.sms_inbound_messages,
  public.scheduled_messages, public.quote_share_tokens
from anon, authenticated;
revoke select on
  public.company_messaging_accounts, public.company_phone_numbers, public.messaging_provisioning_events,
  public.sms_opt_outs, public.sms_templates, public.sms_automation_settings,
  public.sms_conversations, public.sms_conversation_reads, public.sms_inbound_messages,
  public.scheduled_messages, public.quote_share_tokens, public.sms_template_defaults
from anon;

drop policy if exists cma_owner_select on public.company_messaging_accounts;
create policy cma_owner_select on public.company_messaging_accounts for select to authenticated
  using (company_id = public.current_company_id() and public.has_perm('saasBillingManage'));

drop policy if exists cpn_select on public.company_phone_numbers;
create policy cpn_select on public.company_phone_numbers for select to authenticated
  using (company_id = public.current_company_id()
         and (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead')));

drop policy if exists mpe_owner_select on public.messaging_provisioning_events;
create policy mpe_owner_select on public.messaging_provisioning_events for select to authenticated
  using (company_id = public.current_company_id() and public.has_perm('saasBillingManage'));

drop policy if exists soo_select on public.sms_opt_outs;
create policy soo_select on public.sms_opt_outs for select to authenticated
  using (company_id = public.current_company_id() and public.has_perm('smsCreditsConsume'));

drop policy if exists std_select on public.sms_template_defaults;
create policy std_select on public.sms_template_defaults for select to authenticated using (true);

drop policy if exists st_select on public.sms_templates;
create policy st_select on public.sms_templates for select to authenticated
  using (company_id = public.current_company_id()
         and (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead')));

drop policy if exists sas_select on public.sms_automation_settings;
create policy sas_select on public.sms_automation_settings for select to authenticated
  using (company_id = public.current_company_id()
         and (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead')));

drop policy if exists sc_select on public.sms_conversations;
create policy sc_select on public.sms_conversations for select to authenticated
  using (company_id = public.current_company_id() and public.has_perm('customersReadAll')
         and (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead')));

drop policy if exists scr_own on public.sms_conversation_reads;
create policy scr_own on public.sms_conversation_reads for select to authenticated
  using (user_id = auth.uid() and company_id = public.current_company_id());

drop policy if exists sim_select on public.sms_inbound_messages;
create policy sim_select on public.sms_inbound_messages for select to authenticated
  using (company_id = public.current_company_id() and public.has_perm('customersReadAll')
         and (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead')));

drop policy if exists sm_select on public.scheduled_messages;
create policy sm_select on public.scheduled_messages for select to authenticated
  using (company_id = public.current_company_id()
         and (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead')));

drop policy if exists qst_select on public.quote_share_tokens;
create policy qst_select on public.quote_share_tokens for select to authenticated
  using (company_id = public.current_company_id() and public.has_perm('quotesRead'));

-- -----------------------------------------------------------------------------
-- 5. Template catalogue (22 operational messages; no marketing)
-- -----------------------------------------------------------------------------
insert into public.sms_template_defaults
  (template_key, category, title, body, context, allowed_variables, is_automatable, automation_default, automation_description, sort_order)
values
  ('appointment_confirmation','appointment','Appointment Confirmation',
   '{{company_name}}: Hi {{customer_first_name}}, your appointment is confirmed for {{appointment_date}} at {{appointment_time}} (job {{job_number}}). Reply STOP to opt out.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number','appointment_date','appointment_time'],
   true, true, 'When a job is booked with a time.', 1),
  ('appointment_reminder','appointment','Appointment Reminder',
   '{{company_name}}: Reminder, we''re scheduled to visit on {{appointment_date}} at {{appointment_time}}. Reply to this message if you need to change it.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number','appointment_date','appointment_time'],
   true, true, '24 hours before the appointment.', 2),
  ('appointment_rescheduled','appointment','Appointment Rescheduled',
   '{{company_name}}: Your appointment (job {{job_number}}) has moved to {{appointment_date}} at {{appointment_time}}. Reply if this doesn''t work for you.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number','appointment_date','appointment_time'],
   true, true, 'When a booked job moves to a new time.', 3),
  ('appointment_cancelled','appointment','Appointment Cancelled',
   '{{company_name}}: Your appointment for job {{job_number}} has been cancelled. Reply or call us to rebook.',
   'job', array['customer_first_name','customer_last_name','company_name','job_number','appointment_date','appointment_time'],
   true, true, 'When a job is cancelled.', 4),
  ('engineer_on_the_way','engineer','Engineer On The Way',
   '{{company_name}}: {{engineer_name}} is on the way to you now.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number','appointment_date','appointment_time','eta'],
   true, true, 'When the engineer taps Start travel.', 5),
  ('eta_update','engineer','ETA Update',
   '{{company_name}}: Updated arrival time for job {{job_number}}: {{eta}}.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number','appointment_date','appointment_time','eta'],
   true, false, 'When the arrival time changes while the engineer is travelling.', 6),
  ('engineer_arrived','engineer','Engineer Arrived',
   '{{company_name}}: {{engineer_name}} has arrived for your appointment.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number'],
   true, false, 'When the engineer taps Arrived.', 7),
  ('job_started','job','Job Started',
   '{{company_name}}: Work has started on job {{job_number}}. We''ll let you know when it''s done.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number'],
   true, false, 'When work starts on site.', 8),
  ('job_update','job','Job Update',
   '{{company_name}}: There''s an update on job {{job_number}}. Reply with any questions.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number','appointment_date','appointment_time'],
   true, false, 'When a customer-visible note is added to a job.', 9),
  ('job_completed','job','Job Completed',
   '{{company_name}}: Job {{job_number}} is complete. Thank you for choosing us, {{customer_first_name}}.',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number'],
   true, false, 'When a job is marked complete.', 10),
  ('quote_sent','quote','Quote Sent',
   '{{company_name}}: Hi {{customer_first_name}}, your quote {{quote_number}} is ready to view: {{quote_link}} Reply STOP to opt out.',
   'quote', array['customer_first_name','customer_last_name','company_name','quote_number','quote_link'],
   true, false, 'When a quote is marked as sent.', 11),
  ('quote_reminder','quote','Quote Reminder',
   '{{company_name}}: A reminder that quote {{quote_number}} is waiting for you: {{quote_link}}',
   'quote', array['customer_first_name','customer_last_name','company_name','quote_number','quote_link'],
   true, false, '3 days after a quote is sent, if it is still open.', 12),
  ('quote_accepted','quote','Quote Accepted',
   '{{company_name}}: Thanks, {{customer_first_name}}. Quote {{quote_number}} is accepted and we''ll be in touch to schedule the work.',
   'quote', array['customer_first_name','customer_last_name','company_name','quote_number'],
   true, false, 'When a quote is accepted.', 13),
  ('quote_declined','quote','Quote Declined',
   '{{company_name}}: We''ve noted that quote {{quote_number}} was declined. Reply any time if we can help.',
   'quote', array['customer_first_name','customer_last_name','company_name','quote_number'],
   true, false, 'When a quote is declined.', 14),
  ('invoice_sent','invoice','Invoice Sent',
   '{{company_name}}: Invoice {{invoice_number}} for {{invoice_balance}} is ready. View and pay: {{invoice_link}} Reply STOP to opt out.',
   'invoice', array['customer_first_name','customer_last_name','company_name','invoice_number','invoice_balance','invoice_link','payment_link'],
   true, false, 'When an invoice is marked as sent.', 15),
  ('payment_reminder','invoice','Payment Reminder',
   '{{company_name}}: A friendly reminder that invoice {{invoice_number}} ({{invoice_balance}}) is due. Pay here: {{payment_link}}',
   'invoice', array['customer_first_name','customer_last_name','company_name','invoice_number','invoice_balance','invoice_link','payment_link'],
   true, false, '3 days before an invoice is due, if unpaid.', 16),
  ('overdue_reminder','invoice','Overdue Invoice Reminder',
   '{{company_name}}: Invoice {{invoice_number}} is overdue with {{invoice_balance}} outstanding. Pay here: {{payment_link}} or reply to talk to us.',
   'invoice', array['customer_first_name','customer_last_name','company_name','invoice_number','invoice_balance','invoice_link','payment_link'],
   true, false, 'The day after an invoice is due, if unpaid.', 17),
  ('payment_received','invoice','Payment Received',
   '{{company_name}}: Thank you, we''ve received your payment for invoice {{invoice_number}}.',
   'invoice', array['customer_first_name','customer_last_name','company_name','invoice_number','invoice_balance'],
   true, true, 'When a payment is recorded as received.', 18),
  ('general_customer_message','general','General Customer Message',
   '{{company_name}}: Hi {{customer_first_name}}, ',
   'customer', array['customer_first_name','customer_last_name','company_name'], false, false, null, 19),
  ('general_job_update','general','General Job Update',
   '{{company_name}}: An update on job {{job_number}}: ',
   'job', array['customer_first_name','customer_last_name','company_name','engineer_name','job_number','appointment_date','appointment_time'],
   false, false, null, 20),
  ('customer_follow_up','general','Customer Follow-Up',
   '{{company_name}}: Hi {{customer_first_name}}, just following up on our recent visit. How is everything working? Reply to let us know.',
   'customer', array['customer_first_name','customer_last_name','company_name'], false, false, null, 21),
  ('custom_message','general','Custom Message',
   '',
   'customer', array['customer_first_name','customer_last_name','company_name'], false, false, null, 22)
on conflict (template_key) do nothing;

-- NULL when the body is acceptable for that template; otherwise the reason.
create or replace function public.sms_template_problem(p_key text, p_body text)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v_allowed text[];
  v_var text;
  v_body text := coalesce(p_body, '');
begin
  select allowed_variables into v_allowed from public.sms_template_defaults where template_key = p_key;
  if not found then return 'Unknown message type.'; end if;
  if char_length(v_body) > public.sms_setting_int('sms_max_body_chars', 640) then
    return format('Keep the message under %s characters.', public.sms_setting_int('sms_max_body_chars', 640));
  end if;
  if btrim(v_body) = '' and p_key <> 'custom_message' then
    return 'The message can''t be empty.';
  end if;
  for v_var in select (regexp_matches(v_body, '\{\{\s*([^{}]*?)\s*\}\}', 'g'))[1] loop
    if not (v_var = any(v_allowed)) then
      return format('{{%s}} can''t be used in this message.', v_var);
    end if;
  end loop;
  if regexp_replace(v_body, '\{\{\s*[a-z_]+\s*\}\}', '', 'g') ~ '[{}]' then
    return 'Remove the stray { or } characters, or pick a variable from the list.';
  end if;
  return null;
end $$;

create or replace function public.sms_template_catalog()
returns table(template_key text, category text, title text, body text, default_body text, context text,
              allowed_variables text[], is_customised boolean, is_automatable boolean,
              automation_enabled boolean, automation_description text, sort_order integer)
language sql stable security definer set search_path = public as $$
  select d.template_key, d.category, d.title, coalesce(t.body, d.body), d.body, d.context,
         d.allowed_variables, t.body is not null, d.is_automatable,
         case when d.is_automatable then coalesce(s.enabled, d.automation_default) else false end,
         d.automation_description, d.sort_order
    from public.sms_template_defaults d
    left join public.sms_templates t on t.template_key = d.template_key and t.company_id = public.current_company_id()
    left join public.sms_automation_settings s on s.template_key = d.template_key and s.company_id = public.current_company_id()
   where public.current_company_id() is not null
     and (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead'))
   order by d.sort_order
$$;

create or replace function public.sms_can_administer()
returns boolean language sql stable security definer set search_path = public as $$
  select public.has_perm('smsCreditsConsume') and public.has_perm('usersManage')
$$;

create or replace function public.save_sms_template(p_key text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_company uuid := public.current_company_id();
  v_problem text;
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not public.sms_can_administer() then
    raise exception 'Only an owner or admin can edit message templates.' using errcode = 'TD403';
  end if;
  v_problem := public.sms_template_problem(p_key, p_body);
  if v_problem is not null then raise exception '%', v_problem using errcode = 'TD422'; end if;
  insert into public.sms_templates (company_id, template_key, body, updated_by_user_id, updated_at)
  values (v_company, p_key, p_body, auth.uid(), now())
  on conflict (company_id, template_key) do update set body = excluded.body, updated_by_user_id = excluded.updated_by_user_id, updated_at = now();
end $$;

create or replace function public.reset_sms_template(p_key text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if public.current_company_id() is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not public.sms_can_administer() then
    raise exception 'Only an owner or admin can edit message templates.' using errcode = 'TD403';
  end if;
  delete from public.sms_templates where company_id = public.current_company_id() and template_key = p_key;
end $$;

create or replace function public.set_sms_automation(p_key text, p_enabled boolean)
returns void language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.current_company_id();
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not public.sms_can_administer() then
    raise exception 'Only an owner or admin can change automations.' using errcode = 'TD403';
  end if;
  if not exists (select 1 from public.sms_template_defaults where template_key = p_key and is_automatable) then
    raise exception 'That message can''t be automated.' using errcode = 'TD422';
  end if;
  insert into public.sms_automation_settings (company_id, template_key, enabled, updated_by_user_id, updated_at)
  values (v_company, p_key, coalesce(p_enabled, false), auth.uid(), now())
  on conflict (company_id, template_key) do update set enabled = excluded.enabled, updated_by_user_id = excluded.updated_by_user_id, updated_at = now();
end $$;

-- -----------------------------------------------------------------------------
-- 6. Readiness: subscription, messaging status, opt-out
-- -----------------------------------------------------------------------------
create or replace function public.sms_company_entitled(p_company uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select c.closed_at is null from public.companies c where c.id = p_company), false)
     and coalesce((select e.has_entitlement from public.company_entitlement_for(p_company) e), false)
$$;

-- NULL when this company may send to this number right now; otherwise a code:
-- companyClosed · noSubscription · notSetUp · awaitingApproval · suspended ·
-- paused · noNumber · optedOut.
create or replace function public.sms_send_blocker(p_company uuid, p_to text)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  a public.company_messaging_accounts%rowtype;
  v_to text := public.sms_normalise_phone(p_to);
begin
  if exists (select 1 from public.companies c where c.id = p_company and c.closed_at is not null) then
    return 'companyClosed';
  end if;
  if not public.sms_company_entitled(p_company) then return 'noSubscription'; end if;
  select * into a from public.company_messaging_accounts where company_id = p_company;
  if not found or a.status in ('not_started','provisioning','failed') then return 'notSetUp'; end if;
  if a.status = 'awaiting_registration' then return 'awaitingApproval'; end if;
  if a.status in ('suspended','closing','closed') then return 'suspended'; end if;
  if a.billing_state = 'paused' then return 'paused'; end if;
  if not exists (select 1 from public.company_phone_numbers n
                  where n.company_id = p_company and n.is_primary and n.status = 'active') then
    return 'noNumber';
  end if;
  if v_to is not null and exists (select 1 from public.sms_opt_outs o
                                   where o.company_id = p_company and o.phone_e164 = v_to and o.opted_out) then
    return 'optedOut';
  end if;
  return null;
end $$;

create or replace function public.sms_send_readiness(p_to text default null)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_company uuid := public.current_company_id();
begin
  if v_company is null then return 'notSignedIn'; end if;
  if not public.has_perm('smsCreditsConsume') then return 'notPermitted'; end if;
  return public.sms_send_blocker(v_company, p_to);
end $$;

-- -----------------------------------------------------------------------------
-- 7. Segment-aware credit spending
-- -----------------------------------------------------------------------------

-- Unchanged signature and callers. Now charges one credit per SEGMENT of the
-- notification body (a caller can never pay less than the body costs) and
-- refuses companies without an active subscription.
create or replace function public.consume_sms_credit(p_notification uuid, p_credits integer default null,
                                                     p_customer uuid default null, p_job uuid default null)
returns table(outcome text, credits_charged integer, balance_after integer)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_company uuid := public.current_company_id();
  v_cost integer;
  v_segments integer;
  v_balance integer;
  v_body text;
begin
  if v_company is null then raise exception 'No company in context'; end if;
  if not public.has_perm('smsCreditsConsume') then
    outcome := 'notPermitted'; credits_charged := 0; balance_after := null; return next; return;
  end if;
  if not public.sms_company_entitled(v_company) then
    outcome := 'noSubscription'; credits_charged := 0; balance_after := null; return next; return;
  end if;

  perform 1 from public.companies where id = v_company for update;
  if not found then
    raise exception 'Company % not found; refusing to spend SMS credit unserialised', v_company;
  end if;

  select body into v_body from public.notifications where id = p_notification and company_id = v_company;
  select s.segments into v_segments from public.sms_segment_info(coalesce(v_body, '')) s;
  v_cost := greatest(coalesce(v_segments, 0), 1) * public.sms_credits_per_segment();
  if p_credits is not null and p_credits > v_cost then v_cost := p_credits; end if;

  if v_cost <= 0 then
    outcome := 'invalidCost'; credits_charged := 0; balance_after := public.sms_credit_balance_for(v_company);
    return next; return;
  end if;

  v_balance := public.sms_credit_balance_for(v_company);
  if v_balance < v_cost then
    outcome := 'insufficientCredits'; credits_charged := 0; balance_after := v_balance; return next; return;
  end if;

  if p_notification is not null and not exists (
    select 1 from public.notifications where id = p_notification and company_id = v_company) then
    outcome := 'unknownMessage'; credits_charged := 0; balance_after := v_balance; return next; return;
  end if;
  if p_customer is not null and not exists (
    select 1 from public.customers where id = p_customer and company_id = v_company) then
    outcome := 'unknownCustomer'; credits_charged := 0; balance_after := v_balance; return next; return;
  end if;

  v_balance := v_balance - v_cost;
  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, customer_id, job_id, notification_id)
  values (v_company, 'consumption', -v_cost, v_balance, p_customer, p_job, p_notification);
  update public.notifications set credits_charged = v_cost, segments = coalesce(v_segments, segments), updated_at = now()
   where id = p_notification;

  outcome := 'consumed'; credits_charged := v_cost; balance_after := v_balance;
  return next;
end $$;

-- Pre-existing defect fixed, logic unchanged: its OUT column
-- `credits_refunded` collided with notifications.credits_refunded, so the
-- first real refund would have raised "ambiguous column". It had never run.
create or replace function public.refund_sms_credit(p_notification uuid, p_reason text default null)
returns table(outcome text, credits_refunded integer, balance_after integer)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_company  uuid;
  v_charged  integer;
  v_refunded integer;
  v_balance  integer;
begin
  select n.company_id into v_company from public.notifications n where n.id = p_notification;
  if v_company is null then
    outcome := 'unknownMessage'; credits_refunded := 0; balance_after := null; return next; return;
  end if;
  perform 1 from public.companies where id = v_company for update;
  if not found then
    raise exception 'Company % not found; refusing to refund SMS credit unserialised', v_company;
  end if;
  select n.credits_charged, n.credits_refunded into v_charged, v_refunded
    from public.notifications n where n.id = p_notification;
  if coalesce(v_charged, 0) <= 0 or coalesce(v_refunded, 0) > 0 then
    outcome := 'nothingToRefund'; credits_refunded := 0;
    balance_after := public.sms_credit_balance_for(v_company); return next; return;
  end if;
  v_balance := public.sms_credit_balance_for(v_company) + v_charged;
  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, notification_id, purchase_reference)
  values (v_company, 'refund', v_charged, v_balance, p_notification, p_reason);
  update public.notifications set credits_refunded = v_charged, updated_at = now() where id = p_notification;
  outcome := 'refunded'; credits_refunded := v_charged; balance_after := v_balance;
  return next;
end $$;
revoke all on function public.refund_sms_credit(uuid, text) from public, anon, authenticated;
grant execute on function public.refund_sms_credit(uuid, text) to service_role;

-- THE reservation every customer SMS goes through (manual, scheduled,
-- automation, invoice). One transaction, under the company lock:
-- tenancy -> recipient -> subscription/messaging/opt-out -> segments ->
-- balance -> notification + ledger. Nothing reaches Twilio before this commits.
create or replace function public.sms_reserve_internal(
  p_company uuid, p_user uuid, p_customer uuid, p_job uuid, p_quote uuid, p_invoice uuid,
  p_to text, p_body text, p_template text, p_scheduled uuid)
returns table(outcome text, notification_id uuid, credits_charged integer, segments integer, encoding text,
              balance_after integer, messaging_account_id uuid, twilio_account_sid text,
              messaging_service_sid text, from_number text, to_number text, conversation_id uuid)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_to text := public.sms_normalise_phone(p_to);
  v_body text := btrim(coalesce(p_body, ''));
  v_blocker text;
  v_seg record;
  v_cost integer;
  v_balance integer;
  v_account public.company_messaging_accounts%rowtype;
  v_from text;
  v_contact uuid;
  v_conv uuid;
  v_note uuid;
begin
  outcome := null; credits_charged := 0;
  if p_company is null or p_customer is null then outcome := 'invalidRequest'; return next; return; end if;
  if not exists (select 1 from public.customers c where c.id = p_customer and c.company_id = p_company) then
    outcome := 'unknownCustomer'; return next; return;
  end if;
  if p_job is not null and not exists (select 1 from public.jobs j where j.id = p_job and j.company_id = p_company and j.customer_id = p_customer) then
    outcome := 'unknownJob'; return next; return;
  end if;
  if p_quote is not null and not exists (select 1 from public.quotes q where q.id = p_quote and q.company_id = p_company and q.customer_id = p_customer) then
    outcome := 'unknownQuote'; return next; return;
  end if;
  if p_invoice is not null and not exists (select 1 from public.invoices i where i.id = p_invoice and i.company_id = p_company and i.customer_id = p_customer) then
    outcome := 'unknownInvoice'; return next; return;
  end if;
  if p_template is not null and not exists (select 1 from public.sms_template_defaults d where d.template_key = p_template) then
    outcome := 'unknownTemplate'; return next; return;
  end if;

  if v_to is null then outcome := 'invalidRecipient'; return next; return; end if;
  select c.id into v_contact from public.customer_contacts c
   where c.company_id = p_company and c.customer_id = p_customer and public.sms_normalise_phone(c.phone) = v_to
   order by c.is_primary desc limit 1;
  if v_contact is null then outcome := 'recipientNotOnRecord'; return next; return; end if;

  if v_body = '' then outcome := 'emptyMessage'; return next; return; end if;
  if char_length(v_body) > public.sms_setting_int('sms_max_body_chars', 640) then outcome := 'tooLong'; return next; return; end if;
  if v_body ~ '\{\{|\}\}' then outcome := 'unresolvedVariables'; return next; return; end if;

  v_blocker := public.sms_send_blocker(p_company, v_to);
  if v_blocker is not null then outcome := v_blocker; return next; return; end if;

  select * into v_seg from public.sms_segment_info(v_body);
  v_cost := v_seg.segments * public.sms_credits_per_segment();

  perform 1 from public.companies where id = p_company for update;
  if not found then raise exception 'Company % not found; refusing to spend SMS credit unserialised', p_company; end if;

  -- Re-check after the lock: an opt-out or pause that committed while we
  -- waited must win.
  v_blocker := public.sms_send_blocker(p_company, v_to);
  if v_blocker is not null then outcome := v_blocker; return next; return; end if;

  v_balance := public.sms_credit_balance_for(p_company);
  if v_balance < v_cost then
    outcome := 'insufficientCredits'; balance_after := v_balance; segments := v_seg.segments;
    return next; return;
  end if;

  select * into v_account from public.company_messaging_accounts where company_id = p_company;
  select n.e164 into v_from from public.company_phone_numbers n
   where n.company_id = p_company and n.is_primary and n.status = 'active' limit 1;

  insert into public.sms_conversations (company_id, phone_e164, customer_id, contact_id, last_job_id, last_message_at, last_preview, last_direction)
  values (p_company, v_to, p_customer, v_contact, p_job, now(), left(regexp_replace(v_body, '\s+', ' ', 'g'), 140), 'outbound')
  on conflict (company_id, phone_e164) do update
     set customer_id = excluded.customer_id, contact_id = excluded.contact_id,
         last_job_id = coalesce(excluded.last_job_id, public.sms_conversations.last_job_id),
         last_message_at = now(), last_preview = excluded.last_preview, last_direction = 'outbound'
  returning id into v_conv;

  insert into public.notifications (company_id, channel, status, template, recipient, to_number, from_number, body,
                                    customer_id, job_id, invoice_id, quote_id, conversation_id, messaging_account_id,
                                    twilio_account_sid, segments, encoding, credits_charged, sent_by_user_id, scheduled_message_id)
  values (p_company, 'sms', 'queued', coalesce(p_template, 'custom_message'), v_to, v_to, v_from, v_body,
          p_customer, p_job, p_invoice, p_quote, v_conv, v_account.id,
          v_account.twilio_subaccount_sid, v_seg.segments, v_seg.encoding, v_cost, p_user, p_scheduled)
  returning id into v_note;

  v_balance := v_balance - v_cost;
  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, customer_id, job_id, notification_id)
  values (p_company, 'consumption', -v_cost, v_balance, p_customer, p_job, v_note);

  outcome := 'reserved'; notification_id := v_note; credits_charged := v_cost; segments := v_seg.segments;
  encoding := v_seg.encoding; balance_after := v_balance; messaging_account_id := v_account.id;
  twilio_account_sid := v_account.twilio_subaccount_sid; messaging_service_sid := v_account.messaging_service_sid;
  from_number := v_from; to_number := v_to; conversation_id := v_conv;
  return next;
end $$;

create or replace function public.reserve_sms_send(p_customer uuid, p_job uuid, p_quote uuid, p_invoice uuid,
                                                   p_to text, p_body text, p_template text)
returns table(outcome text, notification_id uuid, credits_charged integer, segments integer, encoding text,
              balance_after integer, messaging_account_id uuid, twilio_account_sid text,
              messaging_service_sid text, from_number text, to_number text, conversation_id uuid)
language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.current_company_id();
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not public.has_perm('smsCreditsConsume') then
    outcome := 'notPermitted'; credits_charged := 0; return next; return;
  end if;
  return query select * from public.sms_reserve_internal(v_company, auth.uid(), p_customer, p_job, p_quote, p_invoice,
                                                          p_to, p_body, p_template, null);
end $$;

create or replace function public.reserve_sms_send_service(p_company uuid, p_customer uuid, p_job uuid, p_quote uuid,
                                                           p_invoice uuid, p_to text, p_body text, p_template text,
                                                           p_scheduled uuid)
returns table(outcome text, notification_id uuid, credits_charged integer, segments integer, encoding text,
              balance_after integer, messaging_account_id uuid, twilio_account_sid text,
              messaging_service_sid text, from_number text, to_number text, conversation_id uuid)
language plpgsql security definer set search_path = public as $$
begin
  if not public.push_caller_is_service_role() then
    raise exception 'Service role only' using errcode = 'TD403';
  end if;
  return query select * from public.sms_reserve_internal(p_company, null, p_customer, p_job, p_quote, p_invoice,
                                                          p_to, p_body, p_template, p_scheduled);
end $$;

create or replace function public.sms_set_opt_out(p_company uuid, p_phone text, p_opted_out boolean, p_source text,
                                                  p_keyword text, p_service text, p_account text, p_sid text)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_phone text := public.sms_normalise_phone(p_phone);
  v_customer uuid; v_contact uuid;
begin
  if v_phone is null then return; end if;
  select c.customer_id, c.id into v_customer, v_contact from public.customer_contacts c
   where c.company_id = p_company and public.sms_normalise_phone(c.phone) = v_phone
   order by c.is_primary desc, c.updated_at desc limit 1;
  insert into public.sms_opt_outs (company_id, phone_e164, customer_id, contact_id, opted_out, source, keyword,
                                   messaging_service_sid, twilio_account_sid, last_message_sid, opted_out_at, opted_in_at, updated_at)
  values (p_company, v_phone, v_customer, v_contact, p_opted_out, p_source, p_keyword, p_service, p_account, p_sid,
          case when p_opted_out then now() end, case when not p_opted_out then now() end, now())
  on conflict (company_id, phone_e164) do update
     set opted_out = excluded.opted_out, source = excluded.source, keyword = excluded.keyword,
         messaging_service_sid = coalesce(excluded.messaging_service_sid, public.sms_opt_outs.messaging_service_sid),
         twilio_account_sid = coalesce(excluded.twilio_account_sid, public.sms_opt_outs.twilio_account_sid),
         last_message_sid = coalesce(excluded.last_message_sid, public.sms_opt_outs.last_message_sid),
         opted_out_at = case when excluded.opted_out then now() else public.sms_opt_outs.opted_out_at end,
         opted_in_at = case when not excluded.opted_out then now() else public.sms_opt_outs.opted_in_at end,
         customer_id = coalesce(excluded.customer_id, public.sms_opt_outs.customer_id),
         contact_id = coalesce(excluded.contact_id, public.sms_opt_outs.contact_id),
         updated_at = now();
end $$;

-- The provider's answer to a reserved send. Accepted -> sent (never
-- "delivered"). Rejected -> failed + idempotent refund; 21610 records the opt-out.
create or replace function public.sms_record_provider_result(p_notification uuid, p_accepted boolean, p_sid text,
                                                             p_status text, p_from text, p_segments integer,
                                                             p_price_micros bigint, p_error_code text, p_error text)
returns table(outcome text, credits_refunded integer, balance_after integer)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare n public.notifications%rowtype;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  select * into n from public.notifications where id = p_notification and channel = 'sms';
  if not found then outcome := 'unknownMessage'; credits_refunded := 0; return next; return; end if;

  if p_accepted then
    update public.notifications
       set status = 'sent', provider_reference = p_sid, provider_status = coalesce(p_status, 'queued'),
           from_number = coalesce(p_from, from_number), segments = coalesce(p_segments, segments),
           provider_price_micros = coalesce(p_price_micros, provider_price_micros),
           sent_at = now(), updated_at = now()
     where id = p_notification;
    outcome := 'sent'; credits_refunded := 0; balance_after := public.sms_credit_balance_for(n.company_id);
    return next; return;
  end if;

  update public.notifications
     set status = 'failed', provider_error = p_error_code, failure_reason = coalesce(p_error, 'The SMS provider refused the message.'),
         updated_at = now()
   where id = p_notification;
  if p_error_code = '21610' then
    perform public.sms_set_opt_out(n.company_id, n.to_number, true, 'provider', 'STOP', null, n.twilio_account_sid, null);
  end if;
  return query select r.outcome, r.credits_refunded, r.balance_after
                 from public.refund_sms_credit(p_notification, 'provider rejected before sending') r;
end $$;

-- -----------------------------------------------------------------------------
-- 8. Webhooks: status callbacks and inbound SMS (service role)
-- -----------------------------------------------------------------------------
create or replace function public.messaging_store_subaccount_token(p_account uuid, p_token text)
returns void language plpgsql security definer set search_path = public as $$
declare v_existing uuid; v_new uuid;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  select auth_token_secret_id into v_existing from public.company_messaging_accounts where id = p_account;
  if v_existing is not null then
    perform vault.update_secret(v_existing, p_token);
  else
    v_new := vault.create_secret(p_token, 'twilio_subaccount_token_' || p_account::text, 'Twilio subaccount auth token');
    update public.company_messaging_accounts set auth_token_secret_id = v_new, updated_at = now() where id = p_account;
  end if;
end $$;

create or replace function public.messaging_subaccount_token(p_account uuid)
returns text language plpgsql stable security definer set search_path = public as $$
declare v_token text;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  select s.decrypted_secret into v_token
    from public.company_messaging_accounts a join vault.decrypted_secrets s on s.id = a.auth_token_secret_id
   where a.id = p_account;
  return v_token;
end $$;

-- Resolves a callback to its company from the per-company key in the URL.
create or replace function public.messaging_webhook_context(p_callback_key text)
returns table(company_id uuid, messaging_account_id uuid, twilio_subaccount_sid text, messaging_service_sid text, auth_token text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  return query
    select a.company_id, a.id, a.twilio_subaccount_sid, a.messaging_service_sid, s.decrypted_secret
      from public.company_messaging_accounts a
      left join vault.decrypted_secrets s on s.id = a.auth_token_secret_id
     where a.callback_key = p_callback_key and coalesce(p_callback_key, '') <> '';
end $$;

create or replace function public.sms_apply_status(p_callback_key text, p_account_sid text, p_message_sid text,
                                                   p_status text, p_error_code text, p_error_message text,
                                                   p_price_micros bigint default null)
returns table(outcome text, credits_refunded integer)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  a public.company_messaging_accounts%rowtype;
  n public.notifications%rowtype;
  v_status public.notification_status;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  credits_refunded := 0;
  select * into a from public.company_messaging_accounts where callback_key = p_callback_key and coalesce(p_callback_key,'') <> '';
  if not found then outcome := 'unknownCallback'; return next; return; end if;
  if a.twilio_subaccount_sid is null or a.twilio_subaccount_sid is distinct from p_account_sid then
    outcome := 'wrongAccount'; return next; return;
  end if;
  -- Company AND reference: a SID belonging to another company resolves to nothing.
  select * into n from public.notifications
   where provider_reference = p_message_sid and company_id = a.company_id and channel = 'sms';
  if not found then outcome := 'unknownMessage'; return next; return; end if;

  v_status := case p_status
    when 'queued' then 'sent' when 'accepted' then 'sent' when 'sending' then 'sent' when 'sent' then 'sent'
    when 'delivered' then 'delivered' when 'undelivered' then 'undelivered' when 'failed' then 'failed'
    else null end;
  if v_status is null then outcome := 'ignored'; return next; return; end if;
  if n.status in ('delivered','failed','undelivered') and v_status = 'sent' then
    outcome := 'alreadySettled'; return next; return;
  end if;

  update public.notifications
     set status = v_status, provider_status = p_status, updated_at = now(),
         provider_price_micros = coalesce(p_price_micros, provider_price_micros),
         delivered_at = case when v_status = 'delivered' then now() else delivered_at end,
         failure_reason = case when v_status in ('failed','undelivered') then coalesce(p_error_message, 'The carrier could not deliver this message.') else failure_reason end,
         provider_error = case when v_status in ('failed','undelivered') then p_error_code else provider_error end
   where id = n.id;

  if v_status in ('failed','undelivered') then
    if p_error_code = '21610' then
      perform public.sms_set_opt_out(a.company_id, n.to_number, true, 'provider', 'STOP', a.messaging_service_sid, p_account_sid, p_message_sid);
    end if;
    select r.credits_refunded into credits_refunded from public.refund_sms_credit(n.id, 'carrier ' || p_status) r;
  end if;
  outcome := v_status::text;
  return next;
end $$;

create or replace function public.sms_keyword_type(p_body text, p_opt_out_type text default null)
returns text language sql immutable as $$
  select case
    when upper(coalesce(p_opt_out_type,'')) = 'STOP' then 'stop'
    when upper(coalesce(p_opt_out_type,'')) = 'START' then 'start'
    when upper(coalesce(p_opt_out_type,'')) = 'HELP' then 'help'
    when upper(btrim(coalesce(p_body,''))) in ('STOP','STOPALL','UNSUBSCRIBE','CANCEL','END','QUIT','OPTOUT','REVOKE','STOP ALL') then 'stop'
    when upper(btrim(coalesce(p_body,''))) in ('START','UNSTOP','YES') then 'start'
    when upper(btrim(coalesce(p_body,''))) in ('HELP','INFO') then 'help'
    else null end
$$;

create or replace function public.sms_record_inbound(p_callback_key text, p_account_sid text, p_messaging_service_sid text,
                                                     p_from text, p_to text, p_body text, p_message_sid text,
                                                     p_opt_out_type text default null)
returns table(outcome text, company_id uuid, conversation_id uuid, customer_id uuid, job_id uuid, keyword text, notified integer)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  a public.company_messaging_accounts%rowtype;
  v_from text := public.sms_normalise_phone(p_from);
  v_to text := public.sms_normalise_phone(p_to);
  v_customer uuid; v_contact uuid; v_job uuid; v_job_number text; v_name text;
  v_conv uuid; v_kw text; v_title text; v_preview text;
  v_user uuid; v_n integer := 0;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  notified := 0;
  select * into a from public.company_messaging_accounts x where x.callback_key = p_callback_key and coalesce(p_callback_key,'') <> '';
  if not found then outcome := 'unknownCallback'; return next; return; end if;
  if a.twilio_subaccount_sid is null or a.twilio_subaccount_sid is distinct from p_account_sid then
    outcome := 'wrongAccount'; return next; return;
  end if;
  if coalesce(p_messaging_service_sid, '') <> '' and a.messaging_service_sid is distinct from p_messaging_service_sid then
    outcome := 'wrongService'; return next; return;
  end if;
  if v_to is null or not exists (select 1 from public.company_phone_numbers n
                                  where n.company_id = a.company_id and n.e164 = v_to and n.status in ('active','releasing')) then
    outcome := 'wrongNumber'; return next; return;
  end if;
  if v_from is null then outcome := 'invalidSender'; return next; return; end if;
  if exists (select 1 from public.sms_inbound_messages m where m.provider_reference = p_message_sid) then
    outcome := 'duplicate'; company_id := a.company_id; return next; return;
  end if;

  select c.customer_id, c.id into v_customer, v_contact
    from public.customer_contacts c join public.customers cu on cu.id = c.customer_id
   where c.company_id = a.company_id and public.sms_normalise_phone(c.phone) = v_from
   order by (cu.status = 'active') desc, c.is_primary desc, c.updated_at desc limit 1;

  if v_customer is not null then
    select j.id, j.number into v_job, v_job_number from public.jobs j
     where j.company_id = a.company_id and j.customer_id = v_customer
       and j.status in ('scheduled','workerAssigned','travelling','arrived','inProgress')
     order by abs(extract(epoch from (coalesce(j.scheduled_start, j.created_at) - now()))) limit 1;
    if v_job is null then
      select j.id, j.number into v_job, v_job_number from public.jobs j
       where j.company_id = a.company_id and j.customer_id = v_customer
         and j.status in ('completed','invoiced','paid') and j.updated_at > now() - interval '14 days'
       order by j.updated_at desc limit 1;
    end if;
    select name into v_name from public.customers where id = v_customer;
  end if;

  insert into public.sms_conversations (company_id, phone_e164, customer_id, contact_id, last_job_id, last_message_at, last_preview, last_direction)
  values (a.company_id, v_from, v_customer, v_contact, v_job, now(), left(regexp_replace(coalesce(p_body,''), '\s+', ' ', 'g'), 140), 'inbound')
  on conflict (company_id, phone_e164) do update
     set customer_id = coalesce(excluded.customer_id, public.sms_conversations.customer_id),
         contact_id = coalesce(excluded.contact_id, public.sms_conversations.contact_id),
         last_job_id = coalesce(excluded.last_job_id, public.sms_conversations.last_job_id),
         last_message_at = now(), last_preview = excluded.last_preview, last_direction = 'inbound'
  returning id into v_conv;

  select coalesce(v_job, c.last_job_id), coalesce(v_customer, c.customer_id) into v_job, v_customer
    from public.sms_conversations c where c.id = v_conv;
  if v_job_number is null and v_job is not null then select number into v_job_number from public.jobs where id = v_job; end if;
  if v_name is null and v_customer is not null then select name into v_name from public.customers where id = v_customer; end if;

  v_kw := public.sms_keyword_type(p_body, p_opt_out_type);
  insert into public.sms_inbound_messages (company_id, conversation_id, messaging_account_id, customer_id, job_id,
                                           from_number, to_number, body, provider_reference, keyword_type)
  values (a.company_id, v_conv, a.id, v_customer, v_job, v_from, v_to, coalesce(p_body, ''), p_message_sid, v_kw);

  if v_kw = 'stop' then
    perform public.sms_set_opt_out(a.company_id, v_from, true, 'keyword', upper(btrim(p_body)), a.messaging_service_sid, p_account_sid, p_message_sid);
  elsif v_kw = 'start' then
    perform public.sms_set_opt_out(a.company_id, v_from, false, 'keyword', upper(btrim(p_body)), a.messaging_service_sid, p_account_sid, p_message_sid);
  end if;

  -- Alert only the people who handle customer messages: active users holding
  -- smsCreditsConsume AND customersReadAll. Never engineers, never accounts.
  v_title := 'New message from ' || coalesce(nullif(v_name, ''), v_from)
             || case when v_job_number is not null then ' · Job ' || v_job_number else '' end;
  v_preview := case when v_kw = 'stop' then 'Opted out of text messages.'
                    when v_kw = 'start' then 'Opted back in to text messages.'
                    else left(regexp_replace(coalesce(p_body,''), '\s+', ' ', 'g'), 140) end;
  perform set_config('harbour.push_link_event', 'sms.inbound', true);
  perform set_config('harbour.push_link', 'tradedesk://sms/' || v_conv::text, true);
  begin
    for v_user in
      select u.id from public.app_users u
       where u.company_id = a.company_id and u.status = 'active'
         and exists (select 1 from public.role_permissions rp where rp.role = u.role and rp.permission = 'smsCreditsConsume')
         and exists (select 1 from public.role_permissions rp where rp.role = u.role and rp.permission = 'customersReadAll')
    loop
      perform public.enqueue_push(a.company_id, v_user, 'sms.inbound', v_title, v_preview, null, v_customer);
      v_n := v_n + 1;
    end loop;
  exception when others then
    raise warning 'inbound SMS % saved, but its alert could not be raised: %', p_message_sid, sqlerrm;
  end;

  outcome := 'recorded'; company_id := a.company_id; conversation_id := v_conv; customer_id := v_customer;
  job_id := v_job; keyword := v_kw; notified := v_n;
  return next;
end $$;

-- -----------------------------------------------------------------------------
-- 8b. Push deep links to the exact conversation
-- -----------------------------------------------------------------------------
-- Pre-existing defect: send_office_message() set the conversation link on
-- rows where deep_link IS NULL, but enqueue_push() always writes a link
-- ('tradedesk://jobs'), so a tapped message alert opened Jobs instead of the
-- conversation. enqueue_push() now honours a transaction-local link override
-- for one named event, set by the caller (or by the trigger below for office
-- messages). Signature, recipients, tenancy and job-assignment rules are
-- unchanged.
create or replace function public.enqueue_push(p_company uuid, p_user uuid, p_event text, p_title text, p_body text,
                                               p_job uuid default null, p_customer uuid default null)
returns integer language plpgsql security definer set search_path = public as $$
declare
  v_link text;
  v_rows integer := 0;
begin
  if p_user is null or p_company is null then return 0; end if;
  if pg_trigger_depth() = 0 and auth.uid() is not null then
    if not exists (select 1 from app_users u where u.id = auth.uid() and u.company_id = p_company and u.status = 'active') then
      raise exception 'Push events may only be raised within your own company' using errcode = 'TD403';
    end if;
  end if;
  if p_user = auth.uid() then return 0; end if;
  if not exists (select 1 from app_users u where u.id = p_user and u.company_id = p_company and u.status = 'active') then
    return 0;
  end if;
  if p_job is not null and p_event <> 'job.unassigned'
     and exists (select 1 from app_users u join role_permissions rp on rp.role = u.role
                  where u.id = p_user and rp.permission = 'jobsReadAssignedOnly')
     and not exists (select 1 from field_worker_assignments a where a.job_id = p_job and a.user_id = p_user) then
    return 0;
  end if;

  if coalesce(current_setting('harbour.push_link_event', true), '') = p_event
     and coalesce(current_setting('harbour.push_link', true), '') like 'tradedesk://%' then
    v_link := current_setting('harbour.push_link', true);
  else
    v_link := case when p_job is not null then 'tradedesk://job/' || p_job::text else 'tradedesk://jobs' end;
  end if;

  insert into notifications (company_id, channel, template, recipient, job_id, customer_id,
                             status, target_user_id, push_device_id, title, body, deep_link)
  select p_company, 'push', p_event, 'ios ' || right(d.token, 6), p_job, p_customer,
         'queued', p_user, d.id, p_title, p_body, v_link
    from push_devices d
   where d.user_id = p_user and d.company_id = p_company and d.revoked_at is null;
  get diagnostics v_rows = row_count;

  if v_rows = 0 then
    insert into notifications (company_id, channel, template, recipient, job_id, customer_id,
                               status, target_user_id, title, body, deep_link, failure_reason)
    values (p_company, 'push', p_event, 'no registered device', p_job, p_customer,
            'failed', p_user, p_title, p_body, v_link, 'No device registered for push notifications.');
  end if;
  return v_rows;
end $$;

create or replace function public.office_message_push_link()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  perform set_config('harbour.push_link_event', 'office.message', true);
  perform set_config('harbour.push_link', 'tradedesk://message/' || new.thread_id::text, true);
  return new;
end $$;
drop trigger if exists office_message_push_link on public.office_messages;
create trigger office_message_push_link after insert on public.office_messages
  for each row execute function public.office_message_push_link();

-- -----------------------------------------------------------------------------
-- 9. Conversations, unread, usage and status reads for the app
-- -----------------------------------------------------------------------------
create or replace view public.sms_thread_messages with (security_invoker = true) as
  select n.id, n.company_id, n.conversation_id, 'outbound'::text as direction, n.body, n.created_at as at,
         n.status::text as status, n.template, n.segments, n.credits_charged, n.credits_refunded,
         n.customer_id, n.job_id, n.quote_id, n.invoice_id, n.sent_by_user_id, n.failure_reason
    from public.notifications n
   where n.channel = 'sms' and n.conversation_id is not null
  union all
  select m.id, m.company_id, m.conversation_id, 'inbound', m.body, m.received_at, 'received', coalesce(m.keyword_type, 'reply'),
         null, 0, 0, m.customer_id, m.job_id, null, null, null, null
    from public.sms_inbound_messages m;
revoke all on public.sms_thread_messages from anon;

create or replace function public.mark_sms_conversation_read(p_conversation uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.current_company_id();
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not exists (select 1 from public.sms_conversations c where c.id = p_conversation and c.company_id = v_company)
     or not public.has_perm('customersReadAll') then
    raise exception 'Conversation not found.' using errcode = 'TD404';
  end if;
  insert into public.sms_conversation_reads (conversation_id, user_id, company_id, last_read_at)
  values (p_conversation, auth.uid(), v_company, clock_timestamp())
  on conflict (conversation_id, user_id) do update set last_read_at = clock_timestamp();
end $$;

create or replace function public.sms_conversation_list(p_limit integer default 100)
returns table(conversation_id uuid, phone_e164 text, customer_id uuid, customer_name text, job_id uuid, job_number text,
              last_message_at timestamptz, last_preview text, last_direction text, unread integer, opted_out boolean)
language sql stable security definer set search_path = public as $$
  select c.id, c.phone_e164, c.customer_id, cu.name, c.last_job_id, j.number, c.last_message_at, c.last_preview,
         c.last_direction,
         (select count(*)::integer from public.sms_inbound_messages m
           where m.conversation_id = c.id
             and m.received_at > coalesce((select r.last_read_at from public.sms_conversation_reads r
                                            where r.conversation_id = c.id and r.user_id = auth.uid()), '-infinity')),
         coalesce((select o.opted_out from public.sms_opt_outs o where o.company_id = c.company_id and o.phone_e164 = c.phone_e164), false)
    from public.sms_conversations c
    left join public.customers cu on cu.id = c.customer_id
    left join public.jobs j on j.id = c.last_job_id
   where c.company_id = public.current_company_id()
     and public.has_perm('customersReadAll')
     and (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead'))
   order by c.last_message_at desc
   limit greatest(1, least(coalesce(p_limit, 100), 500))
$$;

-- Unread counts for the global message indicator. Customer replies are only
-- counted for roles that handle them; office threads follow the existing
-- office-thread visibility rule.
create or replace function public.communications_unread()
returns table(customer_unread integer, office_unread integer, latest_title text, latest_body text,
              latest_link text, latest_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_uid uuid := auth.uid();
  v_company uuid := public.current_company_id();
  v_can_customer boolean;
  v_is_office boolean;
  r record;
begin
  customer_unread := 0; office_unread := 0;
  if v_uid is null or v_company is null then return next; return; end if;
  v_can_customer := public.has_perm('smsCreditsConsume') and public.has_perm('customersReadAll');
  v_is_office := public.is_office_user();

  if v_can_customer then
    select count(*)::integer into customer_unread
      from public.sms_inbound_messages m
      left join public.sms_conversation_reads rd on rd.conversation_id = m.conversation_id and rd.user_id = v_uid
     where m.company_id = v_company and m.received_at > coalesce(rd.last_read_at, '-infinity');
    select m.received_at as at, 'New message from ' || coalesce(nullif(cu.name, ''), m.from_number)
             || case when j.number is not null then ' · Job ' || j.number else '' end as title,
           left(m.body, 140) as body, 'tradedesk://sms/' || m.conversation_id::text as link
      into r
      from public.sms_inbound_messages m
      left join public.sms_conversation_reads rd on rd.conversation_id = m.conversation_id and rd.user_id = v_uid
      left join public.customers cu on cu.id = m.customer_id
      left join public.jobs j on j.id = m.job_id
     where m.company_id = v_company and m.received_at > coalesce(rd.last_read_at, '-infinity')
     order by m.received_at desc limit 1;
    if r.at is not null then latest_at := r.at; latest_title := r.title; latest_body := r.body; latest_link := r.link; end if;
  end if;

  select count(*)::integer into office_unread
    from public.office_messages m
    join public.office_threads t on t.id = m.thread_id
    left join public.office_thread_reads rd on rd.thread_id = t.id and rd.user_id = v_uid
   where t.company_id = v_company and m.sender_user_id <> v_uid
     and (t.engineer_user_id = v_uid or v_is_office)
     and m.created_at > coalesce(rd.last_read_at, '-infinity');

  select m.created_at as at, coalesce(nullif(u.name, ''), 'A colleague')
           || case when j.number is not null then ' · Job ' || j.number else '' end as title,
         case when btrim(m.body) = '' then 'Photo' else left(m.body, 140) end as body,
         'tradedesk://message/' || t.id::text as link
    into r
    from public.office_messages m
    join public.office_threads t on t.id = m.thread_id
    left join public.office_thread_reads rd on rd.thread_id = t.id and rd.user_id = v_uid
    left join public.app_users u on u.id = m.sender_user_id
    left join public.jobs j on j.id = t.job_id
   where t.company_id = v_company and m.sender_user_id <> v_uid
     and (t.engineer_user_id = v_uid or v_is_office)
     and m.created_at > coalesce(rd.last_read_at, '-infinity')
   order by m.created_at desc limit 1;
  if r.at is not null and (latest_at is null or r.at > latest_at) then
    latest_at := r.at; latest_title := r.title; latest_body := r.body; latest_link := r.link;
  end if;
  return next;
end $$;

create or replace function public.sms_messaging_status()
returns table(status text, friendly_status text, registration_status text, registration_route text,
              phone_number text, number_status text, billing_state text, next_fee_due_at timestamptz,
              number_fee_cents integer, number_fee_credits integer, setup_fee_cents integer, retention_days integer,
              grace_days integer, credits_per_segment integer, attention text, business_name text,
              can_manage boolean, has_subscription boolean, balance integer, provisioning_step text,
              requested_number text, needs_number_choice boolean, sole_prop_verification_pending boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare
  v_company uuid := public.current_company_id();
  a public.company_messaging_accounts%rowtype;
  n public.company_phone_numbers%rowtype;
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not (public.has_perm('smsCreditsConsume') or public.has_perm('smsLedgerRead') or public.has_perm('saasBillingRead')) then
    raise exception 'Not permitted' using errcode = 'TD403';
  end if;
  select * into a from public.company_messaging_accounts x where x.company_id = v_company;
  select * into n from public.company_phone_numbers x
   where x.company_id = v_company and x.is_primary and x.status <> 'released' order by x.created_at desc limit 1;

  status := coalesce(a.status, 'not_started');
  friendly_status := case
    when a.id is null or a.status = 'not_started' then 'notSetUp'
    when a.status = 'provisioning' then 'settingUp'
    when a.status = 'awaiting_registration' then 'waitingApproval'
    when a.status = 'active' and a.billing_state = 'paused' then 'needsAttention'
    when a.status = 'active' then 'ready'
    when a.status = 'failed' then 'needsAttention'
    else 'suspended' end;
  registration_status := coalesce(a.registration_status, 'not_submitted');
  registration_route := a.registration_route;
  phone_number := n.e164;
  number_status := n.status;
  billing_state := coalesce(a.billing_state, 'current');
  next_fee_due_at := n.next_fee_due_at;
  number_fee_cents := public.sms_setting_int('sms_number_monthly_fee_cents', 299);
  number_fee_credits := public.sms_number_monthly_fee_credits();
  setup_fee_cents := public.sms_setting_int('sms_setup_fee_cents', 0);
  retention_days := public.sms_setting_int('sms_number_retention_days', 60);
  grace_days := public.sms_setting_int('sms_number_grace_days', 7);
  credits_per_segment := public.sms_credits_per_segment();
  attention := case
    when a.status = 'failed' or a.registration_status = 'rejected' then coalesce(a.last_error, a.registration_error, 'Setup couldn''t be completed. Check your details and try again.')
    when a.billing_state = 'grace' then 'Your monthly number fee couldn''t be taken. Add SMS credits to keep your number.'
    when a.billing_state = 'paused' then 'SMS is paused because the monthly number fee is unpaid. Add SMS credits to resume.'
    when a.status = 'suspended' then coalesce(a.suspended_reason, 'SMS is suspended for this company.')
    when a.status in ('closing','closed') then 'SMS has been turned off for this company.'
    when a.provisioning_step = 'number_unavailable' then 'The number you picked was taken by someone else. Choose another number.'
    when a.status = 'provisioning' and a.last_error is not null then a.last_error
    else null end;
  business_name := case when public.has_perm('saasBillingManage') then a.business_details ->> 'legal_name' end;
  can_manage := public.current_app_role() = 'owner';
  has_subscription := public.sms_company_entitled(v_company);
  balance := public.sms_credit_balance_for(v_company);
  provisioning_step := coalesce(a.provisioning_step, 'none');
  requested_number := case when public.has_perm('saasBillingManage') then a.requested_number end;
  needs_number_choice := coalesce(a.provisioning_step = 'number_unavailable', false);
  sole_prop_verification_pending := coalesce(a.registration_route = 'sole_proprietor'
                                              and a.registration_status = 'needs_verification', false);
  return next;
end $$;

create or replace function public.sms_usage_summary()
returns table(balance integer, purchased integer, used integer, refunded integer, fees integer,
              segments_30d integer, messages_sent_30d integer, messages_failed_30d integer, messages_received_30d integer)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare v_company uuid := public.current_company_id();
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not public.has_perm('smsLedgerRead') then raise exception 'Not permitted' using errcode = 'TD403'; end if;
  balance := public.sms_credit_balance_for(v_company);
  select coalesce(sum(amount) filter (where transaction_type = 'purchase'), 0)::integer,
         coalesce(-sum(amount) filter (where transaction_type = 'consumption'), 0)::integer,
         coalesce(sum(amount) filter (where transaction_type = 'refund'), 0)::integer,
         coalesce(-sum(amount) filter (where transaction_type = 'adjustment' and purchase_reference like 'number-fee:%'), 0)::integer
    into purchased, used, refunded, fees
    from public.sms_credit_ledger where company_id = v_company;
  select coalesce(sum(segments) filter (where status in ('sent','delivered','accepted')), 0)::integer,
         count(*) filter (where status in ('sent','delivered','accepted'))::integer,
         count(*) filter (where status in ('failed','undelivered'))::integer
    into segments_30d, messages_sent_30d, messages_failed_30d
    from public.notifications where company_id = v_company and channel = 'sms' and created_at > now() - interval '30 days';
  select count(*)::integer into messages_received_30d from public.sms_inbound_messages
   where company_id = v_company and received_at > now() - interval '30 days';
  return next;
end $$;

-- -----------------------------------------------------------------------------
-- 10. Scheduled messages
-- -----------------------------------------------------------------------------
create or replace function public.schedule_sms(p_customer uuid, p_job uuid, p_quote uuid, p_invoice uuid,
                                               p_template text, p_body text, p_to text, p_scheduled_for timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_company uuid := public.current_company_id();
  v_to text := public.sms_normalise_phone(p_to);
  v_body text := btrim(coalesce(p_body, ''));
  v_blocker text;
  v_id uuid;
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not public.has_perm('smsCreditsConsume') then raise exception 'You can''t send customer messages.' using errcode = 'TD403'; end if;
  if not exists (select 1 from public.customers c where c.id = p_customer and c.company_id = v_company) then
    raise exception 'Customer not found.' using errcode = 'TD404';
  end if;
  if p_job is not null and not exists (select 1 from public.jobs j where j.id = p_job and j.company_id = v_company and j.customer_id = p_customer) then
    raise exception 'Job not found.' using errcode = 'TD404';
  end if;
  if p_quote is not null and not exists (select 1 from public.quotes q where q.id = p_quote and q.company_id = v_company and q.customer_id = p_customer) then
    raise exception 'Quote not found.' using errcode = 'TD404';
  end if;
  if p_invoice is not null and not exists (select 1 from public.invoices i where i.id = p_invoice and i.company_id = v_company and i.customer_id = p_customer) then
    raise exception 'Invoice not found.' using errcode = 'TD404';
  end if;
  if v_to is null or not exists (select 1 from public.customer_contacts c where c.company_id = v_company
                                  and c.customer_id = p_customer and public.sms_normalise_phone(c.phone) = v_to) then
    raise exception 'That number isn''t on the customer''s record.' using errcode = 'TD422';
  end if;
  if v_body = '' or v_body ~ '\{\{|\}\}' or char_length(v_body) > public.sms_setting_int('sms_max_body_chars', 640) then
    raise exception 'The message isn''t ready to schedule.' using errcode = 'TD422';
  end if;
  if p_scheduled_for is null or p_scheduled_for < now() + interval '1 minute' or p_scheduled_for > now() + interval '90 days' then
    raise exception 'Pick a time between now and 90 days ahead.' using errcode = 'TD422';
  end if;
  v_blocker := public.sms_send_blocker(v_company, v_to);
  if v_blocker in ('optedOut','notSetUp','noSubscription','companyClosed','suspended') then
    raise exception '%', v_blocker using errcode = 'TD422';
  end if;
  insert into public.scheduled_messages (company_id, customer_id, job_id, quote_id, invoice_id, template_key, body, to_number,
                                         scheduled_for, source, created_by_user_id)
  values (v_company, p_customer, p_job, p_quote, p_invoice, coalesce(p_template, 'custom_message'), v_body, v_to,
          p_scheduled_for, 'manual', auth.uid())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.cancel_scheduled_sms(p_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.current_company_id(); v_n integer;
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not public.has_perm('smsCreditsConsume') then raise exception 'Not permitted' using errcode = 'TD403'; end if;
  update public.scheduled_messages set status = 'cancelled', cancelled_at = now(), cancelled_by_user_id = auth.uid(), updated_at = now()
   where id = p_id and company_id = v_company and status = 'scheduled';
  get diagnostics v_n = row_count;
  return v_n > 0;
end $$;

create or replace function public.claim_due_scheduled_sms(p_limit integer default 25)
returns setof public.scheduled_messages
language plpgsql security definer set search_path = public as $$
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  return query
  with due as (
    select s.id from public.scheduled_messages s
     where (s.status = 'scheduled' and s.scheduled_for <= now())
        or (s.status = 'sending' and s.claimed_at < now() - interval '10 minutes' and s.notification_id is null)
     order by s.scheduled_for
     limit greatest(1, least(coalesce(p_limit, 25), 200))
     for update skip locked
  )
  update public.scheduled_messages s
     set status = 'sending', claimed_at = now(), attempts = s.attempts + 1, updated_at = now()
   where s.id in (select id from due)
  returning s.*;
end $$;

create or replace function public.finish_scheduled_sms(p_id uuid, p_status text, p_notification uuid, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  update public.scheduled_messages
     set status = p_status, notification_id = coalesce(p_notification, notification_id), failure_reason = p_reason,
         sent_at = case when p_status = 'sent' then now() else sent_at end, updated_at = now()
   where id = p_id and status = 'sending';
end $$;

-- -----------------------------------------------------------------------------
-- 11. Automations (operational only; queue rows, the dispatcher renders them)
-- -----------------------------------------------------------------------------
create or replace function public.sms_queue_automation(p_company uuid, p_key text, p_customer uuid, p_job uuid,
                                                       p_quote uuid, p_invoice uuid, p_when timestamptz, p_dedupe text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_enabled boolean; v_id uuid;
begin
  if p_customer is null then return null; end if;
  select case when d.is_automatable then coalesce(s.enabled, d.automation_default) else false end into v_enabled
    from public.sms_template_defaults d
    left join public.sms_automation_settings s on s.template_key = d.template_key and s.company_id = p_company
   where d.template_key = p_key;
  if not coalesce(v_enabled, false) then return null; end if;
  if not exists (select 1 from public.company_messaging_accounts a where a.company_id = p_company and a.status = 'active') then
    return null;
  end if;
  insert into public.scheduled_messages (company_id, customer_id, job_id, quote_id, invoice_id, template_key, scheduled_for, source, dedupe_key)
  values (p_company, p_customer, p_job, p_quote, p_invoice, p_key, greatest(coalesce(p_when, now()), now()), 'automation', p_dedupe)
  on conflict (dedupe_key) do update
     set status = 'scheduled', scheduled_for = excluded.scheduled_for, cancelled_at = null, cancelled_by_user_id = null,
         failure_reason = null, updated_at = now()
   where public.scheduled_messages.status = 'cancelled'
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.sms_cancel_automations(p_job uuid, p_quote uuid, p_invoice uuid, p_keys text[], p_reason text)
returns integer language plpgsql security definer set search_path = public as $$
declare v_n integer;
begin
  update public.scheduled_messages
     set status = 'cancelled', cancelled_at = now(), failure_reason = p_reason, updated_at = now()
   where status = 'scheduled' and source = 'automation' and template_key = any(p_keys)
     and ((p_job is not null and job_id = p_job) or (p_quote is not null and quote_id = p_quote)
          or (p_invoice is not null and invoice_id = p_invoice));
  get diagnostics v_n = row_count;
  return v_n;
end $$;

create or replace function public.sms_on_job_change()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_epoch text;
begin
  begin
    if not exists (select 1 from public.company_messaging_accounts a where a.company_id = new.company_id and a.status = 'active') then
      return new;
    end if;
    v_epoch := coalesce(extract(epoch from new.scheduled_start)::bigint::text, 'none');

    if tg_op = 'INSERT' then
      if new.scheduled_start is not null and new.status <> 'cancelled' then
        perform public.sms_queue_automation(new.company_id, 'appointment_confirmation', new.customer_id, new.id, null, null, now(), 'appt_confirm:' || new.id);
        if new.scheduled_start - interval '24 hours' > now() + interval '30 minutes' then
          perform public.sms_queue_automation(new.company_id, 'appointment_reminder', new.customer_id, new.id, null, null,
                                              new.scheduled_start - interval '24 hours', 'appt_remind:' || new.id || ':' || v_epoch);
        end if;
      end if;
      return new;
    end if;

    if new.status is distinct from old.status then
      if new.status = 'cancelled' then
        perform public.sms_cancel_automations(new.id, null, null, array['appointment_reminder','appointment_confirmation'], 'Job cancelled');
        perform public.sms_queue_automation(new.company_id, 'appointment_cancelled', new.customer_id, new.id, null, null, now(), 'appt_cancel:' || new.id);
      elsif new.status = 'travelling' then
        perform public.sms_queue_automation(new.company_id, 'engineer_on_the_way', new.customer_id, new.id, null, null, now(), 'otw:' || new.id);
      elsif new.status = 'arrived' then
        perform public.sms_queue_automation(new.company_id, 'engineer_arrived', new.customer_id, new.id, null, null, now(), 'arrived:' || new.id);
      elsif new.status = 'inProgress' then
        perform public.sms_queue_automation(new.company_id, 'job_started', new.customer_id, new.id, null, null, now(), 'started:' || new.id);
      elsif new.status = 'completed' then
        perform public.sms_cancel_automations(new.id, null, null, array['appointment_reminder'], 'Job completed');
        perform public.sms_queue_automation(new.company_id, 'job_completed', new.customer_id, new.id, null, null, now(), 'completed:' || new.id);
      end if;
    end if;

    if new.scheduled_start is not null and new.scheduled_start is distinct from old.scheduled_start
       and new.status not in ('cancelled','completed','invoiced','paid') then
      if old.scheduled_start is null then
        perform public.sms_queue_automation(new.company_id, 'appointment_confirmation', new.customer_id, new.id, null, null, now(), 'appt_confirm:' || new.id);
      elsif new.status = 'travelling' then
        perform public.sms_queue_automation(new.company_id, 'eta_update', new.customer_id, new.id, null, null, now(), 'eta:' || new.id || ':' || v_epoch);
      else
        perform public.sms_queue_automation(new.company_id, 'appointment_rescheduled', new.customer_id, new.id, null, null, now(), 'appt_resched:' || new.id || ':' || v_epoch);
      end if;
      perform public.sms_cancel_automations(new.id, null, null, array['appointment_reminder'], 'Appointment moved');
      if new.scheduled_start - interval '24 hours' > now() + interval '30 minutes' then
        perform public.sms_queue_automation(new.company_id, 'appointment_reminder', new.customer_id, new.id, null, null,
                                            new.scheduled_start - interval '24 hours', 'appt_remind:' || new.id || ':' || v_epoch);
      end if;
    end if;
  exception when others then
    raise warning 'SMS automation skipped for job %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

create or replace function public.sms_on_job_note()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_customer uuid;
begin
  begin
    if new.visibility = 'customerVisible' then
      select customer_id into v_customer from public.jobs where id = new.job_id;
      perform public.sms_queue_automation(new.company_id, 'job_update', v_customer, new.job_id, null, null, now(), 'jobupd:' || new.id);
    end if;
  exception when others then
    raise warning 'SMS automation skipped for note %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

create or replace function public.sms_on_quote_status()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  begin
    if new.status is distinct from old.status then
      if new.status = 'sent' then
        perform public.sms_queue_automation(new.company_id, 'quote_sent', new.customer_id, null, new.id, null, now(), 'quote_sent:' || new.id);
        perform public.sms_queue_automation(new.company_id, 'quote_reminder', new.customer_id, null, new.id, null, now() + interval '3 days', 'quote_remind:' || new.id);
      elsif new.status = 'accepted' then
        perform public.sms_cancel_automations(null, new.id, null, array['quote_reminder'], 'Quote accepted');
        perform public.sms_queue_automation(new.company_id, 'quote_accepted', new.customer_id, null, new.id, null, now(), 'quote_accepted:' || new.id);
      elsif new.status = 'declined' then
        perform public.sms_cancel_automations(null, new.id, null, array['quote_reminder'], 'Quote declined');
        perform public.sms_queue_automation(new.company_id, 'quote_declined', new.customer_id, null, new.id, null, now(), 'quote_declined:' || new.id);
      elsif new.status = 'expired' then
        perform public.sms_cancel_automations(null, new.id, null, array['quote_reminder'], 'Quote expired');
      end if;
    end if;
  exception when others then
    raise warning 'SMS automation skipped for quote %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

create or replace function public.sms_on_invoice_status()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_tz text; v_remind timestamptz; v_overdue timestamptz;
begin
  begin
    if new.status is distinct from old.status then
      if new.status = 'sent' and old.status = 'draft' then
        select time_zone_identifier into v_tz from public.companies where id = new.company_id;
        v_remind := ((new.due_date - 3)::timestamp + interval '10 hours') at time zone coalesce(v_tz, 'UTC');
        v_overdue := ((new.due_date + 1)::timestamp + interval '10 hours') at time zone coalesce(v_tz, 'UTC');
        perform public.sms_queue_automation(new.company_id, 'invoice_sent', new.customer_id, null, null, new.id, now(), 'inv_sent:' || new.id);
        if v_remind > now() then
          perform public.sms_queue_automation(new.company_id, 'payment_reminder', new.customer_id, null, null, new.id, v_remind, 'inv_remind:' || new.id);
        end if;
        perform public.sms_queue_automation(new.company_id, 'overdue_reminder', new.customer_id, null, null, new.id, v_overdue, 'inv_overdue:' || new.id);
      elsif new.status in ('paid','void') then
        perform public.sms_cancel_automations(null, null, new.id, array['payment_reminder','overdue_reminder'], 'Invoice ' || new.status::text);
      end if;
    end if;
  exception when others then
    raise warning 'SMS automation skipped for invoice %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

create or replace function public.sms_on_payment()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_customer uuid;
begin
  begin
    if new.status = 'succeeded' and (tg_op = 'INSERT' or old.status is distinct from 'succeeded') then
      select customer_id into v_customer from public.invoices where id = new.invoice_id;
      perform public.sms_queue_automation(new.company_id, 'payment_received', v_customer, null, null, new.invoice_id, now(), 'paid:' || new.id);
    end if;
  exception when others then
    raise warning 'SMS automation skipped for payment %: %', new.id, sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists sms_job_automation on public.jobs;
create trigger sms_job_automation after insert or update on public.jobs
  for each row execute function public.sms_on_job_change();
drop trigger if exists sms_job_note_automation on public.job_notes;
create trigger sms_job_note_automation after insert on public.job_notes
  for each row execute function public.sms_on_job_note();
drop trigger if exists sms_quote_automation on public.quotes;
create trigger sms_quote_automation after update of status on public.quotes
  for each row execute function public.sms_on_quote_status();
drop trigger if exists sms_invoice_automation on public.invoices;
create trigger sms_invoice_automation after update of status on public.invoices
  for each row execute function public.sms_on_invoice_status();
drop trigger if exists sms_payment_automation on public.payments;
create trigger sms_payment_automation after insert or update of status on public.payments
  for each row execute function public.sms_on_payment();

-- -----------------------------------------------------------------------------
-- 12. Numbers: purchase record, monthly fee, release guard, closure
-- -----------------------------------------------------------------------------
create or replace function public.sms_record_number_purchase(p_account uuid, p_sid text, p_e164 text, p_area text,
                                                             p_locality text, p_region text)
returns uuid language plpgsql security definer set search_path = public as $$
declare a public.company_messaging_accounts%rowtype; v_id uuid;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  select * into a from public.company_messaging_accounts where id = p_account;
  if not found then raise exception 'Unknown messaging account' using errcode = 'TD404'; end if;
  select id into v_id from public.company_phone_numbers where phone_number_sid = p_sid;
  if v_id is not null then return v_id; end if;
  if (select count(*) from public.company_phone_numbers n where n.company_id = a.company_id and n.status <> 'released')
     >= public.sms_setting_int('sms_max_numbers_per_company', 1) then
    raise exception 'This company already has its dedicated number.' using errcode = 'TD409';
  end if;
  insert into public.company_phone_numbers (company_id, messaging_account_id, phone_number_sid, e164, area_code, locality, region,
                                            status, is_primary, monthly_fee_credits, next_fee_due_at, purchased_at)
  values (a.company_id, a.id, p_sid, public.sms_normalise_phone(p_e164), p_area, p_locality, p_region,
          'active', true, public.sms_number_monthly_fee_credits(), now(), now())
  returning id into v_id;
  return v_id;
end $$;

create or replace function public.sms_charge_number_fee(p_number uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  n public.company_phone_numbers%rowtype;
  a public.company_messaging_accounts%rowtype;
  v_fee integer; v_bal integer; v_ref text; v_owner uuid;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  select * into n from public.company_phone_numbers where id = p_number;
  if not found or n.status <> 'active' then return 'inactive'; end if;
  perform 1 from public.companies where id = n.company_id for update;
  select * into n from public.company_phone_numbers where id = p_number;
  select * into a from public.company_messaging_accounts where id = n.messaging_account_id for update;
  if n.next_fee_due_at is not null and n.next_fee_due_at > now() then return 'notDue'; end if;

  v_fee := public.sms_number_monthly_fee_credits();
  v_ref := 'number-fee:' || n.id::text || ':' || to_char(coalesce(n.next_fee_due_at, now()) at time zone 'UTC', 'YYYY-MM-DD');
  if exists (select 1 from public.sms_credit_ledger l where l.company_id = n.company_id and l.purchase_reference = v_ref) then
    update public.company_phone_numbers set next_fee_due_at = coalesce(next_fee_due_at, now()) + interval '1 month', updated_at = now() where id = n.id;
    return 'alreadyCharged';
  end if;

  v_bal := public.sms_credit_balance_for(n.company_id);
  if v_fee = 0 or v_bal >= v_fee then
    if v_fee > 0 then
      insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, purchase_reference)
      values (n.company_id, 'adjustment', -v_fee, v_bal - v_fee, v_ref);
    end if;
    update public.company_phone_numbers
       set next_fee_due_at = coalesce(next_fee_due_at, now()) + interval '1 month', last_fee_charged_at = now(),
           monthly_fee_credits = v_fee, updated_at = now()
     where id = n.id;
    update public.company_messaging_accounts set billing_state = 'current', grace_started_at = null, updated_at = now() where id = a.id;
    return 'charged';
  end if;

  if a.billing_state = 'current' then
    update public.company_messaging_accounts set billing_state = 'grace', grace_started_at = now(), updated_at = now() where id = a.id;
    select u.id into v_owner from public.app_users u where u.company_id = n.company_id and u.role = 'owner' and u.status = 'active' limit 1;
    if v_owner is not null then
      begin
        perform public.enqueue_push(n.company_id, v_owner, 'sms.billing', 'SMS number fee due',
          format('Add SMS credits to keep your number. %s credits are needed for this month.', v_fee), null, null);
      exception when others then null;
      end;
    end if;
    return 'grace';
  end if;
  if a.billing_state = 'grace' and now() > a.grace_started_at + make_interval(days => public.sms_setting_int('sms_number_grace_days', 7)) then
    update public.company_messaging_accounts set billing_state = 'paused', updated_at = now() where id = a.id;
    return 'paused';
  end if;
  if a.billing_state = 'paused' and now() > a.grace_started_at + make_interval(days => public.sms_setting_int('sms_number_retention_days', 60)) then
    return 'releaseEligible';
  end if;
  return a.billing_state;
end $$;

-- The ONLY conditions under which a number may be released. A transient
-- error is never one of them.
create or replace function public.sms_number_release_allowed(p_number uuid)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare n public.company_phone_numbers%rowtype; a public.company_messaging_accounts%rowtype; v_closed timestamptz;
begin
  select * into n from public.company_phone_numbers where id = p_number;
  if not found then return false; end if;
  select * into a from public.company_messaging_accounts where id = n.messaging_account_id;
  select closed_at into v_closed from public.companies where id = n.company_id;
  -- Owner explicitly confirmed.
  if n.release_confirmed_at is not null and n.release_confirmed_by is not null then return true; end if;
  -- Company closed / SMS closing, and the retention period has passed.
  if (v_closed is not null or a.status in ('closing','closed'))
     and coalesce(a.retention_until, coalesce(v_closed, a.closing_started_at)
                  + make_interval(days => public.sms_setting_int('sms_number_retention_days', 60))) <= now() then
    return true;
  end if;
  -- Unpaid: paused and retention elapsed since the fee was first missed.
  if a.billing_state = 'paused' and a.grace_started_at is not null
     and a.grace_started_at + make_interval(days => public.sms_setting_int('sms_number_retention_days', 60)) <= now() then
    return true;
  end if;
  return false;
end $$;

create or replace function public.company_phone_numbers_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Phone number records are never deleted; release them instead.' using errcode = 'TD409';
  end if;
  if new.status in ('releasing','released') and old.status not in ('releasing','released')
     and not public.sms_number_release_allowed(old.id) then
    raise exception 'This number can''t be released: the company is active and no release was confirmed.' using errcode = 'TD409';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists company_phone_numbers_guard on public.company_phone_numbers;
create trigger company_phone_numbers_guard before update or delete on public.company_phone_numbers
  for each row execute function public.company_phone_numbers_guard();

create or replace function public.sms_on_company_closed()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.closed_at is not null and old.closed_at is null then
    update public.company_messaging_accounts
       set status = case when status in ('not_started') then 'closed' else 'closing' end,
           closing_started_at = now(),
           retention_until = now() + make_interval(days => public.sms_setting_int('sms_number_retention_days', 60)),
           updated_at = now()
     where company_id = new.id and status not in ('closing','closed');
    update public.scheduled_messages set status = 'cancelled', cancelled_at = now(), failure_reason = 'Company closed', updated_at = now()
     where company_id = new.id and status = 'scheduled';
  end if;
  return new;
end $$;
drop trigger if exists sms_company_closed on public.companies;
create trigger sms_company_closed after update of closed_at on public.companies
  for each row execute function public.sms_on_company_closed();

-- Owner action: turn SMS off and release the number (explicit confirmation).
create or replace function public.confirm_sms_number_release()
returns boolean language plpgsql security definer set search_path = public as $$
declare v_company uuid := public.current_company_id(); v_n integer;
begin
  if v_company is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if public.current_app_role() <> 'owner' then raise exception 'Only the owner can release the SMS number.' using errcode = 'TD403'; end if;
  update public.company_phone_numbers set release_confirmed_at = now(), release_confirmed_by = auth.uid(), release_reason = 'owner_release'
   where company_id = v_company and status = 'active';
  get diagnostics v_n = row_count;
  update public.company_phone_numbers set status = 'releasing' where company_id = v_company and status = 'active';
  update public.company_messaging_accounts set status = 'closing', closing_started_at = now(), retention_until = now(), updated_at = now()
   where company_id = v_company and status not in ('closing','closed');
  update public.scheduled_messages set status = 'cancelled', cancelled_at = now(), failure_reason = 'SMS turned off', updated_at = now()
   where company_id = v_company and status = 'scheduled';
  return v_n > 0;
end $$;

-- -----------------------------------------------------------------------------
-- 13. Quote share links (customer-facing, token only)
-- -----------------------------------------------------------------------------
create or replace function public.quote_share_token_for(p_company uuid, p_quote uuid, p_user uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text; q record;
begin
  select id, company_id, status into q from public.quotes where id = p_quote and company_id = p_company;
  if not found then raise exception 'Quote not found' using errcode = 'TD404'; end if;
  if q.status = 'draft' then raise exception 'Mark the quote as sent before sharing it.' using errcode = 'TD422'; end if;
  select token into v_token from public.quote_share_tokens where quote_id = p_quote and revoked_at is null limit 1;
  if v_token is not null then return v_token; end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.quote_share_tokens (company_id, quote_id, token, created_by_user_id) values (p_company, p_quote, v_token, p_user);
  return v_token;
end $$;

create or replace function public.issue_quote_share_token(p_quote uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if public.current_company_id() is null then raise exception 'Not signed in' using errcode = 'TD401'; end if;
  if not public.has_perm('quotesRead') or not public.has_perm('smsCreditsConsume') then
    raise exception 'Not permitted' using errcode = 'TD403';
  end if;
  return public.quote_share_token_for(public.current_company_id(), p_quote, auth.uid());
end $$;

create or replace function public.issue_quote_share_token_service(p_company uuid, p_quote uuid)
returns text language plpgsql security definer set search_path = public as $$
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  return public.quote_share_token_for(p_company, p_quote, null);
end $$;

create or replace function public.issue_invoice_share_token_service(p_company uuid, p_invoice uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v_token text; v_owner uuid; i record;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  select id, status into i from public.invoices where id = p_invoice and company_id = p_company;
  if not found then raise exception 'Invoice not found' using errcode = 'TD404'; end if;
  if i.status in ('draft','void') then raise exception 'This invoice can''t be shared.' using errcode = 'TD422'; end if;
  select token into v_token from public.invoice_share_tokens where invoice_id = p_invoice and revoked_at is null limit 1;
  if v_token is not null then return v_token; end if;
  select u.id into v_owner from public.app_users u where u.company_id = p_company and u.role = 'owner' and u.status = 'active' order by u.created_at limit 1;
  if v_owner is null then raise exception 'No active owner to issue the link.' using errcode = 'TD409'; end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.invoice_share_tokens (company_id, invoice_id, token, created_by_user_id) values (p_company, p_invoice, v_token, v_owner);
  return v_token;
end $$;

-- What the customer-facing quote page shows. No internal ids, no staff data,
-- no cost or margin metadata.
create or replace function public.quote_public_view(p_token text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare t public.quote_share_tokens%rowtype; q public.quotes%rowtype; c public.companies%rowtype; v_customer text; v_lines jsonb;
begin
  if coalesce(p_token, '') !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok', false); end if;
  select * into t from public.quote_share_tokens where token = p_token and revoked_at is null;
  if not found then return jsonb_build_object('ok', false); end if;
  select * into q from public.quotes where id = t.quote_id;
  select * into c from public.companies where id = t.company_id;
  if c.closed_at is not null or q.status = 'draft' then return jsonb_build_object('ok', false); end if;
  select name into v_customer from public.customers where id = q.customer_id;
  select coalesce(jsonb_agg(jsonb_build_object('description', l.item_description, 'quantity', l.quantity,
                                               'unit_price', l.unit_price, 'line_total', l.line_total) order by l.sort_order), '[]'::jsonb)
    into v_lines from public.quote_line_items l where l.quote_id = q.id;
  update public.quote_share_tokens set last_viewed_at = now(), view_count = view_count + 1 where id = t.id;
  if q.status = 'sent' then
    update public.quotes set status = 'viewed', viewed_at = coalesce(viewed_at, now()) where id = q.id;
  end if;
  return jsonb_build_object('ok', true,
    'company', jsonb_build_object('name', c.name, 'phone', c.phone, 'email', c.business_email,
                                  'address', concat_ws(', ', nullif(c.address_line,''), nullif(c.city,''), nullif(c.state,''), nullif(c.postal_code,''))),
    'quote', jsonb_build_object('number', q.number, 'title', q.title, 'scope', q.scope_of_work,
                                'status', case when q.status = 'sent' then 'viewed' else q.status::text end,
                                'valid_until', q.valid_until, 'subtotal', q.subtotal, 'tax', q.tax, 'total', q.total,
                                'currency', c.currency_code, 'customer', v_customer),
    'lines', v_lines);
end $$;

-- -----------------------------------------------------------------------------
-- 14. Maintenance tick (pg_cron -> signed call to the sms-maintenance function)
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'sms_maintenance_signing_key') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'sms_maintenance_signing_key',
                                'Signs the scheduled SMS maintenance call');
  end if;
end $$;

create or replace function public.sms_verify_maintenance_signature(p_timestamp text, p_signature text)
returns boolean language plpgsql stable security definer set search_path = public as $$
declare v_key text;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  if coalesce(p_timestamp, '') !~ '^[0-9]{9,12}$' then return false; end if;
  if abs(extract(epoch from clock_timestamp()) - p_timestamp::bigint) > 300 then return false; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'sms_maintenance_signing_key';
  if v_key is null then return false; end if;
  return encode(extensions.hmac(p_timestamp, v_key, 'sha256'), 'hex') = coalesce(p_signature, '');
end $$;

create or replace function public.sms_maintenance_work_waiting()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.scheduled_messages where status = 'scheduled' and scheduled_for <= now())
      or exists (select 1 from public.scheduled_messages where status = 'sending' and notification_id is null and claimed_at < now() - interval '10 minutes')
      or exists (select 1 from public.company_messaging_accounts
                  where status in ('provisioning','awaiting_registration') and coalesce(next_attempt_at, now()) <= now()
                    and provisioning_step <> 'number_unavailable')
      or exists (select 1 from public.company_phone_numbers where status = 'active' and next_fee_due_at <= now())
      or exists (select 1 from public.company_phone_numbers where status = 'releasing')
      or exists (select 1 from public.company_messaging_accounts where status = 'closing' and coalesce(retention_until, now()) <= now())
$$;

create or replace function public.sms_maintenance_tick()
returns bigint language plpgsql security definer set search_path = public as $$
declare v_key text; v_ts text; v_sig text; v_request bigint;
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon') then
    raise exception 'SMS maintenance is service-role only' using errcode = 'TD403';
  end if;
  if not public.sms_maintenance_work_waiting() then return null; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'sms_maintenance_signing_key';
  if v_key is null then raise warning 'sms maintenance: no signing key'; return null; end if;
  v_ts := extract(epoch from clock_timestamp())::bigint::text;
  v_sig := encode(extensions.hmac(v_ts, v_key, 'sha256'), 'hex');
  select net.http_post(
    url := 'https://srfnfimskixjqjyyftak.supabase.co/functions/v1/sms-maintenance',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-sms-timestamp', v_ts, 'x-sms-signature', v_sig),
    body := jsonb_build_object('source', 'cron'),
    timeout_milliseconds := 55000
  ) into v_request;
  return v_request;
end $$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'sms-maintenance') then
    perform cron.unschedule('sms-maintenance');
  end if;
  perform cron.schedule('sms-maintenance', '* * * * *', 'select public.sms_maintenance_tick();');
end $$;

-- -----------------------------------------------------------------------------
-- 15. Execute grants: nothing new is callable by anon except the quote page;
--     service-role functions are callable by nobody else.
-- -----------------------------------------------------------------------------
do $$
declare
  f record;
  v_user text[] := array['sms_credits_per_segment','sms_number_monthly_fee_credits','sms_segment_info','sms_normalise_phone',
    'sms_template_problem','sms_template_catalog','sms_can_administer','save_sms_template','reset_sms_template',
    'set_sms_automation','sms_send_readiness','reserve_sms_send','mark_sms_conversation_read','sms_conversation_list',
    'communications_unread','sms_messaging_status','sms_usage_summary','schedule_sms','cancel_scheduled_sms',
    'confirm_sms_number_release','issue_quote_share_token','sms_keyword_type'];
  v_service text[] := array['sms_rate_card','sms_setting_int','sms_company_entitled','sms_send_blocker','sms_reserve_internal',
    'reserve_sms_send_service','sms_set_opt_out','sms_record_provider_result','messaging_store_subaccount_token',
    'messaging_subaccount_token','messaging_webhook_context','sms_apply_status','sms_record_inbound',
    'claim_due_scheduled_sms','finish_scheduled_sms','sms_queue_automation','sms_cancel_automations',
    'sms_record_number_purchase','sms_charge_number_fee','sms_number_release_allowed','quote_share_token_for',
    'issue_quote_share_token_service','issue_invoice_share_token_service','sms_verify_maintenance_signature',
    'sms_maintenance_work_waiting','sms_maintenance_tick'];
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proname = any(v_user) or p.proname = any(v_service)
                                            or p.proname in ('quote_public_view','sms_on_job_change','sms_on_job_note',
                                              'sms_on_quote_status','sms_on_invoice_status','sms_on_payment',
                                              'company_phone_numbers_guard','sms_on_company_closed','office_message_push_link'))
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname = any(v_user) then
      execute format('grant execute on function %s to authenticated, service_role', f.sig);
    elsif f.proname = any(v_service) then
      execute format('grant execute on function %s to service_role', f.sig);
    elsif f.proname = 'quote_public_view' then
      execute format('grant execute on function %s to anon, authenticated, service_role', f.sig);
    end if;
  end loop;
end $$;

-- consume_sms_credit keeps its existing grants (authenticated, service_role).
revoke all on function public.consume_sms_credit(uuid, integer, uuid, uuid) from public, anon;
grant execute on function public.consume_sms_credit(uuid, integer, uuid, uuid) to authenticated, service_role;

commit;
