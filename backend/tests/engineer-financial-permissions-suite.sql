-- =============================================================================
-- TradeDesk — engineer invoicing/payment permissions + vehicles suite (0018)
-- =============================================================================
-- DEVELOPMENT TOOLING. Defined in pg_temp; fixtures are created inside the run
-- and the final DO block always ends in `raise exception`, so every row it
-- writes is rolled back. Run as one batch after the 0018 body (see
-- preview-0018.sh). A run reporting FAIL=0 is a pass.
-- Only uses brand-new *.invalid test companies; touches no existing record.
-- =============================================================================

create or replace function pg_temp.run_engineer_financial_tests()
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
  v_acct  uuid := gen_random_uuid();
  v_ea    uuid := gen_random_uuid();   -- engineer A: both grants ON
  v_eb    uuid := gen_random_uuid();   -- engineer B: both grants OFF
  v_b_owner uuid := gen_random_uuid();
  v_b_eng uuid := gen_random_uuid();

  v_cust uuid; v_addr uuid; v_cust2 uuid; v_b_cust uuid; v_b_addr uuid;
  v_job uuid; v_job_b uuid; v_job_x uuid; v_office_job uuid;
  v_inv uuid; v_office_inv uuid; v_line uuid;
  v_veh1 uuid; v_veh2 uuid; v_veh_other uuid; v_b_veh uuid;
  v_token text; v_token2 text; v_txt text; v_n int; v_flag boolean; v_j jsonb;
  v_status text;
