-- =============================================================================
-- TradeDesk — scheduled push dispatcher suite (DEVELOPMENT TOOLING)
-- =============================================================================
--
-- The dispatcher is the one component that acts for the whole estate rather
-- than for a signed-in user, so the way it is triggered must not put anything
-- valuable within reach of the app.
--
-- One platform condition shapes the whole design and is worth stating plainly:
-- pg_net records every outbound request, headers included, in
-- net.http_request_queue. That table is owned by supabase_admin and granted to
-- PUBLIC, and postgres is not a member of supabase_admin, so those grants
-- cannot be revoked from a migration. Anything the database sends as a header
-- is therefore effectively readable by any role that can reach the net schema.
--
-- The response is not to hope nobody looks, but to send nothing worth reading:
-- the tick carries a timestamp and an HMAC of it, never a credential. The
-- decisive test below opens the queue row a real tick produced and checks what
-- is actually in it.
--
-- HOW TO RUN
-- ----------
-- Run the whole file as one statement batch. It ends in `raise exception`, so
-- every fixture is rolled back — including the queued HTTP request, which is
-- therefore never sent. FAIL=0 is a pass.
-- =============================================================================

create or replace function pg_temp.run_dispatch_schedule_tests()
returns table(test_name text, passed boolean, detail text)
language plpgsql
as $function$
declare
  r text[] := array[]::text[];
  v_super text := current_user;

  v_company uuid;
  v_user    uuid := gen_random_uuid();
  v_device  uuid;
  v_note    uuid;

  v_n integer;
  v_txt text;
  v_flag boolean;
  v_request bigint;
  v_request2 bigint;
  v_headers jsonb;
  v_url text;
  v_key text;
  v_before bigint;
  v_after bigint;
