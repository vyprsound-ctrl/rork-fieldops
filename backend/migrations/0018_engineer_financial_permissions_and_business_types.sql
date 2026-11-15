-- =============================================================================
-- 0018 - Per-engineer invoicing & payment permissions, business types, vehicles
-- =============================================================================
-- Additive only. Nothing existing is replaced, rewritten or disabled:
--   * Every existing RLS policy, invoice RPC, Stripe function and webhook is
--     untouched. Office invoicing (invoicesManage) works exactly as before.
--   * Existing invoices, payments, share tokens and customers are not modified.
--
-- What is added:
--   1. invoice_share_tokens.expires_at (nullable; NULL = never expires).
--      FIX: the deployed invoice-payment function already selects this column
--      and treats NULL as "no expiry". The column was missing, so every online
--      payment attempt failed with "This payment link is no longer active."
--      Adding it (all existing rows NULL) restores online payment for every
--      existing invoice. No Stripe code changes.
--   2. member_financial_permissions: one row per engineer, two grants
--      (can_invoice, can_collect_payments), default OFF. Readable by the
--      engineer themself and by usersManage holders in the same company.
--      NO write policies: the only write path is
--      set_member_financial_permissions(), which requires usersManage
--      (Owner/Admin), refuses self-edits, and only targets field workers in
--      the caller's own company. An engineer can never grant themself.
--   3. engineer_* RPCs (SECURITY DEFINER, explicit company + grant +
--      assignment checks). A revoked grant blocks the very next call.
--   4. Business types: app_trade gains 'propertyServices' and 'automotive'.
--      Existing values stay valid for existing companies.
--   5. vehicles (registration / VIN / make / model, all optional), many per
--      customer, reusable across jobs via jobs.vehicle_id. No DELETE path.
--      Vehicle data is never removed by a change of business type.
--
-- Rollback: migrations/rollback/0018_rollback.sql
-- =============================================================================

-- 1. Share-token expiry column (fix for online payment) ------------------------
alter table public.invoice_share_tokens
  add column if not exists expires_at timestamptz;

-- 4. Business types --------------------------------------------------------------
-- Not used anywhere in this migration (a new enum value can't be used in the
-- transaction that adds it).
alter type public.app_trade add value if not exists 'propertyServices';
alter type public.app_trade add value if not exists 'automotive';

