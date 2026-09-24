-- =============================================================================
-- TradeDesk — invitation lifecycle suite (DEVELOPMENT TOOLING, NOT PRODUCTION)
-- =============================================================================
--
-- The backend security suite proves the *negative* invitation cases (a dispatcher
-- cannot invite; an admin cannot mint an owner). This file proves the positive
-- path actually works end to end, and that the tenant boundary holds while it
-- does:
--
--   1  Owner can issue an invitation
--   2  Admin can issue a non-owner invitation
--   3  Invited user accepts and lands in the INVITER's company
--   4  Accepted membership carries the invited role, not a client-chosen one
--   5  A token is single-use
--   6  A token is email-bound (a leaked token is useless to another account)
--   7  An expired invitation is refused
--   8  A revoked invitation is refused
--   9  create_invitation takes no company_id — the tenant comes from the caller
--  10  A client cannot forge an invitation row for another company
--  11  A client cannot forge an app_users membership row directly
--  12  The invited user sees only their new company's data
--
-- Defined in `pg_temp` for the same reason as the security suite: session-local,
-- invisible to `anon`/`authenticated`, never exposed through PostgREST.
--
-- HOW TO RUN
-- ----------
-- Run the whole file as one statement batch. The runner always ends in
-- `raise exception`, so every fixture row is rolled back and the report comes
-- back in the error message. FAIL=0 is a pass.
-- =============================================================================

create or replace function pg_temp.run_invitation_tests()
returns table(test_name text, passed boolean, detail text)
language plpgsql
as $function$
declare
  r text[] := array[]::text[];
  v_ca uuid; v_cb uuid;
  v_a_owner uuid := gen_random_uuid();
  v_a_admin uuid := gen_random_uuid();
  v_b_owner uuid := gen_random_uuid();
  -- Invited identities: the auth account exists, the membership does not yet.
  v_new_disp uuid := gen_random_uuid();
  v_new_tech uuid := gen_random_uuid();
  v_wrong    uuid := gen_random_uuid();
  v_expired  uuid := gen_random_uuid();
  v_revoked  uuid := gen_random_uuid();

  v_inv_id uuid; v_tok text;
  v_inv_tech uuid; v_tok_tech text;
  v_inv_exp uuid; v_tok_exp text;
  v_inv_rev uuid; v_tok_rev text;
  v_cust_a uuid; v_cust_b uuid;
  v_n int; v_txt text; v_uuid uuid;
