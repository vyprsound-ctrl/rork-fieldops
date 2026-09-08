-- =============================================================================
-- Harbour South FieldOps — PHASE 2: COMMERCIAL LAYER (ADDITIVE)
-- =============================================================================
--
--  STATUS: WRITTEN, NOT APPLIED.
--
--  The agent that wrote this file has no Supabase administrative credentials
--  (no SUPABASE_ACCESS_TOKEN, no SUPABASE_SERVICE_ROLE_KEY, no SUPABASE_DB_URL),
--  so it could not execute a statement or read an existing policy back.
--
--  WHAT PHASE 1 ALREADY GAVE US — none of it is recreated here:
--    quotes, quote_line_items, invoices, invoice_line_items, payments,
--    sms_credit_ledger, service_agreements, notifications,
--    company_subscriptions, document_sequences,
--    plus create_quote / save_quote_line_item / update_quote_status /
--    convert_quote_to_job / create_invoice_from_job / create_invoice_from_quote /
--    record_payment / queue_invoice_notification / settle_notification /
--    payment_terms_days / sms_credits_per_message.
--
--  WHAT THIS MIGRATION ADDS — the parts Phase 1 genuinely did not have:
--    1. Central, server-side pricing configuration (subscription tiers, SMS
--       bundles, the Harbour South application fee). No price is compiled into
--       the iOS app.
--    2. Stripe Connect: the trade business's own connected account.
--    3. Stripe on payments: intent/charge ids, the split between Stripe's
--       processing fee, Harbour South's application fee and merchant net.
--    4. Stripe subscription identifiers on company_subscriptions, plus a
--       server-side seat-count and price calculator.
--    5. Stripe + Twilio event idempotency ledgers.
--    6. SMS: purchasable bundles, a purchase record, and a race-free generic
--       credit consumption function for customer messages.
--    7. Company default payment terms.
--    8. Recurring service generation that cannot double-book a period.
--
--  ORDERING — THIS IS ONE MIGRATION, APPLIED THE NORMAL WAY.
--
--  This file requires the eight enum labels added by
--  0003_commercial_enum_values.sql. They live in their own migration because
--  PostgreSQL refuses to let a new enum value be used in the transaction that
--  added it (SQLSTATE 55P04), and a migration file is applied as one
--  transaction — so the labels must be COMMITTED by an earlier migration, not
--  by an earlier section of this one. There is no manual pre-step:
--  `supabase db push` applies 0003 then 0004 in filename order, and the
--  boundary between them is the commit this file needs.
--
--  Section 0 below verifies those labels are present AND usable, and aborts
--  the whole migration if they are not, so a mis-ordered or partial deployment
--  fails at statement one having created nothing.
--
--  APPLY WITH, from an authenticated shell:
--    supabase db push --project-ref srfnfimskixjqjyyftak
--  or, in the SQL editor for project srfnfimskixjqjyyftak, run
--  0003_commercial_enum_values.sql first, then this file separately.
--
--  Every statement is guarded so re-running it is safe.
-- =============================================================================


-- =============================================================================
-- SECTION 0 — prerequisite check, then everything else in one transaction
-- =============================================================================

begin;

-- The enum labels this migration depends on are added by
-- 0003_commercial_enum_values.sql. Two separate things are checked here,
-- because they fail in different ways:
--
--   0a. Is the label in the catalogue at all? If 0003 was never applied, name
--       the missing labels now rather than failing hundreds of lines later, in
--       the middle of a function body, on a message that does not mention 0003.
--   0b. Is it COMMITTED, and therefore usable? A label added by the CURRENT
--       transaction is visible in pg_enum but cannot be evaluated, and
--       PostgreSQL only says so at the moment of use. The casts below force
--       that moment to be here — at statement one of the migration — instead
--       of at the first customer card payment weeks later.
--
-- Both abort the transaction, so a failure leaves the database exactly as it
-- was. Neither is a comment asking somebody to go and run something by hand.

-- 0a. Presence.
do $$
declare
  v_missing text;
begin
  select string_agg(
           format('%s.%s', required.type_name, required.label),
           ', ' order by required.type_name, required.label)
    into v_missing
  from (values
    ('subscription_plan',   'growingBusiness'),
    ('subscription_plan',   'largerBusiness'),
    ('notification_status', 'accepted'),
    ('notification_status', 'undelivered'),
    ('payment_status',      'processing'),
    ('payment_status',      'cancelled'),
    ('payment_method',      'stripe'),
    ('service_frequency',   'custom')
  ) as required(type_name, label)
  where not exists (
    select 1
    from pg_enum e
    join pg_type t      on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname   = 'public'
      and t.typname   = required.type_name
      and e.enumlabel = required.label
  );

  if v_missing is not null then
    raise exception 'Missing enum values required by this migration: %', v_missing
      using errcode = 'undefined_object',
            hint    = 'Apply 0003_commercial_enum_values.sql first. With '
                      'supabase db push that happens automatically, in '
                      'filename order.';
  end if;
end $$;

-- 0b. Committed, and therefore usable.
do $$
begin
  perform 'growingBusiness'::text::public.subscription_plan;
  perform 'largerBusiness'::text::public.subscription_plan;
  perform 'accepted'::text::public.notification_status;
  perform 'undelivered'::text::public.notification_status;
  perform 'processing'::text::public.payment_status;
  perform 'cancelled'::text::public.payment_status;
  perform 'stripe'::text::public.payment_method;
  perform 'custom'::text::public.service_frequency;
exception
  -- 55P04 = object_not_in_prerequisite_state. On an enum cast it means exactly
  -- one thing: the label was added by the transaction that is running now.
  when object_not_in_prerequisite_state then
    raise exception
      'Enum values required by this migration are not committed yet: %', sqlerrm
      using errcode = 'object_not_in_prerequisite_state',
            hint    = 'The ALTER TYPE ... ADD VALUE statements belong to '
                      '0003_commercial_enum_values.sql and must COMMIT before '
                      'this file runs. Do not paste both files into one editor '
                      'tab, and do not wrap both in a single transaction.';
end $$;

-- -----------------------------------------------------------------------------
-- 1. Platform pricing configuration
-- -----------------------------------------------------------------------------
-- Harbour South's own prices. These are platform-wide, not company-owned, so
-- they carry no company_id and no company may write them.

-- 1a. Subscription tiers.
--
-- NOT progressive brackets. A company sits in exactly one tier chosen by its
-- TOTAL active paid-user count, and every user beyond the first is charged that
-- tier's single additional-user rate. 15 users is 19.99 + 14 x 9.99, never
-- "the first 10 at one rate and the next 5 at another".
create table if not exists public.subscription_tiers (
  id                      text primary key,
  display_name            text not null,
  min_users               integer not null check (min_users >= 1),
  max_users               integer not null check (max_users >= min_users),
  base_cents              integer not null check (base_cents >= 0),
  additional_user_cents   integer not null check (additional_user_cents >= 0),
  sort_order              integer not null default 0,
  is_active               boolean not null default true,
  updated_at              timestamptz not null default now(),
  constraint subscription_tiers_band_valid check (max_users >= min_users)
);

insert into public.subscription_tiers
  (id, display_name, min_users, max_users, base_cents, additional_user_cents, sort_order)
values
  ('solo',   'Solo',             1,   1,   1999, 0,    1),
  ('team',   'Team',             2,   10,  1999, 1299, 2),
  ('growing','Growing Business', 11,  30,  1999, 999,  3),
  ('larger', 'Larger Business',  31,  100, 1999, 799,  4)
on conflict (id) do nothing;

-- 1b. SMS bundles.
--
-- Deliberately NOT an enum and NOT a constraint on the quantities below: the
-- consumption path takes any positive integer, so Harbour South can add, retire
-- or reprice a bundle with an UPDATE and no app release. There is no minimum
-- purchase quantity anywhere in this schema.
create table if not exists public.sms_bundles (
  id            text primary key,
  credits       integer not null check (credits > 0),
  price_cents   integer not null check (price_cents >= 0),
  sort_order    integer not null default 0,
  is_active     boolean not null default true,
  updated_at    timestamptz not null default now()
);

