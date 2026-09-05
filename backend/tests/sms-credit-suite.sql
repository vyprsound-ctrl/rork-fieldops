-- =============================================================================
-- TradeDesk — SMS credit consumption suite (DEVELOPMENT TOOLING, NOT PRODUCTION)
-- =============================================================================
--
-- Proves that sending an invoice by SMS spends exactly the credit it should,
-- that email never spends any, that a failed delivery gives the credit back,
-- and that none of it leaks across a tenant boundary.
--
-- The debit rate under test is one credit per message — the rate the ledger
-- fixtures already establish, published by public.sms_credits_per_message().
--
-- Balances are asserted as deltas around each operation rather than as fixed
-- totals, so the suite stays honest if earlier steps change.
--
-- Defined in `pg_temp`: session-local, invisible to `anon`/`authenticated`,
-- never exposed through PostgREST, gone when the session ends.
--
-- HOW TO RUN
-- ----------
-- Run the whole file as one statement batch. The runner always ends in
-- `raise exception`, so every fixture row is rolled back and the report comes
-- back in the error message. FAIL=0 is a pass.
-- =============================================================================

create or replace function pg_temp.run_sms_credit_tests()
returns table(test_name text, passed boolean, detail text)
language plpgsql
as $function$
declare
  r text[] := array[]::text[];
  v_super text := current_user;

  v_ca uuid; v_cb uuid;
  v_owner uuid := gen_random_uuid();
  v_admin uuid := gen_random_uuid();
  v_disp  uuid := gen_random_uuid();
  v_work  uuid := gen_random_uuid();
  v_acct  uuid := gen_random_uuid();
  v_b_owner uuid := gen_random_uuid();

  v_cust uuid; v_addr uuid; v_b_cust uuid; v_b_addr uuid;
  v_inv uuid; v_draft uuid; v_b_inv uuid;

  v_note uuid; v_note2 uuid; v_email_note uuid; v_short_note uuid;
  v_outcome text; v_charged int; v_after int;
  v_settle text; v_refunded int;
  v_before int; v_now int; v_n int; v_txt text; v_flag boolean;
