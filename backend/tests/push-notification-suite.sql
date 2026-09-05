-- =============================================================================
-- TradeDesk — push notification suite (DEVELOPMENT TOOLING, NOT PRODUCTION)
-- =============================================================================
--
-- Proves that push notifications are raised by the workflow itself, reach only
-- the people entitled to them, never cross a company boundary, are never
-- recorded as delivered unless Apple accepted them, and never touch SMS credit.
--
-- The device registry and the delivery surface are exercised as the app and the
-- dispatcher actually reach them: registration through the caller's own JWT,
-- delivery through the service role, and every refusal asserted by SQLSTATE.
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

create or replace function pg_temp.run_push_tests()
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
  v_w1    uuid := gen_random_uuid();
  v_w2    uuid := gen_random_uuid();
  v_acct  uuid := gen_random_uuid();
  v_b_owner uuid := gen_random_uuid();
  v_b_work  uuid := gen_random_uuid();

  v_cust uuid; v_addr uuid; v_b_cust uuid; v_b_addr uuid;
  v_job uuid; v_job2 uuid; v_b_job uuid;

  -- 64 hex characters, the shape APNs actually issues.
  t_w1  text := repeat('a1', 32);
  t_w1b text := repeat('b2', 32);
  t_w2  text := repeat('c3', 32);
  t_own text := repeat('d4', 32);
  t_acc text := repeat('e5', 32);
  t_bet text := repeat('f6', 32);

  v_dev uuid; v_dev2 uuid;
  v_n integer; v_m integer; v_txt text; v_flag boolean;
  v_note uuid; v_note2 uuid; v_sms_note uuid;
  v_settle text; v_claimed integer;
  v_start timestamptz := date_trunc('hour', now()) + interval '1 day';