insert into public.sms_bundles (id, credits, price_cents, sort_order) values
  ('sms_25',    25,    400,   1),
  ('sms_50',    50,    750,   2),
  ('sms_100',   100,   1400,  3),
  ('sms_250',   250,   3250,  4),
  ('sms_500',   500,   6000,  5),
  ('sms_1000',  1000,  11000, 6),
  ('sms_2500',  2500,  25000, 7),
  ('sms_5000',  5000,  45000, 8)
on conflict (id) do nothing;

-- 1c. Everything else Harbour South configures centrally, including the
--     application fee. Kept out of the two price lists above because it is not
--     a price a customer is ever shown.
create table if not exists public.platform_settings (
  key         text primary key,
  value       jsonb not null,
  description text not null default '',
  updated_at  timestamptz not null default now()
);

insert into public.platform_settings (key, value, description) values
  ('application_fee_bps',
   '30'::jsonb,
   'Harbour South application fee on eligible connected-account payments, in basis points. 30 = 0.30%. Changing this row changes the fee on the next payment; no app release is involved.'),
  ('application_fee_enabled',
   'true'::jsonb,
   'Master switch for the application fee.'),
  ('application_fee_minimum_cents',
   '0'::jsonb,
   'Fee is skipped entirely when the computed amount falls below this.'),
  ('subscription_max_users',
   '100'::jsonb,
   'Supported ceiling on active paid users. The seat calculator refuses above this.'),
  ('sms_credits_per_message',
   '1'::jsonb,
   'Credits consumed per outbound SMS segment-group.')
on conflict (key) do nothing;

alter table public.subscription_tiers enable row level security;
alter table public.sms_bundles        enable row level security;
alter table public.platform_settings  enable row level security;

-- The two price lists are readable by any signed-in user: they are a published
-- price list, and the app has to render them.
drop policy if exists "subscription tiers are a published price list" on public.subscription_tiers;
create policy "subscription tiers are a published price list"
  on public.subscription_tiers for select to authenticated using (is_active);

drop policy if exists "sms bundles are a published price list" on public.sms_bundles;
create policy "sms bundles are a published price list"
  on public.sms_bundles for select to authenticated using (is_active);

-- platform_settings gets NO policy for `authenticated`, so with RLS enabled it
-- is invisible to every app user and reachable only by the service role. The
-- application fee is not a number the client is allowed to learn, let alone set.

-- -----------------------------------------------------------------------------
-- 2. Subscription: Stripe identifiers and the seat calculator
-- -----------------------------------------------------------------------------
-- Phase 1 modelled the subscription against Apple/Google IAP. Harbour South
-- bills the trade business directly through Stripe, which is a different set of
-- identifiers. The Apple/Google columns are left untouched.

alter table public.company_subscriptions
  add column if not exists stripe_customer_id       text,
  add column if not exists stripe_subscription_id   text,
  add column if not exists stripe_price_id          text,
  add column if not exists tier_id                  text references public.subscription_tiers(id),
  add column if not exists active_paid_users        integer not null default 1,
  add column if not exists additional_user_cents    integer not null default 0,
  add column if not exists base_cents               integer not null default 1999,
  add column if not exists monthly_price_cents      integer not null default 1999,
  add column if not exists past_due_since           timestamptz,
  add column if not exists last_payment_failure     text,
  add column if not exists last_payment_failed_at   timestamptz,
  add column if not exists seats_synced_at          timestamptz;

create unique index if not exists company_subscriptions_stripe_subscription_idx
  on public.company_subscriptions (stripe_subscription_id)
  where stripe_subscription_id is not null;

create unique index if not exists company_subscriptions_stripe_customer_idx
  on public.company_subscriptions (stripe_customer_id)
  where stripe_customer_id is not null;

-- WHICH COMPANY MAY THIS CALLER ASK ABOUT?
--
-- Several helpers below take an optional company id, so the service role can
-- ask about a company it is not signed in as. Left unchecked, that same
-- parameter is a tenancy hole: these functions are SECURITY DEFINER, RLS does
-- not apply inside them, and any signed-in user could pass somebody else's
-- company id and read across the boundary. Every such parameter goes through
-- here first:
--
--   nothing passed     -> the caller's own company
--   service role       -> whatever it asked for; it has no company of its own
--   own company passed -> allowed
--   another company    -> NULL, and every caller treats NULL as "no company",
--                         returning zero/false rather than another tenant's data
--
-- push_caller_is_service_role() is Phase 1's existing service-role test. This
-- does not introduce a second one.
create or replace function public.commerce_company_scope(p_company uuid default null)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p_company is null                        then public.current_company_id()
    when public.push_caller_is_service_role()     then p_company
    when p_company = public.current_company_id()  then p_company
    else null
  end;
$$;