-- 2. Per-engineer grants -----------------------------------------------------------
create table if not exists public.member_financial_permissions (
  user_id uuid primary key references public.app_users(id) on delete cascade,
  company_id uuid not null references public.companies(id) on delete cascade,
  can_invoice boolean not null default false,
  can_collect_payments boolean not null default false,
  updated_by_user_id uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists member_financial_permissions_company_idx
  on public.member_financial_permissions(company_id);

alter table public.member_financial_permissions enable row level security;

drop policy if exists member_financial_permissions_select on public.member_financial_permissions;
create policy member_financial_permissions_select on public.member_financial_permissions
  for select to authenticated
  using (
    user_id = auth.uid()
    or (company_id = public.current_company_id() and public.has_perm('usersManage'))
  );

revoke all on public.member_financial_permissions from anon;
revoke insert, update, delete, truncate on public.member_financial_permissions from authenticated;
grant select on public.member_financial_permissions to authenticated;

create or replace function public.set_member_financial_permissions(
  p_user uuid,
  p_can_invoice boolean,
  p_can_collect boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := current_company_id();
  v_target record;
begin
  if v_company is null or not has_perm('usersManage') then
    raise exception 'usersManage' using errcode = 'TD401';
  end if;
  if p_user = auth.uid() then
    raise exception 'You can''t change your own invoicing or payment permissions.' using errcode = 'TD422';
  end if;

  select id, company_id, role into v_target
    from app_users where id = p_user and company_id = v_company;
  if not found then
    raise exception 'Team member outside company scope' using errcode = 'TD404';
  end if;
  if v_target.role <> 'fieldWorker' then
    raise exception 'Invoicing and payment permissions apply to engineers only.' using errcode = 'TD422';
  end if;

  insert into member_financial_permissions
    (user_id, company_id, can_invoice, can_collect_payments, updated_by_user_id, created_at, updated_at)
  values
    (p_user, v_company, coalesce(p_can_invoice, false), coalesce(p_can_collect, false), auth.uid(), now(), now())
  on conflict (user_id) do update
     set can_invoice = excluded.can_invoice,
         can_collect_payments = excluded.can_collect_payments,
         updated_by_user_id = excluded.updated_by_user_id,
         updated_at = now();
end;
$$;

-- True only for an ACTIVE field worker, in their own company, holding the grant.
create or replace function public.has_engineer_financial_grant(p_kind text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
      from member_financial_permissions g
      join app_users u on u.id = g.user_id
     where g.user_id = auth.uid()
       and u.status = 'active'
       and u.role = 'fieldWorker'
       and g.company_id = u.company_id
       and case p_kind
             when 'invoice' then g.can_invoice
             when 'collect' then g.can_collect_payments
             else false
           end
  )
$$;

-- Internal: the invoice must belong to the caller's company and to a job the
-- caller is assigned to. Returns the invoice row.
create or replace function public.engineer_scoped_invoice(p_invoice uuid)
returns public.invoices
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_invoice invoices%rowtype;
begin
  select * into v_invoice from invoices
   where id = p_invoice and company_id = current_company_id();
  if not found or v_invoice.job_id is null or not is_assigned_to_job(v_invoice.job_id) then
    raise exception 'Invoice outside scope' using errcode = 'TD404';
  end if;
  return v_invoice;
end;
$$;

-- Internal: reuse the live share token or issue a new one (same format as
-- issue_invoice_share_token).
create or replace function public.engineer_share_token(p_invoice uuid, p_company uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_token text;
begin
  select token into v_token from invoice_share_tokens
   where invoice_id = p_invoice and revoked_at is null
     and (expires_at is null or expires_at > now())
   limit 1;
  if v_token is not null then
    return v_token;
  end if;
  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into invoice_share_tokens (company_id, invoice_id, token, created_by_user_id)
  values (p_company, p_invoice, v_token, auth.uid());
  return v_token;
end;
$$;

-- 3. Engineer RPCs ---------------------------------------------------------------
create or replace function public.engineer_job_invoice(p_job uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := current_company_id();
  v_can_invoice boolean := has_engineer_financial_grant('invoice');
  v_can_collect boolean := has_engineer_financial_grant('collect');
  v_job jobs%rowtype;
  v_invoice invoices%rowtype;
  v_email text;
  v_lines jsonb;
begin
  if v_company is null or not (v_can_invoice or v_can_collect) then
    return jsonb_build_object('can_invoice', false, 'can_collect', false, 'job_status', null, 'invoice', null);
  end if;

  select * into v_job from jobs where id = p_job and company_id = v_company;
  if not found or not is_assigned_to_job(p_job) then
    raise exception 'Job outside scope' using errcode = 'TD404';
  end if;

  select * into v_invoice from invoices
   where job_id = p_job and company_id = v_company and status <> 'void'
   order by created_at desc
   limit 1;

  if v_invoice.id is null then
    return jsonb_build_object('can_invoice', v_can_invoice, 'can_collect', v_can_collect,
                              'job_status', v_job.status, 'invoice', null);
  end if;

  select email into v_email from customer_contacts where id = v_invoice.billing_contact_id;
  if coalesce(btrim(v_email), '') = '' then
    select email into v_email from customer_contacts
     where customer_id = v_invoice.customer_id and coalesce(btrim(email), '') <> ''
     order by is_billing_contact desc, is_primary desc
     limit 1;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id,
           'description', l.item_description,
           'quantity', l.quantity,
           'unit_price', l.unit_price,
           'tax_rate', l.tax_rate,
           'line_total', l.line_total
         ) order by l.sort_order, l.id), '[]'::jsonb)
    into v_lines
    from invoice_line_items l where l.invoice_id = v_invoice.id;

  return jsonb_build_object(
    'can_invoice', v_can_invoice,
    'can_collect', v_can_collect,
    'job_status', v_job.status,
    'invoice', jsonb_build_object(
      'id', v_invoice.id,
      'number', v_invoice.number,
      'title', v_invoice.title,
      'status', v_invoice.status,
      'currency_code', v_invoice.currency_code,
      'issue_date', v_invoice.issue_date,
      'due_date', v_invoice.due_date,
      'subtotal', v_invoice.subtotal,
      'tax', v_invoice.tax,
      'total', v_invoice.total,
      'amount_paid', v_invoice.amount_paid,
      'balance', v_invoice.balance,
      'billing_email', coalesce(v_email, ''),
      'lines', v_lines
    )
  );
end;
$$;

create or replace function public.engineer_create_invoice_from_job(p_job uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := current_company_id();
  v_job jobs%rowtype;
  v_quote quotes%rowtype;
  v_existing text;
  v_scope text;
  v_invoice uuid;
begin
  if v_company is null or not has_engineer_financial_grant('invoice') then
    raise exception 'Your invoicing permission is turned off. Ask your office to turn it on.' using errcode = 'TD422';
  end if;

  select * into v_job from jobs where id = p_job and company_id = v_company;
  if not found or not is_assigned_to_job(p_job) then
    raise exception 'Job outside scope' using errcode = 'TD404';
  end if;
  if v_job.status not in ('completed', 'invoiced') then
    raise exception 'Complete the job before invoicing it.' using errcode = 'TD422';
  end if;

  select number into v_existing from invoices where job_id = p_job and status <> 'void' limit 1;
  if v_existing is not null then
    raise exception '% has already been invoiced as %.', v_job.number, v_existing using errcode = 'TD422';
  end if;

  if v_job.quote_id is not null then
    select * into v_quote from quotes where id = v_job.quote_id and company_id = v_company and status = 'accepted';
  end if;
  if v_quote.id is not null then
    select number into v_existing from invoices where quote_id = v_quote.id and status <> 'void' limit 1;
    if v_existing is not null then
      raise exception 'The quote behind % has already been invoiced as %.', v_job.number, v_existing using errcode = 'TD422';
    end if;
  end if;

  v_scope := coalesce(nullif(v_quote.scope_of_work, ''), v_job.job_description);
  v_invoice := make_invoice(v_job.customer_id, v_job.address_id, v_job.id, v_quote.id, v_job.title,
                            v_scope, null, null, null);
  if v_quote.id is not null then
    perform snapshot_quote_lines(v_quote.id, v_invoice);
  end if;
  perform recalculate_invoice_totals(v_invoice);

  -- Advance completed -> invoiced with the same audit row apply_job_status
  -- writes. (try_advance_job needs invoicesManage, which engineers lack.)
  if v_job.status = 'completed' then
    update jobs set status = 'invoiced' where id = v_job.id and company_id = v_company;
    insert into job_status_history (id, company_id, job_id, from_status, to_status, changed_by_user_id, changed_at, latitude, longitude)
    values (gen_random_uuid(), v_company, v_job.id, 'completed', 'invoiced', auth.uid(), now(), null, null);
  end if;

  return v_invoice;
end;
$$;

create or replace function public.engineer_save_invoice_line(
  p_invoice uuid,
  p_line uuid,
  p_description text,
  p_quantity numeric,
  p_unit_price numeric
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := current_company_id();
  v_invoice invoices%rowtype;
  v_description text := btrim(coalesce(p_description, ''));
  v_tax numeric;
  v_order integer;
begin
  if v_company is null or not has_engineer_financial_grant('invoice') then
    raise exception 'Your invoicing permission is turned off. Ask your office to turn it on.' using errcode = 'TD422';
  end if;
  v_invoice := engineer_scoped_invoice(p_invoice);
  if v_invoice.status <> 'draft' then
    raise exception 'This invoice has already been issued, so its line items are locked.' using errcode = 'TD422';
  end if;
  if v_description = '' then
    raise exception 'Describe the line item before saving.' using errcode = 'TD422';
  end if;
  if coalesce(p_quantity, 0) <= 0 then
    raise exception 'Quantity must be greater than zero.' using errcode = 'TD422';
  end if;
  if coalesce(p_unit_price, 0) < 0 then
    raise exception 'Unit price can''t be negative.' using errcode = 'TD422';
  end if;

  if p_line is not null and exists (select 1 from invoice_line_items where id = p_line and invoice_id = p_invoice) then
    update invoice_line_items
       set item_description = v_description,
           quantity = p_quantity,
           unit_price = p_unit_price,
           line_total = round(p_quantity * p_unit_price, 2)
     where id = p_line and invoice_id = p_invoice;
  else
    select default_tax_rate into v_tax from companies where id = v_company;
    select coalesce(max(sort_order), -1) + 1 into v_order from invoice_line_items where invoice_id = p_invoice;
    insert into invoice_line_items (id, company_id, invoice_id, item_description, quantity, unit_price, tax_rate, line_total, sort_order)
    values (gen_random_uuid(), v_company, p_invoice, v_description, p_quantity, p_unit_price,
            coalesce(v_tax, 0), round(p_quantity * p_unit_price, 2), v_order);
  end if;

  perform recalculate_invoice_totals(p_invoice);
end;
$$;

create or replace function public.engineer_delete_invoice_line(p_invoice uuid, p_line uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invoice invoices%rowtype;
begin
  if current_company_id() is null or not has_engineer_financial_grant('invoice') then
    raise exception 'Your invoicing permission is turned off. Ask your office to turn it on.' using errcode = 'TD422';
  end if;
  v_invoice := engineer_scoped_invoice(p_invoice);
  if v_invoice.status <> 'draft' then
    raise exception 'This invoice has already been issued, so its line items are locked.' using errcode = 'TD422';
  end if;

  delete from invoice_line_items where id = p_line and invoice_id = p_invoice;

  with ordered as (
    select id, (row_number() over (order by sort_order, id))::integer - 1 as position
      from invoice_line_items where invoice_id = p_invoice
  )
  update invoice_line_items i set sort_order = o.position from ordered o where i.id = o.id;

  perform recalculate_invoice_totals(p_invoice);
end;
$$;

create or replace function public.engineer_issue_invoice(p_invoice uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_invoice invoices%rowtype;
begin
  if current_company_id() is null or not has_engineer_financial_grant('invoice') then
    raise exception 'Your invoicing permission is turned off. Ask your office to turn it on.' using errcode = 'TD422';
  end if;
  v_invoice := engineer_scoped_invoice(p_invoice);
  if v_invoice.status <> 'draft' then
    raise exception '% has already been issued.', v_invoice.number using errcode = 'TD422';
  end if;
  if not exists (select 1 from invoice_line_items where invoice_id = p_invoice) then
    raise exception 'Add at least one line item before sending this invoice.' using errcode = 'TD422';
  end if;

  update invoices set status = 'sent', sent_at = now() where id = p_invoice;
end;
$$;

create or replace function public.engineer_invoice_email_prepare(p_invoice uuid, p_recipient text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := current_company_id();
  v_invoice invoices%rowtype;
  v_recipient text := btrim(coalesce(p_recipient, ''));
  v_token text;
  v_notification uuid;
  v_co companies%rowtype;
begin
  if v_company is null or not has_engineer_financial_grant('invoice') then
    raise exception 'Your invoicing permission is turned off. Ask your office to turn it on.' using errcode = 'TD422';
  end if;
  v_invoice := engineer_scoped_invoice(p_invoice);
  if v_invoice.status = 'draft' then
    raise exception 'Move % out of draft before sending it.', v_invoice.number using errcode = 'TD422';
  end if;
  if v_invoice.status = 'void' then
    raise exception '% has been voided and can''t be sent.', v_invoice.number using errcode = 'TD422';
  end if;
  if v_recipient !~ '^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$' then
    raise exception 'Enter a valid email address for the customer.' using errcode = 'TD422';
  end if;

  v_token := engineer_share_token(p_invoice, v_company);

  insert into notifications (company_id, channel, template, recipient, customer_id, invoice_id, status, sent_by_user_id)
  values (v_company, 'email', 'invoice.share', v_recipient, v_invoice.customer_id, v_invoice.id, 'queued', auth.uid())
  returning id into v_notification;

  select * into v_co from companies where id = v_company;

  return jsonb_build_object(
    'notification_id', v_notification,
    'token', v_token,
    'invoice', jsonb_build_object(
      'id', v_invoice.id, 'number', v_invoice.number, 'title', v_invoice.title,
      'currency_code', v_invoice.currency_code, 'due_date', v_invoice.due_date,
      'total', v_invoice.total, 'balance', v_invoice.balance,
      'company_id', v_invoice.company_id, 'customer_id', v_invoice.customer_id),
    'company', jsonb_build_object(
      'name', v_co.name, 'phone', v_co.phone, 'time_zone_identifier', v_co.time_zone_identifier,
      'address_line', v_co.address_line, 'city', v_co.city, 'state', v_co.state,
      'postal_code', v_co.postal_code, 'business_email', v_co.business_email)
  );
end;
$$;

create or replace function public.engineer_invoice_email_settle(
  p_notification uuid,
  p_delivered boolean,
  p_reference text default null,
  p_failure text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Settles only the caller's own queued email. No grant check: a send that
  -- was authorised at prepare time must still record its real outcome.
  update notifications
     set status = case when p_delivered then 'sent'::notification_status else 'failed'::notification_status end,
         sent_at = case when p_delivered then now() else sent_at end,
         provider_reference = case when p_delivered then p_reference else provider_reference end,
         failure_reason = case when p_delivered then failure_reason else p_failure end
   where id = p_notification
     and company_id = current_company_id()
     and sent_by_user_id = auth.uid()
     and channel = 'email'
     and status = 'queued';
end;
$$;

create or replace function public.engineer_invoice_payment_link(p_invoice uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := current_company_id();
  v_invoice invoices%rowtype;
begin
  if v_company is null or not has_engineer_financial_grant('collect') then
    raise exception 'Your payment collection permission is turned off. Ask your office to turn it on.' using errcode = 'TD422';
  end if;
  v_invoice := engineer_scoped_invoice(p_invoice);
  if v_invoice.status not in ('sent', 'viewed', 'partPaid', 'overdue') then
    raise exception '% isn''t open for payment.', v_invoice.number using errcode = 'TD422';
  end if;
  if coalesce(v_invoice.balance, 0) <= 0 then
    raise exception '% has nothing left to pay.', v_invoice.number using errcode = 'TD422';
  end if;
  return engineer_share_token(p_invoice, v_company);
end;
$$;

-- 5. Vehicles ------------------------------------------------------------------------
create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  registration text not null default '',
  vin text not null default '',
  make text not null default '',
  model text not null default '',
  created_by_user_id uuid references public.app_users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists vehicles_company_customer_idx on public.vehicles(company_id, customer_id);

alter table public.jobs add column if not exists vehicle_id uuid references public.vehicles(id);
create index if not exists jobs_vehicle_idx on public.jobs(vehicle_id) where vehicle_id is not null;

drop trigger if exists vehicles_set_updated_at on public.vehicles;
create trigger vehicles_set_updated_at
  before update on public.vehicles
  for each row execute function public.set_updated_at();

alter table public.vehicles enable row level security;

drop policy if exists vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles
  for select to authenticated
  using (
    company_id = public.current_company_id()
    and (
      public.has_perm('customersReadAll')
      or (
        public.has_perm('jobsReadAssignedOnly')
        and exists (select 1 from public.jobs j
                     where j.vehicle_id = vehicles.id and public.is_assigned_to_job(j.id))
      )
    )
  );

drop policy if exists vehicles_insert on public.vehicles;
create policy vehicles_insert on public.vehicles
  for insert to authenticated
  with check (
    company_id = public.current_company_id()
    and public.has_perm('customersManage')
    and exists (select 1 from public.customers c
                 where c.id = customer_id and c.company_id = public.current_company_id())
  );

drop policy if exists vehicles_update on public.vehicles;
create policy vehicles_update on public.vehicles
  for update to authenticated
  using (company_id = public.current_company_id() and public.has_perm('customersManage'))
  with check (
    company_id = public.current_company_id()
    and public.has_perm('customersManage')
    and exists (select 1 from public.customers c
                 where c.id = customer_id and c.company_id = public.current_company_id())
  );

revoke all on public.vehicles from anon;
revoke delete, truncate on public.vehicles from authenticated;
grant select, insert, update on public.vehicles to authenticated;

create or replace function public.set_job_vehicle(p_job uuid, p_vehicle uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_company uuid := current_company_id();
  v_job jobs%rowtype;
  v_vehicle vehicles%rowtype;
begin
  if v_company is null or not has_perm('jobsManage') then
    raise exception 'jobsManage' using errcode = 'TD401';
  end if;
  select * into v_job from jobs where id = p_job and company_id = v_company;
  if not found then
    raise exception 'Job outside scope' using errcode = 'TD404';
  end if;
  if p_vehicle is not null then
    select * into v_vehicle from vehicles where id = p_vehicle and company_id = v_company;
    if not found then
      raise exception 'Vehicle outside scope' using errcode = 'TD404';
    end if;
    if v_vehicle.customer_id <> v_job.customer_id then
      raise exception 'That vehicle belongs to a different customer.' using errcode = 'TD422';
    end if;
  end if;
  update jobs set vehicle_id = p_vehicle where id = p_job and company_id = v_company;
end;
$$;

-- Grants -----------------------------------------------------------------------------
revoke all on function public.set_member_financial_permissions(uuid, boolean, boolean) from public, anon;
revoke all on function public.has_engineer_financial_grant(text) from public, anon;
revoke all on function public.engineer_scoped_invoice(uuid) from public, anon, authenticated;
revoke all on function public.engineer_share_token(uuid, uuid) from public, anon, authenticated;
revoke all on function public.engineer_job_invoice(uuid) from public, anon;
revoke all on function public.engineer_create_invoice_from_job(uuid) from public, anon;
revoke all on function public.engineer_save_invoice_line(uuid, uuid, text, numeric, numeric) from public, anon;
revoke all on function public.engineer_delete_invoice_line(uuid, uuid) from public, anon;
revoke all on function public.engineer_issue_invoice(uuid) from public, anon;
revoke all on function public.engineer_invoice_email_prepare(uuid, text) from public, anon;
revoke all on function public.engineer_invoice_email_settle(uuid, boolean, text, text) from public, anon;
revoke all on function public.engineer_invoice_payment_link(uuid) from public, anon;
revoke all on function public.set_job_vehicle(uuid, uuid) from public, anon;

grant execute on function public.set_member_financial_permissions(uuid, boolean, boolean) to authenticated;
grant execute on function public.has_engineer_financial_grant(text) to authenticated;
grant execute on function public.engineer_job_invoice(uuid) to authenticated;
grant execute on function public.engineer_create_invoice_from_job(uuid) to authenticated;
grant execute on function public.engineer_save_invoice_line(uuid, uuid, text, numeric, numeric) to authenticated;
grant execute on function public.engineer_delete_invoice_line(uuid, uuid) to authenticated;
grant execute on function public.engineer_issue_invoice(uuid) to authenticated;
grant execute on function public.engineer_invoice_email_prepare(uuid, text) to authenticated;
grant execute on function public.engineer_invoice_email_settle(uuid, boolean, text, text) to authenticated;
grant execute on function public.engineer_invoice_payment_link(uuid) to authenticated;
grant execute on function public.set_job_vehicle(uuid, uuid) to authenticated;