begin
  -- ---------------------------------------------------------------- fixtures
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
         u.em, 'x', now(), now(), now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, false
  from (values
    (v_owner  ,'owner@smstest.invalid'),
    (v_admin  ,'admin@smstest.invalid'),
    (v_disp   ,'disp@smstest.invalid'),
    (v_work   ,'work@smstest.invalid'),
    (v_acct   ,'acct@smstest.invalid'),
    (v_b_owner,'b.owner@smstest.invalid')
  ) as u(id, em);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('SMSTEST Alpha','hvac','US','USD','America/New_York') returning id into v_ca;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('SMSTEST Beta','plumbing','US','USD','America/Chicago') returning id into v_cb;

  insert into public.app_users (id, company_id, name, email, role) values
    (v_owner  , v_ca, 'S Owner'     ,'owner@smstest.invalid','owner'),
    (v_admin  , v_ca, 'S Admin'     ,'admin@smstest.invalid','admin'),
    (v_disp   , v_ca, 'S Dispatcher','disp@smstest.invalid','dispatcher'),
    (v_work   , v_ca, 'S Worker'    ,'work@smstest.invalid','fieldWorker'),
    (v_acct   , v_ca, 'S Accounts'  ,'acct@smstest.invalid','accounts'),
    (v_b_owner, v_cb, 'B Owner'     ,'b.owner@smstest.invalid','owner');

  insert into public.customers (company_id, name, billing_terms)
    values (v_ca,'SMSTEST Customer','Net 30') returning id into v_cust;
  insert into public.addresses (company_id, customer_id, line1, city, state, postal_code)
    values (v_ca, v_cust,'8 Credit Row','Tampa','FL','33601') returning id into v_addr;

  insert into public.customers (company_id, name) values (v_cb,'BETA Customer') returning id into v_b_cust;
  insert into public.addresses (company_id, customer_id, line1) values (v_cb, v_b_cust,'1 Beta Rd') returning id into v_b_addr;

  perform set_config('role', 'authenticated', true);

  -- ------------------------------------------------------- sendable invoices
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);

  v_inv := public.create_invoice(v_cust, v_addr, 'Condenser replacement', 'Replace failed unit.', 'Net 30', current_date, current_date + 30);
  perform public.save_invoice_line_item(v_inv, null, 'Condenser fan motor', 1, 240.00, 0.07);
  perform public.update_invoice_status(v_inv, 'sent');

  v_draft := public.create_invoice(v_cust, v_addr, 'Still a draft', '', 'Net 30', current_date, current_date + 30);

  perform set_config('request.jwt.claims', json_build_object('sub', v_b_owner::text,'role','authenticated')::text, true);
  v_b_inv := public.create_invoice(v_b_cust, v_b_addr, 'Beta invoice', '', 'Net 30', current_date, current_date + 30);
  perform public.save_invoice_line_item(v_b_inv, null, 'Beta work', 1, 100.00, 0);
  perform public.update_invoice_status(v_b_inv, 'sent');

  -- ============================================================ the debit rate
  r := r || format('Debit rate is one credit per message|%s|rate=%s',
                   public.sms_credits_per_message() = 1, public.sms_credits_per_message());

  -- ================================================================= top up
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);

  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, purchase_reference)
  values (v_ca, 'purchase', 3, 3, 'SUITE-TOPUP-3');

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Purchased credit is the opening balance|%s|balance=%s', v_now = 3, v_now);

  -- ============================================== email never spends SMS credit
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;

  select notification_id, outcome, credits_charged
    into v_email_note, v_outcome, v_charged
    from public.queue_invoice_notification(v_inv, 'email', 'dana@smstest.invalid');

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Email send charges nothing|%s|charged=%s balance %s to %s',
                   (v_charged = 0 and v_now = v_before), v_charged, v_before, v_now);

  select count(*) into v_n from public.sms_credit_ledger where notification_id = v_email_note;
  r := r || format('Email writes no ledger row at all|%s|ledger rows=%s', v_n = 0, v_n);

  select status::text, channel::text into v_txt, v_outcome from public.notifications where id = v_email_note;
  r := r || format('Email attempt is queued for delivery|%s|status=%s channel=%s',
                   (v_txt = 'queued' and v_outcome = 'email'), v_txt, v_outcome);

  -- ============================================ SMS with sufficient credit
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;

  select notification_id, outcome, credits_charged, balance_after
    into v_note, v_outcome, v_charged, v_after
    from public.queue_invoice_notification(v_inv, 'sms', '+15615550142');

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('SMS with credit debits exactly one|%s|outcome=%s charged=%s balance %s to %s',
                   (v_outcome = 'queued' and v_charged = 1 and v_now = v_before - 1),
                   v_outcome, v_charged, v_before, v_now);

  r := r || format('Reported balance matches the ledger|%s|reported=%s actual=%s',
                   v_after = v_now, v_after, v_now);

  select count(*) into v_n from public.sms_credit_ledger
   where notification_id = v_note and transaction_type = 'consumption' and amount = -1;
  r := r || format('Consumption row is tied to its notification|%s|rows=%s', v_n = 1, v_n);

  select balance_after into v_n from public.sms_credit_ledger
   where company_id = v_ca order by created_at desc, id desc limit 1;
  r := r || format('Newest balance_after equals the running sum|%s|balance_after=%s sum=%s',
                   v_n = v_now, v_n, v_now);

  -- =============================== a delivered SMS keeps its credit spent
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;

  select outcome, credits_refunded into v_settle, v_refunded
    from public.settle_notification(v_note, true, 'SM-TEST-DELIVERED', null);

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  select status::text into v_txt from public.notifications where id = v_note;
  r := r || format('Delivered SMS stays charged|%s|outcome=%s refunded=%s status=%s balance %s to %s',
                   (v_settle = 'sent' and v_refunded = 0 and v_now = v_before and v_txt = 'sent'),
                   v_settle, v_refunded, v_txt, v_before, v_now);

  -- ===================== a failed provider delivery must not keep the credit
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;

  select notification_id into v_note2
    from public.queue_invoice_notification(v_inv, 'sms', '+15615550142');

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Credit is held before the provider is called|%s|balance %s to %s',
                   v_now = v_before - 1, v_before, v_now);

  select outcome, credits_refunded into v_settle, v_refunded
    from public.settle_notification(v_note2, false, null, 'SMS provider not configured');

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  select status::text into v_txt from public.notifications where id = v_note2;
  r := r || format('Failed delivery returns the credit|%s|outcome=%s refunded=%s status=%s balance back to %s',
                   (v_settle = 'failedRefunded' and v_refunded = 1 and v_now = v_before and v_txt = 'failed'),
                   v_settle, v_refunded, v_txt, v_now);

  select count(*) into v_n from public.sms_credit_ledger
   where notification_id = v_note2 and transaction_type = 'refund' and amount = 1;
  r := r || format('Refund row is tied to the failed notification|%s|rows=%s', v_n = 1, v_n);

  -- ============================ settling twice must never refund twice
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;

  select outcome, credits_refunded into v_settle, v_refunded
    from public.settle_notification(v_note2, false, null, 'Repeat call');

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Repeat settle refunds nothing more|%s|outcome=%s refunded=%s balance %s to %s',
                   (v_settle = 'alreadySettled' and v_refunded = 0 and v_now = v_before),
                   v_settle, v_refunded, v_before, v_now);

  select outcome, credits_refunded into v_settle, v_refunded
    from public.settle_notification(v_note, true, 'SM-TEST-AGAIN', null);
  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Repeat settle of a sent message is inert|%s|outcome=%s balance=%s',
                   (v_settle = 'alreadySettled' and v_now = v_before), v_settle, v_now);

  -- ======================================= an admin can spend, but not forge
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text,'role','authenticated')::text, true);

  select notification_id, outcome, credits_charged
    into v_note, v_outcome, v_charged
    from public.queue_invoice_notification(v_inv, 'sms', '+15615550142');
  r := r || format('Admin can spend credit to send|%s|outcome=%s charged=%s', v_outcome = 'queued' and v_charged = 1, v_outcome, v_charged);
  perform public.settle_notification(v_note, true, 'SM-ADMIN', null);

  begin
    insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after)
    values (v_ca, 'consumption', -1, 0);
    r := r || 'Admin cannot write the ledger directly|false|insert unexpectedly succeeded';
  exception when others then
    r := r || format('Admin cannot write the ledger directly|%s|%s', true, replace(sqlerrm,'|','/'));
  end;

  begin
    insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, purchase_reference)
    values (v_ca, 'purchase', 500, 500, 'FORGED');
    r := r || 'Admin cannot mint themselves credit|false|insert unexpectedly succeeded';
  exception when others then
    r := r || format('Admin cannot mint themselves credit|%s|%s', true, replace(sqlerrm,'|','/'));
  end;

  -- ============================================ who may not send at all
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  begin
    perform public.queue_invoice_notification(v_inv, 'sms', '+15615550142');
    r := r || 'Dispatcher cannot send an invoice|false|no refusal raised';
  exception when others then
    r := r || format('Dispatcher cannot send an invoice|%s|sqlstate=%s', sqlstate = 'TD403', sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_work::text,'role','authenticated')::text, true);
  begin
    perform public.queue_invoice_notification(v_inv, 'sms', '+15615550142');
    r := r || 'Field worker cannot send an invoice|false|no refusal raised';
  exception when others then
    r := r || format('Field worker cannot send an invoice|%s|sqlstate=%s', sqlstate = 'TD403', sqlstate);
  end;

  -- ============== accounts may invoice by email but may not spend SMS credit
  perform set_config('request.jwt.claims', json_build_object('sub', v_acct::text,'role','authenticated')::text, true);
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;

  begin
    perform public.queue_invoice_notification(v_inv, 'sms', '+15615550142');
    r := r || 'Accounts cannot spend SMS credit|false|no refusal raised';
  exception when others then
    r := r || format('Accounts cannot spend SMS credit|%s|sqlstate=%s', sqlstate = 'TD403', sqlstate);
  end;

  select outcome, credits_charged into v_outcome, v_charged
    from public.queue_invoice_notification(v_inv, 'email', 'dana@smstest.invalid');
  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Accounts can still send by email|%s|outcome=%s charged=%s balance unchanged=%s',
                   (v_outcome = 'queued' and v_charged = 0 and v_now = v_before), v_outcome, v_charged, v_now = v_before);

  -- ================================================== refusals on the invoice
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);

  begin
    perform public.queue_invoice_notification(v_draft, 'sms', '+15615550142');
    r := r || 'A draft invoice cannot be sent|false|no refusal raised';
  exception when others then
    r := r || format('A draft invoice cannot be sent|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  begin
    perform public.queue_invoice_notification(v_inv, 'sms', '   ');
    r := r || 'A blank recipient is refused|false|no refusal raised';
  exception when others then
    r := r || format('A blank recipient is refused|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  select count(*) into v_n from public.sms_credit_ledger
   where company_id = v_ca and notification_id is null and transaction_type = 'consumption';
  r := r || format('No credit was spent by a refused send|%s|orphan consumption rows=%s', v_n = 0, v_n);

  -- ================================================ spend down to empty
  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  while v_now > 0 loop
    select notification_id into v_short_note
      from public.queue_invoice_notification(v_inv, 'sms', '+15615550142');
    perform public.settle_notification(v_short_note, true, 'SM-DRAIN', null);
    select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  end loop;
  r := r || format('Credit can be spent down to zero|%s|balance=%s', v_now = 0, v_now);

  -- ============================================ insufficient credit
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;

  select notification_id, outcome, credits_charged, balance_after
    into v_short_note, v_outcome, v_charged, v_after
    from public.queue_invoice_notification(v_inv, 'sms', '+15615550142');

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Send without credit is refused, not charged|%s|outcome=%s charged=%s balance %s to %s',
                   (v_outcome = 'insufficientCredit' and v_charged = 0 and v_now = v_before),
                   v_outcome, v_charged, v_before, v_now);

  select status::text, failure_reason into v_txt, v_outcome from public.notifications where id = v_short_note;
  r := r || format('The refused attempt is recorded honestly|%s|status=%s reason=%s',
                   (v_txt = 'failed' and v_outcome is not null), v_txt, coalesce(v_outcome,'(none)'));

  select count(*) into v_n from public.sms_credit_ledger where notification_id = v_short_note;
  r := r || format('A refused send writes no ledger row|%s|rows=%s', v_n = 0, v_n);

  select coalesce(min(balance_after), 0) into v_n from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('The balance never goes negative|%s|lowest recorded=%s', v_n >= 0, v_n);

  -- ================== email is not blocked by an empty SMS balance
  select outcome, credits_charged into v_outcome, v_charged
    from public.queue_invoice_notification(v_inv, 'email', 'dana@smstest.invalid');
  r := r || format('Email still sends on an empty SMS balance|%s|outcome=%s charged=%s',
                   (v_outcome = 'queued' and v_charged = 0), v_outcome, v_charged);

  -- ============================================ ledger self-consistency
  select count(*) into v_n
    from public.sms_credit_ledger l
   where l.company_id = v_ca
     and l.balance_after <> (
       select coalesce(sum(e.amount), 0) from public.sms_credit_ledger e
        where e.company_id = l.company_id
          and (e.created_at, e.id) <= (l.created_at, l.id));
  r := r || format('Every row balance_after matches its own history|%s|mismatched rows=%s', v_n = 0, v_n);

  -- ================================================= cross-tenant isolation
  perform set_config('request.jwt.claims', json_build_object('sub', v_b_owner::text,'role','authenticated')::text, true);

  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, purchase_reference)
  values (v_cb, 'purchase', 5, 5, 'SUITE-BETA-5');

  begin
    perform public.queue_invoice_notification(v_inv, 'sms', '+15615550142');
    r := r || 'Another tenant cannot send our invoice|false|no refusal raised';
  exception when others then
    r := r || format('Another tenant cannot send our invoice|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;

  begin
    perform public.settle_notification(v_short_note, true, 'SM-CROSS', null);
    r := r || 'Another tenant cannot settle our notification|false|no refusal raised';
  exception when others then
    r := r || format('Another tenant cannot settle our notification|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_cb;
  r := r || format('Our spending never touched their balance|%s|beta balance=%s', v_now = 5, v_now);

  select count(*) into v_n from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Another tenant cannot read our ledger|%s|visible alpha rows=%s', v_n = 0, v_n);

  select count(*) into v_n from public.notifications where company_id = v_ca;
  r := r || format('Another tenant cannot read our notifications|%s|visible alpha rows=%s', v_n = 0, v_n);

  -- Beta spends its own credit; alpha must be unaffected.
  select notification_id into v_note
    from public.queue_invoice_notification(v_b_inv, 'sms', '+15125550188');
  perform public.settle_notification(v_note, true, 'SM-BETA', null);

  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_cb;
  r := r || format('Their send debits only their own credit|%s|beta balance=%s', v_now = 4, v_now);

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  select coalesce(sum(amount),0) into v_now from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Our balance is untouched by their send|%s|alpha balance=%s', v_now = 0, v_now);

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
  for rec in select * from pg_temp.run_sms_credit_tests() loop
    if rec.passed then v_pass := v_pass + 1; else v_fail := v_fail + 1; end if;
    v_report := v_report || format(E'\n%s  %s  [%s]',
      case when rec.passed then 'PASS' else 'FAIL' end, rec.test_name, rec.detail);
  end loop;
  raise exception E'SMS CREDIT SUITE — PASS=% FAIL=% %', v_pass, v_fail, v_report;
end $$;