begin
  -- ============================================== the machinery is installed
  select count(*) into v_n from pg_extension where extname = 'pg_cron';
  r := r || format('The scheduler is installed|%s|pg_cron rows=%s', v_n = 1, v_n);

  select count(*) into v_n from pg_extension where extname = 'pg_net';
  r := r || format('The database can make outbound requests|%s|pg_net rows=%s', v_n = 1, v_n);

  -- ==================================================== the schedule is live
  select count(*) into v_n from cron.job where jobname = 'push-dispatch';
  r := r || format('Exactly one dispatch schedule exists|%s|jobs named push-dispatch=%s', v_n = 1, v_n);

  select active into v_flag from cron.job where jobname = 'push-dispatch';
  select schedule into v_txt from cron.job where jobname = 'push-dispatch';
  r := r || format('The schedule is active and runs every half minute|%s|active=%s schedule=%s',
                   coalesce(v_flag, false) and v_txt = '30 seconds', v_flag, v_txt);

  select command into v_txt from cron.job where jobname = 'push-dispatch';
  r := r || format('The scheduled command calls the dispatcher|%s|command=%s',
                   v_txt like '%dispatch_push_tick%', v_txt);

  -- The command is what an operator reads out of the catalogue; it must name
  -- the work, never carry the authority to do it.
  r := r || format('The scheduled command carries no credential|%s|command=%s',
                   v_txt not like '%eyJ%' and v_txt not ilike '%bearer%', v_txt);

  -- ================================================= what is held, and where
  select count(*) into v_n from vault.secrets where name = 'push_dispatch_signing_key';
  r := r || format('The signing key is held in the vault|%s|secret rows=%s', v_n = 1, v_n);

  -- The service-role key must not be held in the database at all. Its only
  -- home is the dispatcher's own environment.
  select count(*) into v_n from vault.decrypted_secrets
   where name = 'push_dispatch_service_key'
      or decrypted_secret like 'eyJ%';
  r := r || format('No service-role key is stored in the database|%s|jwt-shaped secrets=%s', v_n = 0, v_n);

  r := r || format('No client role may enter the vault|%s|anon=%s authenticated=%s',
                   not has_schema_privilege('anon','vault','USAGE')
               and not has_schema_privilege('authenticated','vault','USAGE'),
                   has_schema_privilege('anon','vault','USAGE'),
                   has_schema_privilege('authenticated','vault','USAGE'));

  r := r || format('No client role may read the schedule|%s|anon=%s authenticated=%s',
                   not has_schema_privilege('anon','cron','USAGE')
               and not has_schema_privilege('authenticated','cron','USAGE'),
                   has_schema_privilege('anon','cron','USAGE'),
                   has_schema_privilege('authenticated','cron','USAGE'));

  -- ======================================== the dispatch path is service-only
  r := r || format('No client role may run a dispatch|%s|anon=%s authenticated=%s',
                   not has_function_privilege('anon','public.dispatch_push_tick()','EXECUTE')
               and not has_function_privilege('authenticated','public.dispatch_push_tick()','EXECUTE'),
                   has_function_privilege('anon','public.dispatch_push_tick()','EXECUTE'),
                   has_function_privilege('authenticated','public.dispatch_push_tick()','EXECUTE'));

  r := r || format('No client role may claim work|%s|anon=%s authenticated=%s',
                   not has_function_privilege('anon','public.claim_push_batch(integer)','EXECUTE')
               and not has_function_privilege('authenticated','public.claim_push_batch(integer)','EXECUTE'),
                   has_function_privilege('anon','public.claim_push_batch(integer)','EXECUTE'),
                   has_function_privilege('authenticated','public.claim_push_batch(integer)','EXECUTE'));

  r := r || format('No client role may record a delivery|%s|anon=%s authenticated=%s',
                   not has_function_privilege('anon','public.settle_push_delivery(uuid,boolean,text,text,boolean)','EXECUTE')
               and not has_function_privilege('authenticated','public.settle_push_delivery(uuid,boolean,text,text,boolean)','EXECUTE'),
                   has_function_privilege('anon','public.settle_push_delivery(uuid,boolean,text,text,boolean)','EXECUTE'),
                   has_function_privilege('authenticated','public.settle_push_delivery(uuid,boolean,text,text,boolean)','EXECUTE'));

  r := r || format('No client role may raise a push event|%s|anon=%s authenticated=%s',
                   not has_function_privilege('anon','public.enqueue_push(uuid,uuid,text,text,text,uuid,uuid)','EXECUTE')
               and not has_function_privilege('authenticated','public.enqueue_push(uuid,uuid,text,text,text,uuid,uuid)','EXECUTE'),
                   has_function_privilege('anon','public.enqueue_push(uuid,uuid,text,text,text,uuid,uuid)','EXECUTE'),
                   has_function_privilege('authenticated','public.enqueue_push(uuid,uuid,text,text,text,uuid,uuid)','EXECUTE'));

  -- ============================================ refusals, provoked at runtime
  -- A grant table is a claim about what would happen. These make it happen.
  perform set_config('request.jwt.claims',
                     json_build_object('sub', gen_random_uuid()::text, 'role','authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  begin
    perform public.dispatch_push_tick();
    r := r || 'A signed-in user cannot trigger a dispatch|false|no refusal raised';
  exception when others then
    r := r || format('A signed-in user cannot trigger a dispatch|%s|sqlstate=%s',
                     sqlstate in ('42501','TD403'), sqlstate);
  end;

  begin
    perform 1 from cron.job;
    r := r || 'A signed-in user cannot read the schedule|false|no refusal raised';
  exception when others then
    r := r || format('A signed-in user cannot read the schedule|%s|sqlstate=%s',
                     sqlstate in ('42501','3F000','42P01'), sqlstate);
  end;

  begin
    perform 1 from vault.decrypted_secrets;
    r := r || 'A signed-in user cannot read the signing key|false|no refusal raised';
  exception when others then
    r := r || format('A signed-in user cannot read the signing key|%s|sqlstate=%s',
                     sqlstate in ('42501','3F000','42P01'), sqlstate);
  end;

  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
  perform set_config('role', 'anon', true);

  begin
    perform public.dispatch_push_tick();
    r := r || 'An anonymous caller cannot trigger a dispatch|false|no refusal raised';
  exception when others then
    r := r || format('An anonymous caller cannot trigger a dispatch|%s|sqlstate=%s',
                     sqlstate in ('42501','TD403'), sqlstate);
  end;

  perform set_config('role', v_super, true);
  perform set_config('request.jwt.claims', '', true);

  -- ==================================== an empty queue costs nothing to check
  -- The tick fires every half minute forever. With nothing to deliver it must
  -- do nothing at all, rather than issue a request each time.
  select count(*) into v_before from net.http_request_queue;
  select public.dispatch_push_tick() into v_request;
  select count(*) into v_after from net.http_request_queue;
  r := r || format('A tick over an empty queue sends nothing|%s|returned=%s queue before=%s after=%s',
                   v_request is null and v_after = v_before,
                   coalesce(v_request::text,'null'), v_before, v_after);

  -- ============================ what a real tick actually puts on the wire
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin)
  values ('00000000-0000-0000-0000-000000000000', v_user, 'authenticated','authenticated',
          'tick@pushtest.invalid','x', now(), now(), now(),
          '{"provider":"email"}'::jsonb, '{}'::jsonb, false);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('TICKTEST Co','hvac','US','USD','America/New_York') returning id into v_company;

  insert into public.app_users (id, company_id, name, email, role)
  values (v_user, v_company, 'Tick Worker','tick@pushtest.invalid','fieldWorker');

  insert into public.push_devices (company_id, user_id, token, environment, bundle_id)
  values (v_company, v_user, repeat('ab', 32), 'production', 'app.rork.test')
  returning id into v_device;

  insert into public.notifications (company_id, channel, template, recipient, status,
                                    target_user_id, push_device_id, title, body, deep_link)
  values (v_company, 'push', 'job.assigned', 'ios abcdef', 'queued',
          v_user, v_device, 'New job', 'You have been assigned a job.', 'tradedesk://jobs')
  returning id into v_note;

  select public.dispatch_push_tick() into v_request;
  r := r || format('A tick with work to do issues exactly one request|%s|request id=%s',
                   v_request is not null, coalesce(v_request::text,'null'));

  select headers, url into v_headers, v_url
    from net.http_request_queue where id = v_request;

  r := r || format('The request goes to the dispatcher|%s|url=%s',
                   v_url like '%/functions/v1/dispatch-push', coalesce(v_url,'none'));

  -- The decisive check. This queue row is readable by any client role, so its
  -- contents are the honest measure of what the scheduler exposes.
  r := r || format('The outbound request carries no authorization header|%s|keys=%s',
                   not (v_headers ? 'Authorization') and not (v_headers ? 'authorization'),
                   (select coalesce(string_agg(k, ','), 'none') from jsonb_object_keys(v_headers) as k));

  r := r || format('The outbound request contains no bearer token|%s|contains eyJ=%s',
                   v_headers::text not like '%eyJ%' and v_headers::text not ilike '%bearer%',
                   v_headers::text like '%eyJ%');

  select decrypted_secret into v_key from vault.decrypted_secrets
   where name = 'push_dispatch_signing_key';
  r := r || format('The signing key itself is never transmitted|%s|key present in headers=%s',
                   v_key is not null and position(v_key in v_headers::text) = 0,
                   position(v_key in v_headers::text) > 0);

  r := r || format('The request proves itself by signature instead|%s|timestamp=%s signature=%s',
                   (v_headers ? 'x-dispatch-timestamp') and (v_headers ? 'x-dispatch-signature'),
                   v_headers ? 'x-dispatch-timestamp', v_headers ? 'x-dispatch-signature');

  -- The signature must actually verify against the key, not merely be present.
  r := r || format('The signature verifies against the stored key|%s|matches=%s',
                   v_headers->>'x-dispatch-signature'
                     = encode(extensions.hmac(v_headers->>'x-dispatch-timestamp', v_key, 'sha256'), 'hex'),
                   v_headers->>'x-dispatch-signature'
                     = encode(extensions.hmac(v_headers->>'x-dispatch-timestamp', v_key, 'sha256'), 'hex'));

  -- ============================================= nothing was delivered by us
  select status into v_txt from public.notifications where id = v_note;
  r := r || format('Queuing a dispatch does not mark anything delivered|%s|status=%s',
                   v_txt = 'queued', v_txt);

  select count(*) into v_n from public.notifications where status = 'sent';
  r := r || format('Nothing anywhere is recorded as sent|%s|sent rows=%s', v_n = 0, v_n);

  -- ================================== a second tick does not double the work
  -- claim_push_batch marks rows claimed, so a tick that overlaps the previous
  -- one finds nothing left to ask for. Here the row is still queued (no
  -- dispatcher has run), so the guard being tested is the claim window itself.
  update public.notifications set claimed_at = now() where id = v_note;
  select public.dispatch_push_tick() into v_request2;
  r := r || format('A tick overlapping a claim in flight sends nothing|%s|returned=%s',
                   v_request2 is null, coalesce(v_request2::text,'null'));

  -- ...and once the claim goes stale the work is picked up again, so a
  -- dispatcher that died mid-run cannot strand a notification forever.
  update public.notifications set claimed_at = now() - interval '10 minutes' where id = v_note;
  select public.dispatch_push_tick() into v_request2;
  r := r || format('A claim abandoned mid-run is retried|%s|returned=%s',
                   v_request2 is not null, coalesce(v_request2::text,'null'));

  return query
  select split_part(x, '|', 1),
         split_part(x, '|', 2)::boolean,
         split_part(x, '|', 3)
  from unnest(r) as x;
end;
$function$;

-- The runner is called exactly once: it creates fixtures and queues a real
-- request, so a second call would collide with its own leftovers.
do $$
declare
  rec record;
  v_pass int := 0;
  v_fail int := 0;
  v_report text := '';
begin

  for rec in select * from pg_temp.run_dispatch_schedule_tests() loop
    if rec.passed then v_pass := v_pass + 1; else v_fail := v_fail + 1; end if;
    v_report := v_report || format(E'\n%s  %s  [%s]',
                                   case when rec.passed then 'PASS' else 'FAIL' end,
                                   rec.test_name, rec.detail);
  end loop;

  raise exception E'SCHEDULED DISPATCHER SUITE — PASS=% FAIL=% %', v_pass, v_fail, v_report;
end $$;
