-- =============================================================================
-- Harbour South FieldOps — Apple subscription entitlement suite
-- (DEVELOPMENT TOOLING, NOT PRODUCTION)
-- =============================================================================
--
-- Proves, against the real functions from migration 0013:
--
--   * every entitlement state (none, trial, offer code, active, cancelling,
--     grace period, billing retry, expired, revoked) is derived correctly;
--   * a verified Apple transaction maps to the right plan and period for all
--     six products; an unknown product changes nothing;
--   * the 14-day trial and 30/90-day Offer Codes are entitlements, and the
--     renewal after the offer is the normal paid subscription;
--   * upgrade / downgrade / crossgrade between plans and periods;
--   * out-of-order and replayed events cannot roll state backwards;
--   * one Apple subscription cannot be attached to two companies;
--   * only the service role can write entitlement;
--   * plan user limits: Starter 1, Team 5, Business uncapped (12 and 30 users),
--     no plan = 1, existing users are never suspended, and the master switch;
--   * the Founding Member programme has no live function or column left;
--   * the Harbour South platform fee settings are unchanged (30 bps).
--
-- HOW TO RUN
-- ----------
-- Run the whole file as one batch. It always ends in `raise exception`, so every
-- fixture row is rolled back and the report comes back in the error message.
-- FAIL=0 is a pass.
-- =============================================================================

create or replace function pg_temp.run_subscription_tests()
returns table(test_name text, passed boolean, detail text)
language plpgsql
as $function$
declare
  r        text[] := array[]::text[];
  v_c      uuid; v_c2 uuid; v_cb uuid;
  v_owner  uuid := gen_random_uuid();
  v_owner2 uuid := gen_random_uuid();
  v_ownerb uuid := gen_random_uuid();
  v_joiner uuid;
  v_out    text;
  v_state  record;
  v_s      text;
  v_ms_now bigint := floor(extract(epoch from now()) * 1000)::bigint;
  v_day    bigint := 86400000;
  v_err    text;
  v_tok    text;
  v_n      int;
  i        int;
  v_prod   text;
  v_ct uuid; v_co uuid; v_cp uuid; v_cl uuid; v_cd uuid;
  v_ownerl uuid := gen_random_uuid();
  v_workerl uuid := gen_random_uuid();
  v_ownerd uuid := gen_random_uuid();
  v_workerd uuid;
  v_chk record;
  v_ce uuid; v_cf uuid; v_cg uuid; v_cx uuid;
  v_ownere uuid := gen_random_uuid();
  v_ownerf uuid := gen_random_uuid();
  v_ownerg uuid := gen_random_uuid();
  v_workere uuid;
  v_ox1 uuid := gen_random_uuid();
  v_ox2 uuid := gen_random_uuid();
  v_wx  uuid := gen_random_uuid();
  v_cust_x uuid;
  v_before int;
  v_ok boolean;