begin
  -- --------------------------------------------------------------- fixtures
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
         u.em, 'x', now(), now(), now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, false
  from (values
    (v_owner,'owner@engfin.invalid'), (v_admin,'admin@engfin.invalid'),
    (v_disp,'disp@engfin.invalid'), (v_acct,'acct@engfin.invalid'),
    (v_ea,'ea@engfin.invalid'), (v_eb,'eb@engfin.invalid'),
    (v_b_owner,'bowner@engfin.invalid'), (v_b_eng,'beng@engfin.invalid')
  ) as u(id, em);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier, default_tax_rate)
  values ('ENGFIN Alpha','hvac','US','USD','America/New_York', 0.10) returning id into v_ca;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier, default_tax_rate)
  values ('ENGFIN Beta','plumbing','US','USD','America/Chicago', 0.05) returning id into v_cb;

  insert into public.app_users (id, company_id, name, email, role) values
    (v_owner, v_ca,'EF Owner','owner@engfin.invalid','owner'),
    (v_admin, v_ca,'EF Admin','admin@engfin.invalid','admin'),
    (v_disp , v_ca,'EF Dispatcher','disp@engfin.invalid','dispatcher'),
    (v_acct , v_ca,'EF Accounts','acct@engfin.invalid','accounts'),
    (v_ea   , v_ca,'EF Engineer A','ea@engfin.invalid','fieldWorker'),
    (v_eb   , v_ca,'EF Engineer B','eb@engfin.invalid','fieldWorker'),
    (v_b_owner, v_cb,'EF B Owner','bowner@engfin.invalid','owner'),
    (v_b_eng, v_cb,'EF B Engineer','beng@engfin.invalid','fieldWorker');

  insert into public.customers (company_id, name, billing_terms)
    values (v_ca,'ENGFIN Customer','Net 30') returning id into v_cust;
  insert into public.addresses (company_id, customer_id, line1, city, state, postal_code)
    values (v_ca, v_cust,'1 Test Way','Tampa','FL','33601') returning id into v_addr;
  insert into public.customer_contacts (company_id, customer_id, name, contact_role, phone, email, is_primary, is_billing_contact)
    values (v_ca, v_cust,'Billing Person','Accounts','813-555-0100','billing@engfin.invalid', true, true);
  insert into public.customers (company_id, name, billing_terms)
    values (v_ca,'ENGFIN Second Customer','Net 30') returning id into v_cust2;
  insert into public.customers (company_id, name) values (v_cb,'ENGFIN Beta Customer') returning id into v_b_cust;
  insert into public.addresses (company_id, customer_id, line1) values (v_cb, v_b_cust,'2 Beta Rd') returning id into v_b_addr;

  perform set_config('role', 'authenticated', true);

  -- ------------------------------------------------------- grants: who can set
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  perform public.set_member_financial_permissions(v_ea, true, true);
  select can_invoice and can_collect_payments into v_flag from public.member_financial_permissions where user_id = v_ea;
  r := r || format('Owner turns both permissions on for an engineer|%s|row visible to owner', coalesce(v_flag,false));

  select count(*) into v_n from public.member_financial_permissions where user_id = v_eb;
  r := r || format('Engineers default to OFF (no row)|%s|rows=%s', v_n = 0, v_n);

  begin
    perform public.set_member_financial_permissions(v_disp, true, true);
    r := r || 'Grants refused for non-engineer roles|false|no refusal';
  exception when others then
    r := r || format('Grants refused for non-engineer roles|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  begin
    perform public.set_member_financial_permissions(v_b_eng, true, true);
    r := r || 'Owner cannot grant another company''s engineer|false|no refusal';
  exception when others then
    r := r || format('Owner cannot grant another company''s engineer|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text,'role','authenticated')::text, true);
  perform public.set_member_financial_permissions(v_eb, false, false);
  select count(*) into v_n from public.member_financial_permissions where user_id = v_eb and not can_invoice and not can_collect_payments;
  r := r || format('Admin (usersManage) can set engineer permissions|%s|rows=%s', v_n = 1, v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  begin
    perform public.set_member_financial_permissions(v_eb, true, true);
    r := r || 'Dispatcher cannot change engineer permissions|false|no refusal';
  exception when others then
    r := r || format('Dispatcher cannot change engineer permissions|%s|sqlstate=%s', sqlstate = 'TD401', sqlstate);
  end;
  select count(*) into v_n from public.member_financial_permissions;
  r := r || format('Dispatcher cannot read engineer permissions|%s|visible=%s', v_n = 0, v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_acct::text,'role','authenticated')::text, true);
  begin
    perform public.set_member_financial_permissions(v_eb, true, true);
    r := r || 'Accounts cannot change engineer permissions|false|no refusal';
  exception when others then
    r := r || format('Accounts cannot change engineer permissions|%s|sqlstate=%s', sqlstate = 'TD401', sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_eb::text,'role','authenticated')::text, true);
  begin
    perform public.set_member_financial_permissions(v_eb, true, true);
    r := r || 'Engineer cannot grant themself|false|no refusal';
  exception when others then
    r := r || format('Engineer cannot grant themself|%s|sqlstate=%s', sqlstate in ('TD401','TD422'), sqlstate);
  end;
  begin
    insert into public.member_financial_permissions (user_id, company_id, can_invoice, can_collect_payments)
    values (v_eb, v_ca, true, true)
    on conflict (user_id) do update set can_invoice = true, can_collect_payments = true;
    r := r || 'Engineer cannot write the grants table directly|false|write went through';
  exception when others then
    r := r || format('Engineer cannot write the grants table directly|%s|sqlstate=%s', sqlstate = '42501', sqlstate);
  end;
  select count(*) into v_n from public.member_financial_permissions;
  r := r || format('Engineer sees only their own grant row|%s|visible=%s', v_n = 1, v_n);

  -- ------------------------------------------------------- jobs for the engineers
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  v_job := public.create_job(v_cust, v_addr, 'ENGFIN job A', 'Service visit', 'callOut', 'standard', null, null, null, null, null);
  v_job_b := public.create_job(v_cust, v_addr, 'ENGFIN job B', 'Service visit', 'callOut', 'standard', null, null, null, null, null);
  v_job_x := public.create_job(v_cust, v_addr, 'ENGFIN job unassigned', 'Service visit', 'callOut', 'standard', null, null, null, null, null);
  v_office_job := public.create_job(v_cust, v_addr, 'ENGFIN office job', 'Service visit', 'callOut', 'standard', null, null, null, null, null);
  perform public.assign_job(v_job, v_ea, true);
  perform public.assign_job(v_job_b, v_eb, true);
  perform public.assign_job(v_job_x, v_eb, true);   -- assigned to B, not A
  perform public.assign_job(v_office_job, v_eb, true);

  -- Complete the jobs as their workers (the normal path).
  perform set_config('request.jwt.claims', json_build_object('sub', v_ea::text,'role','authenticated')::text, true);
  perform public.update_job_status(v_job, 'travelling', null, null);
  perform public.update_job_status(v_job, 'arrived', null, null);
  perform public.update_job_status(v_job, 'inProgress', null, null);
  perform public.update_job_status(v_job, 'completed', null, null);
  perform set_config('request.jwt.claims', json_build_object('sub', v_eb::text,'role','authenticated')::text, true);
  foreach v_txt in array array['travelling','arrived','inProgress','completed'] loop
    perform public.update_job_status(v_job_b, v_txt::job_status, null, null);
    perform public.update_job_status(v_job_x, v_txt::job_status, null, null);
    perform public.update_job_status(v_office_job, v_txt::job_status, null, null);
  end loop;

  -- ------------------------------------------------------- engineer B (OFF)
  v_j := public.engineer_job_invoice(v_job_b);
  r := r || format('OFF engineer sees no invoice tools|%s|%s', (v_j->>'can_invoice') = 'false' and (v_j->>'can_collect') = 'false', v_j::text);
  begin
    perform public.engineer_create_invoice_from_job(v_job_b);
    r := r || 'OFF engineer cannot generate an invoice|false|no refusal';
  exception when others then
    r := r || format('OFF engineer cannot generate an invoice|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;
  begin
    perform public.create_invoice_from_job(v_job_b, null, null, null, true, true);
    r := r || 'OFF engineer cannot use the office invoice path|false|no refusal';
  exception when others then
    r := r || format('OFF engineer cannot use the office invoice path|%s|sqlstate=%s', sqlstate = 'TD401', sqlstate);
  end;

  -- ------------------------------------------------------- engineer A (ON)
  perform set_config('request.jwt.claims', json_build_object('sub', v_ea::text,'role','authenticated')::text, true);
  begin
    perform public.engineer_create_invoice_from_job(v_job_x);
    r := r || 'ON engineer refused on a job not assigned to them|false|no refusal';
  exception when others then
    r := r || format('ON engineer refused on a job not assigned to them|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;
  begin
    perform public.create_invoice_from_job(v_job, null, null, null, true, true);
    r := r || 'Grant does not unlock the office invoice path|false|no refusal';
  exception when others then
    r := r || format('Grant does not unlock the office invoice path|%s|sqlstate=%s', sqlstate = 'TD401', sqlstate);
  end;

  v_inv := public.engineer_create_invoice_from_job(v_job);
  select status::text into v_status from public.jobs where id = v_job;
  select count(*) into v_n from public.job_status_history where job_id = v_job and to_status = 'invoiced' and changed_by_user_id = v_ea;
  r := r || format('ON engineer generates an invoice; job advances and is audited|%s|job=%s history=%s', v_inv is not null and v_status = 'invoiced' and v_n = 1, v_status, v_n);

  begin
    perform public.engineer_create_invoice_from_job(v_job);
    r := r || 'One live invoice per job|false|no refusal';
  exception when others then
    r := r || format('One live invoice per job|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  perform public.engineer_save_invoice_line(v_inv, null, 'Diagnostic visit', 1, 100.00);
  perform public.engineer_save_invoice_line(v_inv, null, 'Part', 2, 25.00);
  v_j := public.engineer_job_invoice(v_job);
  r := r || format('Lines priced with company tax and totals derived|%s|subtotal=%s tax=%s total=%s',
                   (v_j->'invoice'->>'total')::numeric = 165.00, v_j->'invoice'->>'subtotal', v_j->'invoice'->>'tax', v_j->'invoice'->>'total');
  r := r || format('Billing email prefilled from the billing contact|%s|%s', v_j->'invoice'->>'billing_email' = 'billing@engfin.invalid', v_j->'invoice'->>'billing_email');

  v_line := ((v_j->'invoice'->'lines')->1->>'id')::uuid;
  perform public.engineer_delete_invoice_line(v_inv, v_line);
  perform set_config('role', v_super, true); select total::text into v_txt from public.invoices where id = v_inv; perform set_config('role', 'authenticated', true);
  r := r || format('ON engineer removes a draft line|%s|total=%s', v_txt = '110.00', v_txt);

  begin
    perform public.engineer_invoice_payment_link(v_inv);
    r := r || 'Draft invoice cannot take payment|false|no refusal';
  exception when others then
    r := r || format('Draft invoice cannot take payment|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  perform public.engineer_issue_invoice(v_inv);
  perform set_config('role', v_super, true); select status::text into v_status from public.invoices where id = v_inv; perform set_config('role', 'authenticated', true);
  r := r || format('ON engineer issues the invoice|%s|status=%s', v_status = 'sent', v_status);

  begin
    perform public.engineer_save_invoice_line(v_inv, null, 'Late add', 1, 5);
    r := r || 'Issued invoice lines are locked|false|no refusal';
  exception when others then
    r := r || format('Issued invoice lines are locked|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  v_j := public.engineer_invoice_email_prepare(v_inv, 'billing@engfin.invalid');
  v_token := v_j->>'token';
  perform public.engineer_invoice_email_settle((v_j->>'notification_id')::uuid, true, 'test-ref', null);
  perform set_config('role', v_super, true); select count(*) into v_n from public.notifications where id = (v_j->>'notification_id')::uuid and status = 'sent' and channel = 'email'; perform set_config('role', 'authenticated', true);
  r := r || format('ON engineer emails the invoice (queued then settled)|%s|token=%s sent=%s', v_token is not null and v_n = 1, left(coalesce(v_token,''),8), v_n);

  v_token2 := public.engineer_invoice_payment_link(v_inv);
  r := r || format('ON engineer gets the existing Stripe pay link token|%s|same token=%s', v_token2 = v_token, v_token2 = v_token);

  -- ------------------------------------------------------- revocation is immediate
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  perform public.set_member_financial_permissions(v_ea, false, true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_ea::text,'role','authenticated')::text, true);
  begin
    perform public.engineer_invoice_email_prepare(v_inv, 'billing@engfin.invalid');
    r := r || 'Revoked invoicing blocks the next send|false|no refusal';
  exception when others then
    r := r || format('Revoked invoicing blocks the next send|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;
  v_token2 := public.engineer_invoice_payment_link(v_inv);
  r := r || format('Collection still on independently|%s|token ok', v_token2 is not null);

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  perform public.set_member_financial_permissions(v_ea, false, false);
  perform set_config('request.jwt.claims', json_build_object('sub', v_ea::text,'role','authenticated')::text, true);
  begin
    perform public.engineer_invoice_payment_link(v_inv);
    r := r || 'Revoked collection blocks the next pay link|false|no refusal';
  exception when others then
    r := r || format('Revoked collection blocks the next pay link|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  -- Existing link keeps working for the customer (token row untouched).
  perform set_config('role', v_super, true);
  select count(*) into v_n from public.invoice_share_tokens
   where token = v_token and revoked_at is null and (expires_at is null or expires_at > now());
  r := r || format('Customer''s existing pay link still resolves after revocation|%s|live tokens=%s', v_n = 1, v_n);
  select count(*) into v_n from public.invoice_share_tokens where expires_at is not null;
  r := r || format('expires_at added with no existing token expiring|%s|tokens with expiry=%s', v_n = 0, v_n);
  perform set_config('role', 'authenticated', true);

  -- A suspended engineer loses the grant even if the row says ON.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  perform public.set_member_financial_permissions(v_ea, true, true);
  perform set_config('role', v_super, true);
  update public.app_users set status = 'suspended' where id = v_ea;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_ea::text,'role','authenticated')::text, true);
  begin
    perform public.engineer_invoice_payment_link(v_inv);
    r := r || 'Suspended engineer is blocked|false|no refusal';
  exception when others then
    r := r || format('Suspended engineer is blocked|%s|sqlstate=%s', sqlstate in ('TD422','TD404','TD401'), sqlstate);
  end;

  -- Another company's engineer with a grant cannot reach our invoice.
  perform set_config('role', v_super, true);
  insert into public.member_financial_permissions (user_id, company_id, can_invoice, can_collect_payments)
  values (v_b_eng, v_cb, true, true);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b_eng::text,'role','authenticated')::text, true);
  begin
    perform public.engineer_invoice_payment_link(v_inv);
    r := r || 'Cross-company engineer refused|false|no refusal';
  exception when others then
    r := r || format('Cross-company engineer refused|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;

  -- ------------------------------------------------------- office invoicing unchanged
  perform set_config('request.jwt.claims', json_build_object('sub', v_acct::text,'role','authenticated')::text, true);
  v_office_inv := public.create_invoice_from_job(v_office_job, null, null, null, true, true);
  perform public.save_invoice_line_item(v_office_inv, null, 'Office line', 1, 50, 0.10);
  perform public.update_invoice_status(v_office_inv, 'sent');
  v_token2 := public.issue_invoice_share_token(v_office_inv, false);
  select status::text into v_status from public.invoices where id = v_office_inv;
  r := r || format('Office (accounts) invoicing flow unchanged|%s|status=%s token=%s', v_status = 'sent' and v_token2 is not null, v_status, v_token2 is not null);

  -- ------------------------------------------------------- vehicles
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  insert into public.vehicles (company_id, customer_id, registration, make, model)
    values (v_ca, v_cust, 'AB12 CDE', 'Ford', 'Transit') returning id into v_veh1;
  insert into public.vehicles (company_id, customer_id, vin)
    values (v_ca, v_cust, '1FTFW1E50NFA00001') returning id into v_veh2;
  insert into public.vehicles (company_id, customer_id) values (v_ca, v_cust2) returning id into v_veh_other;
  select count(*) into v_n from public.vehicles where customer_id = v_cust;
  r := r || format('Customer can have several vehicles; all fields optional|%s|count=%s', v_n = 2, v_n);

  perform public.set_job_vehicle(v_job_b, v_veh1);
  perform public.set_job_vehicle(v_job_x, v_veh1);
  select count(*) into v_n from public.jobs where vehicle_id = v_veh1;
  r := r || format('A vehicle is reused across jobs (job history)|%s|jobs=%s', v_n = 2, v_n);

  begin
    perform public.set_job_vehicle(v_job_b, v_veh_other);
    r := r || 'Vehicle of another customer refused on a job|false|no refusal';
  exception when others then
    r := r || format('Vehicle of another customer refused on a job|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  begin
    insert into public.vehicles (company_id, customer_id) values (v_ca, v_b_cust);
    r := r || 'Vehicle for another company''s customer refused|false|insert went through';
  exception when others then
    r := r || format('Vehicle for another company''s customer refused|%s|sqlstate=%s', sqlstate = '42501', sqlstate);
  end;

  begin
    delete from public.vehicles where id = v_veh2;
    r := r || 'Vehicles cannot be deleted|false|delete went through';
  exception when others then
    r := r || format('Vehicles cannot be deleted|%s|sqlstate=%s', sqlstate = '42501', sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_eb::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.vehicles;
  r := r || format('Engineer sees only vehicles on their assigned jobs|%s|visible=%s', v_n = 1, v_n);
  begin
    insert into public.vehicles (company_id, customer_id) values (v_ca, v_cust);
    r := r || 'Engineer cannot create vehicles|false|insert went through';
  exception when others then
    r := r || format('Engineer cannot create vehicles|%s|sqlstate=%s', sqlstate = '42501', sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_b_owner::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.vehicles where company_id = v_ca;
  r := r || format('Another company cannot see our vehicles|%s|visible=%s', v_n = 0, v_n);
  begin
    perform public.set_job_vehicle(v_job, v_veh1);
    r := r || 'Another company cannot link our vehicle|false|no refusal';
  exception when others then
    r := r || format('Another company cannot link our vehicle|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;
  insert into public.vehicles (company_id, customer_id) values (v_cb, v_b_cust) returning id into v_b_veh;
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  begin
    perform public.set_job_vehicle(v_job, v_b_veh);
    r := r || 'Cross-tenant vehicle refused on our job|false|no refusal';
  exception when others then
    r := r || format('Cross-tenant vehicle refused on our job|%s|sqlstate=%s', sqlstate = 'TD404', sqlstate);
  end;

  perform set_config('role', v_super, true);

  return query
    select split_part(x, '|', 1), coalesce(nullif(split_part(x, '|', 2), '')::boolean, false), split_part(x, '|', 3)
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
  for rec in select * from pg_temp.run_engineer_financial_tests() loop
    if rec.passed then v_pass := v_pass + 1; else v_fail := v_fail + 1; end if;
    if not rec.passed then
      v_report := v_report || format(E'\nFAIL  %s  [%s]', rec.test_name, rec.detail);
    end if;
  end loop;
  raise exception E'ENGINEER FINANCIAL SUITE — PASS=% FAIL=% %', v_pass, v_fail, v_report;
end $$;