-- How many people the company is actually paying for.
--
-- Only 'active' counts. An invited user has not accepted and a suspended user
-- cannot sign in, so neither is a paid seat — that is the whole rule, in one
-- place, server-side.
--
-- Split in two: the _for variant is the implementation and takes the company as
-- given, for use inside other SECURITY DEFINER functions that have already
-- established which company they are working on. It is granted to nobody. The
-- public entry point below is the one the app calls, and it is scoped.
create or replace function public.company_active_paid_users_for(p_company uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::integer
  from public.app_users u
  where u.company_id = p_company
    and u.status = 'active';
$$;

create or replace function public.company_active_paid_users(p_company uuid default null)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select public.company_active_paid_users_for(public.commerce_company_scope(p_company));
$$;

-- The authoritative price calculation. The iOS app renders what this returns
-- and never computes a total of its own.
--
-- Flat additional-user rate chosen by the total head count. Explicitly NOT
-- progressive: there is exactly one rate in play for any given company.
create or replace function public.subscription_quote(p_users integer default null)
returns table (
  active_paid_users      integer,
  tier_id                text,
  tier_name              text,
  base_cents             integer,
  additional_users       integer,
  additional_user_cents  integer,
  additional_cents       integer,
  monthly_price_cents    integer,
  max_users              integer,
  is_over_capacity       boolean,
  next_user_cents        integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_users   integer;
  v_max     integer;
  v_tier    public.subscription_tiers%rowtype;
  v_next    public.subscription_tiers%rowtype;
  v_addl    integer;
begin
  v_users := greatest(coalesce(p_users, public.company_active_paid_users()), 1);

  select (value #>> '{}')::integer into v_max
  from public.platform_settings where key = 'subscription_max_users';
  v_max := coalesce(v_max, 100);

  -- Clamp tier lookup to the supported band so a company that has somehow
  -- exceeded the ceiling still gets a truthful price rather than nothing.
  select * into v_tier
  from public.subscription_tiers
  where is_active and least(v_users, v_max) between min_users and max_users
  order by sort_order
  limit 1;

  if not found then
    select * into v_tier from public.subscription_tiers
    where is_active order by sort_order desc limit 1;
  end if;

  v_addl := greatest(v_users - 1, 0);

  -- The rate for the seat *after* this one, which may sit in the next tier and
  -- is what the "add a user" price in the app must show.
  select * into v_next
  from public.subscription_tiers
  where is_active and least(v_users + 1, v_max) between min_users and max_users
  order by sort_order
  limit 1;

  active_paid_users     := v_users;
  tier_id               := v_tier.id;
  tier_name             := v_tier.display_name;
  base_cents            := v_tier.base_cents;
  additional_users      := v_addl;
  additional_user_cents := v_tier.additional_user_cents;
  additional_cents      := v_addl * v_tier.additional_user_cents;
  monthly_price_cents   := v_tier.base_cents + (v_addl * v_tier.additional_user_cents);
  max_users             := v_max;
  is_over_capacity      := v_users > v_max;
  -- Price of the next seat = new total minus current total, so a tier change
  -- shows its true (possibly negative) marginal cost rather than a sticker rate.
  next_user_cents       := case
                             when v_users >= v_max then null
                             else (v_next.base_cents + (v_users * v_next.additional_user_cents))
                                  - (v_tier.base_cents + (v_addl * v_tier.additional_user_cents))
                           end;
  return next;
end $$;

-- Recomputes and stores the company's seat count and price. Called by the
-- subscription Edge Function after any change to the roster, and by the Stripe
-- webhook after a billing event.
create or replace function public.sync_subscription_seats(p_company uuid default null)
returns table (
  active_paid_users    integer,
  tier_id              text,
  monthly_price_cents  integer
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_company uuid := coalesce(p_company, public.current_company_id());
  v_q       record;
  v_updated integer;
begin
  if v_company is null then
    raise exception 'No company in context';
  end if;

  -- _for, not the scoped entry point: the company is already established from
  -- the argument or the caller's own context, and this runs as the service role
  -- from the webhook, which has no company of its own.
  select * into v_q from public.subscription_quote(public.company_active_paid_users_for(v_company));

  update public.company_subscriptions s
  set seat_count            = v_q.active_paid_users,
      active_paid_users     = v_q.active_paid_users,
      included_users        = 1,
      additional_users      = v_q.additional_users,
      tier_id               = v_q.tier_id,
      base_cents            = v_q.base_cents,
      additional_user_cents = v_q.additional_user_cents,
      monthly_price_cents   = v_q.monthly_price_cents,
      seats_synced_at       = now(),
      updated_at            = now()
  where s.company_id = v_company;

  -- An UPDATE that matches nothing is not an error in SQL, so without this the
  -- function returned a freshly computed seat count and price that were stored
  -- NOWHERE, and the Stripe webhook would read that as a successful sync. The
  -- company would then be billed against whatever the subscription row last
  -- said, with no signal that the roster had moved.
  --
  -- The row is NOT created here. company_subscriptions is one row per company
  -- (company_id is unique, per the one-to-one foreign key to companies) and it
  -- is Phase 1 that owns creating it; inventing one would fabricate a billing
  -- relationship, complete with a default 19.99 price, for a company that may
  -- never have subscribed. Failing is the honest outcome, and the only caller
  -- is the Stripe webhook under the service role.
  get diagnostics v_updated = row_count;

  if v_updated = 0 then
    raise exception 'No subscription row for company %; seats were not synced', v_company
      using errcode = 'no_data_found';
  end if;

  active_paid_users   := v_q.active_paid_users;
  tier_id             := v_q.tier_id;
  monthly_price_cents := v_q.monthly_price_cents;
  return next;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Stripe Connect — the trade business's own account
-- -----------------------------------------------------------------------------
-- Customer money belongs to the trade business and lands in the trade
-- business's own Stripe account. Harbour South is never the merchant of record
-- for a customer invoice; it takes a configurable application fee and nothing
-- else. This table is the link, and it is deliberately one row per company.
create table if not exists public.stripe_connect_accounts (
  company_id           uuid primary key references public.companies(id) on delete cascade,
  stripe_account_id    text not null unique,
  charges_enabled      boolean not null default false,
  payouts_enabled      boolean not null default false,
  details_submitted    boolean not null default false,
  requirements_due     text[] not null default '{}',
  disabled_reason      text,
  country_code         text not null default 'US',
  default_currency     text not null default 'usd',
  onboarded_at         timestamptz,
  last_synced_at       timestamptz not null default now(),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

create index if not exists stripe_connect_accounts_account_idx
  on public.stripe_connect_accounts (stripe_account_id);

alter table public.stripe_connect_accounts enable row level security;

-- Readable by anyone who may see the company's money; writable by nobody from
-- the app. Every mutation happens in the Edge Function under the service role
-- after Stripe itself has confirmed the account state.
drop policy if exists "connect account readable by billing roles" on public.stripe_connect_accounts;
create policy "connect account readable by billing roles"
  on public.stripe_connect_accounts for select to authenticated
  using (
    company_id = public.current_company_id()
    and (public.has_perm('paymentsRead') or public.has_perm('saasBillingRead'))
  );

-- Is this company able to take a customer card payment right now?
create or replace function public.company_can_accept_payments(p_company uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select charges_enabled
     from public.stripe_connect_accounts
     where company_id = public.commerce_company_scope(p_company)),
    false);
$$;

-- -----------------------------------------------------------------------------
-- 4. Payments: the Stripe split
-- -----------------------------------------------------------------------------
-- Phase 1's payments table records that money arrived. It has nowhere to record
-- WHERE it arrived from or how it was divided, and the three fees involved are
-- routinely confused, so each gets its own column and its own meaning:
--
--   amount               what the customer paid (gross)
--   processing_fee_cents Stripe's fee, charged to the connected account
--   application_fee_cents Harbour South's fee — NOT Stripe's
--   net_cents            what the trade business actually keeps
alter table public.payments
  add column if not exists stripe_payment_intent_id text,
  add column if not exists stripe_charge_id         text,
  add column if not exists stripe_account_id        text,
  add column if not exists application_fee_cents    integer,
  add column if not exists processing_fee_cents     integer,
  add column if not exists net_cents                integer,
  add column if not exists currency_code            text,
  add column if not exists failure_reason           text,
  add column if not exists paid_by_customer         boolean not null default false;

-- WHO RECORDED A STRIPE PAYMENT? Nobody did.
--
-- Phase 1 made recorded_by_user_id NOT NULL because every payment it knew about
-- was typed in by a person. A customer card payment has no person: the customer
-- is not a Supabase user, and the office user who raised the invoice is not the
-- one who took the money.
--
-- There is no system identity in app_users to point at instead. The roster is
-- owner / admin / dispatcher / fieldWorker / accounts — all real people who sign
-- in — and a synthetic "system" user would be a row that can be assigned jobs,
-- counted as an active paid seat by company_active_paid_users(), and shown in
-- pickers. That is a worse lie than a NULL.
--
-- So the column becomes nullable and NULL carries exactly one meaning: recorded
-- by the system from a verified provider webhook, never by a user.
-- paid_by_customer = true and a non-null stripe_payment_intent_id say the same
-- thing from the other direction.
--
-- What this does NOT change:
--   * manual recording still names the user — Phase 1's record_payment() passes
--     the authenticated user, and the insert policy on payments still governs
--     what any user may write;
--   * tenancy — company_id is still NOT NULL and is still what every policy
--     filters on, so no row becomes reachable to anyone new;
--   * existing rows — dropping NOT NULL rewrites no data and invalidates no
--     foreign key. The FK to app_users survives; NULL simply does not reference.
alter table public.payments alter column recorded_by_user_id drop not null;

-- The idempotency spine for customer payments. One Stripe PaymentIntent can
-- produce at most one payment row, no matter how many times its webhook is
-- delivered or the client retries.
create unique index if not exists payments_stripe_intent_idx
  on public.payments (stripe_payment_intent_id)
  where stripe_payment_intent_id is not null;

-- A pending intent recorded before the customer has paid. Nothing here marks an
-- invoice paid; only the webhook does that.
create table if not exists public.payment_intents (
  id                        uuid primary key default gen_random_uuid(),
  company_id                uuid not null references public.companies(id) on delete cascade,
  invoice_id                uuid not null references public.invoices(id) on delete cascade,
  stripe_payment_intent_id  text not null unique,
  stripe_account_id         text not null,
  amount_cents              integer not null check (amount_cents > 0),
  currency_code             text not null default 'usd',
  application_fee_cents     integer not null default 0,
  status                    text not null default 'requires_payment_method',
  client_secret_issued_at   timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index if not exists payment_intents_invoice_idx on public.payment_intents (invoice_id);
create index if not exists payment_intents_company_idx on public.payment_intents (company_id);

alter table public.payment_intents enable row level security;

drop policy if exists "payment intents readable with payments" on public.payment_intents;
create policy "payment intents readable with payments"
  on public.payment_intents for select to authenticated
  using (company_id = public.current_company_id() and public.has_perm('paymentsRead'));

-- Records a Stripe customer payment and re-derives the invoice.
--
-- Runs as the service role from the webhook, because the customer who paid has
-- no Supabase identity and the office user who raised the invoice is asleep.
--
-- IDEMPOTENT BY CONSTRUCTION: the unique index on stripe_payment_intent_id is
-- the arbiter. A replayed webhook takes the `already recorded` branch and
-- leaves the invoice exactly as it was, so a duplicate delivery can never pay
-- an invoice twice or drive a balance negative.
create or replace function public.record_payment_from_stripe(
  p_invoice               uuid,
  p_company               uuid,
  p_amount_cents          integer,
  p_intent                text,
  p_charge                text default null,
  p_account               text default null,
  p_application_fee_cents integer default 0,
  p_processing_fee_cents  integer default null,
  p_net_cents             integer default null,
  p_currency              text default 'usd'
)
returns table (outcome text, amount_paid numeric, balance numeric, status text)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_amount   numeric := p_amount_cents::numeric / 100;
  v_invoice  public.invoices%rowtype;
  v_paid     numeric;
  v_balance  numeric;
  v_status   public.invoice_status;
begin
  -- Claim the intent first. A duplicate loses here and changes nothing.
  --
  -- recorded_by_user_id is deliberately NULL: see the ALTER above. It is the
  -- honest value, not a placeholder.
  begin
    insert into public.payments (
      company_id, invoice_id, amount, method, status,
      stripe_payment_intent_id, stripe_charge_id, stripe_account_id,
      application_fee_cents, processing_fee_cents, net_cents, currency_code,
      paid_by_customer, is_simulated, received_at, recorded_by_user_id, reference
    ) values (
      p_company, p_invoice, v_amount, 'stripe', 'succeeded',
      p_intent, p_charge, p_account,
      p_application_fee_cents, p_processing_fee_cents, p_net_cents, p_currency,
      true, false, now(), null, p_intent
    );
  exception when unique_violation then
    select i.amount_paid, i.balance, i.status into v_paid, v_balance, v_status
    from public.invoices i where i.id = p_invoice;
    outcome := 'alreadyRecorded'; amount_paid := v_paid;
    balance := v_balance; status := v_status::text;
    return next; return;
  end;

  select * into v_invoice from public.invoices where id = p_invoice for update;

  -- Re-derive from the payments table rather than incrementing a counter, so a
  -- lost or replayed row cannot drift the balance.
  select coalesce(sum(p.amount), 0) into v_paid
  from public.payments p
  where p.invoice_id = p_invoice and p.status = 'succeeded';

  v_balance := greatest(v_invoice.total - v_paid, 0);

  v_status := case
    when v_invoice.status = 'void' then v_invoice.status
    when v_balance <= 0 then 'paid'::public.invoice_status
    when v_paid > 0 then 'partPaid'::public.invoice_status
    else v_invoice.status
  end;

  update public.invoices
  set amount_paid = v_paid,
      balance     = v_balance,
      status      = v_status,
      paid_at     = case when v_balance <= 0 then coalesce(paid_at, now()) else null end,
      updated_at  = now()
  where id = p_invoice;

  outcome := 'recorded'; amount_paid := v_paid;
  balance := v_balance; status := v_status::text;
  return next;
end $$;

-- -----------------------------------------------------------------------------
-- 5. Provider event idempotency
-- -----------------------------------------------------------------------------
-- Stripe and Twilio both retry. Both retry the *same* event id. Recording the
-- id before doing the work, with a primary key doing the arbitration, is what
-- makes a duplicate delivery a no-op instead of a second payment.
create table if not exists public.stripe_events (
  id             text primary key,
  type           text not null,
  account_id     text,
  company_id     uuid references public.companies(id) on delete set null,
  livemode       boolean not null default false,
  received_at    timestamptz not null default now(),
  processed_at   timestamptz,
  outcome        text,
  error_detail   text
);

create index if not exists stripe_events_company_idx on public.stripe_events (company_id);
create index if not exists stripe_events_type_idx on public.stripe_events (type);

alter table public.stripe_events enable row level security;
-- No `authenticated` policy: the provider event log belongs to the server.

-- -----------------------------------------------------------------------------
-- 6. SMS
-- -----------------------------------------------------------------------------

-- 6a. A credit purchase. Separate from the SaaS subscription in every respect:
--     different Stripe object, different money, different ledger.
create table if not exists public.sms_credit_purchases (
  id                        uuid primary key default gen_random_uuid(),
  company_id                uuid not null references public.companies(id) on delete cascade,
  bundle_id                 text references public.sms_bundles(id),
  credits                   integer not null check (credits > 0),
  price_cents               integer not null check (price_cents >= 0),
  currency_code             text not null default 'usd',
  status                    text not null default 'pending',
  stripe_payment_intent_id  text unique,
  stripe_checkout_session_id text unique,
  credited_at               timestamptz,
  requested_by_user_id      uuid references public.app_users(id),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now()
);

create index if not exists sms_credit_purchases_company_idx on public.sms_credit_purchases (company_id);

alter table public.sms_credit_purchases enable row level security;

drop policy if exists "sms purchases readable within the company" on public.sms_credit_purchases;
create policy "sms purchases readable within the company"
  on public.sms_credit_purchases for select to authenticated
  using (company_id = public.current_company_id() and public.has_perm('smsLedgerRead'));

-- 6b. Twilio detail on the delivery ledger. Phase 1's notifications table
--     already carries provider_reference; what it lacks is the number of
--     credits a message cost, without which a refund is a guess.
alter table public.notifications
  add column if not exists credits_charged   integer not null default 0,
  add column if not exists credits_refunded  integer not null default 0,
  add column if not exists provider_status   text,
  add column if not exists provider_error    text,
  add column if not exists to_number         text,
  add column if not exists from_number       text,
  add column if not exists segments          integer,
  add column if not exists updated_at        timestamptz not null default now();

-- Twilio status callbacks are keyed by MessageSid and are retried. One SID must
-- resolve to exactly one notification row.
create unique index if not exists notifications_provider_reference_idx
  on public.notifications (provider_reference)
  where provider_reference is not null;

-- 6c. The balance, derived from the ledger rather than stored as a mutable
--     integer, so the history is the truth.
--     Split the same way as the seat count: _for is the implementation used by
--     the locked credit paths below, which have already established the
--     company; the public entry point is scoped so a caller cannot read another
--     tenant's balance by passing its id.
create or replace function public.sms_credit_balance_for(p_company uuid)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(sum(amount), 0)::integer
  from public.sms_credit_ledger
  where company_id = p_company;
$$;

create or replace function public.sms_credit_balance(p_company uuid default null)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select public.sms_credit_balance_for(public.commerce_company_scope(p_company));
$$;

-- 6d. Race-free consumption for a customer message.
--
-- THE RULE THIS ENFORCES: a company with one credit and two simultaneous send
-- requests sends exactly one message — whichever paths those two requests take.
--
-- THE ONE SERIALISATION POINT. Every function that reads or changes a company's
-- SMS credit balance takes the SAME lock, a row lock on that company's row in
-- public.companies:
--
--     perform 1 from public.companies where id = v_company for update;
--
-- That is: Phase 1's queue_invoice_notification (which already locks this row),
-- and consume_sms_credit / refund_sms_credit / credit_sms_purchase below.
--
-- An earlier draft of this file used pg_advisory_xact_lock() here instead.
-- Advisory locks and row locks live in different lock spaces and do not block
-- each other at all, so a manual customer SMS could run concurrently with an
-- invoice SMS, both read a balance of 1, and both spend it — each writing
-- balance_after = 0, so even the ledger's balance_after >= 0 CHECK would not
-- catch it. The advisory mechanism has been removed rather than kept alongside
-- the row lock; two locking systems that ignore each other are worse than one.
--
-- The lock is held to the end of the transaction, so the balance read and the
-- ledger insert cannot interleave with another consumer. Every balance read and
-- every ledger write below therefore happens AFTER the lock is acquired, and a
-- caller that loses the race sees the post-lock balance, not the stale one.
-- Different companies lock different rows and never block each other.
--
-- Returns the outcome rather than raising, so the Edge Function can report
-- "insufficient credits" as a clean business answer instead of a 500.
create or replace function public.consume_sms_credit(
  p_notification uuid,
  p_credits      integer default null,
  p_customer     uuid default null,
  p_job          uuid default null
)
returns table (
  outcome        text,
  credits_charged integer,
  balance_after  integer
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_company uuid := public.current_company_id();
  v_cost    integer;
  v_balance integer;
begin
  if v_company is null then
    raise exception 'No company in context';
  end if;

  if not public.has_perm('smsCreditsConsume') then
    outcome := 'notPermitted'; credits_charged := 0; balance_after := null;
    return next; return;
  end if;

  -- Serialise every consumer of THIS company's balance, including Phase 1's
  -- queue_invoice_notification, which locks this same row. Nothing below this
  -- line reads or writes the balance until the lock is held.
  perform 1
  from public.companies
  where id = v_company
  for update;

  if not found then
    -- No row means no lock was taken, and an unserialised debit is precisely
    -- how one credit gets spent twice. Refuse instead of proceeding unlocked.
    raise exception 'Company % not found; refusing to spend SMS credit unserialised', v_company;
  end if;

  select coalesce(p_credits,
                  (select (value #>> '{}')::integer from public.platform_settings
                    where key = 'sms_credits_per_message'),
                  1)
    into v_cost;

  if v_cost <= 0 then
    outcome := 'invalidCost'; credits_charged := 0;
    balance_after := public.sms_credit_balance_for(v_company);
    return next; return;
  end if;

  v_balance := public.sms_credit_balance_for(v_company);

  if v_balance < v_cost then
    -- Not an error, and emphatically not a send. Balance untouched.
    outcome := 'insufficientCredits'; credits_charged := 0; balance_after := v_balance;
    return next; return;
  end if;

  -- The notification must belong to this company. Cross-company message ids are
  -- refused here as well as by RLS.
  if p_notification is not null and not exists (
    select 1 from public.notifications
    where id = p_notification and company_id = v_company
  ) then
    outcome := 'unknownMessage'; credits_charged := 0; balance_after := v_balance;
    return next; return;
  end if;

  -- Same rule for the customer the message is about.
  if p_customer is not null and not exists (
    select 1 from public.customers where id = p_customer and company_id = v_company
  ) then
    outcome := 'unknownCustomer'; credits_charged := 0; balance_after := v_balance;
    return next; return;
  end if;

  v_balance := v_balance - v_cost;

  insert into public.sms_credit_ledger
    (company_id, transaction_type, amount, balance_after, customer_id, job_id, notification_id)
  values
    (v_company, 'consumption', -v_cost, v_balance, p_customer, p_job, p_notification);

  update public.notifications
  set credits_charged = v_cost, updated_at = now()
  where id = p_notification;

  outcome := 'consumed'; credits_charged := v_cost; balance_after := v_balance;
  return next;
end $$;

-- 6e. Refund a charge for a message the provider never delivered. Idempotent:
--     a message already refunded is left alone, so a retried status callback
--     cannot credit twice.
create or replace function public.refund_sms_credit(p_notification uuid, p_reason text default null)
returns table (outcome text, credits_refunded integer, balance_after integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_company  uuid;
  v_charged  integer;
  v_refunded integer;
  v_balance  integer;
begin
  -- First read is only to learn which company row to lock. Nothing is decided
  -- on it.
  select company_id into v_company
  from public.notifications where id = p_notification;

  if v_company is null then
    outcome := 'unknownMessage'; credits_refunded := 0; balance_after := null;
    return next; return;
  end if;

  -- The single serialisation point (section 6d): the same row that
  -- queue_invoice_notification and consume_sms_credit lock.
  perform 1
  from public.companies
  where id = v_company
  for update;

  if not found then
    raise exception 'Company % not found; refusing to refund SMS credit unserialised', v_company;
  end if;

  -- Re-read the charge state AFTER the lock. Read committed gives this
  -- statement a fresh snapshot, so a refund that committed while we were
  -- waiting is visible here — which is what makes the idempotency check below
  -- hold under two simultaneous status callbacks for the same message.
  select credits_charged, credits_refunded
    into v_charged, v_refunded
  from public.notifications where id = p_notification;

  if coalesce(v_charged, 0) <= 0 or coalesce(v_refunded, 0) > 0 then
    outcome := 'nothingToRefund'; credits_refunded := 0;
    balance_after := public.sms_credit_balance_for(v_company);
    return next; return;
  end if;

  v_balance := public.sms_credit_balance_for(v_company) + v_charged;

  insert into public.sms_credit_ledger
    (company_id, transaction_type, amount, balance_after, notification_id, purchase_reference)
  values
    (v_company, 'refund', v_charged, v_balance, p_notification, p_reason);

  update public.notifications
  set credits_refunded = v_charged, updated_at = now()
  where id = p_notification;

  outcome := 'refunded'; credits_refunded := v_charged; balance_after := v_balance;
  return next;
end $$;

-- 6f. Credit a completed purchase. Idempotent on the purchase row: a replayed
--     Stripe webhook finds the purchase already credited and does nothing.
create or replace function public.credit_sms_purchase(p_purchase uuid)
returns table (outcome text, credits_added integer, balance_after integer)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_credits integer;
  v_done    timestamptz;
  v_balance integer;
begin
  -- Unlocked read, only to learn which company row to lock.
  select company_id into v_company
  from public.sms_credit_purchases where id = p_purchase;

  if v_company is null then
    outcome := 'unknownPurchase'; credits_added := 0; balance_after := null;
    return next; return;
  end if;

  -- The single serialisation point (section 6d), taken BEFORE the purchase row
  -- lock. Every SMS-credit path acquires the companies row first and only then
  -- any narrower row, so the lock order is the same everywhere and two of these
  -- functions cannot deadlock against each other.
  perform 1
  from public.companies
  where id = v_company
  for update;

  if not found then
    raise exception 'Company % not found; refusing to credit SMS purchase unserialised', v_company;
  end if;

  -- Now claim the purchase itself. Re-read under FOR UPDATE after the company
  -- lock: a replayed webhook that was waiting on either lock sees the
  -- credited_at written by the winner and takes the no-op branch below.
  select credits, credited_at
    into v_credits, v_done
  from public.sms_credit_purchases where id = p_purchase
  for update;

  if v_done is not null then
    outcome := 'alreadyCredited'; credits_added := 0;
    balance_after := public.sms_credit_balance_for(v_company);
    return next; return;
  end if;

  v_balance := public.sms_credit_balance_for(v_company) + v_credits;

  insert into public.sms_credit_ledger
    (company_id, transaction_type, amount, balance_after, purchase_reference)
  values
    (v_company, 'purchase', v_credits, v_balance, p_purchase::text);

  update public.sms_credit_purchases
  set status = 'completed', credited_at = now(), updated_at = now()
  where id = p_purchase;

  outcome := 'credited'; credits_added := v_credits; balance_after := v_balance;
  return next;
end $$;

-- -----------------------------------------------------------------------------
-- 7. Payment terms
-- -----------------------------------------------------------------------------
-- Phase 1 stores a free-text payment_terms_label on the invoice and resolves it
-- with payment_terms_days(). What it has no room for is the company's own
-- default, so every invoice had to restate one.
alter table public.companies
  add column if not exists default_payment_terms_label text not null default 'Due in 30 days',
  add column if not exists default_payment_terms_days  integer not null default 30;

-- "Due on completion" is a rule, not a number of days: the due date is the day
-- the work finished, not a horizon from the invoice date. Encoding it as 0 days
-- only works because the caller passes the completion date as the reference.
-- STABLE, not IMMUTABLE. IMMUTABLE is a promise that the result depends on
-- nothing but the arguments, and this function's result is whatever
-- payment_terms_days() returns. That function belongs to Phase 1 and its body
-- is not in this repository, so the promise cannot be made: if it reads a table
-- (a company default, a terms lookup) the result depends on database state.
-- PostgreSQL does not verify the claim — it trusts it, and constant-folds
-- IMMUTABLE calls into cached plans and index expressions, which is how a due
-- date silently freezes at a stale value. STABLE is accurate either way: an
-- immutable dependency trivially satisfies it, and a table-reading one is
-- exactly what it describes. Nothing about the calculation changes.
create or replace function public.resolve_due_date(
  p_label     text,
  p_reference date default current_date
)
returns date
language sql
stable
set search_path = public
as $$
  select case
    when p_label ilike '%completion%' then p_reference
    else p_reference + (public.payment_terms_days(p_label) || ' days')::interval
  end::date;
$$;

-- -----------------------------------------------------------------------------
-- 8. Recurring service
-- -----------------------------------------------------------------------------
-- service_agreements exists from Phase 1 with customer, site, asset, frequency
-- and next_due_date. What it cannot do is generate a job, or say what it last
-- generated — so nothing stopped two runs producing two identical visits.
alter table public.service_agreements
  add column if not exists last_generated_job_id  uuid references public.jobs(id) on delete set null,
  add column if not exists last_generated_on      date,
  add column if not exists interval_days          integer,
  add column if not exists lead_time_days         integer not null default 14,
  add column if not exists notes                  text,
  add column if not exists template_description   text not null default '';

alter table public.jobs
  add column if not exists service_agreement_id uuid references public.service_agreements(id) on delete set null,
  add column if not exists generated_for_date   date;

-- THE ANTI-DUPLICATE RULE. One agreement produces at most one job per due date,
-- enforced by the database rather than by the generator remembering. A second
-- generation run, a retry, or two schedulers racing all collide here.
create unique index if not exists jobs_recurring_period_idx
  on public.jobs (service_agreement_id, generated_for_date)
  where service_agreement_id is not null and generated_for_date is not null;

create index if not exists service_agreements_due_idx
  on public.service_agreements (next_due_date) where is_active;

-- Advance a frequency by one period.
create or replace function public.next_service_date(
  p_from      date,
  p_frequency public.service_frequency,
  p_interval  integer default null
)
returns date
language sql
immutable
set search_path = public
as $$
  select case p_frequency::text
    when 'monthly'    then p_from + interval '1 month'
    when 'quarterly'  then p_from + interval '3 months'
    when 'semiAnnual' then p_from + interval '6 months'
    when 'annual'     then p_from + interval '1 year'
    when 'custom'     then p_from + (greatest(coalesce(p_interval, 30), 1) || ' days')::interval
    else p_from + interval '1 month'
  end::date;
$$;

-- The company-scoped twin of Phase 1's next_document_number(document_kind).
--
-- NOT a second numbering system. It allocates from the SAME
-- public.document_sequences row, under the same row lock, and formats the
-- number from that row's own prefix and pad_width. It exists for one reason:
-- Phase 1's function derives the company from current_company_id(), and a
-- scheduled generation run has no JWT and no single company — it walks every
-- company with work due. Calling the one-argument function from that loop would
-- resolve to NULL and allocate from nobody's sequence, which is exactly the
-- cross-company hazard this avoids: the company is passed explicitly, taken
-- from the service agreement's own row, and can never be another tenant's.
create or replace function public.next_document_number_for_company(
  p_company uuid,
  p_kind    public.document_kind
)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_rows   integer;
  v_prefix text;
  v_pad    integer;
  v_value  integer;
begin
  if p_company is null then
    raise exception 'next_document_number_for_company requires an explicit company';
  end if;

  -- Two sequence rows for one (company, kind) would hand the same number out
  -- twice. Refuse rather than pick one arbitrarily.
  select count(*) into v_rows
  from public.document_sequences
  where company_id = p_company and kind = p_kind;

  if v_rows > 1 then
    raise exception 'Company % has % "%" document sequences; expected exactly one',
      p_company, v_rows, p_kind;
  end if;

  if v_rows = 0 then
    -- Create the row from the TABLE's own defaults for prefix, pad_width and
    -- next_value. No format and no starting number is invented here.
    begin
      insert into public.document_sequences (company_id, kind) values (p_company, p_kind);
    exception when unique_violation then
      null;  -- another transaction created it first; the UPDATE below finds it
    end;
  end if;

  -- The UPDATE takes the row lock, so two concurrent allocations for the same
  -- company queue here and receive consecutive numbers. next_value is the value
  -- to use next, so the number allocated is the pre-increment value.
  update public.document_sequences
  set next_value = next_value + 1,
      updated_at = now()
  where company_id = p_company and kind = p_kind
  returning prefix, pad_width, next_value - 1
  into v_prefix, v_pad, v_value;

  if v_value is null then
    raise exception 'No "%" document sequence for company %', p_kind, p_company;
  end if;

  -- Formatting mirrors the app's own DocumentSequence.format(_:) exactly:
  --   pad_width > 0  -> zero-pad to that width
  --   pad_width = 0  -> no padding at all (the model's default)
  -- lpad() TRUNCATES when the target width is shorter than the string, so a
  -- pad_width of 0 or 3 would silently turn 1050 into '' or '105'. Widening to
  -- length(v_value) when the number has outgrown the pad width makes that
  -- impossible: a number is never shortened to fit its own padding.
  return v_prefix || case
    when coalesce(v_pad, 0) > 0
      then lpad(v_value::text, greatest(v_pad, length(v_value::text)), '0')
    else v_value::text
  end;
end $$;

-- Generates the jobs that are due, for one company or for all of them.
--
-- Runs as the service role from a scheduled Edge Function, so recurring work
-- appears whether or not anybody has opened the app — the phone is not the
-- scheduler. `on conflict do nothing` against the unique index above is what
-- makes a second run in the same window a no-op.
create or replace function public.generate_due_recurring_jobs(
  p_company uuid default null,
  p_horizon_days integer default 0
)
returns table (
  service_agreement_id uuid,
  job_id               uuid,
  scheduled_for        date,
  outcome              text
)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r          record;
  v_job      uuid;
  v_number   text;
  v_horizon  date := current_date + (greatest(coalesce(p_horizon_days, 0), 0) || ' days')::interval;
begin
  for r in
    select a.*, c.time_zone_identifier
    from public.service_agreements a
    join public.companies c on c.id = a.company_id
    where a.is_active
      and a.next_due_date <= v_horizon::date
      and (p_company is null or a.company_id = p_company)
    order by a.next_due_date
  loop
    v_job := null;
    v_number := null;

    -- Already generated for this period by an earlier run. Checked BEFORE a
    -- number is allocated: the unique index would swallow the insert, but it
    -- would not give the number back, and every no-op run would leave a gap in
    -- the company's job numbering. Advance anyway so the agreement does not get
    -- stuck retrying the same period forever.
    if exists (
      select 1 from public.jobs
      where service_agreement_id = r.id
        and generated_for_date   = r.next_due_date
    ) then
      update public.service_agreements
      set next_due_date = public.next_service_date(next_due_date, frequency, interval_days),
          updated_at = now()
      where id = r.id;

      service_agreement_id := r.id; job_id := null;
      scheduled_for := r.next_due_date; outcome := 'alreadyGenerated';
      return next;
      continue;
    end if;

    -- A job number still comes from the company's own sequence, so recurring
    -- work is numbered indistinguishably from work booked by hand. jobs.number
    -- is NOT NULL with no default: without this the insert below cannot succeed
    -- at all, and every agreement would report 'failed: null value in column
    -- "number"' forever.
    begin
      v_number := public.next_document_number_for_company(r.company_id, 'job');

      insert into public.jobs (
        company_id, number, customer_id, address_id, equipment_id,
        title, job_description, kind, priority, status,
        scheduled_start, scheduled_end,
        service_agreement_id, generated_for_date
      )
      values (
        r.company_id, v_number, r.customer_id, r.address_id, r.equipment_id,
        coalesce(nullif(r.template_title, ''), 'Scheduled service'),
        coalesce(r.template_description, ''),
        r.template_job_kind, 'standard', 'scheduled',
        (r.next_due_date::timestamp at time zone coalesce(r.time_zone_identifier, 'UTC')) + interval '9 hours',
        (r.next_due_date::timestamp at time zone coalesce(r.time_zone_identifier, 'UTC')) + interval '11 hours',
        r.id, r.next_due_date
      )
      -- The WHERE repeats jobs_recurring_period_idx's predicate verbatim, and is
      -- NOT optional. That index is PARTIAL, and PostgreSQL will only infer a
      -- partial index as the ON CONFLICT arbiter when the statement restates
      -- its predicate. Without it every insert here raises 42P10, 'there is no
      -- unique or exclusion constraint matching the ON CONFLICT specification'
      -- — which the handler below would have turned into a 'failed:' row, so
      -- recurring generation would have reported itself as running while never
      -- creating a single job.
      on conflict (service_agreement_id, generated_for_date)
        where service_agreement_id is not null and generated_for_date is not null
      do nothing
      returning id into v_job;
    exception when others then
      service_agreement_id := r.id; job_id := null;
      scheduled_for := r.next_due_date; outcome := 'failed: ' || sqlerrm;
      return next;
      continue;
    end;

    if v_job is null then
      -- Lost a race: a concurrent run generated this same period between the
      -- check above and the insert. The unique index arbitrated correctly and
      -- one number is spent for nothing — a gap, never a duplicate visit.
      update public.service_agreements
      set next_due_date = public.next_service_date(next_due_date, frequency, interval_days),
          updated_at = now()
      where id = r.id;

      service_agreement_id := r.id; job_id := null;
      scheduled_for := r.next_due_date; outcome := 'alreadyGenerated';
      return next;
      continue;
    end if;

    update public.service_agreements
    set last_generated_job_id = v_job,
        last_generated_on     = r.next_due_date,
        next_due_date         = public.next_service_date(r.next_due_date, r.frequency, r.interval_days),
        updated_at            = now()
    where id = r.id;

    service_agreement_id := r.id; job_id := v_job;
    scheduled_for := r.next_due_date; outcome := 'generated';
    return next;
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 9. EXECUTE privileges
-- -----------------------------------------------------------------------------
-- WHY THIS SECTION WAS REWRITTEN.
--
-- PostgreSQL grants EXECUTE on a newly created function to PUBLIC by default,
-- and every function in this file is SECURITY DEFINER. An earlier draft of this
-- section revoked from `authenticated` and `anon` — which removes an explicit
-- grant those roles never had, and leaves the inherited PUBLIC grant completely
-- intact. The privileged functions therefore stayed callable by anyone holding
-- any JWT, by name, over PostgREST:
--
--   record_payment_from_stripe(p_invoice, p_company, ...) — both ids are
--     arguments, so any signed-in user could mark ANY company's invoice paid;
--   credit_sms_purchase(p_purchase)  — grant credits without paying;
--   generate_due_recurring_jobs(null) — write jobs into EVERY company;
--   sync_subscription_seats(p_company) — rewrite another company's billed seats.
--
-- The model below is: revoke the PUBLIC default on everything this migration
-- defines, then grant to the one role that has a reason to call it. Nothing is
-- granted to `anon`. Nothing is granted "just in case".
--
-- Note that revoking from PUBLIC does not affect calls made from INSIDE another
-- SECURITY DEFINER function: those execute with the definer's rights, and the
-- definer (the role applying this migration) owns these functions.

-- 9a. Remove the default PUBLIC grant from every function defined above.
revoke execute on function public.commerce_company_scope(uuid)                              from public;
revoke execute on function public.company_active_paid_users_for(uuid)                       from public;
revoke execute on function public.company_active_paid_users(uuid)                           from public;
revoke execute on function public.subscription_quote(integer)                               from public;
revoke execute on function public.sync_subscription_seats(uuid)                             from public;
revoke execute on function public.company_can_accept_payments(uuid)                         from public;
revoke execute on function public.sms_credit_balance_for(uuid)                              from public;
revoke execute on function public.sms_credit_balance(uuid)                                  from public;
revoke execute on function public.consume_sms_credit(uuid, integer, uuid, uuid)             from public;
revoke execute on function public.refund_sms_credit(uuid, text)                             from public;
revoke execute on function public.credit_sms_purchase(uuid)                                 from public;
revoke execute on function public.resolve_due_date(text, date)                              from public;
revoke execute on function public.next_service_date(date, public.service_frequency, integer) from public;
revoke execute on function public.next_document_number_for_company(uuid, public.document_kind) from public;
revoke execute on function public.generate_due_recurring_jobs(uuid, integer)                from public;
revoke execute on function public.record_payment_from_stripe(
  uuid, uuid, integer, text, text, text, integer, integer, integer, text)                    from public;

-- Belt and braces: if any of these names existed before this migration ran, an
-- explicit grant to anon/authenticated may survive the PUBLIC revoke above.
revoke execute on function public.sync_subscription_seats(uuid)                             from anon, authenticated;
revoke execute on function public.credit_sms_purchase(uuid)                                 from anon, authenticated;
revoke execute on function public.refund_sms_credit(uuid, text)                             from anon, authenticated;
revoke execute on function public.generate_due_recurring_jobs(uuid, integer)                from anon, authenticated;
revoke execute on function public.next_document_number_for_company(uuid, public.document_kind) from anon, authenticated;
revoke execute on function public.company_active_paid_users_for(uuid)                       from anon, authenticated;
revoke execute on function public.sms_credit_balance_for(uuid)                              from anon, authenticated;
revoke execute on function public.record_payment_from_stripe(
  uuid, uuid, integer, text, text, text, integer, integer, integer, text)                    from anon, authenticated;

-- 9b. Callable by a signed-in app user.
--
-- Each of these either takes no company at all, or routes its company argument
-- through commerce_company_scope(), so passing another tenant's id returns
-- nothing rather than that tenant's data. subscription_quote takes a head count
-- and no company: it is arithmetic over the published price list.
-- resolve_due_date and next_service_date are pure date arithmetic.
grant execute on function public.commerce_company_scope(uuid)                to authenticated, service_role;
grant execute on function public.company_active_paid_users(uuid)             to authenticated, service_role;
grant execute on function public.subscription_quote(integer)                 to authenticated, service_role;
grant execute on function public.company_can_accept_payments(uuid)           to authenticated, service_role;
grant execute on function public.sms_credit_balance(uuid)                    to authenticated, service_role;
grant execute on function public.resolve_due_date(text, date)                to authenticated, service_role;
grant execute on function public.next_service_date(date, public.service_frequency, integer) to authenticated, service_role;

-- consume_sms_credit MUST stay callable by `authenticated`: the sms-send Edge
-- Function calls it with the end user's own JWT precisely so that
-- current_company_id() and has_perm('smsCreditsConsume') resolve to the real
-- person, not to the service role. It spends only the caller's own company's
-- credits, checks the permission itself, and cannot name another tenant.
grant execute on function public.consume_sms_credit(uuid, integer, uuid, uuid) to authenticated, service_role;

-- 9c. Service role only — the Edge Functions, which authenticate the outside
--     world by Stripe signature, Twilio signature or the cron secret before
--     they call anything here.
grant execute on function public.record_payment_from_stripe(
  uuid, uuid, integer, text, text, text, integer, integer, integer, text)     to service_role;
grant execute on function public.credit_sms_purchase(uuid)                    to service_role;
grant execute on function public.refund_sms_credit(uuid, text)                to service_role;
grant execute on function public.sync_subscription_seats(uuid)                to service_role;
grant execute on function public.generate_due_recurring_jobs(uuid, integer)   to service_role;

-- 9d. Granted to NOBODY. These are internal implementations reached only from
--     inside the SECURITY DEFINER functions above, which run with the owner's
--     rights. They take a company id and do not scope it, which is safe only
--     because no external caller can reach them:
--       company_active_paid_users_for(uuid)
--       sms_credit_balance_for(uuid)
--       next_document_number_for_company(uuid, document_kind)
--     If a future Edge Function genuinely needs one, grant it to service_role
--     then — deliberately, and only that one.

commit;


-- =============================================================================
-- AFTER APPLYING
-- =============================================================================
-- 0. MIGRATION ORDER, for the record:
--      0002_field_service_core_workflow.sql   (field service core)
--      0003_commercial_enum_values.sql        (enum labels; commits on its own)
--      0004_commercial_layer.sql              (this file)
--    0003 exists only so its ALTER TYPE ... ADD VALUE statements commit before
--    anything uses them. Section 0 of this file proves that happened.
--
-- 1. Regenerate the typed schema:
--      supabase gen types typescript --project-ref srfnfimskixjqjyyftak > backend/types.ts
--
-- 2. Set the Edge Function secrets (none of these belong in the iOS app):
--      supabase secrets set \
--        STRIPE_SECRET_KEY=sk_live_... \
--        STRIPE_WEBHOOK_SECRET=whsec_... \
--        STRIPE_CONNECT_WEBHOOK_SECRET=whsec_... \
--        STRIPE_SUBSCRIPTION_PRICE_BASE=price_... \
--        STRIPE_SUBSCRIPTION_PRICE_SEAT_TEAM=price_... \
--        STRIPE_SUBSCRIPTION_PRICE_SEAT_GROWING=price_... \
--        STRIPE_SUBSCRIPTION_PRICE_SEAT_LARGER=price_... \
--        TWILIO_ACCOUNT_SID=AC... \
--        TWILIO_AUTH_TOKEN=... \
--        TWILIO_MESSAGING_SERVICE_SID=MG... \
--        APP_RETURN_URL=https://harboursouth.us
--
-- 3. Deploy the functions:
--      supabase functions deploy stripe-connect
--      supabase functions deploy stripe-webhook --no-verify-jwt
--      supabase functions deploy sms-send
--      supabase functions deploy sms-status --no-verify-jwt
--      supabase functions deploy sms-purchase
--      supabase functions deploy recurring-tick --no-verify-jwt
--    The three marked --no-verify-jwt are called by Stripe, Twilio and the
--    scheduler, none of which carry a Supabase JWT. Each authenticates itself:
--    the Stripe ones by signature, sms-status by Twilio signature, and
--    recurring-tick by a shared secret header.
--
-- 4. Schedule recurring generation (daily is enough):
--      select cron.schedule('recurring-jobs', '0 6 * * *',
--        $$select net.http_post(
--            url := 'https://srfnfimskixjqjyyftak.supabase.co/functions/v1/recurring-tick',
--            headers := '{"x-cron-secret":"<CRON_SECRET>"}'::jsonb) $$);
--
-- 5. Point Stripe at the webhook, enabling at minimum:
--      payment_intent.succeeded, payment_intent.payment_failed,
--      payment_intent.canceled, charge.refunded, account.updated,
--      checkout.session.completed, customer.subscription.created,
--      customer.subscription.updated, customer.subscription.deleted,
--      invoice.payment_failed, invoice.payment_succeeded
--
-- 6. Point the Twilio Messaging Service status callback at:
--      https://srfnfimskixjqjyyftak.supabase.co/functions/v1/sms-status
--
-- 7. VERIFY BEFORE TRUSTING (this file has never been executed):
--    - select * from public.subscription_quote(1);   -- expect 1999
--    - select * from public.subscription_quote(5);   -- expect 1999 + 4*1299  = 7195
--    - select * from public.subscription_quote(15);  -- expect 1999 + 14*999  = 15985
--    - select * from public.subscription_quote(35);  -- expect 1999 + 34*799  = 29165
--    - CONFIRMED, and this file was corrected accordingly: Phase 1's
--      queue_invoice_notification serialises on `select 1 from companies
--      where id = v_company for update`. Section 6d's functions now take that
--      same row lock; the pg_advisory_xact_lock mechanism has been removed.
--      Re-confirm after applying, with:
--        select pg_get_functiondef(p.oid)
--        from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--        where n.nspname = 'public'
--          and p.proname in ('queue_invoice_notification','consume_sms_credit',
--                            'refund_sms_credit','credit_sms_purchase');
--      Every one of the four must contain `for update` on public.companies and
--      none may contain pg_advisory_xact_lock.
--
-- 8. VERIFY THE PRIVILEGE MODEL ACTUALLY TOOK (section 9 was rewritten because
--    the previous version silently did nothing). This must return NO rows:
--
--      select p.proname, r.rolname
--      from pg_proc p
--      join pg_namespace n on n.oid = p.pronamespace
--      cross join lateral (values ('public'),('anon'),('authenticated')) as r(rolname)
--      where n.nspname = 'public'
--        and p.proname in ('record_payment_from_stripe','credit_sms_purchase',
--                          'refund_sms_credit','sync_subscription_seats',
--                          'generate_due_recurring_jobs',
--                          'next_document_number_for_company',
--                          'company_active_paid_users_for','sms_credit_balance_for')
--        and has_function_privilege(r.rolname, p.oid, 'execute');
--
--    And this must return true for each of them:
--      select has_function_privilege('service_role', 'public.record_payment_from_stripe(
--        uuid,uuid,integer,text,text,text,integer,integer,integer,text)', 'execute');
--
-- 9. VERIFY THE DOCUMENT NUMBER FORMAT MATCHES PHASE 1 BEFORE TRUSTING
--    RECURRING JOBS. next_document_number_for_company() allocates from the same
--    document_sequences row as Phase 1's next_document_number(), but this file
--    was written without being able to read Phase 1's body, so its formatting is
--    an assumption: prefix || (pad_width > 0 ? zero-padded : plain) next_value,
--    with any separator living inside `prefix`, and next_value meaning "the
--    number to use next". That shape is corroborated by the app's own
--    DocumentSequence.format(_:) (Models/DocumentNumbering.swift) and by the
--    MockDataStore fixtures, but NOT by Phase 1's SQL, which was never read.
--    Confirm with:
--
--      select pg_get_functiondef(p.oid)
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--      where n.nspname = 'public' and p.proname = 'next_document_number';
--
--    If it differs, change next_document_number_for_company to match EXACTLY.
--    Then check no company has duplicate sequence rows (the new function refuses
--    to allocate if it finds any, which would show up as a 'failed: ...' row):
--
--      select company_id, kind, count(*)
--      from public.document_sequences group by 1,2 having count(*) > 1;
--
--    Then dry-run one company before scheduling the cron:
--      select * from public.generate_due_recurring_jobs('<company-uuid>', 0);
--    Expect 'generated' with a job_id, and a second identical call to return
--    'alreadyGenerated' with no new job and no new number consumed.
--
-- 10. VERIFY THE PAYMENTS COLUMN CHANGE:
--      select is_nullable from information_schema.columns
--      where table_name = 'payments' and column_name = 'recorded_by_user_id';
--     Expect YES. The iOS decoder already reads it as an optional UUID
--     (SupabaseFinancialRecords.swift), so no app change accompanies this.
--
-- 11. VERIFY THE ENUM LABELS ARE USABLE AT RUNTIME, not merely present. The
--     three paths that actually evaluate a new label do so inside PL/pgSQL,
--     which means they are compiled at apply time but not resolved until they
--     first run — so a missing label surfaces as a failed customer payment,
--     not as a failed migration. Force it now, in a NEW session:
--
--       select 'stripe'::text::public.payment_method,
--              'custom'::text::public.service_frequency,
--              'undelivered'::text::public.notification_status;
--
--     Then exercise the one that matters most, against a real invoice in a
--     throwaway company, and confirm the payment row lands with method =
--     'stripe' and recorded_by_user_id null:
--
--       select * from public.record_payment_from_stripe(
--         '<invoice-uuid>', '<company-uuid>', 1000,
--         'pi_test', 'ch_test', 'acct_test', 3, 59, 938, 'usd');
-- =============================================================================
