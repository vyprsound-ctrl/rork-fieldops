-- =============================================================================
-- Harbour South FieldOps - Apple Sandbox review-access suite (migration 0017)
-- (DEVELOPMENT TOOLING, NOT PRODUCTION)
-- =============================================================================
--
-- Proves, against the real functions AFTER migration 0017:
--
--   * the switch platform_settings.apple_sandbox_any_company ships OFF, and with
--     it OFF behaviour is exactly as before (ordinary company refused,
--     allowlisted company applied);
--   * with the switch ON a brand-new company gets a Sandbox trial / paid plan;
--   * Sandbox never replaces Production - active OR expired - and any
--     Production row in the ledger refuses Sandbox, even for allowlisted
--     companies; Production still replaces Sandbox;
--   * ownership: one Apple subscription per company (TD409), appAccountToken
--     for another company refused (TD409);
--   * Sandbox renewals, expiry (workspace closes), upgrades, downgrades;
--   * renewal info from the other environment is ignored; unknown environments
--     are refused; only the service role can apply;
--   * SMS: a Sandbox-only entitlement never unlocks SMS; allowlisted Sandbox,
--     Production and legacy (null environment) entitlements keep it;
--   * turning the switch OFF again stops new Sandbox purchases instantly;
--   * app users cannot read or change the switch;
--   * the demo company is not touched by the migration.
--
-- HOW TO RUN
-- ----------
-- Run migration 0017 (without begin/commit) followed by this whole file as ONE
-- batch (see preview-0017.sh). It always ends in `raise exception`, so the
-- migration and every fixture row are rolled back. FAIL=0 is a pass.
-- =============================================================================

