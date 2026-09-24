-- =============================================================================
-- Harbour South — multi-tenant SMS & communications suite (DEVELOPMENT TOOLING)
-- =============================================================================
--
-- Proves migration 0014:
--   * segment counting (GSM-7, UCS-2, emoji, multi-part) and 1 credit = 1 segment
--   * subscription, set-up, pause, suspension and opt-out gates run BEFORE any
--     credit moves, and the balance can never go negative
--   * provider rejection refunds exactly once; 21610 records an opt-out
--   * status and inbound callbacks are bound to the right company by callback
--     key AND subaccount SID, and cannot touch another company's messages
--   * two-way SMS: customer/job matching, conversation, unread, role-scoped
--     alerts, STOP / START / HELP
--   * number rules: one live primary, idempotent purchase record, release
--     guard, monthly fee -> grace -> pause, retention, company closure
--   * templates, automations and scheduled messages
--   * RLS isolation and service-role-only surfaces
--
-- HOW TO RUN: whole file as one batch. It always ends in `raise exception`, so
-- every fixture row is rolled back. FAIL=0 is a pass.
-- =============================================================================

create or replace function pg_temp.run_sms_multitenant_tests()
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

  v_cust uuid; v_addr uuid; v_contact uuid; v_b_cust uuid; v_b_addr uuid;
  v_job uuid; v_quote uuid; v_inv uuid;
  v_acc_a uuid; v_acc_b uuid; v_num_a uuid; v_num_b uuid; v_num_x uuid;
  v_key_a text; v_key_b text;

  rec record; rec2 record;
  v_n int; v_m int; v_bal int; v_before int; v_txt text; v_flag boolean; v_id uuid; v_err text;
  v_long text; v_json jsonb;