begin
  -- ---------------------------------------------------------------------------
  -- Pure state function
  -- ---------------------------------------------------------------------------
  r := r || format('No store means no entitlement|%s|%s', public.subscription_entitlement_state('none', now() + interval '1 day', null, true, null, false, false, null) = 'none', '');
  r := r || format('Free introductory offer is trial|%s|', public.subscription_entitlement_state('apple', now() + interval '14 days', null, true, null, false, true, 1) = 'trial');
  r := r || format('Free Offer Code is offer|%s|', public.subscription_entitlement_state('apple', now() + interval '90 days', null, true, null, false, true, 3) = 'offer');
  r := r || format('Paid unexpired is active|%s|', public.subscription_entitlement_state('apple', now() + interval '20 days', null, true, null, false, false, null) = 'active');
  r := r || format('Auto-renew off but unexpired is cancelling (still entitled)|%s|', public.subscription_entitlement_state('apple', now() + interval '5 days', null, false, null, false, false, null) = 'cancelling');
  r := r || format('Expired inside grace period is gracePeriod|%s|', public.subscription_entitlement_state('apple', now() - interval '1 day', null, true, now() + interval '5 days', true, false, null) = 'gracePeriod');
  r := r || format('Expired in billing retry without grace is billingRetry|%s|', public.subscription_entitlement_state('apple', now() - interval '1 day', null, true, null, true, false, null) = 'billingRetry');
  r := r || format('Expired is expired|%s|', public.subscription_entitlement_state('apple', now() - interval '1 day', null, false, null, false, false, null) = 'expired');
  r := r || format('Refunded is revoked even if unexpired|%s|', public.subscription_entitlement_state('apple', now() + interval '20 days', now(), true, null, false, false, null) = 'revoked');
  r := r || format('Entitled states are exactly trial/offer/active/cancelling/grace|%s|',
    public.subscription_state_is_entitled('trial') and public.subscription_state_is_entitled('offer')
    and public.subscription_state_is_entitled('active') and public.subscription_state_is_entitled('cancelling')
    and public.subscription_state_is_entitled('gracePeriod') and not public.subscription_state_is_entitled('billingRetry')
    and not public.subscription_state_is_entitled('expired') and not public.subscription_state_is_entitled('revoked')
    and not public.subscription_state_is_entitled('none'));

  -- ---------------------------------------------------------------------------
  -- Price list
  -- ---------------------------------------------------------------------------
  select count(*) into v_n from public.subscription_tiers where is_active;
  r := r || format('Exactly three active plans|%s|n=%s', v_n = 3, v_n);
  r := r || format('Starter 19.99/mo 191.99/yr 1 user|%s|', exists(select 1 from public.subscription_tiers where id='starter' and base_cents=1999 and annual_cents=19199 and user_limit=1 and included_users=1 and is_active));
  r := r || format('Team 39.99/mo 384.99/yr up to 5|%s|', exists(select 1 from public.subscription_tiers where id='team' and base_cents=3999 and annual_cents=38499 and user_limit=5 and included_users=5 and is_active));
  r := r || format('Business 69.99/mo 669.99/yr, 10 included, NO cap|%s|', exists(select 1 from public.subscription_tiers where id='business' and base_cents=6999 and annual_cents=66999 and user_limit is null and included_users=10 and is_active));
  r := r || format('No extra-user price in this revision|%s|', not exists(select 1 from public.subscription_tiers where is_active and additional_user_cents <> 0));
  r := r || format('Annual is ~20%% below 12 x monthly for every plan|%s|', not exists(
    select 1 from public.subscription_tiers where is_active
      and abs((1 - annual_cents::numeric / (12 * base_cents)) - 0.20) > 0.01));

  -- ---------------------------------------------------------------------------
  -- Founding programme retired; fee unchanged
  -- ---------------------------------------------------------------------------
  r := r || format('claim_founding_member_slot no longer exists|%s|', to_regprocedure('public.claim_founding_member_slot(uuid)') is null);
  r := r || format('founding_activity no longer exists|%s|', to_regprocedure('public.founding_activity(uuid)') is null);
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname ilike '%founding%' and p.proname <> 'founding_member_slots_guard';
  r := r || format('No live founding function remains|%s|n=%s', v_n = 0, v_n);
  select count(*) into v_n from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'company_commercial_state'
     and pg_get_function_result(p.oid) ilike '%founding%';
  r := r || format('Commercial state exposes no founding column|%s|', v_n = 0);
  r := r || format('App users cannot read the retired slots table|%s|', not has_table_privilege('authenticated', 'public.founding_member_slots', 'select'));
  r := r || format('Platform fee still 30 bps, enabled, min 0|%s|',
    (select (value #>> '{}')::int from public.platform_settings where key='application_fee_bps') = 30
    and (select (value #>> '{}')::boolean from public.platform_settings where key='application_fee_enabled')
    and (select (value #>> '{}')::int from public.platform_settings where key='application_fee_minimum_cents') = 0);
  r := r || format('Seat limits are ON as shipped by the migration|%s|', public.seat_limits_enforced());

  -- ---------------------------------------------------------------------------
  -- Fixtures
  -- ---------------------------------------------------------------------------
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.em, 'x', now(), now(), now(),
         '{"provider":"email"}'::jsonb, '{}'::jsonb, false
  from (values (v_owner,'owner@subtest.invalid'), (v_owner2,'owner2@subtest.invalid'), (v_ownerb,'ownerb@subtest.invalid')) u(id, em);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SUBTEST One','hvac','US','USD','America/New_York') returning id into v_c;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SUBTEST Two','hvac','US','USD','America/New_York') returning id into v_c2;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SUBTEST Big','hvac','US','USD','America/New_York') returning id into v_cb;
  insert into public.company_subscriptions (company_id) values (v_c), (v_c2), (v_cb);
  insert into public.app_users (id, company_id, name, email, role) values
    (v_owner, v_c, 'Owner', 'owner@subtest.invalid', 'owner'),
    (v_owner2, v_c2, 'Owner2', 'owner2@subtest.invalid', 'owner'),
    (v_ownerb, v_cb, 'OwnerB', 'ownerb@subtest.invalid', 'owner');

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

  -- A brand-new company has no Harbour South trial of its own.
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('New company: no entitlement and no local trial|%s|state=%s trial=%s', not v_state.has_entitlement and v_state.entitlement_state = 'none' and not v_state.is_trial_active and v_state.trial_ends_at is null, v_state.entitlement_state, v_state.is_trial_active);
  r := r || format('New company without a plan is limited to 1 user|%s|limit=%s', v_state.plan_user_limit = 1, v_state.plan_user_limit);

  -- Unknown product changes nothing.
  v_out := public.apple_apply_transaction(v_c, jsonb_build_object('environment','Production','transactionId','T0','originalTransactionId','O1','productId','com.example.other','purchaseDate',v_ms_now,'expiresDate',v_ms_now + v_day));
  r := r || format('Unknown product is refused without effect|%s|%s', v_out = 'unknownProduct' and (select store from public.company_subscriptions where company_id=v_c) = 'none', v_out);

  -- 14-day introductory free trial on Team monthly.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T1','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 14*v_day,'offerType',1,'offerDiscountType','FREE_TRIAL','offerPeriod','P2W','signedDate',v_ms_now,'price',0),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.team.monthly','signedDate',v_ms_now), 'app');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('14-day introductory trial is an entitlement on Team monthly|%s|out=%s state=%s tier=%s period=%s', v_out = 'applied:trial' and v_state.has_entitlement and v_state.entitlement_state='trial' and v_state.tier_id='team' and v_state.billing_period='monthly' and v_state.is_free_offer and v_state.trial_days_remaining = 14, v_out, v_state.entitlement_state, v_state.tier_id, v_state.billing_period);
  r := r || format('During the free trial the company pays 0 and will renew at 39.99|%s|eff=%s price=%s', v_state.effective_monthly_cents = 0 and v_state.plan_price_cents = 3999 and v_state.will_auto_renew and v_state.renews_to_tier_id='team', v_state.effective_monthly_cents, v_state.plan_price_cents);
  r := r || format('Legacy status mirrors Apple: trialing|%s|', (select status::text from public.company_subscriptions where company_id=v_c) = 'trialing');

  -- Replay is idempotent.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T1','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 14*v_day,'offerType',1,'offerDiscountType','FREE_TRIAL','signedDate',v_ms_now), null, 'notification');
  select count(*) into v_n from public.apple_transactions where original_transaction_id='O1';
  r := r || format('A replayed transaction is idempotent|%s|rows=%s out=%s', v_n = 1 and v_out = 'applied:trial', v_n, v_out);

  -- After the trial Apple bills automatically: first paid renewal.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T2','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 1000,'price',39990),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.team.monthly','signedDate',v_ms_now + 1000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Paid renewal after the trial is active and no longer a free offer|%s|out=%s', v_out='applied:active' and v_state.entitlement_state='active' and not v_state.is_free_offer and v_state.effective_monthly_cents = 3999 and v_state.trial_ends_at is null, v_out);

  -- Out-of-order: the trial transaction arriving late cannot roll it back.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T1','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 14*v_day,'offerType',1,'offerDiscountType','FREE_TRIAL','signedDate',v_ms_now), null, 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('A late older transaction cannot roll state backwards|%s|out=%s state=%s', v_out = 'stale' and v_state.entitlement_state='active', v_out, v_state.entitlement_state);

  -- Cancellation: auto-renew off, still entitled until the period ends.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T2','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 2000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',0,'autoRenewProductId','com.harboursouth.fieldservice.team.monthly','signedDate',v_ms_now + 2000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Cancelling keeps the plan until the period ends|%s|out=%s', v_out='applied:cancelling' and v_state.has_entitlement and not v_state.will_auto_renew, v_out);

  -- Downgrade scheduled (Team -> Starter at renewal): current plan unchanged.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T2','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 3000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.starter.monthly','signedDate',v_ms_now + 3000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('A scheduled downgrade keeps Team now and reports Starter at renewal|%s|tier=%s next=%s', v_state.tier_id='team' and v_state.renews_to_tier_id='starter' and v_state.will_auto_renew, v_state.tier_id, v_state.renews_to_tier_id);

  -- Immediate upgrade (Team monthly -> Business annual): the old transaction is
  -- marked upgraded and a new one starts now.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T2','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'isUpgraded',true,'signedDate',v_ms_now + 4000), null, 'notification');
  r := r || format('The superseded transaction of an upgrade is history only|%s|%s', v_out='upgradedAway', v_out);
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T3','originalTransactionId','O1','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 5000,'expiresDate',v_ms_now + 365*v_day,'signedDate',v_ms_now + 5000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.business.annual','signedDate',v_ms_now + 5000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Upgrade to Business annual applies immediately, uncapped|%s|tier=%s period=%s limit=%s price=%s', v_state.tier_id='business' and v_state.billing_period='annual' and v_state.plan_user_limit is null and v_state.plan_price_cents = 66999, v_state.tier_id, v_state.billing_period, v_state.plan_user_limit, v_state.plan_price_cents);

  -- Billing problem: expired, Apple retrying, grace period running.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T4','originalTransactionId','O1','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 6000,'expiresDate',v_ms_now - v_day,'signedDate',v_ms_now + 6000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'isInBillingRetryPeriod',true,'gracePeriodExpiresDate',v_ms_now + 6*v_day,'signedDate',v_ms_now + 6000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Billing grace period stays entitled and reports past due|%s|out=%s status=%s', v_out='applied:gracePeriod' and v_state.has_entitlement and v_state.subscription_status='pastDue' and v_state.grace_period_ends_at is not null, v_out, v_state.subscription_status);

  -- Grace over, Apple still retrying: not entitled.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T4','originalTransactionId','O1','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 6000,'expiresDate',v_ms_now - v_day,'signedDate',v_ms_now + 7000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'isInBillingRetryPeriod',true,'signedDate',v_ms_now + 7000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Billing retry after grace is not entitled|%s|out=%s', v_out='applied:billingRetry' and not v_state.has_entitlement and v_state.plan_user_limit = 1, v_out);

  -- Retry gave up: expired.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T4','originalTransactionId','O1','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 6000,'expiresDate',v_ms_now - v_day,'signedDate',v_ms_now + 8000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',0,'isInBillingRetryPeriod',false,'expirationIntent',2,'signedDate',v_ms_now + 8000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Expired subscription is not entitled|%s|out=%s status=%s', v_out='applied:expired' and not v_state.has_entitlement and v_state.subscription_status='expired', v_out, v_state.subscription_status);

  -- Resubscribe (restore of a new purchase), then refund.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T5','originalTransactionId','O1','productId','com.harboursouth.fieldservice.starter.annual',
      'purchaseDate',v_ms_now + 9000,'expiresDate',v_ms_now + 365*v_day,'signedDate',v_ms_now + 9000), null, 'restore');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Resubscribing (or restoring) re-entitles on Starter annual|%s|out=%s', v_out='applied:active' and v_state.tier_id='starter' and v_state.billing_period='annual' and v_state.plan_price_cents = 19199, v_out);
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('environment','Production','transactionId','T5','originalTransactionId','O1','productId','com.harboursouth.fieldservice.starter.annual',
      'purchaseDate',v_ms_now + 9000,'expiresDate',v_ms_now + 365*v_day,'revocationDate',v_ms_now + 10000,'signedDate',v_ms_now + 10000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('A refunded subscription is revoked immediately|%s|out=%s', v_out='applied:revoked' and not v_state.has_entitlement, v_out);

  -- Offer Codes: 30-day and 90-day free, then normal renewal.
  v_out := public.apple_apply_transaction(v_c2,
    jsonb_build_object('environment','Production','transactionId','U1','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'offerType',3,'offerIdentifier','SPRING30','offerDiscountType','FREE_TRIAL','offerPeriod','P1M','signedDate',v_ms_now), null, 'app');
  select * into v_state from public.company_commercial_state(v_c2);
  r := r || format('A 30-day free Offer Code is an entitlement|%s|out=%s code=%s', v_out='applied:offer' and v_state.has_entitlement and v_state.offer_type = 3 and v_state.offer_identifier='SPRING30' and v_state.effective_monthly_cents = 0, v_out, v_state.offer_identifier);
  v_out := public.apple_apply_transaction(v_c2,
    jsonb_build_object('environment','Production','transactionId','U2','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 90*v_day,'offerType',3,'offerIdentifier','PARTNER90','offerDiscountType','FREE_TRIAL','offerPeriod','P3M','signedDate',v_ms_now + 1000), null, 'app');
  select * into v_state from public.company_commercial_state(v_c2);
  r := r || format('A 90-day free Offer Code is an entitlement|%s|days=%s', v_out='applied:offer' and v_state.trial_days_remaining = 90, v_state.trial_days_remaining);
  v_out := public.apple_apply_transaction(v_c2,
    jsonb_build_object('environment','Production','transactionId','U3','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 2000,'expiresDate',v_ms_now + 120*v_day,'signedDate',v_ms_now + 2000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_c2);
  r := r || format('After an Offer Code the normal paid subscription follows|%s|out=%s', v_out='applied:active' and not v_state.is_free_offer and v_state.effective_monthly_cents=1999 and v_state.offer_type is null, v_out);

  -- One Apple subscription, one company.
  begin
    v_out := public.apple_apply_transaction(v_cb,
      jsonb_build_object('environment','Production','transactionId','U4','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
        'purchaseDate',v_ms_now + 3000,'expiresDate',v_ms_now + 150*v_day,'signedDate',v_ms_now + 3000), null, 'app');
    r := r || format('An App Store subscription cannot be attached to a second company|false|accepted %s', v_out);
  exception when others then
    r := r || format('An App Store subscription cannot be attached to a second company|%s|%s', sqlstate = 'TD409', sqlerrm);
  end;

  -- All six products map.
  foreach v_prod in array array['starter.monthly','starter.annual','team.monthly','team.annual','business.monthly','business.annual'] loop
    v_out := public.apple_apply_transaction(v_cb,
      jsonb_build_object('environment','Production','transactionId','P-' || v_prod,'originalTransactionId','O3','productId','com.harboursouth.fieldservice.' || v_prod,
        'purchaseDate',v_ms_now + (array_position(array['starter.monthly','starter.annual','team.monthly','team.annual','business.monthly','business.annual'], v_prod) * 1000),
        'expiresDate',v_ms_now + 40*v_day,'signedDate',v_ms_now), null, 'app');
    select * into v_state from public.company_commercial_state(v_cb);
    r := r || format('Product %s maps to its plan and period|%s|tier=%s period=%s', v_prod,
      v_state.tier_id = split_part(v_prod,'.',1) and v_state.billing_period = split_part(v_prod,'.',2), v_state.tier_id, v_state.billing_period);
  end loop;

  -- ---------------------------------------------------------------------------
  -- Company ownership of the subscription
  -- ---------------------------------------------------------------------------
  -- v_cb is now on O3 (Business annual, 40 days left).
  select * into v_state from public.company_commercial_state(v_cb);
  r := r || format('The commercial read names the linked Apple subscription|%s|%s', v_state.apple_original_transaction_id = 'O3', v_state.apple_original_transaction_id);

  -- A second owner subscribes on their own Apple ID while the company plan is
  -- live and runs longer: the company keeps its plan; nothing is overwritten.
  v_out := public.apple_apply_transaction(v_cb,
    jsonb_build_object('environment','Production','transactionId','N1','originalTransactionId','O4','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 50000,'expiresDate',v_ms_now + 20*v_day,'signedDate',v_ms_now + 50000),
    jsonb_build_object('originalTransactionId','O4','autoRenewStatus',0,'autoRenewProductId','com.harboursouth.fieldservice.starter.monthly','signedDate',v_ms_now + 50000), 'app');
  select * into v_state from public.company_commercial_state(v_cb);
  r := r || format('A second Apple subscription never replaces a live, longer company plan|%s|out=%s tier=%s orig=%s renew=%s',
    v_out = 'otherSubscription' and v_state.tier_id = 'business' and v_state.apple_original_transaction_id = 'O3' and v_state.will_auto_renew,
    v_out, v_state.tier_id, v_state.apple_original_transaction_id, v_state.will_auto_renew);

  -- A family-shared copy is not the purchaser's subscription.
  v_out := public.apple_apply_transaction(v_cb,
    jsonb_build_object('environment','Production','transactionId','F1','originalTransactionId','O3','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 51000,'expiresDate',v_ms_now + 40*v_day,'signedDate',v_ms_now + 51000,'inAppOwnershipType','FAMILY_SHARED'), null, 'app');
  r := r || format('A family-shared transaction is not treated as a purchase|%s|%s', v_out = 'notPurchaser', v_out);

  -- The company plan lapses in favour of a longer one bought by the new owner:
  -- the company follows the subscription that actually entitles it.
  v_out := public.apple_apply_transaction(v_cb,
    jsonb_build_object('environment','Production','transactionId','N2','originalTransactionId','O5','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 52000,'expiresDate',v_ms_now + 400*v_day,'signedDate',v_ms_now + 52000),
    jsonb_build_object('originalTransactionId','O5','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.business.annual','signedDate',v_ms_now + 52000), 'app');
  select * into v_state from public.company_commercial_state(v_cb);
  r := r || format('A longer subscription for the same company takes over cleanly|%s|out=%s orig=%s',
    v_out = 'applied:active' and v_state.apple_original_transaction_id = 'O5' and v_state.tier_id = 'business' and v_state.will_auto_renew,
    v_out, v_state.apple_original_transaction_id);

  -- A subscription a company has moved off still belongs to that company.
  begin
    v_out := public.apple_apply_transaction(v_c2,
      jsonb_build_object('environment','Production','transactionId','R1','originalTransactionId','O3','productId','com.harboursouth.fieldservice.business.annual',
        'purchaseDate',v_ms_now + 53000,'expiresDate',v_ms_now + 40*v_day,'signedDate',v_ms_now + 53000), null, 'restore');
    r := r || format('Restoring a superseded subscription into another company is refused|false|accepted %s', v_out);
  exception when others then
    r := r || format('Restoring a superseded subscription into another company is refused|%s|%s', sqlstate = 'TD409', sqlerrm);
  end;

  -- A purchase made for one company (appAccountToken) can never land in another.
  begin
    v_out := public.apple_apply_transaction(v_c2,
      jsonb_build_object('environment','Production','transactionId','K1','originalTransactionId','O6','productId','com.harboursouth.fieldservice.team.monthly',
        'purchaseDate',v_ms_now + 54000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 54000,'appAccountToken', upper(v_cb::text)), null, 'restore');
    r := r || format('A purchase tagged for another company is refused|false|accepted %s', v_out);
  exception when others then
    r := r || format('A purchase tagged for another company is refused|%s|%s', sqlstate = 'TD409', sqlerrm);
  end;
  select count(*) into v_n from public.apple_transactions where transaction_id in ('K1','R1');
  r := r || format('Refused purchases leave no ledger row|%s|n=%s', v_n = 0, v_n);

  -- The subscription is the company's, not a person's.
  select count(*) into v_n
    from information_schema.key_column_usage k
    join information_schema.referential_constraints rc on rc.constraint_name = k.constraint_name and rc.constraint_schema = k.constraint_schema
    join information_schema.constraint_column_usage u on u.constraint_name = rc.unique_constraint_name and u.constraint_schema = rc.unique_constraint_schema
   where k.table_schema = 'public' and k.table_name in ('company_subscriptions','apple_transactions')
     and u.table_name in ('app_users','users');
  r := r || format('No subscription table references a user|%s|n=%s', v_n = 0, v_n);


  -- ---------------------------------------------------------------------------
  -- Apple environments: Production vs Sandbox (TestFlight / App Review)
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SUBTEST QA','hvac','US','USD','America/New_York') returning id into v_ct;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SUBTEST Ordinary','hvac','US','USD','America/New_York') returning id into v_co;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SUBTEST QA Prod','hvac','US','USD','America/New_York') returning id into v_cp;
  insert into public.company_subscriptions (company_id) values (v_ct), (v_co), (v_cp);
  insert into public.apple_sandbox_companies (company_id, note) values (v_ct, 'suite'), (v_cp, 'suite');

  -- Production creates a real entitlement.
  v_out := public.apple_apply_transaction(v_cp,
    jsonb_build_object('environment','Production','transactionId','E-P1','originalTransactionId','E-OP','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_state from public.company_commercial_state(v_cp);
  r := r || format('ENV: a Production purchase creates a real entitlement|%s|out=%s env=%s', v_out = 'applied:active' and v_state.has_entitlement and v_state.tier_id = 'team' and v_state.apple_environment = 'Production', v_out, v_state.apple_environment);

  -- Sandbox on an allowlisted test company: a test entitlement, marked Sandbox.
  v_out := public.apple_apply_transaction(v_ct,
    jsonb_build_object('environment','Sandbox','transactionId','E-S1','originalTransactionId','E-OS','productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_state from public.company_commercial_state(v_ct);
  r := r || format('ENV: Sandbox on an approved test company gives a test entitlement only|%s|out=%s env=%s', v_out = 'applied:active' and v_state.has_entitlement and v_state.apple_environment = 'Sandbox', v_out, v_state.apple_environment);

  -- Sandbox on an ordinary company: recorded as a test transaction, no entitlement.
  v_out := public.apple_apply_transaction(v_co,
    jsonb_build_object('environment','Sandbox','transactionId','E-S2','originalTransactionId','E-OS2','productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  select * into v_state from public.company_commercial_state(v_co);
  r := r || format('ENV: Sandbox on an ordinary company does not change its entitlement|%s|out=%s state=%s store=%s', v_out = 'sandboxNotApplied' and not v_state.has_entitlement and v_state.entitlement_state = 'none' and v_state.billing_store = 'none', v_out, v_state.entitlement_state, v_state.billing_store);
  r := r || format('ENV: the ordinary company''s test purchase is kept as a test ledger row|%s|', exists(select 1 from public.apple_transactions where environment = 'Sandbox' and transaction_id = 'E-S2' and company_id = v_co));

  -- Sandbox on an ordinary company that holds a Production plan: untouched.
  v_out := public.apple_apply_transaction(v_c2,
    jsonb_build_object('environment','Sandbox','transactionId','E-S4','originalTransactionId','E-OS4','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 900000,'expiresDate',v_ms_now + 400*v_day,'signedDate',v_ms_now + 900000),
    jsonb_build_object('environment','Sandbox','originalTransactionId','E-OS4','autoRenewStatus',0,'signedDate',v_ms_now + 900000), 'app');
  select * into v_state from public.company_commercial_state(v_c2);
  r := r || format('ENV: Sandbox leaves an ordinary company''s Production plan untouched|%s|out=%s tier=%s env=%s orig=%s', v_out = 'sandboxNotApplied' and v_state.tier_id = 'starter' and v_state.apple_environment = 'Production' and v_state.apple_original_transaction_id = 'O2' and v_state.will_auto_renew, v_out, v_state.tier_id, v_state.apple_environment, v_state.apple_original_transaction_id);

  -- Sandbox can never replace Production, even on an allowlisted company.
  v_out := public.apple_apply_transaction(v_cp,
    jsonb_build_object('environment','Sandbox','transactionId','E-S3','originalTransactionId','E-OS3','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 400*v_day,'signedDate',v_ms_now + 1000), null, 'app');
  select * into v_state from public.company_commercial_state(v_cp);
  r := r || format('ENV: Sandbox cannot replace a Production entitlement (test company too)|%s|out=%s tier=%s env=%s', v_out = 'sandboxNotApplied' and v_state.tier_id = 'team' and v_state.apple_environment = 'Production' and v_state.apple_original_transaction_id = 'E-OP', v_out, v_state.tier_id, v_state.apple_environment);

  -- Sandbox renewal info can never be written onto the Production subscription.
  v_out := public.apple_apply_transaction(v_cp,
    jsonb_build_object('environment','Production','transactionId','E-P1','originalTransactionId','E-OP','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now),
    jsonb_build_object('environment','Sandbox','originalTransactionId','E-OP','autoRenewStatus',0,'signedDate',v_ms_now + 5000), 'notification');
  select * into v_state from public.company_commercial_state(v_cp);
  r := r || format('ENV: renewal info from the other environment is ignored|%s|out=%s renew=%s', v_state.will_auto_renew and v_state.entitlement_state = 'active', v_out, v_state.will_auto_renew);

  -- Production always takes over from a test subscription, even a shorter one.
  v_out := public.apple_apply_transaction(v_ct,
    jsonb_build_object('environment','Production','transactionId','E-P2','originalTransactionId','E-OP2','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 2000,'expiresDate',v_ms_now + 10*v_day,'signedDate',v_ms_now + 2000), null, 'app');
  select * into v_state from public.company_commercial_state(v_ct);
  r := r || format('ENV: Production takes precedence over a test subscription|%s|out=%s tier=%s env=%s', v_out = 'applied:active' and v_state.tier_id = 'starter' and v_state.apple_environment = 'Production', v_out, v_state.tier_id, v_state.apple_environment);
  v_out := public.apple_apply_transaction(v_ct,
    jsonb_build_object('environment','Sandbox','transactionId','E-S1b','originalTransactionId','E-OS','productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now + 3000,'expiresDate',v_ms_now + 60*v_day,'signedDate',v_ms_now + 3000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_ct);
  r := r || format('ENV: a later test renewal cannot take the plan back from Production|%s|out=%s tier=%s', v_out = 'sandboxNotApplied' and v_state.tier_id = 'starter' and v_state.apple_environment = 'Production', v_out, v_state.tier_id);

  -- Test and Production identities are separate: the same ids in each
  -- environment belong to different companies without colliding.
  v_out := public.apple_apply_transaction(v_co,
    jsonb_build_object('environment','Production','transactionId','SAME-1','originalTransactionId','SAME-O','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  begin
    v_s := public.apple_apply_transaction(v_cb,
      jsonb_build_object('environment','Sandbox','transactionId','SAME-1','originalTransactionId','SAME-O','productId','com.harboursouth.fieldservice.team.monthly',
        'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  exception when others then
    v_s := 'error ' || sqlstate;
  end;
  select count(*) into v_n from public.apple_transactions where transaction_id = 'SAME-1';
  r := r || format('ENV: test and Production purchase identities stay separate|%s|prod=%s test=%s rows=%s', v_out = 'applied:active' and v_s = 'sandboxNotApplied' and v_n = 2
    and exists(select 1 from public.apple_transactions where transaction_id='SAME-1' and environment='Production' and company_id=v_co)
    and exists(select 1 from public.apple_transactions where transaction_id='SAME-1' and environment='Sandbox' and company_id=v_cb), v_out, v_s, v_n);
  select * into v_state from public.company_commercial_state(v_co);
  r := r || format('ENV: the ordinary company is now entitled only through Production|%s|env=%s', v_state.has_entitlement and v_state.apple_environment = 'Production', v_state.apple_environment);

  -- Unknown and missing environments are refused without a trace.
  v_out := public.apple_apply_transaction(v_ct,
    jsonb_build_object('environment','Xcode','transactionId','X-1','originalTransactionId','X-O1','productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now + 4000,'expiresDate',v_ms_now + 60*v_day,'signedDate',v_ms_now + 4000), null, 'app');
  v_s := public.apple_apply_transaction(v_ct,
    jsonb_build_object('transactionId','X-2','originalTransactionId','X-O2','productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now + 4000,'expiresDate',v_ms_now + 60*v_day,'signedDate',v_ms_now + 4000), null, 'app');
  v_tok := public.apple_apply_transaction(v_ct,
    jsonb_build_object('environment','LocalTesting','transactionId','X-3','originalTransactionId','X-O3','productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now + 4000,'expiresDate',v_ms_now + 60*v_day,'signedDate',v_ms_now + 4000), null, 'app');
  select count(*) into v_n from public.apple_transactions where transaction_id in ('X-1','X-2','X-3');
  select * into v_state from public.company_commercial_state(v_ct);
  r := r || format('ENV: unknown or missing environments are rejected, nothing recorded|%s|xcode=%s missing=%s local=%s rows=%s tier=%s',
    v_out = 'unsupportedEnvironment' and v_s = 'unsupportedEnvironment' and v_tok = 'unsupportedEnvironment' and v_n = 0 and v_state.tier_id = 'starter',
    v_out, v_s, v_tok, v_n, v_state.tier_id);

  -- The allowlist cannot be read, joined or edited by app users.
  r := r || format('ENV: app users cannot read or edit the test-company allowlist|%s|',
    not has_table_privilege('authenticated', 'public.apple_sandbox_companies', 'select')
    and not has_table_privilege('authenticated', 'public.apple_sandbox_companies', 'insert')
    and not has_table_privilege('authenticated', 'public.apple_sandbox_companies', 'update')
    and not has_table_privilege('authenticated', 'public.apple_sandbox_companies', 'delete')
    and not has_table_privilege('anon', 'public.apple_sandbox_companies', 'select')
    and not exists(select 1 from pg_policies where schemaname = 'public' and tablename = 'apple_sandbox_companies')
    and not exists(select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.prosrc ilike '%insert into public.apple_sandbox_companies%'));

  -- ---------------------------------------------------------------------------
  -- Only the server writes entitlement
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner2::text, 'role', 'authenticated')::text, true);
  begin
    perform public.apple_apply_transaction(v_c2, jsonb_build_object('environment','Production','transactionId','X','originalTransactionId','X','productId','com.harboursouth.fieldservice.business.annual'));
    r := r || array['A signed-in user cannot write entitlement|false|accepted'];
  exception when others then
    r := r || format('A signed-in user cannot write entitlement|%s|%s', sqlstate in ('TD403','42501'), sqlstate);
  end;
  r := r || format('The authenticated role has no execute grant on apple_apply_transaction|%s|', not has_function_privilege('authenticated', 'public.apple_apply_transaction(uuid,jsonb,jsonb,text)', 'execute'));

  -- ---------------------------------------------------------------------------
  -- Seats
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update public.platform_settings set value = 'false'::jsonb where key = 'seat_limits_enforced';

  -- v_c2 is on Starter (1 user) and already has its owner.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner2::text, 'role', 'authenticated')::text, true);
  begin
    perform public.create_invitation('a@subtest.invalid', 'fieldWorker', 7);
    r := r || array['With the switch off, Starter may still invite (nobody blocked before purchasing exists)|true|'];
  exception when others then
    r := r || format('With the switch off, Starter may still invite (nobody blocked before purchasing exists)|false|%s', sqlerrm);
  end;
  delete from public.invitations where email = 'a@subtest.invalid';

  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  update public.platform_settings set value = 'true'::jsonb where key = 'seat_limits_enforced';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner2::text, 'role', 'authenticated')::text, true);

  begin
    perform public.create_invitation('b@subtest.invalid', 'fieldWorker', 7);
    r := r || array['Starter with 1 active user cannot invite a second|false|accepted'];
  exception when others then
    v_err := sqlerrm;
    r := r || format('Starter with 1 active user cannot invite a second|%s|%s', v_err ilike '%Starter plan includes up to 1 user%Team%', v_err);
  end;

  -- Team: 5 users total.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.apple_apply_transaction(v_c2,
    jsonb_build_object('environment','Production','transactionId','U9','originalTransactionId','O2','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 99000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 99000), null, 'app');
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner2::text, 'role', 'authenticated')::text, true);
  v_n := 0;
  for i in 1..5 loop
    begin
      perform public.create_invitation('t' || i || '@subtest.invalid', 'fieldWorker', 7);
      v_n := v_n + 1;
    exception when others then
      v_err := sqlerrm;
    end;
  end loop;
  r := r || format('Team allows exactly 4 invitations beside the owner (5 users)|%s|issued=%s last=%s', v_n = 4, v_n, coalesce(v_err,''));
  r := r || format('The fifth is refused with a Business suggestion|%s|%s', coalesce(v_err,'') ilike '%Team plan includes up to 5 users%Business%', coalesce(v_err,''));

  -- Accepting an invitation respects the limit too (joiner beyond the plan).
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  delete from public.invitations where company_id = v_c2;
  for i in 1..4 loop
    v_joiner := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
      values ('00000000-0000-0000-0000-000000000000', v_joiner, 'authenticated', 'authenticated', 'm' || i || '@subtest.invalid', 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false);
    insert into public.app_users (id, company_id, name, email, role, status) values (v_joiner, v_c2, 'M' || i, 'm' || i || '@subtest.invalid', 'fieldWorker', 'active');
  end loop;
  select count(*) into v_n from public.app_users where company_id = v_c2 and status = 'active';
  r := r || format('The server itself is not limited (fixture: 5 active on Team)|%s|n=%s', v_n = 5, v_n);

  v_joiner := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
    values ('00000000-0000-0000-0000-000000000000', v_joiner, 'authenticated', 'authenticated', 'late@subtest.invalid', 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false);
  v_tok := encode(extensions.gen_random_bytes(16), 'hex');
  insert into public.invitations (company_id, email, role, token, invited_by_user_id, expires_at)
    values (v_c2, 'late@subtest.invalid', 'fieldWorker', v_tok, v_owner2, now() + interval '7 days');
  perform set_config('request.jwt.claims', json_build_object('sub', v_joiner::text, 'role', 'authenticated')::text, true);
  begin
    perform public.accept_invitation(v_tok);
    r := r || array['A sixth person cannot join a full Team plan|false|accepted'];
  exception when others then
    r := r || format('A sixth person cannot join a full Team plan|%s|%s', sqlerrm ilike '%Team plan%', sqlerrm);
  end;

  -- Downgrade to Starter: nobody is suspended; adding is refused.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.apple_apply_transaction(v_c2,
    jsonb_build_object('environment','Production','transactionId','U10','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 199000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 199000), null, 'app');
  select count(*) into v_n from public.app_users where company_id = v_c2 and status = 'active';
  select * into v_state from public.company_commercial_state(v_c2);
  r := r || format('Downgrading never suspends anybody|%s|active=%s', v_n = 5 and not v_state.can_add_user, v_n);

  -- Reactivating a suspended person counts as adding.
  update public.app_users set status = 'suspended' where company_id = v_c2 and email = 'm4@subtest.invalid';
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner2::text, 'role', 'authenticated')::text, true);
  begin
    update public.app_users set status = 'active' where company_id = v_c2 and email = 'm4@subtest.invalid';
    get diagnostics v_n = row_count;
    r := r || format('Reactivating somebody beyond the plan is refused|false|updated=%s', v_n);
  exception when others then
    r := r || format('Reactivating somebody beyond the plan is refused|%s|%s', sqlerrm ilike '%plan%', sqlerrm);
  end;

  -- Business: 12 and 30 people, no cap.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  for i in 1..29 loop
    v_joiner := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
      values ('00000000-0000-0000-0000-000000000000', v_joiner, 'authenticated', 'authenticated', 'big' || i || '@subtest.invalid', 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false);
    insert into public.app_users (id, company_id, name, email, role, status) values (v_joiner, v_cb, 'B' || i, 'big' || i || '@subtest.invalid', 'fieldWorker', (case when i <= 11 then 'active' else 'suspended' end)::public.app_user_status);
  end loop;
  perform set_config('request.jwt.claims', json_build_object('sub', v_ownerb::text, 'role', 'authenticated')::text, true);
  begin
    update public.app_users set status = 'active' where company_id = v_cb and status = 'suspended';
    get diagnostics v_n = row_count;
    select count(*) into v_n from public.app_users where company_id = v_cb and status = 'active';
    r := r || format('Business grows past 10 to 12 and then 30 active people|%s|active=%s', v_n = 30, v_n);
  exception when others then
    r := r || format('Business grows past 10 to 12 and then 30 active people|false|%s', sqlerrm);
  end;
  begin
    perform public.create_invitation('more@subtest.invalid', 'fieldWorker', 7);
    r := r || array['Business can still invite with 30 active people|true|'];
  exception when others then
    r := r || format('Business can still invite with 30 active people|false|%s', sqlerrm);
  end;

  -- Removing people, including the Owner who bought the plan, leaves the
  -- company's subscription exactly as it was.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select * into v_state from public.company_commercial_state(v_cb);
  v_s := v_state.apple_original_transaction_id;
  v_joiner := gen_random_uuid();
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
    values ('00000000-0000-0000-0000-000000000000', v_joiner, 'authenticated', 'authenticated', 'newowner@subtest.invalid', 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false);
  insert into public.app_users (id, company_id, name, email, role, status) values (v_joiner, v_cb, 'New Owner', 'newowner@subtest.invalid', 'owner', 'active');
  delete from public.invitations where company_id = v_cb;
  delete from public.app_users where company_id = v_cb and email like 'big%' and email <= 'big2@';
  delete from public.app_users where id = v_ownerb;
  update public.app_users set status = 'suspended' where company_id = v_cb and email like 'big%';
  select * into v_state from public.company_commercial_state(v_cb);
  r := r || format('Deleting the purchasing Owner and suspending staff keeps the company plan|%s|entitled=%s tier=%s orig=%s',
    v_state.has_entitlement and v_state.tier_id = 'business' and v_state.apple_original_transaction_id = v_s,
    v_state.has_entitlement, v_state.tier_id, v_state.apple_original_transaction_id);
  perform set_config('request.jwt.claims', json_build_object('sub', v_joiner::text, 'role', 'authenticated')::text, true);
  select * into v_state from public.company_commercial_state(null);
  r := r || format('The new Owner sees the same company plan|%s|tier=%s', v_state.has_entitlement and v_state.tier_id = 'business', v_state.tier_id);


  -- ---------------------------------------------------------------------------
  -- Workspace lock: the minimal member read
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.em, 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false
  from (values (v_ownerl,'ownerl@subtest.invalid'), (v_workerl,'workerl@subtest.invalid'), (v_ownerd,'ownerd@subtest.invalid')) u(id, em);
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SUBTEST Lock','hvac','US','USD','America/New_York') returning id into v_cl;
  insert into public.company_subscriptions (company_id) values (v_cl);
  insert into public.app_users (id, company_id, name, email, role) values
    (v_ownerl, v_cl, 'OwnerL', 'ownerl@subtest.invalid', 'owner'),
    (v_workerl, v_cl, 'WorkerL', 'workerl@subtest.invalid', 'fieldWorker');

  perform set_config('request.jwt.claims', json_build_object('sub', v_workerl::text, 'role', 'authenticated')::text, true);
  select * into v_chk from public.company_workspace_access();
  r := r || format('LOCK: a company with no plan is locked|%s|has=%s state=%s', not v_chk.has_active_subscription and v_chk.subscription_state = 'none', v_chk.has_active_subscription, v_chk.subscription_state);

  foreach v_s in array array['expired','revoked','billingRetry','trial','active','offer','gracePeriod','cancelling'] loop
    perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
    update public.company_subscriptions set
      store = 'apple',
      apple_expires_at = case v_s when 'expired' then now() - interval '1 day' when 'billingRetry' then now() - interval '1 day'
                                  when 'gracePeriod' then now() - interval '1 day' when 'cancelling' then now() + interval '5 days'
                                  else now() + interval '20 days' end,
      apple_revoked_at = case when v_s = 'revoked' then now() end,
      apple_auto_renew = v_s not in ('expired','cancelling'),
      apple_grace_period_expires_at = case when v_s = 'gracePeriod' then now() + interval '5 days' end,
      apple_in_billing_retry = v_s in ('billingRetry','gracePeriod'),
      apple_is_free_offer = v_s in ('trial','offer'),
      apple_offer_type = case v_s when 'trial' then 1 when 'offer' then 3 end,
      tier_id = 'team'
    where company_id = v_cl;
    perform set_config('request.jwt.claims', json_build_object('sub', v_workerl::text, 'role', 'authenticated')::text, true);
    select * into v_chk from public.company_workspace_access();
    r := r || format('LOCK: %s company is %s|%s|has=%s state=%s', v_s,
      case when v_s in ('expired','revoked','billingRetry') then 'locked' else 'unlocked' end,
      v_chk.subscription_state = v_s and v_chk.has_active_subscription = (v_s not in ('expired','revoked','billingRetry')),
      v_chk.has_active_subscription, v_chk.subscription_state);
  end loop;

  r := r || format('LOCK: members read the workspace position only (no billing) and cannot name a company|%s|%s',
    pg_get_function_result('public.company_workspace_access()'::regprocedure) = 'TABLE(has_active_subscription boolean, subscription_state text, plan_name text, user_limit integer, active_users integer, seats_over_limit boolean, users_to_deactivate integer)'
    and (select pronargs from pg_proc where oid = 'public.company_workspace_access()'::regprocedure) = 0
    and has_function_privilege('authenticated', 'public.company_workspace_access()', 'execute')
    and not has_function_privilege('anon', 'public.company_workspace_access()', 'execute'),
    pg_get_function_result('public.company_workspace_access()'::regprocedure));
  begin
    select * into v_state from public.company_commercial_state(null);
    r := r || array['LOCK: a field worker still cannot read billing details|false|accepted'];
  exception when others then
    r := r || format('LOCK: a field worker still cannot read billing details|%s|%s', sqlstate = 'TD403', sqlstate);
  end;

  -- ---------------------------------------------------------------------------
  -- Downgrades: refused while active users exceed the target plan
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
    values ('SUBTEST Downgrade','hvac','US','USD','America/New_York') returning id into v_cd;
  insert into public.company_subscriptions (company_id) values (v_cd);
  insert into public.app_users (id, company_id, name, email, role) values (v_ownerd, v_cd, 'OwnerD', 'ownerd@subtest.invalid', 'owner');
  for i in 1..9 loop
    v_workerd := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
      values ('00000000-0000-0000-0000-000000000000', v_workerd, 'authenticated', 'authenticated', 'dg' || i || '@subtest.invalid', 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false);
    insert into public.app_users (id, company_id, name, email, role, status) values (v_workerd, v_cd, 'DG' || i, 'dg' || i || '@subtest.invalid', 'fieldWorker', 'active');
  end loop;
  perform public.apple_apply_transaction(v_cd,
    jsonb_build_object('environment','Production','transactionId','D-1','originalTransactionId','D-O','productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');

  perform set_config('request.jwt.claims', json_build_object('sub', v_ownerd::text, 'role', 'authenticated')::text, true);
  select * into v_chk from public.subscription_plan_change_check('team');
  r := r || format('SEATS: Business (10 active) -> Team is never refused; it warns 5 must be deactivated|%s|allowed=%s remove=%s msg=%s', v_chk.allowed and v_chk.users_to_deactivate = 5 and v_chk.active_users = 10 and v_chk.message ilike '%deactivate 5 people%', v_chk.allowed, v_chk.users_to_deactivate, v_chk.message);
  select * into v_chk from public.subscription_plan_change_check('starter');
  r := r || format('SEATS: Business (10 active) -> Starter is never refused; it warns 9 must be deactivated|%s|allowed=%s remove=%s', v_chk.allowed and v_chk.users_to_deactivate = 9, v_chk.allowed, v_chk.users_to_deactivate);
  select * into v_chk from public.subscription_plan_change_check('business');
  r := r || format('SEATS: Business has no hard-coded cap in the plan check|%s|limit=%s', v_chk.allowed and v_chk.user_limit is null, v_chk.user_limit);
  select count(*) into v_n from public.app_users where company_id = v_cd and status = 'active';
  r := r || format('SEATS: the plan-change check suspends nobody|%s|active=%s', v_n = 10, v_n);

  -- The owner chooses who to deactivate.
  update public.app_users set status = 'suspended' where company_id = v_cd and email in ('dg1@subtest.invalid','dg2@subtest.invalid','dg3@subtest.invalid','dg4@subtest.invalid','dg5@subtest.invalid');
  select * into v_chk from public.subscription_plan_change_check('team');
  r := r || format('SEATS: Team needs nobody deactivated once the owner is down to 5 active|%s|allowed=%s active=%s', v_chk.allowed and v_chk.active_users = 5 and v_chk.users_to_deactivate = 0 and v_chk.message is null, v_chk.allowed, v_chk.active_users);
  select * into v_chk from public.subscription_plan_change_check('starter');
  r := r || format('SEATS: Starter still needs 4 more deactivated|%s|remove=%s', v_chk.allowed and v_chk.users_to_deactivate = 4, v_chk.users_to_deactivate);
  update public.app_users set status = 'suspended' where company_id = v_cd and email in ('dg6@subtest.invalid','dg7@subtest.invalid','dg8@subtest.invalid','dg9@subtest.invalid');
  select * into v_chk from public.subscription_plan_change_check('starter');
  r := r || format('SEATS: Starter needs nobody deactivated once only the owner is active|%s|allowed=%s', v_chk.allowed and v_chk.users_to_deactivate = 0, v_chk.allowed);
  select count(*) into v_n from public.app_users where company_id = v_cd;
  r := r || format('SEATS: no user record is deleted by the downgrade process|%s|rows=%s', v_n = 10 and (select count(*) from public.app_users where company_id = v_cd and status = 'suspended') = 9, v_n);

  -- After the move to Starter, a deactivated person stays recoverable but
  -- cannot be reactivated beyond the plan.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.apple_apply_transaction(v_cd,
    jsonb_build_object('environment','Production','transactionId','D-2','originalTransactionId','D-O','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 1000), null, 'notification');
  perform set_config('request.jwt.claims', json_build_object('sub', v_ownerd::text, 'role', 'authenticated')::text, true);
  begin
    update public.app_users set status = 'active' where company_id = v_cd and email = 'dg1@subtest.invalid';
    r := r || array['SEATS: on Starter, reactivating a second person is refused|false|accepted'];
  exception when others then
    r := r || format('SEATS: on Starter, reactivating a second person is refused|%s|%s', sqlerrm ilike '%Starter plan%', sqlerrm);
  end;
  begin
    perform public.create_invitation('dgnew@subtest.invalid', 'fieldWorker', 7);
    r := r || array['SEATS: on Starter, adding a second person is refused|false|accepted'];
  exception when others then
    r := r || format('SEATS: on Starter, adding a second person is refused|%s|%s', sqlerrm ilike '%Starter plan%', sqlerrm);
  end;

  -- Upgrading again makes the deactivated people recoverable.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.apple_apply_transaction(v_cd,
    jsonb_build_object('environment','Production','transactionId','D-3','originalTransactionId','D-O','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 2000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 2000), null, 'notification');
  perform set_config('request.jwt.claims', json_build_object('sub', v_ownerd::text, 'role', 'authenticated')::text, true);
  begin
    update public.app_users set status = 'active' where company_id = v_cd and email in ('dg1@subtest.invalid','dg2@subtest.invalid','dg3@subtest.invalid','dg4@subtest.invalid');
    select count(*) into v_n from public.app_users where company_id = v_cd and status = 'active';
    r := r || format('SEATS: after upgrading to Team, deactivated people can be reactivated up to 5|%s|active=%s', v_n = 5, v_n);
  exception when others then
    r := r || format('SEATS: after upgrading to Team, deactivated people can be reactivated up to 5|false|%s', sqlerrm);
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', v_workerl::text, 'role', 'authenticated')::text, true);
  begin
    perform public.subscription_plan_change_check('starter');
    r := r || array['SEATS: only the owner can run the plan-change check|false|accepted'];
  exception when others then
    r := r || format('SEATS: only the owner can run the plan-change check|%s|%s', sqlstate = 'TD403', sqlstate);
  end;


  -- ===========================================================================
  -- APPLE DOWNGRADES: pending (scheduled for renewal) and applied
  -- ===========================================================================
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.em, 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false
  from (values (v_ownere,'ownere@subtest.invalid'), (v_ownerf,'ownerf@subtest.invalid'), (v_ownerg,'ownerg@subtest.invalid')) u(id, em);
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier) values ('SUBTEST Pending','hvac','US','USD','America/New_York') returning id into v_ce;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier) values ('SUBTEST Pending4','hvac','US','USD','America/New_York') returning id into v_cf;
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier) values ('SUBTEST ToStarter','hvac','US','USD','America/New_York') returning id into v_cg;
  insert into public.company_subscriptions (company_id) values (v_ce), (v_cf), (v_cg);
  insert into public.app_users (id, company_id, name, email, role) values
    (v_ownere, v_ce, 'OwnerE', 'ownere@subtest.invalid', 'owner'),
    (v_ownerf, v_cf, 'OwnerF', 'ownerf@subtest.invalid', 'owner'),
    (v_ownerg, v_cg, 'OwnerG', 'ownerg@subtest.invalid', 'owner');
  -- v_ce: owner + 9 active + 1 suspended. v_cf: owner + 3 active + 3 suspended. v_cg: owner + 9 active.
  for i in 1..10 loop
    v_workere := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
      values ('00000000-0000-0000-0000-000000000000', v_workere, 'authenticated', 'authenticated', 'pe' || i || '@subtest.invalid', 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false);
    insert into public.app_users (id, company_id, name, email, role, status) values (v_workere, v_ce, 'PE' || i, 'pe' || i || '@subtest.invalid', 'fieldWorker', (case when i <= 9 then 'active' else 'suspended' end)::public.app_user_status);
  end loop;
  for i in 1..6 loop
    v_workere := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
      values ('00000000-0000-0000-0000-000000000000', v_workere, 'authenticated', 'authenticated', 'pf' || i || '@subtest.invalid', 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false);
    insert into public.app_users (id, company_id, name, email, role, status) values (v_workere, v_cf, 'PF' || i, 'pf' || i || '@subtest.invalid', 'fieldWorker', (case when i <= 3 then 'active' else 'suspended' end)::public.app_user_status);
  end loop;
  for i in 1..9 loop
    v_workere := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
      values ('00000000-0000-0000-0000-000000000000', v_workere, 'authenticated', 'authenticated', 'pg' || i || '@subtest.invalid', 'x', now(), now(), now(), '{}'::jsonb, '{}'::jsonb, false);
    insert into public.app_users (id, company_id, name, email, role, status) values (v_workere, v_cg, 'PG' || i, 'pg' || i || '@subtest.invalid', 'fieldWorker', 'active');
  end loop;

  -- Business, then Apple schedules Business -> Team for the next renewal.
  foreach v_cx in array array[v_ce, v_cf] loop
    perform public.apple_apply_transaction(v_cx,
      jsonb_build_object('environment','Production','transactionId','PD-1-' || v_cx::text,'originalTransactionId','PD-O-' || v_cx::text,'productId','com.harboursouth.fieldservice.business.monthly',
        'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now),
      jsonb_build_object('originalTransactionId','PD-O-' || v_cx::text,'autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.business.monthly','signedDate',v_ms_now), 'app');
    v_out := public.apple_apply_transaction(v_cx,
      jsonb_build_object('environment','Production','transactionId','PD-1-' || v_cx::text,'originalTransactionId','PD-O-' || v_cx::text,'productId','com.harboursouth.fieldservice.business.monthly',
        'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 1000),
      jsonb_build_object('originalTransactionId','PD-O-' || v_cx::text,'autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.team.monthly','signedDate',v_ms_now + 1000), 'notification');
  end loop;
  v_cx := null;
  select * into v_state from public.company_commercial_state(v_ce);
  r := r || format('PENDING: a scheduled Business -> Team keeps Business (no early downgrade)|%s|out=%s tier=%s next=%s entitled=%s', v_out = 'applied:active' and v_state.tier_id = 'business' and v_state.renews_to_tier_id = 'team' and v_state.has_entitlement and v_state.pending_user_limit = 5 and not v_state.seats_over_limit, v_out, v_state.tier_id, v_state.renews_to_tier_id, v_state.has_entitlement);
  r := r || format('PENDING: 10 active on Business with Team pending cannot add more|%s|can_add=%s', not v_state.can_add_user and v_state.active_users = 10, v_state.can_add_user);

  perform set_config('request.jwt.claims', json_build_object('sub', v_ownere::text, 'role', 'authenticated')::text, true);
  select * into v_chk from public.company_workspace_access();
  r := r || format('PENDING: existing users keep normal Business access (workspace open, no seat resolution)|%s|has=%s over=%s', v_chk.has_active_subscription and not v_chk.seats_over_limit and v_chk.user_limit is null, v_chk.has_active_subscription, v_chk.seats_over_limit);
  begin
    perform public.create_invitation('pe-new@subtest.invalid', 'fieldWorker', 7);
    r := r || array['PENDING: inviting an 11th person is blocked|false|accepted'];
  exception when others then
    r := r || format('PENDING: inviting an 11th person is blocked|%s|%s', sqlerrm ilike '%changes to Team at renewal%', sqlerrm);
  end;
  begin
    update public.app_users set status = 'active' where company_id = v_ce and email = 'pe10@subtest.invalid';
    r := r || array['PENDING: reactivating an 11th person is blocked|false|accepted'];
  exception when others then
    r := r || format('PENDING: reactivating an 11th person is blocked|%s|%s', sqlerrm ilike '%changes to Team at renewal%', sqlerrm);
  end;
  begin
    update public.app_users set status = 'suspended' where company_id = v_ce and email = 'pe9@subtest.invalid';
    select count(*) into v_n from public.app_users where company_id = v_ce and status = 'active';
    r := r || format('PENDING: voluntary deactivation is still allowed|%s|active=%s', v_n = 9, v_n);
  exception when others then
    r := r || format('PENDING: voluntary deactivation is still allowed|false|%s', sqlerrm);
  end;

  -- Business with Team pending and 4 active: a 5th may be added, a 6th may not.
  perform set_config('request.jwt.claims', json_build_object('sub', v_ownerf::text, 'role', 'authenticated')::text, true);
  begin
    update public.app_users set status = 'active' where company_id = v_cf and email = 'pf4@subtest.invalid';
    select count(*) into v_n from public.app_users where company_id = v_cf and status = 'active';
    r := r || format('PENDING: with 4 active, reactivating a 5th is allowed|%s|active=%s', v_n = 5, v_n);
  exception when others then
    r := r || format('PENDING: with 4 active, reactivating a 5th is allowed|false|%s', sqlerrm);
  end;
  begin
    update public.app_users set status = 'active' where company_id = v_cf and email = 'pf5@subtest.invalid';
    r := r || array['PENDING: with 5 active, reactivating a 6th is blocked|false|accepted'];
  exception when others then
    r := r || format('PENDING: with 5 active, reactivating a 6th is blocked|%s|%s', sqlerrm ilike '%Team%', sqlerrm);
  end;
  begin
    perform public.create_invitation('pf-new@subtest.invalid', 'fieldWorker', 7);
    r := r || array['PENDING: with 5 active, inviting a 6th is blocked|false|accepted'];
  exception when others then
    r := r || format('PENDING: with 5 active, inviting a 6th is blocked|%s|%s', sqlerrm ilike '%Team%', sqlerrm);
  end;
  update public.app_users set status = 'suspended' where company_id = v_cf and email = 'pf4@subtest.invalid';
  begin
    perform public.create_invitation('pf-new@subtest.invalid', 'fieldWorker', 7);
    r := r || array['PENDING: with 4 active, inviting a 5th is allowed|true|'];
  exception when others then
    r := r || format('PENDING: with 4 active, inviting a 5th is allowed|false|%s', sqlerrm);
  end;

  -- Apple applies the downgrade at renewal: Team is now the plan, 9 active.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select count(*) into v_before from public.app_users where company_id = v_ce;
  v_out := public.apple_apply_transaction(v_ce,
    jsonb_build_object('environment','Production','transactionId','PD-2','originalTransactionId','PD-O-' || v_ce::text,'productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 5000,'expiresDate',v_ms_now + 60*v_day,'signedDate',v_ms_now + 5000),
    jsonb_build_object('originalTransactionId','PD-O-' || v_ce::text,'autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.team.monthly','signedDate',v_ms_now + 5000), 'notification');
  select * into v_state from public.company_commercial_state(v_ce);
  r := r || format('APPLIED: Harbour South recognises the lower Apple plan (Team)|%s|out=%s tier=%s', v_out = 'applied:active' and v_state.tier_id = 'team' and v_state.has_entitlement and v_state.pending_user_limit is null, v_out, v_state.tier_id);
  r := r || format('APPLIED: 9 active on Team (5) enters seat resolution: deactivate 4|%s|over=%s remove=%s', v_state.seats_over_limit and v_state.users_to_deactivate = 4 and not v_state.can_add_user, v_state.seats_over_limit, v_state.users_to_deactivate);
  select count(*) into v_n from public.app_users where company_id = v_ce and status = 'active';
  r := r || format('APPLIED: nobody is suspended automatically|%s|active=%s', v_n = 9, v_n);
  select count(*) into v_n from public.app_users where company_id = v_ce;
  r := r || format('APPLIED: no user record is deleted|%s|rows=%s before=%s', v_n = v_before, v_n, v_before);

  perform set_config('request.jwt.claims', json_build_object('sub', (select id from public.app_users where company_id = v_ce and email = 'pe1@subtest.invalid')::text, 'role', 'authenticated')::text, true);
  select * into v_chk from public.company_workspace_access();
  r := r || format('APPLIED: members see seat resolution (still subscribed, over the plan)|%s|has=%s over=%s limit=%s active=%s remove=%s plan=%s', v_chk.has_active_subscription and v_chk.seats_over_limit and v_chk.user_limit = 5 and v_chk.active_users = 9 and v_chk.users_to_deactivate = 4 and v_chk.plan_name = 'Team', v_chk.has_active_subscription, v_chk.seats_over_limit, v_chk.user_limit, v_chk.active_users, v_chk.users_to_deactivate, v_chk.plan_name);

  perform set_config('request.jwt.claims', json_build_object('sub', v_ownere::text, 'role', 'authenticated')::text, true);
  begin
    perform public.create_invitation('pe-new2@subtest.invalid', 'fieldWorker', 7);
    r := r || array['APPLIED: an over-limit company cannot invite|false|accepted'];
  exception when others then
    r := r || format('APPLIED: an over-limit company cannot invite|%s|%s', sqlerrm ilike '%Team plan%', sqlerrm);
  end;
  begin
    update public.app_users set status = 'active' where company_id = v_ce and email = 'pe10@subtest.invalid';
    r := r || array['APPLIED: an over-limit company cannot reactivate|false|accepted'];
  exception when others then
    r := r || format('APPLIED: an over-limit company cannot reactivate|%s|%s', sqlerrm ilike '%Team plan%', sqlerrm);
  end;

  -- The owner chooses who to deactivate.
  update public.app_users set status = 'suspended' where company_id = v_ce and email in ('pe5@subtest.invalid','pe6@subtest.invalid','pe7@subtest.invalid');
  select * into v_chk from public.company_workspace_access();
  r := r || format('RESOLUTION: still over by one after deactivating 3|%s|over=%s remove=%s', v_chk.seats_over_limit and v_chk.users_to_deactivate = 1, v_chk.seats_over_limit, v_chk.users_to_deactivate);
  update public.app_users set status = 'suspended' where company_id = v_ce and email = 'pe8@subtest.invalid';
  select * into v_chk from public.company_workspace_access();
  r := r || format('RESOLUTION: within the plan, normal workspace access resumes|%s|has=%s over=%s active=%s', v_chk.has_active_subscription and not v_chk.seats_over_limit and v_chk.active_users = 5 and v_chk.users_to_deactivate = 0, v_chk.has_active_subscription, v_chk.seats_over_limit, v_chk.active_users);
  begin
    update public.app_users set status = 'active' where company_id = v_ce and email = 'pe8@subtest.invalid';
    r := r || array['RESOLUTION: at the limit, reactivating another is refused|false|accepted'];
  exception when others then
    r := r || format('RESOLUTION: at the limit, reactivating another is refused|%s|%s', sqlerrm ilike '%Team plan%', sqlerrm);
  end;
  update public.app_users set status = 'suspended' where company_id = v_ce and email = 'pe4@subtest.invalid';
  begin
    update public.app_users set status = 'active' where company_id = v_ce and email = 'pe8@subtest.invalid';
    select count(*) into v_n from public.app_users where company_id = v_ce and status = 'active';
    r := r || format('RESOLUTION: reactivation after resolution works within the plan|%s|active=%s', v_n = 5, v_n);
  exception when others then
    r := r || format('RESOLUTION: reactivation after resolution works within the plan|false|%s', sqlerrm);
  end;

  -- Team -> Starter applied with 5 active: 4 to deactivate.
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  perform public.apple_apply_transaction(v_ce,
    jsonb_build_object('environment','Production','transactionId','PD-3','originalTransactionId','PD-O-' || v_ce::text,'productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 6000,'expiresDate',v_ms_now + 90*v_day,'signedDate',v_ms_now + 6000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_ce);
  r := r || format('APPLIED: Team -> Starter with 5 active means deactivate 4|%s|tier=%s remove=%s', v_state.tier_id = 'starter' and v_state.seats_over_limit and v_state.users_to_deactivate = 4, v_state.tier_id, v_state.users_to_deactivate);

  -- Upgrade: Starter -> Business ends seat resolution; nobody removed.
  perform public.apple_apply_transaction(v_ce,
    jsonb_build_object('environment','Production','transactionId','PD-4','originalTransactionId','PD-O-' || v_ce::text,'productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now + 7000,'expiresDate',v_ms_now + 90*v_day,'signedDate',v_ms_now + 7000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_ce);
  r := r || format('UPGRADE: Starter -> Business applies at once and seats use the new plan|%s|tier=%s over=%s limit=%s', v_state.tier_id = 'business' and not v_state.seats_over_limit and v_state.plan_user_limit is null and v_state.can_add_user, v_state.tier_id, v_state.seats_over_limit, v_state.plan_user_limit);
  select count(*) into v_n from public.app_users where company_id = v_ce;
  r := r || format('UPGRADE: every user record is still there|%s|rows=%s', v_n = v_before, v_n);

  -- Crossgrade: Business monthly -> Business annual.
  perform public.apple_apply_transaction(v_ce,
    jsonb_build_object('environment','Production','transactionId','PD-5','originalTransactionId','PD-O-' || v_ce::text,'productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 8000,'expiresDate',v_ms_now + 400*v_day,'signedDate',v_ms_now + 8000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_ce);
  r := r || format('CROSSGRADE: Business monthly -> annual keeps the plan, changes the period|%s|tier=%s period=%s', v_state.tier_id = 'business' and v_state.billing_period = 'annual' and v_state.plan_price_cents = 66999, v_state.tier_id, v_state.billing_period);

  -- Out-of-order renewal info: an older cancellation cannot overwrite newer state.
  perform public.apple_apply_transaction(v_ce,
    jsonb_build_object('environment','Production','transactionId','PD-5','originalTransactionId','PD-O-' || v_ce::text,'productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 8000,'expiresDate',v_ms_now + 400*v_day,'signedDate',v_ms_now + 9000),
    jsonb_build_object('originalTransactionId','PD-O-' || v_ce::text,'autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.business.annual','signedDate',v_ms_now + 9000), 'notification');
  v_out := public.apple_apply_transaction(v_ce,
    jsonb_build_object('environment','Production','transactionId','PD-1-' || v_ce::text,'originalTransactionId','PD-O-' || v_ce::text,'productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now - v_day,'signedDate',v_ms_now + 100),
    jsonb_build_object('originalTransactionId','PD-O-' || v_ce::text,'autoRenewStatus',0,'expirationIntent',1,'signedDate',v_ms_now + 100), 'notification');
  select * into v_state from public.company_commercial_state(v_ce);
  r := r || format('ORDER: an old cancellation/expiry event cannot overwrite a newer active plan|%s|out=%s state=%s renew=%s', v_out = 'stale' and v_state.entitlement_state = 'active' and v_state.will_auto_renew and v_state.billing_period = 'annual', v_out, v_state.entitlement_state, v_state.will_auto_renew);

  -- Business -> Starter applied with 10 active: 9 to deactivate.
  perform public.apple_apply_transaction(v_cg,
    jsonb_build_object('environment','Production','transactionId','PG-1','originalTransactionId','PG-O','productId','com.harboursouth.fieldservice.business.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now), null, 'app');
  perform public.apple_apply_transaction(v_cg,
    jsonb_build_object('environment','Production','transactionId','PG-2','originalTransactionId','PG-O','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 60*v_day,'signedDate',v_ms_now + 1000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_cg);
  select count(*) into v_n from public.app_users where company_id = v_cg and status = 'active';
  r := r || format('APPLIED: Business -> Starter with 10 active means deactivate 9, nobody suspended|%s|tier=%s remove=%s active=%s', v_state.tier_id = 'starter' and v_state.seats_over_limit and v_state.users_to_deactivate = 9 and v_n = 10, v_state.tier_id, v_state.users_to_deactivate, v_n);

  -- Grace period is full service; no local grace invented.
  update public.company_subscriptions set apple_expires_at = now() - interval '1 hour', apple_grace_period_expires_at = now() + interval '3 days', apple_in_billing_retry = true where company_id = v_cg;
  select * into v_state from public.company_commercial_state(v_cg);
  r := r || format('GRACE: Apple billing grace period keeps full entitlement|%s|state=%s', v_state.entitlement_state = 'gracePeriod' and v_state.has_entitlement, v_state.entitlement_state);
  update public.company_subscriptions set apple_grace_period_expires_at = now() - interval '1 minute' where company_id = v_cg;
  select * into v_state from public.company_commercial_state(v_cg);
  r := r || format('GRACE: when Apple''s grace ends in billing retry, service stops (no Harbour South grace)|%s|state=%s', v_state.entitlement_state = 'billingRetry' and not v_state.has_entitlement and not v_state.seats_over_limit, v_state.entitlement_state);

  -- Duplicate Apple notification ids are claimed once only.
  insert into public.apple_notifications (notification_uuid, notification_type) values ('DUP-1', 'DID_RENEW');
  begin
    insert into public.apple_notifications (notification_uuid, notification_type) values ('DUP-1', 'DID_RENEW');
    r := r || array['NOTIFY: a duplicate notification id cannot be processed twice|false|accepted'];
  exception when unique_violation then
    r := r || array['NOTIFY: a duplicate notification id cannot be processed twice|true|23505'];
  end;

  -- ===========================================================================
  -- ACCOUNT DELETION
  -- ===========================================================================
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, created_at, updated_at, raw_app_meta_data, raw_user_meta_data, is_super_admin)
  select '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.em, 'x', now(), now(), now(), '{"provider":"email"}'::jsonb, '{"name":"x"}'::jsonb, false
  from (values (v_ox1,'ox1@subtest.invalid'), (v_ox2,'ox2@subtest.invalid'), (v_wx,'wx@subtest.invalid')) u(id, em);
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier) values ('SUBTEST Delete','hvac','US','USD','America/New_York') returning id into v_cx;
  insert into public.company_subscriptions (company_id) values (v_cx);
  insert into public.app_users (id, company_id, name, email, phone, role) values
    (v_ox1, v_cx, 'OX1', 'ox1@subtest.invalid', '555', 'owner'),
    (v_ox2, v_cx, 'OX2', 'ox2@subtest.invalid', '555', 'owner'),
    (v_wx,  v_cx, 'WX',  'wx@subtest.invalid',  '555', 'fieldWorker');
  insert into public.customers (company_id, name) values (v_cx, 'SUBTEST Delete Customer') returning id into v_cust_x;
  insert into public.stripe_connect_accounts (company_id, stripe_account_id, charges_enabled) values (v_cx, 'acct_subtest_delete', true);
  insert into auth.sessions (id, user_id) values (gen_random_uuid(), v_wx), (gen_random_uuid(), v_ox1);
  insert into auth.refresh_tokens (token, user_id, revoked) values ('rt-wx-subtest', v_wx::text, false), ('rt-ox1-subtest', v_ox1::text, false);

  r := r || format('DELETE: only signed-in users can delete an account|%s|', has_function_privilege('authenticated', 'public.delete_my_account(boolean)', 'execute') and not has_function_privilege('anon', 'public.delete_my_account(boolean)', 'execute'));

  -- Non-sole-owner: a field worker.
  perform set_config('request.jwt.claims', json_build_object('sub', v_wx::text, 'role', 'authenticated')::text, true);
  select * into v_chk from public.account_deletion_context();
  r := r || format('DELETE: a staff member is not the sole owner|%s|sole=%s others=%s', not v_chk.is_sole_owner and not v_chk.is_owner and v_chk.other_active_members = 2, v_chk.is_sole_owner, v_chk.other_active_members);
  v_out := public.delete_my_account(false);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  r := r || format('DELETE: staff deletion deletes only that account|%s|out=%s', v_out = 'accountDeleted', v_out);
  r := r || format('DELETE: the membership is anonymised and deactivated, not removed|%s|', exists(select 1 from public.app_users where id = v_wx and status = 'suspended' and name = 'Deleted user' and email like 'deleted-%@deleted.invalid' and phone = ''));
  r := r || format('DELETE: the sign-in is anonymised and banned|%s|', exists(select 1 from auth.users where id = v_wx and email like 'deleted-%@deleted.invalid' and banned_until > now() + interval '100 years' and deleted_at is not null and encrypted_password = ''));
  r := r || format('DELETE: every session and refresh token of the deleted user is gone|%s|', not exists(select 1 from auth.sessions where user_id = v_wx) and not exists(select 1 from auth.refresh_tokens where user_id = v_wx::text));
  r := r || format('DELETE: other people''s sessions are untouched|%s|', exists(select 1 from auth.sessions where user_id = v_ox1) and exists(select 1 from auth.refresh_tokens where user_id = v_ox1::text));
  r := r || format('DELETE: the company, its owners and its records are preserved|%s|', exists(select 1 from public.companies where id = v_cx and closed_at is null)
    and (select count(*) from public.app_users where company_id = v_cx and status = 'active') = 2
    and exists(select 1 from public.customers where id = v_cust_x)
    and exists(select 1 from public.stripe_connect_accounts where company_id = v_cx and stripe_account_id = 'acct_subtest_delete'));
  perform set_config('request.jwt.claims', json_build_object('sub', v_wx::text, 'role', 'authenticated')::text, true);
  r := r || format('DELETE: a leftover access token of the deleted user reaches no company|%s|', public.current_company_id() is null and not public.has_perm('jobsReadAssignedOnly'::app_permission));
  begin
    perform public.company_workspace_access();
    r := r || array['DELETE: the deleted user cannot open the workspace|false|accepted'];
  exception when others then
    r := r || format('DELETE: the deleted user cannot open the workspace|%s|%s', sqlstate = 'TD404', sqlstate);
  end;

  -- Non-sole owner (another active Owner exists).
  perform set_config('request.jwt.claims', json_build_object('sub', v_ox2::text, 'role', 'authenticated')::text, true);
  select * into v_chk from public.account_deletion_context();
  v_ok := v_chk.is_owner and not v_chk.is_sole_owner;
  v_out := public.delete_my_account(false);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  r := r || format('DELETE: an owner with a co-owner deletes their account; the company carries on|%s|out=%s', v_ok and v_out = 'accountDeleted'
    and exists(select 1 from public.app_users where id = v_ox1 and status = 'active' and role = 'owner')
    and exists(select 1 from public.companies where id = v_cx and closed_at is null), v_out);

  -- The last-Owner rule still holds outside a closure (marker alone is useless).
  perform set_config('request.jwt.claims', json_build_object('sub', v_ox1::text, 'role', 'authenticated')::text, true);
  perform set_config('harbour.closing_company', v_cx::text, true);
  begin
    update public.app_users set status = 'suspended' where id = v_ox1;
    r := r || array['DELETE: the last active Owner still cannot be suspended outside a closure|false|accepted'];
  exception when others then
    r := r || format('DELETE: the last active Owner still cannot be suspended outside a closure|%s|%s', sqlerrm ilike '%at least one active Owner%', sqlerrm);
  end;
  perform set_config('harbour.closing_company', '', true);

  -- Sole owner: refused without explicit closure.
  select * into v_chk from public.account_deletion_context();
  r := r || format('DELETE: the remaining owner is the sole owner|%s|', v_chk.is_sole_owner);
  begin
    perform public.delete_my_account(false);
    r := r || array['DELETE: the sole owner cannot silently delete the company|false|accepted'];
  exception when others then
    r := r || format('DELETE: the sole owner cannot silently delete the company|%s|%s', sqlstate = 'TD409', sqlstate);
  end;
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  r := r || format('DELETE: a refused sole-owner deletion changes nothing|%s|', exists(select 1 from public.app_users where id = v_ox1 and status = 'active' and name = 'OX1')
    and exists(select 1 from public.companies where id = v_cx and closed_at is null) and exists(select 1 from auth.sessions where user_id = v_ox1));

  -- Sole owner with explicit closure.
  select count(*) into v_before from public.app_users where company_id = v_cx;
  perform set_config('request.jwt.claims', json_build_object('sub', v_ox1::text, 'role', 'authenticated')::text, true);
  v_out := public.delete_my_account(true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  r := r || format('DELETE: the sole owner closes the workspace with explicit confirmation|%s|out=%s', v_out = 'workspaceClosed' and exists(select 1 from public.companies where id = v_cx and closed_at is not null), v_out);
  r := r || format('DELETE: after closure no membership remains active; none is deleted|%s|', not exists(select 1 from public.app_users where company_id = v_cx and status = 'active')
    and (select count(*) from public.app_users where company_id = v_cx) = v_before);
  r := r || format('DELETE: the sole owner''s sign-in is banned and sessions gone|%s|', exists(select 1 from auth.users where id = v_ox1 and banned_until > now() and deleted_at is not null)
    and not exists(select 1 from auth.sessions where user_id = v_ox1) and not exists(select 1 from auth.refresh_tokens where user_id = v_ox1::text));
  r := r || format('DELETE: closure retains business records and the Stripe account row|%s|', exists(select 1 from public.customers where id = v_cust_x)
    and exists(select 1 from public.stripe_connect_accounts where company_id = v_cx and stripe_account_id = 'acct_subtest_delete' and charges_enabled)
    and exists(select 1 from public.company_subscriptions where company_id = v_cx));
  r := r || format('DELETE: the platform fee is untouched (30 bps)|%s|', (select (value #>> '{}')::int from public.platform_settings where key='application_fee_bps') = 30);

  -- Tidy (the whole transaction is rolled back anyway).
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);

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
  for rec in select * from pg_temp.run_subscription_tests() loop
    if rec.passed then
      v_pass := v_pass + 1;
    else
      v_fail := v_fail + 1;
      v_report := v_report || chr(10) || 'FAIL: ' || rec.test_name || ' -- ' || coalesce(rec.detail, '');
    end if;
  end loop;

  raise exception 'SUBSCRIPTION SUITE  pass=% fail=% %', v_pass, v_fail, v_report;
end
$runner$;
