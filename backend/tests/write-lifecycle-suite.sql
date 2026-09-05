-- =============================================================================
-- TradeDesk — write lifecycle suite (DEVELOPMENT TOOLING, NOT PRODUCTION)
-- =============================================================================
--
-- Exercises the whole write layer end to end against the real database, as real
-- users, with Row Level Security switched on: quote → job → field work →
-- invoice → payment, plus the refusals that make those paths trustworthy.
--
-- Like the security suite, this is defined in `pg_temp` — session-local, never
-- visible to `anon` or `authenticated`, never exposed through PostgREST, and
-- gone when the session ends.
--
-- HOW TO RUN
-- ----------
-- Run the whole file as one migration/statement batch. The final DO block always
-- ends in `raise exception`, so every fixture row and every document written by
-- the run is rolled back. The report comes back in the error message. A run that
-- reports FAIL=0 is a pass.
--
-- Never re-create this in the `public` schema.
-- =============================================================================

create or replace function pg_temp.run_write_lifecycle_tests()
returns table(test_name text, passed boolean, detail text)
language plpgsql
as $function$
declare
  r text[] := array[]::text[];
  v_super text := current_user;

  v_ca uuid; v_cb uuid;
  v_owner uuid := gen_random_uuid();
  v_disp  uuid := gen_random_uuid();
  v_w1    uuid := gen_random_uuid();
  v_w2    uuid := gen_random_uuid();
  v_acct  uuid := gen_random_uuid();
  v_b_owner uuid := gen_random_uuid();

  v_cust uuid; v_addr uuid; v_b_cust uuid; v_b_addr uuid;

  v_quote uuid; v_quote2 uuid; v_b_quote uuid;
  v_line uuid; v_job uuid; v_job2 uuid; v_invoice uuid;
  v_number text; v_number2 text; v_b_number text;
  v_status text; v_n int; v_txt text; v_flag boolean;
  v_lat double precision;