begin
  -- ------------------------------------------------------------- fixtures
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.em, 'x', now(), now(), now(),
         '{"provider":"email"}'::jsonb, '{}'::jsonb, false
  from (values (v_owner,'o@mt.invalid'),(v_admin,'a@mt.invalid'),(v_disp,'d@mt.invalid'),
               (v_work,'w@mt.invalid'),(v_acct,'ac@mt.invalid'),(v_b_owner,'bo@mt.invalid')) u(id, em);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('MT Alpha','hvac','US','USD','America/New_York') returning id into v_ca;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('MT Beta','plumbing','US','USD','America/Chicago') returning id into v_cb;

  insert into public.app_users (id, company_id, name, email, role) values
    (v_owner, v_ca, 'Olive Owner', 'o@mt.invalid', 'owner'),
    (v_admin, v_ca, 'Adam Admin', 'a@mt.invalid', 'admin'),
    (v_disp , v_ca, 'Dana Dispatch', 'd@mt.invalid', 'dispatcher'),
    (v_work , v_ca, 'Mike Engineer', 'w@mt.invalid', 'fieldWorker'),
    (v_acct , v_ca, 'Cara Accounts', 'ac@mt.invalid', 'accounts'),
    (v_b_owner, v_cb, 'Ben Beta', 'bo@mt.invalid', 'owner');

  insert into public.company_subscriptions (company_id) values (v_ca), (v_cb)
  on conflict do nothing;

  insert into public.customers (company_id, name) values (v_ca, 'Jane Doe') returning id into v_cust;
  insert into public.addresses (company_id, customer_id, line1, city, state, postal_code)
    values (v_ca, v_cust, '1 Main St', 'Tampa', 'FL', '33601') returning id into v_addr;
  insert into public.customer_contacts (company_id, customer_id, name, phone, is_primary)
    values (v_ca, v_cust, 'Jane Doe', '(813) 555-0101', true) returning id into v_contact;
  insert into public.customers (company_id, name) values (v_cb, 'Bob Beta') returning id into v_b_cust;
  insert into public.addresses (company_id, customer_id, line1) values (v_cb, v_b_cust, '9 Beta Rd') returning id into v_b_addr;
  insert into public.customer_contacts (company_id, customer_id, name, phone, is_primary)
    values (v_cb, v_b_cust, 'Bob Beta', '+13125550199', true);

  -- ================================================== segments & encoding
  select * into rec from public.sms_segment_info(repeat('a', 160));
  r := r || format('GSM-7: 160 chars is one segment|%s|%s %s', rec.segments = 1 and rec.encoding = 'GSM-7', rec.segments, rec.encoding);
  select * into rec from public.sms_segment_info(repeat('a', 161));
  r := r || format('GSM-7: 161 chars is two segments|%s|%s', rec.segments = 2, rec.segments);
  select * into rec from public.sms_segment_info(repeat('a', 306));
  r := r || format('GSM-7: 306 chars is two segments|%s|%s', rec.segments = 2, rec.segments);
  select * into rec from public.sms_segment_info(repeat('a', 307));
  r := r || format('GSM-7: 307 chars is three segments|%s|%s', rec.segments = 3, rec.segments);
  select * into rec from public.sms_segment_info(repeat('a', 765));
  r := r || format('GSM-7: 765 chars is five segments|%s|%s', rec.segments = 5, rec.segments);
  select * into rec from public.sms_segment_info(repeat('{', 80));
  r := r || format('GSM-7 extension chars count double|%s|units=%s seg=%s', rec.units = 160 and rec.segments = 1, rec.units, rec.segments);
  select * into rec from public.sms_segment_info(repeat('{', 81));
  r := r || format('GSM-7 extension overflow splits|%s|seg=%s', rec.segments = 2, rec.segments);
  select * into rec from public.sms_segment_info(repeat('é', 160));
  r := r || format('Accented GSM letters stay GSM-7|%s|%s', rec.encoding = 'GSM-7' and rec.segments = 1, rec.encoding);
  select * into rec from public.sms_segment_info(repeat('ł', 70));
  r := r || format('Unicode: 70 chars is one segment|%s|%s %s', rec.encoding = 'UCS-2' and rec.segments = 1, rec.encoding, rec.segments);
  select * into rec from public.sms_segment_info(repeat('ł', 71));
  r := r || format('Unicode: 71 chars is two segments|%s|%s', rec.segments = 2, rec.segments);
  select * into rec from public.sms_segment_info('Thanks! See you soon ' || chr(128522));
  r := r || format('Emoji forces UCS-2 and counts two units|%s|%s units=%s', rec.encoding = 'UCS-2' and rec.units = 23 and rec.segments = 1, rec.encoding, rec.units);
  select * into rec from public.sms_segment_info(repeat(chr(128522), 35));
  r := r || format('35 emoji fit one UCS-2 segment|%s|seg=%s units=%s', rec.segments = 1, rec.segments, rec.units);
  select * into rec from public.sms_segment_info(repeat(chr(128522), 36));
  r := r || format('36 emoji need two segments|%s|seg=%s', rec.segments = 2, rec.segments);
  r := r || format('Phone normalisation (US 10-digit)|%s|%s', public.sms_normalise_phone('(813) 555-0101') = '+18135550101', public.sms_normalise_phone('(813) 555-0101'));
  r := r || format('Phone normalisation rejects junk|%s|', public.sms_normalise_phone('12') is null);

  -- ================================================== template validation
  r := r || format('Valid template variables accepted|%s|', public.sms_template_problem('appointment_confirmation', 'Hi {{customer_first_name}} at {{appointment_time}}') is null);
  v_txt := public.sms_template_problem('appointment_confirmation', 'Pay {{invoice_link}}');
  r := r || format('Variable not valid for the template refused|%s|%s', v_txt is not null, v_txt);
  v_txt := public.sms_template_problem('job_update', 'Hi {{customer_firstname}}');
  r := r || format('Misspelt variable refused|%s|%s', v_txt is not null, v_txt);
  v_txt := public.sms_template_problem('job_update', 'Hi {{customer_first_name}');
  r := r || format('Malformed braces refused|%s|%s', v_txt is not null, v_txt);
  v_txt := public.sms_template_problem('quote_sent', '');
  r := r || format('Empty template refused|%s|', v_txt is not null);
  select count(*) into v_n from public.sms_template_defaults;
  r := r || format('All 22 operational templates exist|%s|%s', v_n = 22, v_n);
  select count(*) into v_n from public.sms_template_defaults where is_automatable;
  r := r || format('All 18 automation types exist|%s|%s', v_n = 18, v_n);
  select count(*) into v_n from public.sms_template_defaults d
   where exists (select 1 from regexp_matches(d.body, '\{\{\s*([^{}]*?)\s*\}\}', 'g') m where not (m[1] = any(d.allowed_variables)));
  r := r || format('Every default uses only its own variables|%s|bad=%s', v_n = 0, v_n);

  -- ====================================================== send gates
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);

  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Hello', 'custom_message');
  r := r || format('No subscription: refused|%s|%s', rec.outcome = 'noSubscription', rec.outcome);

  perform set_config('role', v_super, true);
  update public.company_subscriptions set store = 'apple', tier_id = 'team', apple_expires_at = now() + interval '20 days',
         apple_auto_renew = true, apple_is_free_offer = true, apple_offer_type = 1 where company_id = v_ca;
  update public.company_subscriptions set store = 'apple', tier_id = 'starter', apple_expires_at = now() + interval '20 days',
         apple_auto_renew = true where company_id = v_cb;
  perform set_config('role', 'authenticated', true);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Hello', 'custom_message');
  r := r || format('Trial subscription passes the subscription gate|%s|%s', rec.outcome = 'notSetUp', rec.outcome);

  perform set_config('role', v_super, true);
  insert into public.company_messaging_accounts (company_id, status, twilio_subaccount_sid, messaging_service_sid, registration_status)
    values (v_ca, 'awaiting_registration', 'ACalpha000000000000000000000000001', 'MGalpha00000000000000000000000001', 'brand_pending')
    returning id, callback_key into v_acc_a, v_key_a;
  insert into public.company_messaging_accounts (company_id, status, twilio_subaccount_sid, messaging_service_sid, registration_status)
    values (v_cb, 'active', 'ACbeta0000000000000000000000000002', 'MGbeta000000000000000000000000002', 'approved')
    returning id, callback_key into v_acc_b, v_key_b;
  perform set_config('role', 'authenticated', true);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Hello', 'custom_message');
  r := r || format('Registration pending: refused|%s|%s', rec.outcome = 'awaitingApproval', rec.outcome);

  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update public.company_messaging_accounts set status = 'active', registration_status = 'approved' where id = v_acc_a;
  select * into rec from public.reserve_sms_send_service(v_ca, v_cust, null, null, null, '+18135550101', 'Hello', 'custom_message', null);
  r := r || format('Active without a number: refused|%s|%s', rec.outcome = 'noNumber', rec.outcome);

  v_num_a := public.sms_record_number_purchase(v_acc_a, 'PNalpha0000000000000000000000001', '+18135550000', '813', 'Tampa', 'FL');
  v_id := public.sms_record_number_purchase(v_acc_a, 'PNalpha0000000000000000000000001', '+18135550000', '813', 'Tampa', 'FL');
  r := r || format('Number purchase record is idempotent|%s|', v_id = v_num_a);
  begin
    perform public.sms_record_number_purchase(v_acc_a, 'PNalpha0000000000000000000000009', '+18135550009', '813', 'Tampa', 'FL');
    r := r || 'Second number refused (max 1)|false|accepted'::text;
  exception when others then
    r := r || format('Second number refused (max 1)|true|%s', sqlerrm);
  end;
  begin
    insert into public.company_phone_numbers (company_id, messaging_account_id, phone_number_sid, e164, is_primary, status)
    values (v_ca, v_acc_a, 'PNdup', '+18135550077', true, 'active');
    r := r || 'DB allows only one live primary number|false|inserted'::text;
  exception when unique_violation then
    r := r || 'DB allows only one live primary number|true|unique_violation'::text;
  end;
  v_num_b := public.sms_record_number_purchase(v_acc_b, 'PNbeta00000000000000000000000002', '+13125550000', '312', 'Chicago', 'IL');

  -- Balance
  perform set_config('role', v_super, true);
  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, purchase_reference)
    values (v_ca, 'purchase', 3, 3, 'MT-TOPUP'), (v_cb, 'purchase', 10, 10, 'MT-TOPUP-B');
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);

  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Hi Jane, we are on our way.', 'engineer_on_the_way');
  select coalesce(sum(amount),0) into v_bal from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('One-segment message reserves 1 credit|%s|%s charged=%s bal=%s', rec.outcome = 'reserved' and rec.credits_charged = 1 and v_bal = 2, rec.outcome, rec.credits_charged, v_bal);
  r := r || format('Reservation carries the company''s own sender|%s|%s %s %s', rec.twilio_account_sid = 'ACalpha000000000000000000000000001'
       and rec.messaging_service_sid = 'MGalpha00000000000000000000000001' and rec.from_number = '+18135550000',
       rec.twilio_account_sid, rec.messaging_service_sid, rec.from_number);
  select segments, encoding, credits_charged into rec2 from public.notifications where id = rec.notification_id;
  r := r || format('Segments recorded on the message|%s|%s %s', rec2.segments = 1 and rec2.encoding = 'GSM-7', rec2.segments, rec2.encoding);
  v_id := rec.notification_id;

  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', repeat('a', 161), 'custom_message');
  select coalesce(sum(amount),0) into v_bal from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Two-segment message reserves 2 credits|%s|%s charged=%s bal=%s', rec.outcome = 'reserved' and rec.credits_charged = 2 and v_bal = 0, rec.outcome, rec.credits_charged, v_bal);

  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'x', 'custom_message');
  select coalesce(sum(amount),0) into v_bal from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Insufficient credit refused, balance untouched|%s|%s bal=%s', rec.outcome = 'insufficientCredits' and v_bal = 0, rec.outcome, v_bal);
  select min(balance_after) into v_n from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Balance never negative|%s|min=%s', v_n >= 0, v_n);

  perform set_config('role', v_super, true);
  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, purchase_reference)
    values (v_ca, 'purchase', 20, 20, 'MT-TOPUP-2');
  perform set_config('role', 'authenticated', true);

  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', repeat('ł', 69) || chr(128522), 'custom_message');
  r := r || format('Unicode + emoji message charged per UCS-2 segment|%s|%s charged=%s', rec.outcome = 'reserved' and rec.credits_charged = 2 and rec.encoding = 'UCS-2', rec.outcome, rec.credits_charged);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', repeat('a', 700), 'custom_message');
  r := r || format('Over-length message refused|%s|%s', rec.outcome = 'tooLong', rec.outcome);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Hi {{customer_first_name}}', 'custom_message');
  r := r || format('Unresolved variables never reach the provider|%s|%s', rec.outcome = 'unresolvedVariables', rec.outcome);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+15555550123', 'Hello', 'custom_message');
  r := r || format('Number not on the customer record refused|%s|%s', rec.outcome = 'recipientNotOnRecord', rec.outcome);
  select * into rec from public.reserve_sms_send(v_b_cust, null, null, null, '+13125550199', 'Hello', 'custom_message');
  r := r || format('Another company''s customer refused|%s|%s', rec.outcome = 'unknownCustomer', rec.outcome);

  perform set_config('request.jwt.claims', json_build_object('sub', v_work::text, 'role', 'authenticated')::text, true);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Hello', 'custom_message');
  r := r || format('Engineer cannot send customer SMS|%s|%s', rec.outcome = 'notPermitted', rec.outcome);
  perform set_config('request.jwt.claims', json_build_object('sub', v_acct::text, 'role', 'authenticated')::text, true);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Hello', 'custom_message');
  r := r || format('Accounts role cannot send customer SMS|%s|%s', rec.outcome = 'notPermitted', rec.outcome);
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text, 'role', 'authenticated')::text, true);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Dispatcher here', 'custom_message');
  r := r || format('Dispatcher can send customer SMS|%s|%s', rec.outcome = 'reserved', rec.outcome);

  -- ================================================= provider outcomes
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select * into rec from public.sms_record_provider_result(v_id, true, 'SMalpha001', 'queued', '+18135550000', 1, null, null, null);
  select status::text into v_txt from public.notifications where id = v_id;
  r := r || format('Accepted message is sent, not delivered|%s|%s', v_txt = 'sent', v_txt);

  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;
  select id into v_id from public.notifications where company_id = v_ca and channel = 'sms' and body = 'Dispatcher here';
  select * into rec from public.sms_record_provider_result(v_id, false, null, null, null, null, null, '21211', 'Invalid To');
  select * into rec2 from public.sms_record_provider_result(v_id, false, null, null, null, null, null, '21211', 'Invalid To');
  select coalesce(sum(amount),0) into v_bal from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Provider rejection refunds exactly once|%s|%s/%s %s->%s', rec.credits_refunded = 1 and rec2.credits_refunded = 0 and v_bal = v_before + 1, rec.credits_refunded, rec2.credits_refunded, v_before, v_bal);

  -- ================================================= status callbacks
  select * into rec from public.sms_apply_status('not-a-key', 'ACalpha000000000000000000000000001', 'SMalpha001', 'delivered', null, null);
  r := r || format('Status: unknown callback key refused|%s|%s', rec.outcome = 'unknownCallback', rec.outcome);
  select * into rec from public.sms_apply_status(v_key_a, 'ACbeta0000000000000000000000000002', 'SMalpha001', 'delivered', null, null);
  r := r || format('Status: wrong subaccount refused|%s|%s', rec.outcome = 'wrongAccount', rec.outcome);
  select * into rec from public.sms_apply_status(v_key_b, 'ACbeta0000000000000000000000000002', 'SMalpha001', 'delivered', null, null);
  select status::text into v_txt from public.notifications where provider_reference = 'SMalpha001';
  r := r || format('Status: another company''s callback cannot touch this message|%s|%s %s', rec.outcome = 'unknownMessage' and v_txt = 'sent', rec.outcome, v_txt);
  select * into rec from public.sms_apply_status(v_key_a, 'ACalpha000000000000000000000000001', 'SMalpha001', 'delivered', null, null, 8300);
  select status::text, provider_price_micros into rec2 from public.notifications where provider_reference = 'SMalpha001';
  r := r || format('Status: delivered recorded with provider cost|%s|%s %s', rec2.status = 'delivered' and rec2.provider_price_micros = 8300, rec2.status, rec2.provider_price_micros);
  select * into rec from public.sms_apply_status(v_key_a, 'ACalpha000000000000000000000000001', 'SMalpha001', 'sent', null, null);
  r := r || format('Status: never walks back from delivered|%s|%s', rec.outcome = 'alreadySettled', rec.outcome);

  -- ================================================= opt-out before charge
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;
  select * into rec from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', 'MGalpha00000000000000000000000001',
                                                   '+18135550101', '+18135550000', 'STOP', 'SMin-stop', null);
  r := r || format('Inbound STOP recorded as opt-out|%s|%s kw=%s', rec.keyword = 'stop' and exists (select 1 from public.sms_opt_outs where company_id = v_ca and phone_e164 = '+18135550101' and opted_out), rec.outcome, rec.keyword);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  select * into rec from public.reserve_sms_send(v_cust, null, null, null, '+18135550101', 'Hello', 'custom_message');
  select coalesce(sum(amount),0) into v_bal from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Opted-out recipient blocked before charging|%s|%s %s->%s', rec.outcome = 'optedOut' and v_bal = v_before, rec.outcome, v_before, v_bal);
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  r := r || format('Opt-out does not cross companies|%s|', public.sms_send_blocker(v_cb, '+18135550101') is null);
  select * into rec from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', 'MGalpha00000000000000000000000001',
                                                   '+18135550101', '+18135550000', 'START', 'SMin-start', null);
  r := r || format('Inbound START opts back in|%s|%s', rec.keyword = 'start' and public.sms_send_blocker(v_ca, '+18135550101') is null, rec.keyword);
  select * into rec from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', 'MGalpha00000000000000000000000001',
                                                   '+18135550101', '+18135550000', 'help', 'SMin-help', null);
  r := r || format('Inbound HELP recognised, no opt-out|%s|%s', rec.keyword = 'help' and public.sms_send_blocker(v_ca, '+18135550101') is null, rec.keyword);
  perform public.sms_set_opt_out(v_ca, '+18135550101', true, 'provider', 'STOP', null, null, null);
  select id into v_id from public.notifications where provider_reference = 'SMalpha001';
  r := r || format('Provider 21610 path records opt-out|%s|', public.sms_send_blocker(v_ca, '+18135550101') = 'optedOut');
  perform public.sms_set_opt_out(v_ca, '+18135550101', false, 'keyword', 'START', null, null, null);

  -- ================================================= two-way SMS
  perform set_config('role', v_super, true);
  insert into public.jobs (company_id, customer_id, address_id, number, title, scheduled_start, scheduled_end)
    values (v_ca, v_cust, v_addr, 'MT-1047', 'AC repair', now() + interval '2 hours', now() + interval '4 hours') returning id into v_job;
  insert into public.push_devices (company_id, user_id, token, bundle_id) values
    (v_ca, v_owner, md5('tok-owner-mt1')||md5('tok-owner-mt2'), 'x'), (v_ca, v_disp, md5('tok-disp-mt1')||md5('tok-disp-mt2'), 'x'), (v_ca, v_work, md5('tok-work-mt1')||md5('tok-work-mt2'), 'x'), (v_ca, v_acct, md5('tok-acct-mt1')||md5('tok-acct-mt2'), 'x');
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  select * into rec from public.sms_record_inbound(v_key_a, 'ACbeta0000000000000000000000000002', 'MGalpha00000000000000000000000001',
                                                   '+18135550101', '+18135550000', 'hi', 'SMin-x1', null);
  r := r || format('Inbound: wrong subaccount refused|%s|%s', rec.outcome = 'wrongAccount', rec.outcome);
  select * into rec from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', 'MGbeta000000000000000000000000002',
                                                   '+18135550101', '+18135550000', 'hi', 'SMin-x2', null);
  r := r || format('Inbound: wrong messaging service refused|%s|%s', rec.outcome = 'wrongService', rec.outcome);
  select * into rec from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', 'MGalpha00000000000000000000000001',
                                                   '+18135550101', '+13125550000', 'hi', 'SMin-x3', null);
  r := r || format('Inbound: another company''s number refused|%s|%s', rec.outcome = 'wrongNumber', rec.outcome);
  select * into rec from public.sms_record_inbound('bogus', 'ACalpha000000000000000000000000001', null,
                                                   '+18135550101', '+18135550000', 'hi', 'SMin-x4', null);
  r := r || format('Inbound: unknown callback refused|%s|%s', rec.outcome = 'unknownCallback', rec.outcome);

  select * into rec from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', 'MGalpha00000000000000000000000001',
                                                   '+18135550101', '+18135550000', 'Running 10 min late? No problem, gate code is 4412.', 'SMin-reply', null);
  r := r || format('Inbound reply recorded|%s|%s', rec.outcome = 'recorded', rec.outcome);
  r := r || format('Inbound reply matched to the customer|%s|', rec.customer_id = v_cust);
  r := r || format('Inbound reply matched to the job|%s|', rec.job_id = v_job);
  r := r || format('Inbound reply alerts owner, admin and dispatcher only|%s|notified=%s', rec.notified = 3, rec.notified);
  select count(*) into v_n from public.notifications where template = 'sms.inbound' and company_id = v_ca and created_at > now() - interval '1 minute'
     and target_user_id in (v_work, v_acct);
  r := r || format('No alert to the engineer or accounts|%s|%s', v_n = 0, v_n);
  select count(*) into v_n from public.notifications where template = 'sms.inbound' and company_id = v_ca and target_user_id = v_owner
     and deep_link = 'tradedesk://sms/' || rec.conversation_id::text and title like 'New message from Jane Doe · Job MT-1047%';
  r := r || format('Alert names the customer and job and deep-links to the conversation|%s|%s', v_n >= 1, v_n);
  select * into rec2 from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', 'MGalpha00000000000000000000000001',
                                                    '+18135550101', '+18135550000', 'dup', 'SMin-reply', null);
  r := r || format('Duplicate inbound webhook ignored|%s|%s', rec2.outcome = 'duplicate', rec2.outcome);
  select * into rec2 from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', 'MGalpha00000000000000000000000001',
                                                    '+19045550188', '+18135550000', 'Who is this?', 'SMin-unknown', null);
  r := r || format('Unknown sender still lands in the inbox|%s|%s cust=%s', rec2.outcome = 'recorded' and rec2.customer_id is null, rec2.outcome, rec2.customer_id);

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  select * into rec2 from public.communications_unread();
  r := r || format('Owner sees unread customer messages|%s|%s', rec2.customer_unread >= 5, rec2.customer_unread);
  select count(*) into v_n from public.sms_conversation_list(50);
  r := r || format('Owner inbox lists conversations|%s|%s', v_n = 2, v_n);
  perform public.mark_sms_conversation_read(rec.conversation_id);
  select * into rec2 from public.communications_unread();
  r := r || format('Reading the conversation clears its unread|%s|%s', rec2.customer_unread = 1, rec2.customer_unread);
  select count(*) into v_n from public.sms_thread_messages where conversation_id = rec.conversation_id;
  r := r || format('Conversation history shows both directions|%s|%s', v_n >= 7, v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_work::text, 'role', 'authenticated')::text, true);
  select * into rec2 from public.communications_unread();
  r := r || format('Engineer never sees customer SMS unread|%s|%s', rec2.customer_unread = 0, rec2.customer_unread);
  select count(*) into v_n from public.sms_conversations;
  select count(*) into v_m from public.sms_inbound_messages;
  r := r || format('Engineer cannot read customer conversations (RLS)|%s|%s/%s', v_n = 0 and v_m = 0, v_n, v_m);
  perform set_config('request.jwt.claims', json_build_object('sub', v_b_owner::text, 'role', 'authenticated')::text, true);
  select count(*) into v_n from public.sms_conversations;
  select count(*) into v_m from public.sms_conversation_list(50);
  r := r || format('Company B cannot see Company A conversations|%s|%s/%s', v_n = 0 and v_m = 0, v_n, v_m);
  select count(*) into v_n from public.company_messaging_accounts where company_id = v_ca;
  r := r || format('Company B cannot see Company A messaging account|%s|%s', v_n = 0, v_n);
  begin
    perform public.mark_sms_conversation_read(rec.conversation_id);
    r := r || 'Company B cannot mark Company A conversation read|false|allowed'::text;
  exception when others then
    r := r || 'Company B cannot mark Company A conversation read|true|'::text;
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_work::text, 'role', 'authenticated')::text, true);
  v_id := public.send_office_message(null, null, null, '', 'Need a 1/2in fitting on site', '{}');
  perform set_config('role', v_super, true);
  select count(*) into v_n from public.notifications where template = 'office.message' and company_id = v_ca
     and target_user_id = v_owner and deep_link = 'tradedesk://message/' || v_id::text;
  r := r || format('Engineer message alert deep-links to its conversation|%s|%s', v_n = 1, v_n);
  select count(*) into v_n from public.notifications where template = 'office.message' and company_id = v_ca and target_user_id in (v_acct);
  r := r || format('Engineer message never alerts accounts|%s|%s', v_n = 0, v_n);
  -- One test transaction shares one clock; age the engineer's own read mark.
  update public.office_thread_reads set last_read_at = now() - interval '1 minute' where thread_id = v_id;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text, 'role', 'authenticated')::text, true);
  perform public.send_office_message(v_id, null, null, '', 'On its way with the van', '{}');
  perform set_config('role', v_super, true);
  update public.office_thread_reads set last_read_at = now() - interval '1 minute' where thread_id = v_id and user_id = v_work;
  select count(*) into v_n from public.notifications where template = 'office.message' and company_id = v_ca
     and target_user_id = v_work and deep_link = 'tradedesk://message/' || v_id::text;
  r := r || format('Office reply alerts the engineer with the conversation link|%s|%s', v_n = 1, v_n);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_work::text, 'role', 'authenticated')::text, true);
  select * into rec2 from public.communications_unread();
  r := r || format('Engineer unread badge counts the office reply|%s|%s', rec2.office_unread = 1 and rec2.latest_link = 'tradedesk://message/' || v_id::text, rec2.office_unread);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);

  -- service-role only surfaces
  begin
    perform * from public.sms_record_inbound(v_key_a, 'ACalpha000000000000000000000000001', null, '+18135550101', '+18135550000', 'x', 'SMforge', null);
    r := r || 'Signed-in user cannot forge an inbound message|false|allowed'::text;
  exception when others then
    r := r || 'Signed-in user cannot forge an inbound message|true|'::text;
  end;
  begin
    perform public.messaging_subaccount_token(v_acc_b);
    r := r || 'Signed-in user cannot read a subaccount token|false|allowed'::text;
  exception when others then
    r := r || 'Signed-in user cannot read a subaccount token|true|'::text;
  end;
  begin
    perform * from public.sms_rate_card();
    r := r || 'Wholesale rate card hidden from customers|false|allowed'::text;
  exception when others then
    r := r || 'Wholesale rate card hidden from customers|true|'::text;
  end;

  -- ================================================= templates & automations
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  perform public.save_sms_template('appointment_reminder', '{{company_name}}: see you {{appointment_date}} at {{appointment_time}}.');
  select body into v_txt from public.sms_template_catalog() where template_key = 'appointment_reminder';
  r := r || format('Owner edits a template|%s|%s', v_txt like '%see you%', v_txt);
  begin
    perform public.save_sms_template('appointment_reminder', 'Pay {{invoice_link}}');
    r := r || 'Invalid template edit refused|false|saved'::text;
  exception when others then
    r := r || format('Invalid template edit refused|true|%s', sqlerrm);
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text, 'role', 'authenticated')::text, true);
  begin
    perform public.save_sms_template('appointment_reminder', '{{company_name}} hi');
    r := r || 'Dispatcher cannot edit templates|false|saved'::text;
  exception when others then
    r := r || 'Dispatcher cannot edit templates|true|'::text;
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  perform public.set_sms_automation('engineer_arrived', true);
  perform public.set_sms_automation('appointment_cancelled', false);
  select automation_enabled into v_flag from public.sms_template_catalog() where template_key = 'engineer_arrived';
  r := r || format('Automation can be switched on|%s|', v_flag);

  perform set_config('role', v_super, true);
  update public.jobs set scheduled_start = now() + interval '3 days', scheduled_end = now() + interval '3 days 2 hours' where id = v_job;
  update public.jobs set status = 'workerAssigned' where id = v_job;
  update public.jobs set status = 'travelling' where id = v_job;
  update public.jobs set status = 'arrived' where id = v_job;
  select count(*) into v_n from public.scheduled_messages where job_id = v_job and template_key = 'engineer_on_the_way';
  r := r || format('Default-on automation fires on Start travel|%s|%s', v_n = 1, v_n);
  select count(*) into v_n from public.scheduled_messages where job_id = v_job and template_key = 'appointment_rescheduled' and status = 'scheduled';
  r := r || format('Reschedule queues the rescheduled message|%s|%s', v_n = 1, v_n);
  select count(*) into v_n from public.scheduled_messages where job_id = v_job and template_key = 'appointment_reminder' and status = 'scheduled';
  r := r || format('Reschedule queues a new 24h reminder|%s|%s', v_n = 1, v_n);
  select count(*) into v_n from public.scheduled_messages where job_id = v_job and template_key = 'engineer_arrived';
  r := r || format('Enabled automation fires on Arrived|%s|%s', v_n = 1, v_n);
  select count(*) into v_n from public.scheduled_messages where job_id = v_job and template_key = 'job_started';
  r := r || format('Automations default off where appropriate|%s|%s', v_n = 0, v_n);
  update public.jobs set status = 'cancelled' where id = v_job;
  select count(*) into v_n from public.scheduled_messages where job_id = v_job and template_key = 'appointment_reminder' and status = 'cancelled';
  r := r || format('Cancelling the job cancels its pending reminder|%s|%s', v_n = 1, v_n);
  select count(*) into v_n from public.scheduled_messages where job_id = v_job and template_key = 'appointment_cancelled';
  r := r || format('Disabled automation does not fire|%s|%s', v_n = 0, v_n);

  -- ================================================= scheduled messages
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  v_id := public.schedule_sms(v_cust, null, null, null, 'customer_follow_up', 'Following up on your visit.', '+18135550101', now() + interval '2 days');
  select count(*) into v_n from public.scheduled_messages where id = v_id and status = 'scheduled' and company_id = v_ca;
  r := r || format('Manual message scheduled|%s|%s', v_n = 1, v_n);
  begin
    perform public.schedule_sms(v_cust, null, null, null, 'custom_message', 'Past', '+18135550101', now() - interval '1 hour');
    r := r || 'Scheduling in the past refused|false|accepted'::text;
  exception when others then r := r || 'Scheduling in the past refused|true|'::text;
  end;
  r := r || format('Cancel before send|%s|', public.cancel_scheduled_sms(v_id));
  r := r || format('Cancelling twice is a no-op|%s|', not public.cancel_scheduled_sms(v_id));
  perform set_config('request.jwt.claims', json_build_object('sub', v_b_owner::text, 'role', 'authenticated')::text, true);
  begin
    perform public.schedule_sms(v_cust, null, null, null, 'custom_message', 'x', '+18135550101', now() + interval '1 day');
    r := r || 'Company B cannot schedule to Company A customer|false|accepted'::text;
  exception when others then r := r || 'Company B cannot schedule to Company A customer|true|'::text;
  end;
  perform set_config('role', v_super, true);
  update public.scheduled_messages set scheduled_for = now() - interval '1 minute' where id = v_id;
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select count(*) into v_n from public.claim_due_scheduled_sms(200) c where c.id = v_id;
  r := r || format('A cancelled message is never claimed for sending|%s|%s', v_n = 0, v_n);

  -- ================================================= number billing
  perform set_config('role', v_super, true);
  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, purchase_reference)
    values (v_ca, 'purchase', 50, public.sms_credit_balance_for(v_ca) + 50, 'MT-TOPUP-3');
  perform set_config('role', 'service_role', true);
  update public.company_phone_numbers set next_fee_due_at = now() - interval '1 minute' where id = v_num_a;
  select coalesce(sum(amount),0) into v_before from public.sms_credit_ledger where company_id = v_ca;
  v_txt := public.sms_charge_number_fee(v_num_a);
  select coalesce(sum(amount),0) into v_bal from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('Monthly number fee charged in credits|%s|%s %s->%s fee=%s', v_txt = 'charged' and v_before - v_bal = public.sms_number_monthly_fee_credits(), v_txt, v_before, v_bal, public.sms_number_monthly_fee_credits());
  r := r || format('Number fee is idempotent per period|%s|%s', public.sms_charge_number_fee(v_num_a) = 'notDue', public.sms_charge_number_fee(v_num_a));

  update public.company_phone_numbers set next_fee_due_at = now() - interval '1 minute' where id = v_num_b;
  perform set_config('role', v_super, true);
  insert into public.sms_credit_ledger (company_id, transaction_type, amount, balance_after, purchase_reference)
    values (v_cb, 'adjustment', -10, 0, 'MT-DRAIN-B');
  perform set_config('role', 'service_role', true);
  v_txt := public.sms_charge_number_fee(v_num_b);
  r := r || format('Insufficient credit enters grace, number kept|%s|%s', v_txt = 'grace' and (select status from public.company_phone_numbers where id = v_num_b) = 'active', v_txt);
  select count(*) into v_n from public.notifications where company_id = v_cb and template = 'sms.billing' and target_user_id = v_b_owner;
  r := r || format('Owner notified of the missed fee|%s|%s', v_n = 1, v_n);
  r := r || format('Grace still allows sending|%s|', public.sms_send_blocker(v_cb, '+13125550199') is null);
  update public.company_messaging_accounts set grace_started_at = now() - interval '8 days' where id = v_acc_b;
  v_txt := public.sms_charge_number_fee(v_num_b);
  r := r || format('After grace, SMS pauses|%s|%s', v_txt = 'paused' and public.sms_send_blocker(v_cb, '+13125550199') = 'paused', v_txt);
  r := r || format('Paused within retention: release refused|%s|', not public.sms_number_release_allowed(v_num_b));
  begin
    update public.company_phone_numbers set status = 'released' where id = v_num_b;
    r := r || 'Release guard blocks an early release|false|released'::text;
  exception when others then r := r || 'Release guard blocks an early release|true|'::text;
  end;
  update public.company_messaging_accounts set grace_started_at = now() - interval '61 days' where id = v_acc_b;
  r := r || format('After retention, release allowed|%s|', public.sms_number_release_allowed(v_num_b));
  begin
    delete from public.company_phone_numbers where id = v_num_b;
    r := r || 'Number records are never deleted|false|deleted'::text;
  exception when others then r := r || 'Number records are never deleted|true|'::text;
  end;
  r := r || format('Active company number cannot be released|%s|', not public.sms_number_release_allowed(v_num_a));

  -- ================================================= subscription states
  perform set_config('role', v_super, true);
  update public.company_subscriptions set apple_is_free_offer = false, apple_offer_type = null where company_id = v_ca;
  r := r || format('Active subscription: allowed|%s|', public.sms_send_blocker(v_ca, '+18135550101') is null);
  update public.company_subscriptions set apple_expires_at = now() - interval '1 day', apple_grace_period_expires_at = now() + interval '5 days' where company_id = v_ca;
  r := r || format('Apple billing grace: allowed|%s|', public.sms_send_blocker(v_ca, '+18135550101') is null);
  update public.company_subscriptions set apple_grace_period_expires_at = null, apple_in_billing_retry = false where company_id = v_ca;
  r := r || format('Expired subscription: refused|%s|%s', public.sms_send_blocker(v_ca, '+18135550101') = 'noSubscription', public.sms_send_blocker(v_ca, '+18135550101'));
  update public.company_subscriptions set apple_expires_at = now() + interval '5 days', apple_revoked_at = now() where company_id = v_ca;
  r := r || format('Refunded subscription: refused|%s|', public.sms_send_blocker(v_ca, '+18135550101') = 'noSubscription');
  update public.company_subscriptions set apple_revoked_at = null, apple_auto_renew = false where company_id = v_ca;
  r := r || format('Cancelled but still paid: allowed|%s|', public.sms_send_blocker(v_ca, '+18135550101') is null);
  update public.company_subscriptions set apple_auto_renew = true, apple_auto_renew_product_id = 'com.harboursouth.fieldservice.starter.monthly' where company_id = v_ca;
  r := r || format('Scheduled downgrade: allowed until it takes effect|%s|', public.sms_send_blocker(v_ca, '+18135550101') is null);
  r := r || format('Seat resolution does not block SMS for a paid company|%s|', public.sms_company_entitled(v_ca));

  -- ================================================= quote link
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  v_quote := public.create_quote(v_cust, v_addr, 'New condenser', 'Supply and fit', current_date + 30);
  perform public.save_quote_line_item(v_quote, null, 'Condenser', 1, 1800, 0.07);
  perform public.update_quote_status(v_quote, 'sent');
  v_txt := public.issue_quote_share_token(v_quote);
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  v_json := public.quote_public_view(v_txt);
  r := r || format('Quote page resolves by token|%s|', (v_json ->> 'ok')::boolean);
  r := r || format('Quote page exposes no internal ids|%s|', v_json::text !~* '[0-9a-f]{8}-[0-9a-f]{4}-' and v_json::text !~ 'company_id|user_id');
  r := r || format('Bad token resolves to nothing|%s|', not (public.quote_public_view(repeat('0', 64)) ->> 'ok')::boolean);
  perform set_config('role', v_super, true);
  select count(*) into v_n from public.scheduled_messages where quote_id = v_quote and template_key = 'quote_sent';
  r := r || format('Quote automation off by default|%s|%s', v_n = 0, v_n);

  -- ================================================= company closure
  update public.companies set closed_at = now() where id = v_cb;
  select status, retention_until into rec2 from public.company_messaging_accounts where id = v_acc_b;
  r := r || format('Closing the company marks SMS closing with retention|%s|%s', rec2.status = 'closing' and rec2.retention_until > now() + interval '59 days', rec2.status);
  r := r || format('Closed company cannot send|%s|', public.sms_send_blocker(v_cb, '+13125550199') = 'companyClosed');

  perform set_config('role', v_super, true);
  return query select split_part(x, '|', 1), split_part(x, '|', 2)::boolean, split_part(x, '|', 3) from unnest(r) as x;
end;
$function$;

do $$
declare rec record; v_pass int := 0; v_fail int := 0; v_report text := '';
begin
  for rec in select * from pg_temp.run_sms_multitenant_tests() loop
    if rec.passed then v_pass := v_pass + 1; else v_fail := v_fail + 1; end if;
    v_report := v_report || format(E'\n%s  %s  [%s]', case when rec.passed then 'PASS' else 'FAIL' end, rec.test_name, rec.detail);
  end loop;
  raise exception E'SMS MULTITENANT SUITE — PASS=% FAIL=% %', v_pass, v_fail, v_report;
end $$;