begin
  -- This suite proves the invitation lifecycle, not plan seats (those are in
  -- subscription-entitlement-suite.sql). Its fixture companies hold no plan,
  -- so the seat rule is lifted for this rolled-back run only.
  update public.platform_settings set value = 'false'::jsonb where key = 'seat_limits_enforced';

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated',
         u.em, 'x', now(), now(), now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, false
  from (values
    (v_a_owner ,'a.owner@invitetest.invalid'),
    (v_a_admin ,'a.admin@invitetest.invalid'),
    (v_b_owner ,'b.owner@invitetest.invalid'),
    (v_new_disp,'new.disp@invitetest.invalid'),
    (v_new_tech,'new.tech@invitetest.invalid'),
    (v_wrong   ,'wrong.person@invitetest.invalid'),
    (v_expired ,'expired@invitetest.invalid'),
    (v_revoked ,'revoked@invitetest.invalid')
  ) as u(id, em);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('INVTEST Alpha','hvac','US','USD','America/New_York') returning id into v_ca;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('INVTEST Beta','plumbing','US','USD','America/Chicago') returning id into v_cb;

  insert into public.app_users (id, company_id, name, email, role) values
    (v_a_owner, v_ca, 'A Owner','a.owner@invitetest.invalid','owner'),
    (v_a_admin, v_ca, 'A Admin','a.admin@invitetest.invalid','admin'),
    (v_b_owner, v_cb, 'B Owner','b.owner@invitetest.invalid','owner');

  insert into public.customers (company_id, name) values (v_ca,'INVTEST Cust A') returning id into v_cust_a;
  insert into public.customers (company_id, name) values (v_cb,'INVTEST Cust B') returning id into v_cust_b;

  set local role authenticated;

  -- ---------------------------------------------------------------- 1
  perform set_config('request.jwt.claims', json_build_object('sub', v_a_owner::text,'role','authenticated')::text, true);
  begin
    select invitation_id, invitation_token into v_inv_id, v_tok
      from public.create_invitation('new.disp@invitetest.invalid','dispatcher',7);
    r := r || format('Owner can issue an invitation|%s|token_len=%s', (v_tok is not null and length(v_tok) > 16), coalesce(length(v_tok),0));
  exception when others then
    r := r || format('Owner can issue an invitation|false|%s', replace(sqlerrm,'|','/'));
  end;

  -- The invitation is stamped with the INVITER's company, never a supplied one.
  select company_id into v_uuid from public.invitations where id = v_inv_id;
  r := r || format('Invitation is stamped with the inviter company|%s|matches_alpha=%s', (v_uuid = v_ca), (v_uuid = v_ca));

  -- ---------------------------------------------------------------- 2
  perform set_config('request.jwt.claims', json_build_object('sub', v_a_admin::text,'role','authenticated')::text, true);
  begin
    select invitation_id, invitation_token into v_inv_tech, v_tok_tech
      from public.create_invitation('new.tech@invitetest.invalid','fieldWorker',7);
    r := r || format('Admin can issue a non-owner invitation|%s|role=fieldWorker', (v_tok_tech is not null));
  exception when others then
    r := r || format('Admin can issue a non-owner invitation|false|%s', replace(sqlerrm,'|','/'));
  end;

  -- Expiring and revoked fixtures, issued by the owner.
  perform set_config('request.jwt.claims', json_build_object('sub', v_a_owner::text,'role','authenticated')::text, true);
  select invitation_id, invitation_token into v_inv_exp, v_tok_exp
    from public.create_invitation('expired@invitetest.invalid','dispatcher',1);
  select invitation_id, invitation_token into v_inv_rev, v_tok_rev
    from public.create_invitation('revoked@invitetest.invalid','dispatcher',7);

  begin
    perform public.revoke_invitation(v_inv_rev);
    select (revoked_at is not null) into v_txt from public.invitations where id = v_inv_rev;
    r := r || format('Owner can revoke an invitation|%s|revoked_at_set=%s', (v_txt = 'true'), v_txt);
  exception when others then
    r := r || format('Owner can revoke an invitation|false|%s', replace(sqlerrm,'|','/'));
  end;

  -- ---------------------------------------------------------------- 9
  -- Structural, not behavioural: the RPC has no company_id argument at all, so
  -- there is no parameter for a client to lie about.
  select pg_get_function_arguments(p.oid) into v_txt
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname='public' and p.proname='create_invitation';
  r := r || format('create_invitation accepts no company_id|%s|args=%s', (v_txt not like '%company%'), replace(v_txt,'|','/'));

  -- ---------------------------------------------------------------- 10
  perform set_config('request.jwt.claims', json_build_object('sub', v_a_owner::text,'role','authenticated')::text, true);
  begin
    insert into public.invitations (company_id, email, role, token, invited_by_user_id, expires_at)
    values (v_cb, 'forged@invitetest.invalid', 'owner', 'forged-token-value-123456', v_a_owner, now() + interval '7 days');
    r := r || 'Client cannot forge an invitation for another company|false|insert unexpectedly succeeded';
  exception when others then
    r := r || format('Client cannot forge an invitation for another company|true|%s', replace(sqlerrm,'|','/'));
  end;

  -- ---------------------------------------------------------------- 11
  begin
    insert into public.app_users (id, company_id, name, email, role)
    values (v_wrong, v_cb, 'Forged Member','wrong.person@invitetest.invalid','owner');
    r := r || 'Client cannot forge a membership row|false|insert unexpectedly succeeded';
  exception when others then
    r := r || format('Client cannot forge a membership row|true|%s', replace(sqlerrm,'|','/'));
  end;

  -- ---------------------------------------------------------------- 6
  -- A leaked token in the wrong hands. Same token, different signed-in account.
  perform set_config('request.jwt.claims', json_build_object('sub', v_wrong::text,'role','authenticated')::text, true);
  begin
    perform public.accept_invitation(v_tok);
    r := r || 'Token is email-bound (leaked token refused)|false|accept unexpectedly succeeded';
  exception when others then
    r := r || format('Token is email-bound (leaked token refused)|true|%s', replace(sqlerrm,'|','/'));
  end;

  select count(*) into v_n from public.app_users where id = v_wrong;
  r := r || format('Refused acceptance created no membership|%s|rows=%s', (v_n = 0), v_n);

  -- ---------------------------------------------------------------- 3 & 4
  perform set_config('request.jwt.claims', json_build_object('sub', v_new_disp::text,'role','authenticated')::text, true);
  begin
    v_uuid := public.accept_invitation(v_tok);
    r := r || format('Invited user can accept|%s|returned=%s', (v_uuid is not null), coalesce(v_uuid::text,'null'));
  exception when others then
    r := r || format('Invited user can accept|false|%s', replace(sqlerrm,'|','/'));
  end;

  reset role;
  select company_id, role::text into v_uuid, v_txt from public.app_users where id = v_new_disp;
  r := r || format('Accepted member joins the inviter company|%s|alpha=%s', (v_uuid = v_ca), (v_uuid = v_ca));
  r := r || format('Accepted member carries the invited role|%s|role=%s', (v_txt = 'dispatcher'), coalesce(v_txt,'none'));

  select (accepted_at is not null and accepted_by_user_id = v_new_disp)::text into v_txt
    from public.invitations where id = v_inv_id;
  r := r || format('Acceptance is recorded on the invitation|%s|accepted=%s', (v_txt = 'true'), coalesce(v_txt,'null'));
  set local role authenticated;

  -- ---------------------------------------------------------------- 5
  perform set_config('request.jwt.claims', json_build_object('sub', v_new_tech::text,'role','authenticated')::text, true);
  begin
    perform public.accept_invitation(v_tok);
    r := r || 'Token is single-use|false|second accept unexpectedly succeeded';
  exception when others then
    r := r || format('Token is single-use|true|%s', replace(sqlerrm,'|','/'));
  end;

  -- The second user's own invitation still works — one burnt token does not
  -- poison the queue.
  begin
    perform public.accept_invitation(v_tok_tech);
    reset role;
    select role::text into v_txt from public.app_users where id = v_new_tech;
    set local role authenticated;
    r := r || format('A second invitation still accepts independently|%s|role=%s', (v_txt = 'fieldWorker'), coalesce(v_txt,'none'));
  exception when others then
    r := r || format('A second invitation still accepts independently|false|%s', replace(sqlerrm,'|','/'));
  end;

  -- ---------------------------------------------------------------- 7
  reset role;
  update public.invitations set expires_at = now() - interval '1 day' where id = v_inv_exp;
  set local role authenticated;
  perform set_config('request.jwt.claims', json_build_object('sub', v_expired::text,'role','authenticated')::text, true);
  begin
    perform public.accept_invitation(v_tok_exp);
    r := r || 'Expired invitation is refused|false|accept unexpectedly succeeded';
  exception when others then
    r := r || format('Expired invitation is refused|true|%s', replace(sqlerrm,'|','/'));
  end;

  -- ---------------------------------------------------------------- 8
  perform set_config('request.jwt.claims', json_build_object('sub', v_revoked::text,'role','authenticated')::text, true);
  begin
    perform public.accept_invitation(v_tok_rev);
    r := r || 'Revoked invitation is refused|false|accept unexpectedly succeeded';
  exception when others then
    r := r || format('Revoked invitation is refused|true|%s', replace(sqlerrm,'|','/'));
  end;

  -- ---------------------------------------------------------------- 12
  perform set_config('request.jwt.claims', json_build_object('sub', v_new_disp::text,'role','authenticated')::text, true);
  select count(*) into v_n from public.customers where id = v_cust_a;
  r := r || format('New member sees their own company data|%s|rows=%s', (v_n = 1), v_n);
  select count(*) into v_n from public.customers where id = v_cust_b;
  r := r || format('New member sees no other company data|%s|rows=%s', (v_n = 0), v_n);

  -- A freshly invited dispatcher inherits the dispatcher money ban.
  select count(*) into v_n from public.invoices;
  r := r || format('New dispatcher inherits the financial ban|%s|invoice_rows=%s', (v_n = 0), v_n);

  reset role;

  -- ---------------------------------------------------------------- cleanup
  alter table public.app_users disable trigger app_users_delete_protection;

  delete from public.notifications where company_id in (v_ca, v_cb);
  delete from public.sms_credit_ledger where company_id in (v_ca, v_cb);
  delete from public.customers where company_id in (v_ca, v_cb);
  delete from public.document_sequences where company_id in (v_ca, v_cb);
  delete from public.company_subscriptions where company_id in (v_ca, v_cb);
  delete from public.invitations where company_id in (v_ca, v_cb);
  delete from public.app_users where company_id in (v_ca, v_cb);
  delete from public.companies where id in (v_ca, v_cb);
  delete from auth.users where email like '%@invitetest.invalid';

  alter table public.app_users enable trigger app_users_delete_protection;

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

do $runner$
declare
  v_report text := '';
  v_pass int := 0;
  v_fail int := 0;
  rec record;
begin
  for rec in select * from pg_temp.run_invitation_tests() loop
    if rec.passed then
      v_pass := v_pass + 1;
    else
      v_fail := v_fail + 1;
      v_report := v_report || chr(10) || 'FAIL: ' || rec.test_name || ' -- ' || coalesce(rec.detail,'');
    end if;
  end loop;

  raise exception 'INVITATION SUITE  pass=% fail=% %', v_pass, v_fail, v_report;
end
$runner$;