begin
  -- ---------------------------------------------------------------- fixtures
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
         u.em, 'x', now(), now(), now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, false
  from (values
    (v_owner  ,'owner@pushtest.invalid'),
    (v_admin  ,'admin@pushtest.invalid'),
    (v_disp   ,'disp@pushtest.invalid'),
    (v_w1     ,'w1@pushtest.invalid'),
    (v_w2     ,'w2@pushtest.invalid'),
    (v_acct   ,'acct@pushtest.invalid'),
    (v_b_owner,'b.owner@pushtest.invalid'),
    (v_b_work ,'b.work@pushtest.invalid')
  ) as u(id, em);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('PUSHTEST Alpha','hvac','US','USD','America/New_York') returning id into v_ca;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('PUSHTEST Beta','plumbing','US','USD','America/Chicago') returning id into v_cb;

  insert into public.app_users (id, company_id, name, email, role) values
    (v_owner  , v_ca, 'P Owner'     ,'owner@pushtest.invalid','owner'),
    (v_admin  , v_ca, 'P Admin'     ,'admin@pushtest.invalid','admin'),
    (v_disp   , v_ca, 'P Dispatcher','disp@pushtest.invalid','dispatcher'),
    (v_w1     , v_ca, 'P Worker One','w1@pushtest.invalid','fieldWorker'),
    (v_w2     , v_ca, 'P Worker Two','w2@pushtest.invalid','fieldWorker'),
    (v_acct   , v_ca, 'P Accounts'  ,'acct@pushtest.invalid','accounts'),
    (v_b_owner, v_cb, 'B Owner'     ,'b.owner@pushtest.invalid','owner'),
    (v_b_work , v_cb, 'B Worker'    ,'b.work@pushtest.invalid','fieldWorker');

  insert into public.customers (company_id, name, billing_terms)
    values (v_ca,'PUSHTEST Customer','Net 30') returning id into v_cust;
  insert into public.addresses (company_id, customer_id, line1, city, state, postal_code)
    values (v_ca, v_cust,'12 Alert Way','Tampa','FL','33601') returning id into v_addr;
  insert into public.customers (company_id, name) values (v_cb,'BETA Customer') returning id into v_b_cust;
  insert into public.addresses (company_id, customer_id, line1) values (v_cb, v_b_cust,'1 Beta Rd') returning id into v_b_addr;

  perform set_config('role', 'authenticated', true);

  -- ======================================================== device registration
  perform set_config('request.jwt.claims', json_build_object('sub', v_w1::text,'role','authenticated')::text, true);
  v_dev := public.register_push_device(t_w1, 'production', 'app.rork.test', '1.0.0', 'iPhone');

  select count(*) into v_n from public.push_devices
   where id = v_dev and company_id = v_ca and user_id = v_w1 and revoked_at is null;
  r := r || format('A device registers to the caller''s own company and user|%s|rows=%s', v_n = 1, v_n);

  -- The function takes no company or user argument at all: tenancy is derived,
  -- so there is nothing here a client could point somewhere else.
  select count(*) into v_n
    from information_schema.parameters
   where specific_schema = 'public'
     and specific_name in (select specific_name from information_schema.routines
                            where routine_schema='public' and routine_name='register_push_device')
     and parameter_name in ('p_company_id','p_user_id','p_company','p_user');
  r := r || format('Registration accepts no tenancy argument|%s|tenancy params=%s', v_n = 0, v_n);

  begin
    perform public.register_push_device('not-a-token', 'production', '', '', '');
    r := r || 'A malformed device token is refused|false|no refusal raised';
  exception when others then
    r := r || format('A malformed device token is refused|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  begin
    perform public.register_push_device(t_w1b, 'staging', '', '', '');
    r := r || 'An unknown APNs environment is refused|false|no refusal raised';
  exception when others then
    r := r || format('An unknown APNs environment is refused|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  -- A second handset for the same engineer: both must be delivered to.
  v_dev2 := public.register_push_device(t_w1b, 'sandbox', 'app.rork.test', '1.0.0', 'iPad');
  select count(*) into v_n from public.push_devices where user_id = v_w1 and revoked_at is null;
  r := r || format('One person can hold more than one device|%s|live devices=%s', v_n = 2, v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_w2::text,'role','authenticated')::text, true);
  perform public.register_push_device(t_w2, 'production', 'app.rork.test', '1.0.0', 'iPhone');

  select count(*) into v_n from public.push_devices;
  r := r || format('A device token is never readable by anyone else|%s|visible to worker two=%s', v_n = 1, v_n);

  begin
    insert into public.push_devices (company_id, user_id, token)
    values (v_ca, v_w1, repeat('09', 32));
    r := r || 'Nobody can register a device for another person|false|insert succeeded';
  exception when others then
    r := r || format('Nobody can register a device for another person|%s|%s', true, left(sqlerrm, 60));
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text,'role','authenticated')::text, true);
  perform public.register_push_device(t_own, 'production', 'app.rork.test', '1.0.0', 'iPhone');
  perform set_config('request.jwt.claims', json_build_object('sub', v_admin::text,'role','authenticated')::text, true);
  perform public.register_push_device(repeat('1a', 32), 'production', 'app.rork.test', '1.0.0', 'iPhone');
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  perform public.register_push_device(repeat('2b', 32), 'production', 'app.rork.test', '1.0.0', 'iPhone');
  perform set_config('request.jwt.claims', json_build_object('sub', v_acct::text,'role','authenticated')::text, true);
  perform public.register_push_device(t_acc, 'production', 'app.rork.test', '1.0.0', 'iPhone');
  perform set_config('request.jwt.claims', json_build_object('sub', v_b_work::text,'role','authenticated')::text, true);
  perform public.register_push_device(t_bet, 'production', 'app.rork.test', '1.0.0', 'iPhone');

  -- ============================================================ workflow events
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  v_job := public.create_job(v_cust, v_addr, 'Condenser strip-down',
                             'Full strip and rebuild of the outdoor unit.',
                             'maintenance', 'standard', v_start, v_start + interval '2 hours',
                             null, null, null);

  -- --- new assignment
  perform public.assign_job(v_job, v_w1, false);

  select count(*) into v_n from public.notifications
   where channel = 'push' and template = 'job.assigned' and target_user_id = v_w1 and job_id = v_job;
  r := r || format('A new assignment notifies the engineer who got it|%s|rows=%s (one per device)', v_n = 2, v_n);

  select count(*) into v_n from public.notifications
   where channel = 'push' and job_id = v_job and status = 'queued';
  select count(*) into v_m from public.notifications
   where channel = 'push' and job_id = v_job and status in ('sent','delivered');
  r := r || format('A raised notification starts queued, never delivered|%s|queued=%s claimed-delivered=%s',
                   v_n = 2 and v_m = 0, v_n, v_m);

  select deep_link into v_txt from public.notifications
   where channel='push' and template='job.assigned' and target_user_id = v_w1 limit 1;
  r := r || format('Every notification carries its destination|%s|link=%s',
                   v_txt = 'tradedesk://job/' || v_job::text, coalesce(v_txt,'none'));

  select count(*) into v_n from public.notifications
   where channel = 'push' and target_user_id = v_disp;
  r := r || format('Nobody is notified about their own action|%s|dispatcher rows=%s', v_n = 0, v_n);

  select count(*) into v_n from public.notifications
   where channel = 'push' and target_user_id = v_w2 and job_id = v_job;
  r := r || format('An engineer not on the job is never told about it|%s|worker two rows=%s', v_n = 0, v_n);

  -- --- reassignment
  perform public.assign_job(v_job, v_w2, true);

  select count(*) into v_n from public.notifications
   where channel='push' and template='job.unassigned' and target_user_id = v_w1 and job_id = v_job;
  r := r || format('Reassignment tells the outgoing engineer they are off it|%s|rows=%s', v_n = 2, v_n);

  select count(*) into v_n from public.notifications
   where channel='push' and template='job.reassigned' and target_user_id = v_w2 and job_id = v_job;
  r := r || format('Reassignment tells the incoming engineer it is theirs|%s|rows=%s', v_n = 1, v_n);

  -- --- time change
  perform public.reschedule_job(v_job, v_start + interval '5 hours', v_start + interval '7 hours', true);
  select count(*) into v_n from public.notifications
   where channel='push' and template='job.rescheduled' and target_user_id = v_w2 and job_id = v_job;
  select body into v_txt from public.notifications
   where channel='push' and template='job.rescheduled' and target_user_id = v_w2 limit 1;
  r := r || format('A time change notifies the assigned engineer|%s|rows=%s body=%s',
                   v_n = 1, v_n, left(coalesce(v_txt,'none'), 60));

  -- --- job detail change
  update public.jobs set title = 'Condenser strip-down (roof access)' where id = v_job;
  select count(*) into v_n from public.notifications
   where channel='push' and template='job.updated' and target_user_id = v_w2 and job_id = v_job;
  r := r || format('A change to the job itself notifies the engineer|%s|rows=%s', v_n = 1, v_n);

  -- --- a note the engineer should act on
  insert into public.job_notes (company_id, job_id, user_id, body, visibility)
  values (v_ca, v_job, v_disp, 'Gate code changed to 4417.', 'internalOnly');
  select count(*) into v_n from public.notifications
   where channel='push' and template='job.note' and target_user_id = v_w2 and job_id = v_job;
  r := r || format('A note on the job reaches the assigned engineer|%s|rows=%s', v_n = 1, v_n);

  -- --- field progress travels back to the office, by permission
  perform set_config('request.jwt.claims', json_build_object('sub', v_w2::text,'role','authenticated')::text, true);
  perform public.update_job_status(v_job, 'travelling', null, null);

  -- Counted with the tenant gate lifted. An engineer cannot read alerts
  -- addressed to the office — that is asserted separately below — so asking
  -- under their identity would prove nothing about what was raised.
  perform set_config('role', v_super, true);

  select count(*) into v_n from public.notifications
   where channel='push' and template='job.fieldUpdate' and target_user_id in (v_owner, v_admin, v_disp);
  r := r || format('Field progress reaches the roles permitted to see it|%s|office rows=%s', v_n = 3, v_n);

  select count(*) into v_n from public.notifications
   where channel='push' and template='job.fieldUpdate' and target_user_id = v_acct;
  select count(*) into v_m from public.role_permissions
   where role = 'accounts' and permission = 'assignmentsManage';
  r := r || format('Accounts, holding no operational permission, are not told|%s|accounts rows=%s (permission held=%s)',
                   v_n = 0 and v_m = 0, v_n, v_m);

  perform set_config('role', 'authenticated', true);

  -- --- cancellation
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  perform public.update_job_status(v_job, 'cancelled', null, null);

  select count(*) into v_n from public.notifications
   where channel='push' and template='job.cancelled' and target_user_id = v_w2 and job_id = v_job;
  select body into v_txt from public.notifications
   where channel='push' and template='job.cancelled' and target_user_id = v_w2 limit 1;
  r := r || format('Cancelling a job notifies the engineer standing by|%s|rows=%s body=%s',
                   v_n = 1 and v_txt like '%Do not travel%', v_n, left(coalesce(v_txt,'none'), 70));

  -- --- an engineer with no device: recorded, honestly, as failed
  perform set_config('request.jwt.claims', json_build_object('sub', v_w1::text,'role','authenticated')::text, true);
  perform public.unregister_push_device(t_w1);
  perform public.unregister_push_device(t_w1b);

  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  v_job2 := public.create_job(v_cust, v_addr, 'Coil clean', 'Chemical clean.',
                              'maintenance', 'standard', v_start, v_start + interval '1 hour',
                              null, null, null);
  perform public.assign_job(v_job2, v_w1, false);

  select count(*), max(failure_reason) into v_n, v_txt from public.notifications
   where channel='push' and job_id = v_job2 and target_user_id = v_w1;
  select count(*) into v_m from public.notifications
   where channel='push' and job_id = v_job2 and target_user_id = v_w1 and status = 'failed';
  r := r || format('An alert with no registered device is recorded as failed|%s|rows=%s failed=%s reason=%s',
                   v_n = 1 and v_m = 1, v_n, v_m, left(coalesce(v_txt,'none'), 45));

  select count(*) into v_n from public.notifications
   where channel='push' and job_id = v_job2 and status in ('sent','delivered');
  r := r || format('An undeliverable alert is never recorded as sent|%s|claimed-sent=%s', v_n = 0, v_n);

  -- --- sign-out only ever affects your own device
  perform set_config('request.jwt.claims', json_build_object('sub', v_w1::text,'role','authenticated')::text, true);
  select public.unregister_push_device(t_w2) into v_flag;
  r := r || format('Signing out cannot revoke somebody else''s device|%s|removed=%s', v_flag = false, v_flag);

  perform set_config('role', v_super, true);
  select count(*) into v_n from public.push_devices where token = t_w2 and revoked_at is null;
  r := r || format('The other engineer''s device is still live|%s|live=%s', v_n = 1, v_n);
  perform set_config('role', 'authenticated', true);

  -- Re-registering the same handset revives it rather than duplicating it.
  perform set_config('request.jwt.claims', json_build_object('sub', v_w1::text,'role','authenticated')::text, true);
  perform public.register_push_device(t_w1, 'production', 'app.rork.test', '1.0.1', 'iPhone');
  perform set_config('role', v_super, true);
  select count(*) into v_n from public.push_devices where token = t_w1;
  select count(*) into v_m from public.push_devices where token = t_w1 and revoked_at is null;
  r := r || format('Signing back in revives the same device row|%s|rows=%s live=%s', v_n = 1 and v_m = 1, v_n, v_m);
  perform set_config('role', 'authenticated', true);

  -- A handset passed to another engineer follows the person signed in on it.
  perform set_config('request.jwt.claims', json_build_object('sub', v_w2::text,'role','authenticated')::text, true);
  perform public.register_push_device(t_w1, 'production', 'app.rork.test', '1.0.1', 'iPhone');
  perform set_config('role', v_super, true);
  select user_id = v_w2 into v_flag from public.push_devices where token = t_w1;
  select count(*) into v_n from public.push_devices where token = t_w1;
  r := r || format('A shared handset follows whoever signs in on it|%s|moved=%s rows=%s', v_flag and v_n = 1, v_flag, v_n);

  -- Hand it back, because the move above is real: alerts still queued for the
  -- first engineer on this handset are now orphaned, and the dispatcher will
  -- correctly abandon them rather than deliver them to the second engineer.
  -- Leaving it moved would silently change what the assertions below are
  -- testing. The security consequence of a move is proved on its own handset
  -- at the end of this suite.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_w1::text,'role','authenticated')::text, true);
  perform public.register_push_device(t_w1, 'production', 'app.rork.test', '1.0.1', 'iPhone');
  perform set_config('role', 'authenticated', true);

  -- ================================================== who may read what
  perform set_config('request.jwt.claims', json_build_object('sub', v_w2::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.notifications where target_user_id = v_w2;
  r := r || format('An engineer can read the alerts addressed to them|%s|own rows=%s', v_n > 0, v_n);

  select count(*) into v_n from public.notifications where target_user_id is distinct from v_w2;
  r := r || format('An engineer can read nobody else''s alerts|%s|other rows=%s', v_n = 0, v_n);

  -- Customer SMS/email rows carry no target user, so the addressee clause
  -- cannot reach them: they stay 'jobsReadAll' only.
  perform set_config('role', v_super, true);
  insert into public.notifications (company_id, channel, template, recipient, status)
  values (v_ca, 'sms', 'invoice.share', '+15615550142', 'queued') returning id into v_sms_note;
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', v_w2::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.notifications where id = v_sms_note;
  r := r || format('Widening the policy did not expose customer messages|%s|sms rows visible to engineer=%s', v_n = 0, v_n);

  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.notifications where id = v_sms_note;
  r := r || format('An office role still reads the whole ledger|%s|sms rows visible=%s', v_n = 1, v_n);

  -- ================================================== the tenant boundary
  perform set_config('request.jwt.claims', json_build_object('sub', v_b_owner::text,'role','authenticated')::text, true);

  select count(*) into v_n from public.notifications where company_id = v_ca;
  r := r || format('Another company cannot read our notifications|%s|alpha rows visible=%s', v_n = 0, v_n);

  select count(*) into v_n from public.push_devices where company_id = v_ca;
  r := r || format('Another company cannot read our devices|%s|alpha devices visible=%s', v_n = 0, v_n);

  begin
    perform public.assign_job(v_job2, v_w1, false);
    r := r || 'Another company cannot assign our job|false|no refusal raised';
  exception when others then
    r := r || format('Another company cannot assign our job|%s|sqlstate=%s', sqlstate in ('TD404','TD401'), sqlstate);
  end;

  -- Beta's own event must reach Beta's own engineer and nobody else.
  v_b_job := public.create_job(v_b_cust, v_b_addr, 'Water heater service', 'Annual service.',
                               'maintenance', 'standard', v_start, v_start + interval '1 hour',
                               null, null, null);
  perform public.assign_job(v_b_job, v_b_work, false);

  perform set_config('role', v_super, true);
  select count(*) into v_n from public.notifications
   where channel='push' and job_id = v_b_job and target_user_id = v_b_work and company_id = v_cb;
  select count(*) into v_m from public.notifications
   where channel='push' and job_id = v_b_job and company_id = v_ca;
  r := r || format('Their event reaches only their own people|%s|beta rows=%s leaked into alpha=%s',
                   v_n = 1 and v_m = 0, v_n, v_m);
  perform set_config('role', 'authenticated', true);

  -- =================================== the event surface is closed to clients
  -- enqueue_push is SECURITY DEFINER and takes the company and addressee as
  -- arguments. If a client could reach it, it could raise an alert inside a
  -- company it does not belong to, addressed to an engineer it has no
  -- relationship with. It must be unreachable from a signed-in session.
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  begin
    perform public.enqueue_push(v_cb, v_b_work, 'job.cancelled',
                                'Forged', 'Do not travel to this job.', null, null);
    r := r || 'A signed-in user cannot raise an alert in another company|false|no refusal raised';
  exception when others then
    r := r || format('A signed-in user cannot raise an alert in another company|%s|sqlstate=%s',
                     sqlstate in ('42501','TD403'), sqlstate);
  end;

  begin
    perform public.enqueue_push(v_ca, v_w1, 'job.cancelled',
                                'Forged', 'Do not travel to this job.', null, null);
    r := r || 'A signed-in user cannot raise an alert even inside their own company|false|no refusal raised';
  exception when others then
    r := r || format('A signed-in user cannot raise an alert even inside their own company|%s|sqlstate=%s',
                     sqlstate in ('42501','TD403'), sqlstate);
  end;

  -- The forgery attempts left nothing behind.
  perform set_config('role', v_super, true);
  select count(*) into v_n from public.notifications
   where template = 'job.cancelled' and title = 'Forged';
  r := r || format('A refused forgery writes nothing to the ledger|%s|forged rows=%s', v_n = 0, v_n);
  perform set_config('role', 'authenticated', true);

  -- ============================================ the delivery surface is closed
  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);

  begin
    perform public.claim_push_batch(10);
    r := r || 'A signed-in user cannot claim notifications for delivery|false|no refusal raised';
  exception when others then
    r := r || format('A signed-in user cannot claim notifications for delivery|%s|sqlstate=%s',
                     sqlstate in ('42501','TD403'), sqlstate);
  end;

  select id into v_note from public.notifications
   where channel='push' and status='queued' and push_device_id is not null limit 1;

  begin
    perform public.settle_push_delivery(v_note, true, 'FORGED', null, false);
    r := r || 'A signed-in user cannot mark their own alert delivered|false|no refusal raised';
  exception when others then
    r := r || format('A signed-in user cannot mark their own alert delivered|%s|sqlstate=%s',
                     sqlstate in ('42501','TD403'), sqlstate);
  end;

  perform set_config('role', v_super, true);
  select status into v_txt from public.notifications where id = v_note;
  r := r || format('The forged attempt changed nothing|%s|status=%s', v_txt = 'queued', v_txt);

  -- ================================================ the dispatcher's own path
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  select count(*) into v_claimed from public.claim_push_batch(100);
  r := r || format('The dispatcher can claim the queued batch|%s|claimed=%s', v_claimed > 0, v_claimed);

  select count(*) into v_n from public.claim_push_batch(100);
  r := r || format('A second run cannot claim the same rows again|%s|claimed=%s', v_n = 0, v_n);

  -- Delivered: the only path to 'sent'.
  select public.settle_push_delivery(v_note, true, 'apns-id-0001', null, false) into v_settle;
  select status, provider_reference into v_txt, v_txt from public.notifications where id = v_note;
  select status into v_txt from public.notifications where id = v_note;
  select (sent_at is not null) into v_flag from public.notifications where id = v_note;
  r := r || format('Apple accepting it is what makes it sent|%s|outcome=%s status=%s stamped=%s',
                   v_settle = 'sent' and v_txt = 'sent' and v_flag, v_settle, v_txt, v_flag);

  select public.settle_push_delivery(v_note, true, 'apns-id-0002', null, false) into v_settle;
  r := r || format('Settling the same alert twice changes nothing|%s|outcome=%s', v_settle = 'alreadySettled', v_settle);

  -- Failed: recorded as failed, with the provider's own reason.
  select id into v_note2 from public.notifications
   where channel='push' and status='queued' and push_device_id is not null limit 1;
  select public.settle_push_delivery(v_note2, false, null, 'ServiceUnavailable (HTTP 503)', false) into v_settle;
  select status, failure_reason into v_txt, v_txt from public.notifications where id = v_note2;
  select failure_reason into v_txt from public.notifications where id = v_note2;
  select (status = 'failed') into v_flag from public.notifications where id = v_note2;
  r := r || format('A refused delivery is recorded as failed, with its reason|%s|failed=%s reason=%s',
                   v_flag and v_txt like '%503%', v_flag, left(coalesce(v_txt,'none'), 40));

  -- A dead token takes its device out of service.
  select id into v_note from public.notifications
   where channel='push' and status='queued' and push_device_id is not null limit 1;
  select push_device_id into v_dev from public.notifications where id = v_note;
  select public.settle_push_delivery(v_note, false, null, 'Unregistered (HTTP 410)', true) into v_settle;

  select count(*) into v_n from public.push_devices where id = v_dev and revoked_at is not null;
  r := r || format('An expired token takes its device out of service|%s|outcome=%s revoked=%s',
                   v_settle = 'failedTokenRevoked' and v_n = 1, v_settle, v_n);

  select count(*) into v_n from public.notifications
   where push_device_id = v_dev and status = 'queued';
  r := r || format('Nothing stays queued to a dead address|%s|still queued=%s', v_n = 0, v_n);

  -- A revoked device is never queued to again.
  --
  -- Counted as a delta around a fresh event: how many rows pointed at the dead
  -- address before, how many after. Anything other than "no change" means a
  -- revoked token is still generating work.
  perform set_config('role', v_super, true);
  select count(*) into v_m from public.notifications where push_device_id = v_dev;

  perform set_config('request.jwt.claims', json_build_object('sub', v_disp::text,'role','authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  insert into public.job_notes (company_id, job_id, user_id, body, visibility)
  values (v_ca, v_job, v_disp, 'Second note after the token died.', 'internalOnly');

  perform set_config('role', v_super, true);
  select count(*) into v_n from public.notifications where push_device_id = v_dev;
  r := r || format('A dead address is never queued to again|%s|rows to it before=%s after=%s',
                   v_n = v_m, v_m, v_n);

  -- The event itself was still raised — the engineer is simply unreachable, and
  -- that is recorded rather than silently dropped.
  select count(*) into v_n from public.notifications
   where channel='push' and template='job.note' and job_id = v_job
     and created_at > now() - interval '5 seconds';
  r := r || format('The event is still recorded when the address is dead|%s|rows raised=%s', v_n >= 1, v_n);
  perform set_config('role', 'authenticated', true);

  -- Reached as the dispatcher genuinely reaches it: past the grant, past the
  -- service-role assertion, and refused on the merits of the row itself.
  perform set_config('role', v_super, true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  begin
    perform public.settle_push_delivery(v_sms_note, true, 'X', null, false);
    r := r || 'The push settler refuses a customer message|false|no refusal raised';
  exception when others then
    r := r || format('The push settler refuses a customer message|%s|sqlstate=%s', sqlstate = 'TD422', sqlstate);
  end;

  -- And the SMS row it refused is untouched by the attempt.
  select status into v_txt from public.notifications where id = v_sms_note;
  r := r || format('The customer message it refused is unchanged|%s|status=%s', v_txt = 'queued', v_txt);

  -- ============================================ push never costs SMS credit
  perform set_config('role', v_super, true);

  select count(*) into v_n
    from public.sms_credit_ledger l
    join public.notifications n on n.id = l.notification_id
   where n.channel = 'push';
  r := r || format('No credit is ever spent on a push notification|%s|ledger rows referencing push=%s', v_n = 0, v_n);

  select coalesce(sum(amount), 0) into v_n from public.sms_credit_ledger where company_id = v_ca;
  r := r || format('The SMS balance is untouched by every alert above|%s|balance=%s', v_n = 0, v_n);

  -- ==================================================== the ledger's own shape
  begin
    insert into public.notifications (company_id, channel, template, recipient, status)
    values (v_ca, 'push', 'job.assigned', 'ios abcdef', 'queued');
    r := r || 'A push row must name the person it is for|false|insert succeeded';
  exception when others then
    r := r || format('A push row must name the person it is for|%s|%s', true, left(sqlerrm, 50));
  end;

  begin
    insert into public.notifications (company_id, channel, template, recipient, status, target_user_id)
    values (v_ca, 'sms', 'invoice.share', '+15615550001', 'queued', v_w1);
    r := r || 'A customer message cannot borrow the push columns|false|insert succeeded';
  exception when others then
    r := r || format('A customer message cannot borrow the push columns|%s|%s', true, left(sqlerrm, 50));
  end;

  select count(*) into v_n from public.notifications where channel = 'push' and target_user_id is null;
  r := r || format('Every push row in the ledger is addressed|%s|unaddressed=%s', v_n = 0, v_n);

  select count(*) into v_n from public.notifications where channel = 'push' and deep_link is null;
  r := r || format('Every push row can be tapped through to a screen|%s|without a destination=%s', v_n = 0, v_n);

  -- ======================================== a handset that changes hands
  -- A phone outlives a session. Signing in re-registers the same APNs token
  -- against the new person, which revives the device row that signing out
  -- revoked. An alert still queued for the previous owner must not ride that
  -- revival onto the new owner's lock screen — it is the one way one person's
  -- job could be shown to another. A fresh handset is used here so this does
  -- not depend on what earlier assertions did to the other devices.
  perform set_config('role', v_super, true);
  insert into public.push_devices (company_id, user_id, token, environment, bundle_id)
  values (v_ca, v_w1, repeat('9c', 32), 'production', 'app.rork.test')
  returning id into v_dev2;

  insert into public.notifications (company_id, channel, template, recipient, status,
                                    target_user_id, push_device_id, title, body, deep_link)
  values (v_ca, 'push', 'job.assigned', 'ios handover', 'queued',
          v_w1, v_dev2, 'Job for the previous owner', 'body', 'tradedesk://job/handover')
  returning id into v_note2;

  -- The second engineer signs in on that handset, through the real path.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', v_w2::text,'role','authenticated')::text, true);
  perform public.register_push_device(repeat('9c', 32), 'production', 'app.rork.test', '1.0.1', 'iPhone');

  perform set_config('role', v_super, true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select count(*) into v_n from public.claim_push_batch(500) c where c.notification_id = v_note2;
  r := r || format('An alert for the previous owner never reaches the new one|%s|claimed=%s', v_n = 0, v_n);

  select status into v_txt from public.notifications where id = v_note2;
  select (failure_reason like '%different person%') into v_flag
    from public.notifications where id = v_note2;
  r := r || format('That alert is abandoned, and says why|%s|status=%s explained=%s',
                   v_txt = 'failed' and v_flag, v_txt, coalesce(v_flag::text,'null'));

  -- ...while the person actually holding the handset still gets their own.
  insert into public.notifications (company_id, channel, template, recipient, status,
                                    target_user_id, push_device_id, title, body, deep_link)
  values (v_ca, 'push', 'job.assigned', 'ios handover', 'queued',
          v_w2, v_dev2, 'Job for the new owner', 'body', 'tradedesk://job/handover2')
  returning id into v_note;

  select count(*) into v_n from public.claim_push_batch(500) c where c.notification_id = v_note;
  r := r || format('The person now holding it still gets their own alerts|%s|claimed=%s', v_n = 1, v_n);

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
  for rec in select * from pg_temp.run_push_tests() loop
    if rec.passed then v_pass := v_pass + 1; else v_fail := v_fail + 1; end if;
    v_report := v_report || format(E'\n%s  %s  [%s]',
      case when rec.passed then 'PASS' else 'FAIL' end, rec.test_name, rec.detail);
  end loop;
  raise exception E'PUSH NOTIFICATION SUITE — PASS=% FAIL=% %', v_pass, v_fail, v_report;
end $$;
