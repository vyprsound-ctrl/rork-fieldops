-- =============================================================================
-- TradeDesk — backend security suite (DEVELOPMENT TOOLING, NOT PRODUCTION)
-- =============================================================================
--
-- This is the tenancy / RLS / role-enforcement suite that used to live in the
-- database as `public.run_backend_security_tests()`. That was a mistake: it was
-- a SECURITY-adjacent RPC on a live schema that wrote to `auth.users`, disabled
-- a protection trigger, and was reachable through PostgREST. It has been dropped.
--
-- The validation logic itself is worth keeping, so it lives here instead and is
-- defined in `pg_temp` — a session-local schema. A pg_temp function:
--   * is never visible to `anon` or `authenticated`,
--   * is never exposed through PostgREST,
--   * disappears when the session ends.
--
-- HOW TO RUN
-- ----------
-- Run the whole file as one migration/statement batch. The final DO block always
-- ends in `raise exception`, so the entire transaction — every fixture row, the
-- trigger toggle, and the temp function — is rolled back. The report comes back
-- in the error message. A run that reports FAIL=0 is a pass.
--
-- Never re-create this in the `public` schema.
-- =============================================================================

create or replace function pg_temp.run_backend_security_tests()
returns table(test_name text, passed boolean, detail text)
language plpgsql
as $function$
declare
  r text[] := array[]::text[];
  v_ca uuid; v_cb uuid;
  v_a_owner uuid := gen_random_uuid();
  v_a_admin uuid := gen_random_uuid();
  v_a_disp  uuid := gen_random_uuid();
  v_a_w1    uuid := gen_random_uuid();
  v_a_w2    uuid := gen_random_uuid();
  v_a_acct  uuid := gen_random_uuid();
  v_b_owner uuid := gen_random_uuid();
  v_cust_a uuid; v_cust_b uuid;
  v_addr_a uuid; v_addr_b uuid;
  v_job_a uuid; v_job_a2 uuid; v_job_b uuid;
  v_inv_a uuid; v_quote_a uuid;
  v_n int; v_txt text; v_bad int;
  v_inv_draft uuid; v_tok text; v_tok2 text; v_before text;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
         u.em, 'x', now(), now(), now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, false
  from (values
    (v_a_owner,'a.owner@securitytest.invalid'),
    (v_a_admin,'a.admin@securitytest.invalid'),
    (v_a_disp ,'a.disp@securitytest.invalid'),
    (v_a_w1   ,'a.w1@securitytest.invalid'),
    (v_a_w2   ,'a.w2@securitytest.invalid'),
    (v_a_acct ,'a.acct@securitytest.invalid'),
    (v_b_owner,'b.owner@securitytest.invalid')
  ) as u(id, em);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('SECTEST Alpha','hvac','US','USD','America/New_York') returning id into v_ca;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('SECTEST Beta','plumbing','US','USD','America/Chicago') returning id into v_cb;

  insert into public.app_users (id, company_id, name, email, role) values
    (v_a_owner, v_ca, 'A Owner','a.owner@securitytest.invalid','owner'),
    (v_a_admin, v_ca, 'A Admin','a.admin@securitytest.invalid','admin'),
    (v_a_disp , v_ca, 'A Disp' ,'a.disp@securitytest.invalid','dispatcher'),
    (v_a_w1   , v_ca, 'A W1'   ,'a.w1@securitytest.invalid','fieldWorker'),
    (v_a_w2   , v_ca, 'A W2'   ,'a.w2@securitytest.invalid','fieldWorker'),
    (v_a_acct , v_ca, 'A Acct' ,'a.acct@securitytest.invalid','accounts'),
    (v_b_owner, v_cb, 'B Owner','b.owner@securitytest.invalid','owner');

  insert into public.customers (company_id, name) values (v_ca,'SECTEST Cust A') returning id into v_cust_a;
  insert into public.customers (company_id, name) values (v_cb,'SECTEST Cust B') returning id into v_cust_b;
  insert into public.addresses (company_id, customer_id, line1) values (v_ca, v_cust_a,'1 A St') returning id into v_addr_a;
  insert into public.addresses (company_id, customer_id, line1) values (v_cb, v_cust_b,'1 B St') returning id into v_addr_b;

  insert into public.jobs (company_id, customer_id, address_id, number, title)
    values (v_ca, v_cust_a, v_addr_a, 'SEC-J1','Assigned job') returning id into v_job_a;
  insert into public.jobs (company_id, customer_id, address_id, number, title)
    values (v_ca, v_cust_a, v_addr_a, 'SEC-J2','Unassigned job') returning id into v_job_a2;
  insert into public.jobs (company_id, customer_id, address_id, number, title)
    values (v_cb, v_cust_b, v_addr_b, 'SEC-J3','B job') returning id into v_job_b;

  insert into public.field_worker_assignments (company_id, job_id, user_id, assigned_by_user_id)
    values (v_ca, v_job_a, v_a_w1, v_a_admin);

  insert into public.invoices (company_id, customer_id, number, currency_code,
                               issue_date, due_date, subtotal, tax, total, amount_paid, balance)
    values (v_ca, v_cust_a, 'SEC-INV1','USD', current_date, current_date + 30,
            19.99, 1.40, 21.39, 0, 21.39) returning id into v_inv_a;
  insert into public.invoice_line_items (company_id, invoice_id, item_description, quantity, unit_price, tax_rate, line_total)
    values (v_ca, v_inv_a, 'SECTEST line', 1, 19.99, 0.07, 19.99);
  insert into public.payments (company_id, invoice_id, amount, method, status, recorded_by_user_id)
    values (v_ca, v_inv_a, 10.00, 'cash','succeeded', v_a_acct);
  insert into public.quotes (company_id, customer_id, address_id, number, title, subtotal, tax, total)
    values (v_ca, v_cust_a, v_addr_a, 'SEC-Q1','Quote', 100.00, 7.00, 107.00) returning id into v_quote_a;

  -- A second invoice, left in draft, for the "a draft is never shareable" case.
  insert into public.invoices (company_id, customer_id, number, currency_code,
                               issue_date, due_date, subtotal, tax, total, amount_paid, balance)
    values (v_ca, v_cust_a, 'SEC-INV2','USD', current_date, current_date + 30,
            10.00, 0.70, 10.70, 0, 10.70) returning id into v_inv_draft;

  insert into public.field_worker_locations (company_id, user_id, latitude, longitude, capture_event)
    values (v_ca, v_a_w1, 40.0, -74.0, 'arrived'), (v_ca, v_a_w2, 41.0, -75.0, 'arrived');

  set local role authenticated;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_owner::text,'role','authenticated')::text, true);

  select count(*) into v_n from public.customers where id = v_cust_b;
  r := r || format('A cannot READ B customer|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.jobs where id = v_job_b;
  r := r || format('A cannot READ B job (no existence leak)|%s|rows=%s', (v_n = 0), v_n);

  begin
    insert into public.customers (company_id, name) values (v_cb, 'SECTEST injected');
    r := r || 'A cannot INSERT into B|false|insert unexpectedly succeeded';
  exception when others then
    r := r || format('A cannot INSERT into B|true|%s', replace(sqlerrm,'|','/'));
  end;

  update public.customers set name = 'HIJACKED' where id = v_cust_b;
  get diagnostics v_n = row_count;
  r := r || format('A cannot UPDATE B row|%s|rows_affected=%s', (v_n = 0), v_n);

  delete from public.customers where id = v_cust_b;
  get diagnostics v_n = row_count;
  r := r || format('A cannot DELETE B row|%s|rows_affected=%s', (v_n = 0), v_n);

  begin
    update public.customers set company_id = v_cb where id = v_cust_a;
    get diagnostics v_n = row_count;
    r := r || format('A cannot RE-STAMP row to B|%s|rows_affected=%s', (v_n = 0), v_n);
  exception when others then
    r := r || format('A cannot RE-STAMP row to B|true|%s', replace(sqlerrm,'|','/'));
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_w1::text,'role','authenticated')::text, true);

  select count(*) into v_n from public.invoices;
  r := r || format('Engineer cannot read invoices|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.payments;
  r := r || format('Engineer cannot read payments|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.quotes;
  r := r || format('Engineer cannot read quotes|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.field_worker_locations where user_id = v_a_w2;
  r := r || format('Engineer cannot read other worker location|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.field_worker_locations where user_id = v_a_w1;
  r := r || format('Engineer CAN read own location|%s|rows=%s', (v_n = 1), v_n);

  select count(*) into v_n from public.jobs where id = v_job_a;
  r := r || format('Engineer CAN read assigned job|%s|rows=%s', (v_n = 1), v_n);

  select count(*) into v_n from public.jobs where id = v_job_a2;
  r := r || format('Engineer cannot read unassigned job|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.customers;
  r := r || format('Engineer cannot read customer list|%s|rows=%s', (v_n = 0), v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_disp::text,'role','authenticated')::text, true);

  select count(*) into v_n from public.invoices;
  r := r || format('Dispatcher cannot read invoices|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.payments;
  r := r || format('Dispatcher cannot read payments|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.quotes;
  r := r || format('Dispatcher cannot read quote money|%s|rows=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.quotes_operational;
  r := r || format('Dispatcher CAN read money-free quote view|%s|rows=%s', (v_n = 1), v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_acct::text,'role','authenticated')::text, true);

  update public.jobs set title = 'ACCOUNTS EDIT' where id = v_job_a;
  get diagnostics v_n = row_count;
  r := r || format('Accounts cannot mutate jobs|%s|rows_affected=%s', (v_n = 0), v_n);

  begin
    insert into public.jobs (company_id, customer_id, address_id, number, title)
      values (v_ca, v_cust_a, v_addr_a, 'SEC-ACCT','x');
    r := r || 'Accounts cannot create jobs|false|insert unexpectedly succeeded';
  exception when others then
    r := r || format('Accounts cannot create jobs|true|%s', replace(sqlerrm,'|','/'));
  end;

  -- Two invoices are seeded for company A: the sent one and the draft used by
  -- the share-link cases below.
  select count(*) into v_n from public.invoices;
  r := r || format('Accounts CAN read invoices|%s|rows=%s', (v_n = 2), v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_w1::text,'role','authenticated')::text, true);
  begin
    update public.app_users set company_id = v_cb where id = v_a_w1;
    r := r || 'User cannot self-assign to another company|false|update unexpectedly succeeded';
  exception when others then
    r := r || format('User cannot self-assign to another company|true|%s', replace(sqlerrm,'|','/'));
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_admin::text,'role','authenticated')::text, true);
  begin
    update public.app_users set role = 'owner' where id = v_a_admin;
    r := r || 'User cannot escalate own role|false|update unexpectedly succeeded';
  exception when others then
    r := r || format('User cannot escalate own role|true|%s', replace(sqlerrm,'|','/'));
  end;

  begin
    update public.app_users set role = 'owner' where id = v_a_disp;
    r := r || 'Non-owner cannot create an Owner|false|update unexpectedly succeeded';
  exception when others then
    r := r || format('Non-owner cannot create an Owner|true|%s', replace(sqlerrm,'|','/'));
  end;

  begin
    update public.app_users set role = 'admin' where id = v_a_owner;
    r := r || 'Last Owner cannot be demoted|false|update unexpectedly succeeded';
  exception when others then
    r := r || format('Last Owner cannot be demoted|true|%s', replace(sqlerrm,'|','/'));
  end;

  begin
    delete from public.app_users where id = v_a_owner;
    get diagnostics v_n = row_count;
    r := r || format('Last Owner cannot be deleted|%s|rows_affected=%s', (v_n = 0), v_n);
  exception when others then
    r := r || format('Last Owner cannot be deleted|true|%s', replace(sqlerrm,'|','/'));
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_w1::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.app_users;
  r := r || format('Engineer sees only own membership row|%s|rows=%s', (v_n = 1), v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_owner::text,'role','authenticated')::text, true);
  begin
    perform public.create_company_and_owner('SECTEST Gamma','other','US','USD','America/New_York');
    r := r || 'User cannot create a second company|false|rpc unexpectedly succeeded';
  exception when others then
    r := r || format('User cannot create a second company|true|%s', replace(sqlerrm,'|','/'));
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_disp::text,'role','authenticated')::text, true);
  begin
    perform public.create_invitation('intruder@securitytest.invalid','admin',7);
    r := r || 'Dispatcher cannot issue invitations|false|rpc unexpectedly succeeded';
  exception when others then
    r := r || format('Dispatcher cannot issue invitations|true|%s', replace(sqlerrm,'|','/'));
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_admin::text,'role','authenticated')::text, true);
  begin
    perform public.create_invitation('newowner@securitytest.invalid','owner',7);
    r := r || 'Admin cannot invite an Owner|false|rpc unexpectedly succeeded';
  exception when others then
    r := r || format('Admin cannot invite an Owner|true|%s', replace(sqlerrm,'|','/'));
  end;

  begin
    update public.jobs set status = 'completed' where id = v_job_a2;
    r := r || 'Invalid job transition rejected by DB|false|update unexpectedly succeeded';
  exception when others then
    r := r || format('Invalid job transition rejected by DB|true|%s', replace(sqlerrm,'|','/'));
  end;

  update public.jobs set status = 'workerAssigned' where id = v_job_a2;
  get diagnostics v_n = row_count;
  r := r || format('Valid job transition accepted|%s|rows_affected=%s', (v_n = 1), v_n);

  select total::text into v_txt from public.invoices where id = v_inv_a;
  r := r || format('Invoice total is exact decimal 21.39|%s|total=%s', (v_txt = '21.39'), v_txt);

  -- ================================================ online payment link
  -- TradeDesk stores a URL and nothing else. The database refuses anything
  -- that isn't a credential-free https address, and only companyProfileManage
  -- may write it at all.

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_acct::text,'role','authenticated')::text, true);
  update public.companies set online_payment_link_url = 'https://buy.stripe.com/acct' where id = v_ca;
  get diagnostics v_n = row_count;
  r := r || format('Accounts cannot set the payment link|%s|rows_affected=%s', (v_n = 0), v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_disp::text,'role','authenticated')::text, true);
  update public.companies set online_payment_link_url = 'https://buy.stripe.com/disp' where id = v_ca;
  get diagnostics v_n = row_count;
  r := r || format('Dispatcher cannot set the payment link|%s|rows_affected=%s', (v_n = 0), v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_owner::text,'role','authenticated')::text, true);

  begin
    update public.companies set online_payment_link_url = 'http://pay.example.com/x' where id = v_ca;
    r := r || 'Plain http payment link refused|false|update unexpectedly succeeded';
  exception when others then
    r := r || format('Plain http payment link refused|true|%s', replace(sqlerrm,'|','/'));
  end;

  begin
    update public.companies set online_payment_link_url = 'https://user:pw@pay.example.com/x' where id = v_ca;
    r := r || 'Payment link with credentials refused|false|update unexpectedly succeeded';
  exception when others then
    r := r || format('Payment link with credentials refused|true|%s', replace(sqlerrm,'|','/'));
  end;

  begin
    update public.companies set online_payment_link_url = 'javascript:alert(1)' where id = v_ca;
    r := r || 'javascript: payment link refused|false|update unexpectedly succeeded';
  exception when others then
    r := r || format('javascript: payment link refused|true|%s', replace(sqlerrm,'|','/'));
  end;

  update public.companies set online_payment_link_url = 'https://buy.stripe.com/test_ok' where id = v_ca;
  select online_payment_link_url into v_txt from public.companies where id = v_ca;
  r := r || format('Owner CAN set a real https payment link|%s|stored=%s', (v_txt = 'https://buy.stripe.com/test_ok'), coalesce(v_txt,'null'));

  update public.companies set online_payment_link_url = null where id = v_ca;
  select online_payment_link_url into v_txt from public.companies where id = v_ca;
  r := r || format('Payment link can be cleared|%s|stored=%s', (v_txt is null), coalesce(v_txt,'null'));

  -- ============================================ customer-facing share links

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_acct::text,'role','authenticated')::text, true);
  perform public.update_invoice_status(v_inv_a, 'sent');

  -- What the invoice says is owed *before* anything is shared or sent.
  select format('%s/%s/%s', status, amount_paid, balance) into v_before
    from public.invoices where id = v_inv_a;

  begin
    perform public.issue_invoice_share_token(v_inv_draft, false);
    r := r || 'A draft invoice cannot be shared|false|token unexpectedly issued';
  exception when others then
    r := r || format('A draft invoice cannot be shared|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  v_tok := public.issue_invoice_share_token(v_inv_a, false);
  r := r || format('Share token is 32 random bytes|%s|len=%s', (v_tok ~ '^[a-f0-9]{64}$'), length(coalesce(v_tok,'')));

  r := r || format('Share token carries no identifier|%s|token is opaque',
    (position(v_inv_a::text in v_tok) = 0 and position(v_ca::text in v_tok) = 0
     and position(v_cust_a::text in v_tok) = 0 and position('SEC-INV1' in v_tok) = 0));

  r := r || format('Re-issuing returns the same live link|%s|stable',
    (public.issue_invoice_share_token(v_inv_a, false) = v_tok));

  v_tok2 := public.issue_invoice_share_token(v_inv_a, true);
  select count(*) into v_n from public.invoice_share_tokens
   where invoice_id = v_inv_a and revoked_at is null;
  r := r || format('Rotation replaces the link, leaving one live|%s|different=%s live=%s',
    (v_tok2 <> v_tok and v_n = 1), (v_tok2 <> v_tok), v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_disp::text,'role','authenticated')::text, true);
  begin
    perform public.issue_invoice_share_token(v_inv_a, false);
    r := r || 'Dispatcher cannot issue a share link|false|token unexpectedly issued';
  exception when others then
    r := r || format('Dispatcher cannot issue a share link|%s|sqlstate=%s', sqlstate = 'TD401', sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_w1::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.invoice_share_tokens;
  r := r || format('Engineer cannot read share tokens|%s|rows=%s', (v_n = 0), v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_b_owner::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.invoice_share_tokens;
  r := r || format('Another tenant cannot read A share tokens|%s|rows=%s', (v_n = 0), v_n);

  update public.invoice_share_tokens set revoked_at = null where invoice_id = v_inv_a;
  get diagnostics v_n = row_count;
  r := r || format('Another tenant cannot revive a revoked link|%s|rows_affected=%s', (v_n = 0), v_n);

  begin
    perform public.revoke_invoice_share_tokens(v_inv_a);
    r := r || 'Another tenant cannot revoke A links|false|rpc unexpectedly succeeded';
  exception when others then
    r := r || format('Another tenant cannot revoke A links|%s|sqlstate=%s', sqlstate in ('TD401','TD404'), sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_a_acct::text,'role','authenticated')::text, true);
  perform public.revoke_invoice_share_tokens(v_inv_a);
  select count(*) into v_n from public.invoice_share_tokens
   where invoice_id = v_inv_a and revoked_at is null;
  r := r || format('Revoking kills every live link|%s|live=%s', (v_n = 0), v_n);

  select count(*) into v_n from public.invoice_share_tokens where invoice_id = v_inv_a;
  r := r || format('Revoked links are kept for the audit trail|%s|rows=%s', (v_n = 2), v_n);

  -- Delivery never moves money: the invoice is untouched by all of the above.
  select format('%s/%s/%s', status, amount_paid, balance) into v_txt
    from public.invoices where id = v_inv_a;
  r := r || format('Sharing an invoice never changes what is owed|%s|status/paid/balance %s then %s',
    (v_txt = v_before), v_before, v_txt);

  reset role;

  select count(*) into v_bad
  from information_schema.columns c
  join pg_class pc on pc.relname = c.table_name
  join pg_namespace pn on pn.oid = pc.relnamespace and pn.nspname = 'public'
  where c.table_schema = 'public'
    and c.column_name = 'company_id'
    and pc.relkind = 'r'
    and pc.relrowsecurity = false;
  r := r || format('RLS on every company-scoped table|%s|without_rls=%s', (v_bad = 0), v_bad);

  select count(*) into v_bad
  from pg_class pc
  join pg_namespace pn on pn.oid = pc.relnamespace and pn.nspname = 'public'
  where pc.relkind = 'r' and pc.relrowsecurity = false;
  r := r || format('RLS on every public table|%s|without_rls=%s', (v_bad = 0), v_bad);

  -- Extra guard added when the RPC was retired: prove the dangerous entry point
  -- is gone from the public schema and therefore off PostgREST.
  select count(*) into v_bad
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'run_backend_security_tests';
  r := r || format('Security suite is NOT a public RPC|%s|public_functions=%s', (v_bad = 0), v_bad);

  alter table public.app_users disable trigger app_users_delete_protection;

  delete from public.payments where company_id in (v_ca, v_cb);
  delete from public.invoice_share_tokens where company_id in (v_ca, v_cb);
  delete from public.invoice_line_items where company_id in (v_ca, v_cb);
  delete from public.invoices where company_id in (v_ca, v_cb);
  delete from public.quote_line_items where company_id in (v_ca, v_cb);
  delete from public.notifications where company_id in (v_ca, v_cb);
  delete from public.sms_credit_ledger where company_id in (v_ca, v_cb);
  delete from public.job_status_history where company_id in (v_ca, v_cb);
  delete from public.job_notes where company_id in (v_ca, v_cb);
  delete from public.job_photos where company_id in (v_ca, v_cb);
  delete from public.field_worker_locations where company_id in (v_ca, v_cb);
  delete from public.field_worker_assignments where company_id in (v_ca, v_cb);
  update public.jobs set quote_id = null where company_id in (v_ca, v_cb);
  delete from public.quotes where company_id in (v_ca, v_cb);
  delete from public.jobs where company_id in (v_ca, v_cb);
  delete from public.service_agreements where company_id in (v_ca, v_cb);
  delete from public.equipment_history where company_id in (v_ca, v_cb);
  delete from public.equipment where company_id in (v_ca, v_cb);
  delete from public.customer_contacts where company_id in (v_ca, v_cb);
  delete from public.addresses where company_id in (v_ca, v_cb);
  delete from public.customers where company_id in (v_ca, v_cb);
  delete from public.document_sequences where company_id in (v_ca, v_cb);
  delete from public.company_subscriptions where company_id in (v_ca, v_cb);
  delete from public.invitations where company_id in (v_ca, v_cb);
  delete from public.app_users where company_id in (v_ca, v_cb);
  delete from public.companies where id in (v_ca, v_cb);
  delete from auth.users where email like '%@securitytest.invalid';

  alter table public.app_users enable trigger app_users_delete_protection;

  -- Boolean output is 't'/'f'; casting accepts that and 'true'/'false'.
  return query
    select split_part(x, '|', 1),
           split_part(x, '|', 2)::boolean,
           split_part(x, '|', 3)
    from unnest(r) as x;
exception when others then
  reset role;
  begin
    alter table public.app_users enable trigger app_users_delete_protection;
  exception when others then
    null;
  end;
  raise;
end;
$function$;

-- Runner. Always raises so the whole transaction rolls back.
do $runner$
declare
  v_report text := '';
  v_pass int := 0;
  v_fail int := 0;
  rec record;
begin
  for rec in select * from pg_temp.run_backend_security_tests() loop
    if rec.passed then
      v_pass := v_pass + 1;
    else
      v_fail := v_fail + 1;
      v_report := v_report || chr(10) || 'FAIL: ' || rec.test_name || ' -- ' || coalesce(rec.detail,'');
    end if;
  end loop;

  raise exception 'SECURITY SUITE  pass=% fail=% %', v_pass, v_fail, v_report;
end
$runner$;