create or replace function pg_temp.run_apple_sandbox_review_tests()
returns table(test_name text, passed boolean, detail text)
language plpgsql
as $function$
declare
  r        text[] := array[]::text[];
  v_ms_now bigint := floor(extract(epoch from now()) * 1000)::bigint;
  v_day    bigint := 86400000;
  v_out    text;
  v_s      text;
  v_state  record;
  v_ent    record;
  v_wa     record;
  v_n      int;
  v_ok     boolean;
  v_rows   int;
  v_super  text := current_user;
  v_exp1   timestamptz;
  v_new    uuid; v_new2 uuid; v_allow uuid; v_prod uuid; v_prodx uuid; v_ledger uuid;
  v_legacy uuid; v_kill uuid; v_other uuid;
  v_owner  uuid := gen_random_uuid();
  v_demo   uuid := 'c45b2428-fc93-4322-a55e-6e5eb95584b6';
  v_team   text := 'com.harboursouth.fieldservice.team.monthly';
  v_bus    text := 'com.harboursouth.fieldservice.business.monthly';
  v_start  text := 'com.harboursouth.fieldservice.starter.monthly';
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- ---------------------------------------------------------------------------
  -- Switch shipped OFF and server-only
  -- ---------------------------------------------------------------------------
  r := r || format('SWITCH: row exists and is false|%s|value=%s',
    (select value from public.platform_settings where key = 'apple_sandbox_any_company') = 'false'::jsonb,
    (select value::text from public.platform_settings where key = 'apple_sandbox_any_company'));
  -- platform_settings carries Supabase's default table grants, so protection is
  -- row-level security ON with NO policies: app roles see and change 0 rows.
  r := r || format('SWITCH: platform_settings has RLS on and no policies|%s|',
    (select relrowsecurity from pg_class where oid = 'public.platform_settings'::regclass)
    and not exists (select 1 from pg_policies where schemaname = 'public' and tablename = 'platform_settings'));
  perform set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid()::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into v_n from public.platform_settings where key = 'apple_sandbox_any_company';
  update public.platform_settings set value = 'true'::jsonb where key = 'apple_sandbox_any_company';
  get diagnostics v_rows = row_count;
  perform set_config('role', 'anon', true);
  select v_n + count(*) into v_n from public.platform_settings;
  perform set_config('role', v_super, true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  r := r || format('SWITCH: signed-in and anonymous users can neither read nor flip it|%s|seen=%s updated=%s value=%s',
    v_n = 0 and v_rows = 0 and (select value from public.platform_settings where key = 'apple_sandbox_any_company') = 'false'::jsonb,
    v_n, v_rows, (select value::text from public.platform_settings where key = 'apple_sandbox_any_company'));
  r := r || format('GRANTS: apple_apply_transaction still not executable by app users|%s|',
    not has_function_privilege('authenticated', 'public.apple_apply_transaction(uuid,jsonb,jsonb,text)', 'execute')
    and not has_function_privilege('anon', 'public.apple_apply_transaction(uuid,jsonb,jsonb,text)', 'execute')
    and has_function_privilege('service_role', 'public.apple_apply_transaction(uuid,jsonb,jsonb,text)', 'execute'));
  r := r || format('GRANTS: sms_company_entitled still not executable by app users|%s|',
    not has_function_privilege('authenticated', 'public.sms_company_entitled(uuid)', 'execute')
    and not has_function_privilege('anon', 'public.sms_company_entitled(uuid)', 'execute'));

  -- Demo company untouched by the migration.
  select * into v_state from public.company_commercial_state(v_demo);
  r := r || format('DEMO: subscription row unchanged (Sandbox, orig 2000001246177223, allowlisted)|%s|env=%s orig=%s exp=%s',
    v_state.apple_environment = 'Sandbox' and v_state.apple_original_transaction_id = '2000001246177223'
    and exists (select 1 from public.apple_sandbox_companies where company_id = v_demo),
    v_state.apple_environment, v_state.apple_original_transaction_id, v_state.period_ends_at);
  select count(*) into v_n from public.apple_transactions where company_id = v_demo;
  r := r || format('DEMO: purchase history unchanged (11 Sandbox rows)|%s|rows=%s', v_n = 11, v_n);

  -- ---------------------------------------------------------------------------
  -- Fixtures
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
  values ('00000000-0000-0000-0000-000000000000', v_owner, 'authenticated', 'authenticated', 'owner@sbxtest.invalid', 'x',
          now(), now(), now(), '{"provider":"email"}'::jsonb, '{}'::jsonb, false);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST New','hvac','US','USD','America/New_York') returning id into v_new;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST New 2','hvac','US','USD','America/New_York') returning id into v_new2;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST Allowlisted','hvac','US','USD','America/New_York') returning id into v_allow;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST Prod','hvac','US','USD','America/New_York') returning id into v_prod;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST Prod Expired','hvac','US','USD','America/New_York') returning id into v_prodx;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST Ledger','hvac','US','USD','America/New_York') returning id into v_ledger;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST Legacy','hvac','US','USD','America/New_York') returning id into v_legacy;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST Kill','hvac','US','USD','America/New_York') returning id into v_kill;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SBXTEST Other','hvac','US','USD','America/New_York') returning id into v_other;
  insert into public.company_subscriptions (company_id)
    values (v_new), (v_new2), (v_allow), (v_prod), (v_prodx), (v_ledger), (v_legacy), (v_kill), (v_other);
  insert into public.app_users (id, company_id, name, email, role)
    values (v_owner, v_new, 'Sbx Owner', 'owner@sbxtest.invalid', 'owner');
  insert into public.apple_sandbox_companies (company_id, note) values (v_allow, 'suite'), (v_ledger, 'suite');

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- ---------------------------------------------------------------------------
  -- Switch OFF: unchanged behaviour
  -- ---------------------------------------------------------------------------
  v_out := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Sandbox','transactionId','SB-OFF-1','originalTransactionId','SB-O-NEW','productId',v_team,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now,'appAccountToken',v_new::text), null, 'app');
  select * into v_ent from public.company_entitlement_for(v_new);
  r := r || format('OFF: Sandbox on a new company is refused, no entitlement|%s|out=%s ent=%s',
    v_out = 'sandboxNotApplied' and not v_ent.has_entitlement, v_out, v_ent.has_entitlement);
  r := r || format('OFF: the refused purchase is kept as a Sandbox ledger row|%s|',
    exists (select 1 from public.apple_transactions where environment='Sandbox' and transaction_id='SB-OFF-1' and company_id=v_new));

  v_out := public.apple_apply_transaction(v_allow,
    jsonb_build_object('environment','Sandbox','transactionId','SB-AL-1','originalTransactionId','SB-O-AL','productId',v_bus,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_state from public.company_commercial_state(v_allow);
  r := r || format('OFF: allowlisted company still gets its Sandbox plan|%s|out=%s tier=%s env=%s',
    v_out = 'applied:active' and v_state.has_entitlement and v_state.tier_id = 'business' and v_state.apple_environment = 'Sandbox',
    v_out, v_state.tier_id, v_state.apple_environment);

  -- ---------------------------------------------------------------------------
  -- Switch ON
  -- ---------------------------------------------------------------------------
  update public.platform_settings set value = 'true'::jsonb where key = 'apple_sandbox_any_company';

  -- Workspace is read-only before the purchase.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  begin
    select * into v_wa from public.company_workspace_access();
    r := r || format('ON: new company workspace is closed before purchase|%s|has=%s state=%s', not v_wa.has_active_subscription, v_wa.has_active_subscription, v_wa.subscription_state);
  exception when others then
    r := r || format('ON: new company workspace is closed before purchase|false|error %s %s', sqlstate, sqlerrm);
  end;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- Free trial (same original transaction the app retries after the first refusal).
  v_out := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Sandbox','transactionId','SB-ON-1','originalTransactionId','SB-O-NEW','productId',v_team,
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 14*v_day,'offerType',1,'offerDiscountType','FREE_TRIAL',
      'signedDate',v_ms_now + 1000,'appAccountToken',v_new::text),
    jsonb_build_object('environment','Sandbox','originalTransactionId','SB-O-NEW','autoRenewStatus',1,'autoRenewProductId',v_team,'signedDate',v_ms_now + 1000), 'app');
  select * into v_state from public.company_commercial_state(v_new);
  r := r || format('ON: new company Sandbox trial is applied|%s|out=%s state=%s tier=%s env=%s',
    v_out = 'applied:trial' and v_state.has_entitlement and v_state.entitlement_state = 'trial' and v_state.tier_id = 'team' and v_state.apple_environment = 'Sandbox',
    v_out, v_state.entitlement_state, v_state.tier_id, v_state.apple_environment);

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  begin
    select * into v_wa from public.company_workspace_access();
    r := r || format('ON: workspace opens after the purchase|%s|has=%s state=%s plan=%s', v_wa.has_active_subscription and v_wa.plan_name is not null, v_wa.has_active_subscription, v_wa.subscription_state, v_wa.plan_name);
  exception when others then
    r := r || format('ON: workspace opens after the purchase|false|error %s %s', sqlstate, sqlerrm);
  end;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- Paid renewal after the trial extends expiry.
  v_out := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Sandbox','transactionId','SB-ON-2','originalTransactionId','SB-O-NEW','productId',v_team,
      'purchaseDate',v_ms_now + 14*v_day,'expiresDate',v_ms_now + 44*v_day,'signedDate',v_ms_now + 2000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_new);
  v_exp1 := v_state.period_ends_at;
  r := r || format('ON: Sandbox paid renewal is active and extends the period|%s|out=%s state=%s ends=%s',
    v_out = 'applied:active' and v_state.entitlement_state = 'active' and not v_state.is_free_offer
    and v_state.period_ends_at > now() + interval '43 days', v_out, v_state.entitlement_state, v_state.period_ends_at);

  -- Downgrade scheduled at renewal.
  v_out := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Sandbox','transactionId','SB-ON-2','originalTransactionId','SB-O-NEW','productId',v_team,
      'purchaseDate',v_ms_now + 14*v_day,'expiresDate',v_ms_now + 44*v_day,'signedDate',v_ms_now + 3000),
    jsonb_build_object('environment','Sandbox','originalTransactionId','SB-O-NEW','autoRenewStatus',1,'autoRenewProductId',v_start,'signedDate',v_ms_now + 3000), 'notification');
  select * into v_state from public.company_commercial_state(v_new);
  select * into v_ent from public.company_entitlement_for(v_new);
  r := r || format('ON: Sandbox downgrade keeps Team now and schedules Starter|%s|tier=%s next=%s pending=%s/%s',
    v_state.tier_id = 'team' and v_state.renews_to_tier_id = 'starter' and v_ent.pending_tier_id = 'starter' and v_ent.pending_user_limit = 1,
    v_state.tier_id, v_state.renews_to_tier_id, v_ent.pending_tier_id, v_ent.pending_user_limit);

  -- Immediate upgrade: superseded transaction is history; new product applied.
  v_out := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Sandbox','transactionId','SB-ON-2','originalTransactionId','SB-O-NEW','productId',v_team,
      'purchaseDate',v_ms_now + 14*v_day,'expiresDate',v_ms_now + 44*v_day,'signedDate',v_ms_now + 4000,'isUpgraded',true), null, 'notification');
  v_s := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Sandbox','transactionId','SB-ON-3','originalTransactionId','SB-O-NEW','productId',v_bus,
      'purchaseDate',v_ms_now + 15*v_day,'expiresDate',v_ms_now + 45*v_day,'signedDate',v_ms_now + 5000),
    jsonb_build_object('environment','Sandbox','originalTransactionId','SB-O-NEW','autoRenewStatus',1,'autoRenewProductId',v_bus,'signedDate',v_ms_now + 5000), 'notification');
  select * into v_state from public.company_commercial_state(v_new);
  r := r || format('ON: Sandbox upgrade - old tx upgradedAway, Business applied|%s|old=%s new=%s tier=%s',
    v_out = 'upgradedAway' and v_s = 'applied:active' and v_state.tier_id = 'business', v_out, v_s, v_state.tier_id);

  -- Renewal info from Production is ignored on a Sandbox subscription.
  v_out := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Sandbox','transactionId','SB-ON-3','originalTransactionId','SB-O-NEW','productId',v_bus,
      'purchaseDate',v_ms_now + 15*v_day,'expiresDate',v_ms_now + 45*v_day,'signedDate',v_ms_now + 5000),
    jsonb_build_object('environment','Production','originalTransactionId','SB-O-NEW','autoRenewStatus',0,'signedDate',v_ms_now + 6000), 'notification');
  select * into v_state from public.company_commercial_state(v_new);
  r := r || format('ON: renewal info from the other environment is ignored|%s|renew=%s', v_state.will_auto_renew, v_state.will_auto_renew);

  -- Unknown environment still refused with the switch ON.
  v_out := public.apple_apply_transaction(v_new2,
    jsonb_build_object('environment','Xcode','transactionId','SB-X','originalTransactionId','SB-OX','productId',v_bus,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  v_s := public.apple_apply_transaction(v_new2,
    jsonb_build_object('transactionId','SB-X2','originalTransactionId','SB-OX2','productId',v_bus,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select count(*) into v_n from public.apple_transactions where transaction_id in ('SB-X','SB-X2');
  r := r || format('ON: unknown / missing environment refused, nothing recorded|%s|xcode=%s missing=%s rows=%s',
    v_out = 'unsupportedEnvironment' and v_s = 'unsupportedEnvironment' and v_n = 0, v_out, v_s, v_n);

  -- Ownership: the same Sandbox subscription cannot move to another company.
  begin
    v_out := public.apple_apply_transaction(v_new2,
      jsonb_build_object('environment','Sandbox','transactionId','SB-ON-4','originalTransactionId','SB-O-NEW','productId',v_bus,
        'purchaseDate',v_ms_now + 16*v_day,'expiresDate',v_ms_now + 46*v_day,'signedDate',v_ms_now + 7000), null, 'app');
  exception when others then v_out := 'error ' || sqlstate;
  end;
  r := r || format('ON: one Sandbox subscription cannot be attached to a second company (TD409)|%s|out=%s', v_out = 'error TD409', v_out);

  -- Ownership: appAccountToken for another company.
  begin
    v_out := public.apple_apply_transaction(v_new2,
      jsonb_build_object('environment','Sandbox','transactionId','SB-TK-1','originalTransactionId','SB-O-TK','productId',v_bus,
        'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now,'appAccountToken',v_new::text), null, 'app');
  exception when others then v_out := 'error ' || sqlstate;
  end;
  r := r || format('ON: purchase made for another company (appAccountToken) is refused (TD409)|%s|out=%s', v_out = 'error TD409', v_out);

  -- Only the server can apply.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner::text, 'role', 'authenticated')::text, true);
  begin
    v_out := public.apple_apply_transaction(v_new2,
      jsonb_build_object('environment','Sandbox','transactionId','SB-U','originalTransactionId','SB-OU','productId',v_bus,
        'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  exception when others then v_out := 'error ' || sqlstate;
  end;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  r := r || format('ON: an app user cannot apply a transaction (TD403)|%s|out=%s', v_out = 'error TD403', v_out);

  -- Expiry: a Sandbox subscription that has expired gives no entitlement.
  v_out := public.apple_apply_transaction(v_new2,
    jsonb_build_object('environment','Sandbox','transactionId','SB-EX-1','originalTransactionId','SB-O-EX','productId',v_team,
      'purchaseDate',v_ms_now - 31*v_day,'expiresDate',v_ms_now - v_day,'signedDate',v_ms_now - 31*v_day), null, 'app');
  select * into v_ent from public.company_entitlement_for(v_new2);
  r := r || format('ON: an expired Sandbox subscription gives no entitlement (read-only)|%s|out=%s state=%s has=%s',
    v_out = 'applied:expired' and not v_ent.has_entitlement and v_ent.entitlement_state = 'expired', v_out, v_ent.entitlement_state, v_ent.has_entitlement);
  -- ...and a renewal re-opens it.
  v_out := public.apple_apply_transaction(v_new2,
    jsonb_build_object('environment','Sandbox','transactionId','SB-EX-2','originalTransactionId','SB-O-EX','productId',v_team,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_ent from public.company_entitlement_for(v_new2);
  r := r || format('ON: a Sandbox renewal after expiry restores the plan|%s|out=%s', v_out = 'applied:active' and v_ent.has_entitlement, v_out);

  -- ---------------------------------------------------------------------------
  -- Production protections (switch ON)
  -- ---------------------------------------------------------------------------
  v_out := public.apple_apply_transaction(v_prod,
    jsonb_build_object('environment','Production','transactionId','PR-1','originalTransactionId','PR-O1','productId',v_team,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  v_s := public.apple_apply_transaction(v_prod,
    jsonb_build_object('environment','Sandbox','transactionId','PR-S1','originalTransactionId','PR-OS1','productId',v_bus,
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 400*v_day,'signedDate',v_ms_now + 1000), null, 'app');
  select * into v_state from public.company_commercial_state(v_prod);
  r := r || format('PROD: Sandbox cannot replace an active Production plan|%s|prod=%s sbx=%s tier=%s env=%s',
    v_out = 'applied:active' and v_s = 'sandboxNotApplied' and v_state.tier_id = 'team' and v_state.apple_environment = 'Production' and v_state.apple_original_transaction_id = 'PR-O1',
    v_out, v_s, v_state.tier_id, v_state.apple_environment);

  v_out := public.apple_apply_transaction(v_prodx,
    jsonb_build_object('environment','Production','transactionId','PX-1','originalTransactionId','PX-O1','productId',v_team,
      'purchaseDate',v_ms_now - 40*v_day,'expiresDate',v_ms_now - 10*v_day,'signedDate',v_ms_now - 40*v_day), null, 'app');
  v_s := public.apple_apply_transaction(v_prodx,
    jsonb_build_object('environment','Sandbox','transactionId','PX-S1','originalTransactionId','PX-OS1','productId',v_bus,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_state from public.company_commercial_state(v_prodx);
  r := r || format('PROD: Sandbox cannot revive an EXPIRED Production company|%s|prod=%s sbx=%s has=%s env=%s',
    v_out = 'applied:expired' and v_s = 'sandboxNotApplied' and not v_state.has_entitlement and v_state.apple_environment = 'Production',
    v_out, v_s, v_state.has_entitlement, v_state.apple_environment);

  -- Production history only in the ledger, on an ALLOWLISTED company.
  insert into public.apple_transactions (transaction_id, original_transaction_id, company_id, product_id, purchase_at, expires_at,
                                         environment, signed_at, source)
  values ('LG-1', 'LG-O1', v_ledger, v_team, now() - interval '90 days', now() - interval '60 days', 'Production', now() - interval '90 days', 'notification');
  v_s := public.apple_apply_transaction(v_ledger,
    jsonb_build_object('environment','Sandbox','transactionId','LG-S1','originalTransactionId','LG-OS1','productId',v_bus,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_ent from public.company_entitlement_for(v_ledger);
  r := r || format('PROD: any Production purchase history refuses Sandbox (even allowlisted)|%s|sbx=%s has=%s',
    v_s = 'sandboxNotApplied' and not v_ent.has_entitlement, v_s, v_ent.has_entitlement);

  -- Production replaces a Sandbox plan, and Sandbox cannot take it back.
  v_out := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Production','transactionId','NP-1','originalTransactionId','NP-O1','productId',v_start,
      'purchaseDate',v_ms_now + 20*v_day,'expiresDate',v_ms_now + 50*v_day,'signedDate',v_ms_now + 8000,'appAccountToken',v_new::text), null, 'app');
  v_s := public.apple_apply_transaction(v_new,
    jsonb_build_object('environment','Sandbox','transactionId','SB-ON-5','originalTransactionId','SB-O-NEW','productId',v_bus,
      'purchaseDate',v_ms_now + 21*v_day,'expiresDate',v_ms_now + 60*v_day,'signedDate',v_ms_now + 9000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_new);
  r := r || format('PROD: Production replaces Sandbox; a later Sandbox renewal cannot take it back|%s|prod=%s sbx=%s tier=%s env=%s',
    v_out = 'applied:active' and v_s = 'sandboxNotApplied' and v_state.tier_id = 'starter' and v_state.apple_environment = 'Production',
    v_out, v_s, v_state.tier_id, v_state.apple_environment);

  -- ---------------------------------------------------------------------------
  -- SMS safeguard
  -- ---------------------------------------------------------------------------
  v_out := public.apple_apply_transaction(v_other,
    jsonb_build_object('environment','Sandbox','transactionId','SM-S1','originalTransactionId','SM-OS1','productId',v_bus,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_ent from public.company_entitlement_for(v_other);
  r := r || format('SMS: Sandbox-only company is entitled to the workspace but NOT to SMS|%s|out=%s has=%s sms=%s',
    v_out = 'applied:active' and v_ent.has_entitlement and not public.sms_company_entitled(v_other),
    v_out, v_ent.has_entitlement, public.sms_company_entitled(v_other));
  r := r || format('SMS: allowlisted Sandbox company keeps SMS|%s|', public.sms_company_entitled(v_allow));
  r := r || format('SMS: Production company keeps SMS|%s|', public.sms_company_entitled(v_prod));
  r := r || format('SMS: Production that replaced Sandbox has SMS|%s|', public.sms_company_entitled(v_new));
  r := r || format('SMS: expired Production company has no SMS (unchanged)|%s|', not public.sms_company_entitled(v_prodx));
  update public.company_subscriptions set store = 'apple', tier_id = 'team', apple_expires_at = now() + interval '20 days', apple_auto_renew = true
   where company_id = v_legacy;
  r := r || format('SMS: legacy entitlement with no environment keeps SMS (existing fixtures)|%s|env=%s',
    public.sms_company_entitled(v_legacy), (select apple_environment from public.company_subscriptions where company_id = v_legacy));
  r := r || format('SMS: no company has SMS without an entitlement (unchanged)|%s|', not public.sms_company_entitled(v_kill));
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname in ('sms_send_blocker','consume_sms_credit','sms_messaging_status')
     and p.prosrc ilike '%sms_company_entitled%';
  r := r || format('SMS: send, credit and status gates all go through sms_company_entitled|%s|n=%s', v_n = 3, v_n);

  -- ---------------------------------------------------------------------------
  -- Kill switch: OFF again stops new Sandbox purchases instantly
  -- ---------------------------------------------------------------------------
  update public.platform_settings set value = 'false'::jsonb where key = 'apple_sandbox_any_company';
  v_out := public.apple_apply_transaction(v_kill,
    jsonb_build_object('environment','Sandbox','transactionId','KL-1','originalTransactionId','KL-O1','productId',v_bus,
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_ent from public.company_entitlement_for(v_kill);
  r := r || format('KILL: switch OFF again refuses new Sandbox purchases|%s|out=%s has=%s', v_out = 'sandboxNotApplied' and not v_ent.has_entitlement, v_out, v_ent.has_entitlement);
  v_s := public.apple_apply_transaction(v_allow,
    jsonb_build_object('environment','Sandbox','transactionId','SB-AL-2','originalTransactionId','SB-O-AL','productId',v_bus,
      'purchaseDate',v_ms_now + 30*v_day,'expiresDate',v_ms_now + 60*v_day,'signedDate',v_ms_now + 1000), null, 'notification');
  r := r || format('KILL: allowlisted company still renews with the switch OFF|%s|out=%s', v_s = 'applied:active', v_s);

  return query
    select split_part(x, '|', 1), split_part(x, '|', 2)::boolean, split_part(x, '|', 3)
    from unnest(r) as x;
end;
$function$;

do $runner$
declare
  v_report text := '';
  v_pass int := 0;
  v_fail int := 0;
  rec record;
begin
  for rec in select * from pg_temp.run_apple_sandbox_review_tests() loop
    if rec.passed then
      v_pass := v_pass + 1;
    else
      v_fail := v_fail + 1;
      v_report := v_report || chr(10) || 'FAIL: ' || rec.test_name || ' -- ' || coalesce(rec.detail, '');
    end if;
  end loop;

  raise exception 'APPLE SANDBOX REVIEW SUITE  pass=% fail=% %', v_pass, v_fail, v_report;
end
$runner$;