begin
  -- ---------------------------------------------------------------- fixtures
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
         u.em, 'x', now(), now(), now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, false
  from (values
    (v_owner  ,'owner@writetest.invalid'),
    (v_disp   ,'disp@writetest.invalid'),
    (v_w1     ,'w1@writetest.invalid'),
    (v_w2     ,'w2@writetest.invalid'),
    (v_acct   ,'acct@writetest.invalid'),
    (v_b_owner,'b.owner@writetest.invalid')
  ) as u(id, em);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier, default_tax_rate)
  values ('WRITETEST Alpha','hvac','US','USD','America/New_York', 0.07) returning id into v_ca;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier, default_tax_rate)
  values ('WRITETEST Beta','roofing','US','USD','America/Chicago', 0.05) returning id into v_cb;

  insert into public.app_users (id, company_id, name, email, role) values
    (v_owner  , v_ca, 'W Owner'     ,'owner@writetest.invalid','owner'),
    (v_disp   , v_ca, 'W Dispatcher','disp@writetest.invalid','dispatcher'),
    (v_w1     , v_ca, 'W Worker One','w1@writetest.invalid','fieldWorker'),
    (v_w2     , v_ca, 'W Worker Two','w2@writetest.invalid','fieldWorker'),
    (v_acct   , v_ca, 'W Accounts'  ,'acct@writetest.invalid','accounts'),
    (v_b_owner, v_cb, 'B Owner'     ,'b.owner@writetest.invalid','owner');

  insert into public.customers (company_id, name, billing_terms)
    values (v_ca,'WRITETEST Customer','Net 30') returning id into v_cust;
  insert into public.addresses (company_id, customer_id, line1, city, state, postal_code)
    values (v_ca, v_cust,'12 Alpha Way','Tampa','FL','33601') returning id into v_addr;
  insert into public.customer_contacts (company_id, customer_id, name, contact_role, phone, email, is_primary, is_billing_contact)
    values (v_ca, v_cust,'Dana Reyes','Facilities','813-555-0100','dana@writetest.invalid', true, true);

  insert into public.customers (company_id, name) values (v_cb,'BETA Customer') returning id into v_b_cust;
  insert into public.addresses (company_id, customer_id, line1) values (v_cb, v_b_cust,'1 Beta Rd') returning id into v_b_addr;

  -- Everything from here runs as an ordinary authenticated user, so RLS applies
  -- to every statement exactly as it does for the app.
  perform set_config('role', 'authenticated', true);

  -- =========================================================== quote lifecycle
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);

  v_quote := public.create_quote(v_cust, v_addr, '  Rooftop unit replacement  ', 'Replace the failed condenser.', current_date + 30);
  select number, status::text into v_number, v_status from public.quotes where id = v_quote;
  r := r || format('Quote created as a numbered draft|%s|number=%s status=%s', (v_number = 'Q-1001' and v_status = 'draft'), v_number, v_status);

  select title = 'Rooftop unit replacement' into v_flag from public.quotes where id = v_quote;
  r := r || format('Quote title trimmed by the database|%s|stored trimmed', coalesce(v_flag, false));

  begin
    perform public.create_quote(v_cust, v_addr, '   ', '', null);
    r := r || 'Blank quote title refused|false|no refusal raised';
  exception when others then
    r := r || format('Blank quote title refused|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  begin
    perform public.create_quote(v_b_cust, v_b_addr, 'Cross tenant quote', '', null);
    r := r || 'Quote against another tenant refused|false|no refusal raised';
  exception when others then
    r := r || format('Quote against another tenant refused|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;

  -- Money: 3 x 19.99 @ 7% is the case a float gets wrong.
  perform public.save_quote_line_item(v_quote, null, 'Condenser fan motor', 3, 19.99, 0.07);
  perform public.save_quote_line_item(v_quote, null, 'Refrigerant charge', 1, 120.00, 0.07);
  select format('%s/%s/%s', subtotal, tax, total) into v_txt from public.quotes where id = v_quote;
  r := r || format('Quote totals derived to the cent|%s|subtotal/tax/total=%s', v_txt = '179.97/12.60/192.57', v_txt);

  select id into v_line from public.quote_line_items where quote_id = v_quote and sort_order = 0;
  perform public.save_quote_line_item(v_quote, v_line, 'Condenser fan motor', 2, 19.99, 0.07);
  select format('%s/%s/%s', subtotal, tax, total) into v_txt from public.quotes where id = v_quote;
  r := r || format('Editing a line re-derives the totals|%s|now %s', v_txt = '159.98/11.20/171.18', v_txt);

  begin
    perform public.save_quote_line_item(v_quote, null, 'Bad quantity', 0, 10.00, 0.07);
    r := r || 'Zero quantity refused|false|no refusal raised';
  exception when others then
    r := r || format('Zero quantity refused|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  -- Status workflow.
  begin
    perform public.update_quote_status(v_quote, 'accepted');
    r := r || 'Draft cannot jump straight to accepted|false|no refusal raised';
  exception when others then
    r := r || format('Draft cannot jump straight to accepted|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  perform public.update_quote_status(v_quote, 'sent');
  select (sent_at is not null) into v_flag from public.quotes where id = v_quote;
  r := r || format('Sending stamps sent_at|%s|timestamped by the database', coalesce(v_flag, false));

  begin
    perform public.save_quote_line_item(v_quote, null, 'Late addition', 1, 50.00, 0.07);
    r := r || 'Sent quote locks its line items|false|no refusal raised';
  exception when others then
    r := r || format('Sent quote locks its line items|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  perform public.update_quote_status(v_quote, 'accepted');

  -- ============================================================== conversion
  v_job := public.convert_quote_to_job(v_quote, 'install', 'standard', now() + interval '1 day', now() + interval '1 day 3 hours', null);
  select number, status::text into v_number2, v_status from public.jobs where id = v_job;
  r := r || format('Accepted quote converts to a numbered job|%s|number=%s status=%s', (v_number2 = 'J-1001' and v_status = 'scheduled'), v_number2, v_status);

  select count(*) into v_n from public.job_status_history where job_id = v_job;
  r := r || format('Job creation writes its history row|%s|rows=%s', v_n = 1, v_n);

  select (converted_job_id = v_job and status::text = 'accepted' and total = 171.18)
    into v_flag from public.quotes where id = v_quote;
  r := r || format('Converted quote keeps status totals and lines|%s|only the back reference changed', coalesce(v_flag, false));

  begin
    perform public.convert_quote_to_job(v_quote, 'install', 'standard', null, null, null);
    r := r || 'A quote converts only once|false|no refusal raised';
  exception when others then
    r := r || format('A quote converts only once|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  -- ================================================================ dispatch
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);

  perform public.assign_job(v_job, v_w1, false);
  select status::text into v_status from public.jobs where id = v_job;
  select count(*) into v_n from public.job_status_history where job_id = v_job;
  r := r || format('Assigning advances the job and records it|%s|status=%s history=%s', (v_status = 'workerAssigned' and v_n = 2), v_status, v_n);

  -- A second job in the same slot, to prove the double-booking rule.
  v_job2 := public.create_job(v_cust, v_addr, 'Overlapping call out', 'Same slot on purpose', 'callOut', 'urgent',
                              now() + interval '1 day 1 hour', now() + interval '1 day 2 hours', null, null, null);
  begin
    perform public.assign_job(v_job2, v_w1, false);
    r := r || 'Overlapping assignment refused until acknowledged|false|no refusal raised';
  exception when others then
    r := r || format('Overlapping assignment refused until acknowledged|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  perform public.assign_job(v_job2, v_w1, true);
  select count(*) into v_n from public.field_worker_assignments where job_id = v_job2 and user_id = v_w1;
  r := r || format('Acknowledged overlap goes through|%s|assignments=%s', v_n = 1, v_n);

  perform public.assign_job(v_job2, null, false);
  select status::text into v_status from public.jobs where id = v_job2;
  select count(*) into v_n from public.field_worker_assignments where job_id = v_job2;
  r := r || format('Clearing an assignment returns the job to scheduled|%s|status=%s assignments=%s', (v_status = 'scheduled' and v_n = 0), v_status, v_n);

  perform public.reschedule_job(v_job2, now() + interval '3 days', now() + interval '3 days 2 hours', false);
  select (scheduled_start > now() + interval '2 days') into v_flag from public.jobs where id = v_job2;
  r := r || format('Rescheduling moves the slot|%s|new slot stored', coalesce(v_flag, false));

  begin
    perform public.reschedule_job(v_job2, now() + interval '4 days', now() + interval '3 days', false);
    r := r || 'A job cannot finish before it starts|false|no refusal raised';
  exception when others then
    r := r || format('A job cannot finish before it starts|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  -- Dispatch is operational, never financial.
  select count(*) into v_n from public.quotes where id = v_quote;
  r := r || format('Dispatcher gets no priced quote rows|%s|rows=%s', v_n = 0, v_n);
  select count(*) into v_n from public.quotes_operational where id = v_quote;
  r := r || format('Dispatcher reads the money free quote view|%s|rows=%s', v_n = 1, v_n);

  -- ============================================================== field work
  perform set_config('request.jwt.claims', json_build_object('sub', v_w2::text,'role','authenticated')::text, true);
  begin
    perform public.update_job_status(v_job, 'travelling', 27.95, -82.45);
    r := r || 'Unassigned worker cannot move a job|false|no refusal raised';
  exception when others then
    r := r || format('Unassigned worker cannot move a job|%s|sqlstate=%s', sqlstate in ('TD401','TD404'), sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_w1::text,'role','authenticated')::text, true);

  begin
    perform public.update_job_status(v_job, 'completed', null, null);
    r := r || 'Out of order transition refused|false|no refusal raised';
  exception when others then
    r := r || format('Out of order transition refused|%s|sqlstate=%s', sqlstate = 'TD409', sqlstate);
  end;

  perform public.update_job_status(v_job, 'travelling', 27.9506, -82.4572);
  select count(*) into v_n from public.field_worker_locations where job_id = v_job and user_id = v_w1;
  select latitude into v_lat from public.job_status_history where job_id = v_job and to_status = 'travelling';
  r := r || format('Travel captures a position and stamps the history|%s|fixes=%s history lat=%s', (v_n = 1 and v_lat is not null), v_n, coalesce(v_lat::text,'null'));

  perform public.update_job_status(v_job, 'arrived', 27.9510, -82.4580);
  perform public.update_job_status(v_job, 'inProgress', null, null);
  select (actual_start is not null) into v_flag from public.jobs where id = v_job;
  r := r || format('Starting work stamps actual_start|%s|set by the database', coalesce(v_flag, false));

  perform public.update_job_status(v_job, 'completed', 27.9512, -82.4585);
  select status::text, (actual_end is not null) into v_status, v_flag from public.jobs where id = v_job;
  select count(*) into v_n from public.job_status_history where job_id = v_job;
  r := r || format('Completion stamps actual_end and history|%s|status=%s history=%s', (v_status = 'completed' and coalesce(v_flag,false) and v_n = 6), v_status, v_n);

  -- A field worker never reaches money, even for their own job.
  select count(*) into v_n from public.invoices;
  r := r || format('Field worker reads no invoices at all|%s|rows=%s', v_n = 0, v_n);

  begin
    perform public.create_job(v_cust, v_addr, 'Worker made this', '', 'callOut', 'standard', null, null, null, null, null);
    r := r || 'Field worker cannot create a job|false|no refusal raised';
  exception when others then
    r := r || format('Field worker cannot create a job|%s|sqlstate=%s', sqlstate = 'TD401', sqlstate);
  end;

  -- ================================================================ invoicing
  perform set_config('request.jwt.claims', json_build_object('sub', v_acct::text,'role','authenticated')::text, true);

  v_invoice := public.create_invoice_from_job(v_job, null, current_date, null, true, true);
  select number, status::text into v_number2, v_status from public.invoices where id = v_invoice;
  r := r || format('Invoice raised from the completed job|%s|number=%s status=%s', (v_number2 = 'INV-1001' and v_status = 'draft'), v_number2, v_status);

  select count(*) into v_n from public.invoice_line_items where invoice_id = v_invoice and source_quote_line_item_id is not null;
  select format('%s/%s/%s', subtotal, tax, total) into v_txt from public.invoices where id = v_invoice;
  r := r || format('Quote lines snapshotted by value onto the invoice|%s|lines=%s totals=%s', (v_n = 2 and v_txt = '159.98/11.20/171.18'), v_n, v_txt);

  select btrim(currency_code), payment_terms_label, (due_date - issue_date) into v_txt, v_status, v_n from public.invoices where id = v_invoice;
  r := r || format('Currency and terms snapshotted from company and customer|%s|currency=%s terms=%s netdays=%s', (v_txt = 'USD' and v_status = 'Net 30' and v_n = 30), v_txt, v_status, v_n);

  select status::text into v_status from public.jobs where id = v_job;
  r := r || format('Accounts carries the job to invoiced|%s|status=%s', v_status = 'invoiced', v_status);

  -- Accounts holds neither history permission, so it writes an audit row it is
  -- not entitled to read back. The rows are verified below as the owner.
  select count(*) into v_n from public.job_status_history where job_id = v_job;
  r := r || format('Accounts writes history it cannot read back|%s|visible rows=%s', v_n = 0, v_n);

  begin
    perform public.create_invoice_from_job(v_job, null, current_date, null, true, true);
    r := r || 'A job is invoiced only once|false|no refusal raised';
  exception when others then
    r := r || format('A job is invoiced only once|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  begin
    perform public.create_invoice_from_quote(v_quote, null, current_date, null, true, true);
    r := r || 'The quote behind an invoiced job cannot be billed again|false|no refusal raised';
  exception when others then
    r := r || format('The quote behind an invoiced job cannot be billed again|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  -- ================================================================= payments
  begin
    perform public.record_payment(v_invoice, 50.00, 'card', now(), null, null);
    r := r || 'A draft invoice takes no payment|false|no refusal raised';
  exception when others then
    r := r || format('A draft invoice takes no payment|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  perform public.update_invoice_status(v_invoice, 'sent');

  perform public.record_payment(v_invoice, 71.18, 'card', now(), 'ref-001', 'Deposit');
  select status::text, format('%s/%s', amount_paid, balance) into v_status, v_txt from public.invoices where id = v_invoice;
  r := r || format('Part payment derives status and balance|%s|status=%s paid/balance=%s', (v_status = 'partPaid' and v_txt = '71.18/100.00'), v_status, v_txt);

  select (reference = 'ref-001' and is_simulated)
    into v_flag from public.payments where invoice_id = v_invoice limit 1;
  r := r || format('A recorded payment keeps the operator''s own reference|%s|no processor was contacted', coalesce(v_flag, false));

  select not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'payments'
      and column_name in ('stripe_payment_intent_reference', 'stripe_connect_account_reference')
  ) into v_flag;
  r := r || format('Payments carry no payment-processor columns|%s|generic reference only', coalesce(v_flag, false));

  begin
    perform public.record_payment(v_invoice, 150.00, 'cash', now(), null, null);
    r := r || 'Overpayment refused|false|no refusal raised';
  exception when others then
    r := r || format('Overpayment refused|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  perform public.record_payment(v_invoice, 100.00, 'check', now(), '9912', null);
  select status::text, format('%s/%s', amount_paid, balance), (paid_at is not null)
    into v_status, v_txt, v_flag from public.invoices where id = v_invoice;
  r := r || format('Settling in full derives paid and stamps paid_at|%s|status=%s paid/balance=%s', (v_status = 'paid' and v_txt = '171.18/0.00' and coalesce(v_flag,false)), v_status, v_txt);

  select status::text into v_status from public.jobs where id = v_job;
  r := r || format('A settled invoice carries its job to paid|%s|status=%s', v_status = 'paid', v_status);

  -- The audit trail is append only: there is no update or delete policy on it.
  update public.job_status_history set to_status = 'cancelled' where job_id = v_job;
  get diagnostics v_n = row_count;
  r := r || format('Status history cannot be rewritten|%s|rows updated=%s', v_n = 0, v_n);

  delete from public.jobs where id = v_job2;
  get diagnostics v_n = row_count;
  r := r || format('Jobs cannot be deleted|%s|rows deleted=%s', v_n = 0, v_n);

  -- ================================================== numbering across tenants
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);

  -- The whole lifecycle, audited: created, assigned, four field steps,
  -- invoiced, paid.
  select count(*) into v_n from public.job_status_history where job_id = v_job;
  r := r || format('Every step of the lifecycle left an audit row|%s|history=%s', v_n = 8, v_n);

  select count(*) into v_n from public.job_status_history
   where job_id = v_job and changed_by_user_id = v_acct and to_status in ('invoiced','paid');
  r := r || format('The financial steps are attributed to accounts|%s|rows=%s', v_n = 2, v_n);

  -- All four field steps carry a position, but only three of them took a fresh
  -- fix: starting work captures location without a capture event of its own, so
  -- it stamps the worker's last known position rather than inventing one.
  select count(*) into v_n from public.job_status_history
   where job_id = v_job and changed_by_user_id = v_w1 and latitude is not null;
  r := r || format('Field steps carry the worker position|%s|stamped rows=%s', v_n = 4, v_n);

  select count(*) into v_n from public.field_worker_locations where job_id = v_job;
  r := r || format('Only genuine fixes are stored as positions|%s|stored fixes=%s', v_n = 3, v_n);

  v_quote2 := public.create_quote(v_cust, v_addr, 'Second quote', '', null);
  select number into v_number2 from public.quotes where id = v_quote2;
  r := r || format('Numbering advances within the company|%s|second quote=%s', v_number2 = 'Q-1002', v_number2);

  perform set_config('request.jwt.claims', json_build_object('sub', v_b_owner::text,'role','authenticated')::text, true);
  v_b_quote := public.create_quote(v_b_cust, v_b_addr, 'Beta quote', '', null);
  select number into v_b_number from public.quotes where id = v_b_quote;
  r := r || format('Another tenant numbers independently|%s|beta quote=%s', v_b_number = 'Q-1001', v_b_number);

  begin
    perform public.update_quote_status(v_quote, 'declined');
    r := r || 'Another tenant cannot write our quote|false|no refusal raised';
  exception when others then
    r := r || format('Another tenant cannot write our quote|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;

  begin
    perform public.record_payment(v_invoice, 10.00, 'cash', now(), null, null);
    r := r || 'Another tenant cannot pay our invoice|false|no refusal raised';
  exception when others then
    r := r || format('Another tenant cannot pay our invoice|%s|sqlstate=%s', sqlstate in ('TD404','TD401'), sqlstate);
  end;

  begin
    perform public.update_job_status(v_job, 'cancelled', null, null);
    r := r || 'Another tenant cannot move our job|false|no refusal raised';
  exception when others then
    r := r || format('Another tenant cannot move our job|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;

  perform set_config('role', v_super, true);

  return query
    select split_part(x, '|', 1),
           split_part(x, '|', 2)::boolean,
           split_part(x, '|', 3)
      from unnest(r) as x;
end;
$function$;

do $$
declare
  rec record;
  v_pass int := 0;
  v_fail int := 0;
  v_report text := '';
begin
  for rec in select * from pg_temp.run_write_lifecycle_tests() loop
    if rec.passed then v_pass := v_pass + 1; else v_fail := v_fail + 1; end if;
    v_report := v_report || format(E'\n%s  %s  [%s]',
      case when rec.passed then 'PASS' else 'FAIL' end, rec.test_name, rec.detail);
  end loop;
  raise exception E'WRITE LIFECYCLE SUITE — PASS=% FAIL=% %', v_pass, v_fail, v_report;
end $$;
