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
  v_out := public.apple_apply_transaction(v_c, jsonb_build_object('transactionId','T0','originalTransactionId','O1','productId','com.example.other','purchaseDate',v_ms_now,'expiresDate',v_ms_now + v_day));
  r := r || format('Unknown product is refused without effect|%s|%s', v_out = 'unknownProduct' and (select store from public.company_subscriptions where company_id=v_c) = 'none', v_out);

  -- 14-day introductory free trial on Team monthly.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T1','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 14*v_day,'offerType',1,'offerDiscountType','FREE_TRIAL','offerPeriod','P2W','environment','Sandbox','signedDate',v_ms_now,'price',0),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.team.monthly','signedDate',v_ms_now), 'app');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('14-day introductory trial is an entitlement on Team monthly|%s|out=%s state=%s tier=%s period=%s', v_out = 'applied:trial' and v_state.has_entitlement and v_state.entitlement_state='trial' and v_state.tier_id='team' and v_state.billing_period='monthly' and v_state.is_free_offer and v_state.trial_days_remaining = 14, v_out, v_state.entitlement_state, v_state.tier_id, v_state.billing_period);
  r := r || format('During the free trial the company pays 0 and will renew at 39.99|%s|eff=%s price=%s', v_state.effective_monthly_cents = 0 and v_state.plan_price_cents = 3999 and v_state.will_auto_renew and v_state.renews_to_tier_id='team', v_state.effective_monthly_cents, v_state.plan_price_cents);
  r := r || format('Legacy status mirrors Apple: trialing|%s|', (select status::text from public.company_subscriptions where company_id=v_c) = 'trialing');

  -- Replay is idempotent.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T1','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 14*v_day,'offerType',1,'offerDiscountType','FREE_TRIAL','signedDate',v_ms_now), null, 'notification');
  select count(*) into v_n from public.apple_transactions where original_transaction_id='O1';
  r := r || format('A replayed transaction is idempotent|%s|rows=%s out=%s', v_n = 1 and v_out = 'applied:trial', v_n, v_out);

  -- After the trial Apple bills automatically: first paid renewal.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T2','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 1000,'price',39990),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.team.monthly','signedDate',v_ms_now + 1000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Paid renewal after the trial is active and no longer a free offer|%s|out=%s', v_out='applied:active' and v_state.entitlement_state='active' and not v_state.is_free_offer and v_state.effective_monthly_cents = 3999 and v_state.trial_ends_at is null, v_out);

  -- Out-of-order: the trial transaction arriving late cannot roll it back.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T1','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 14*v_day,'offerType',1,'offerDiscountType','FREE_TRIAL','signedDate',v_ms_now), null, 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('A late older transaction cannot roll state backwards|%s|out=%s state=%s', v_out = 'stale' and v_state.entitlement_state='active', v_out, v_state.entitlement_state);

  -- Cancellation: auto-renew off, still entitled until the period ends.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T2','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 2000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',0,'autoRenewProductId','com.harboursouth.fieldservice.team.monthly','signedDate',v_ms_now + 2000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Cancelling keeps the plan until the period ends|%s|out=%s', v_out='applied:cancelling' and v_state.has_entitlement and not v_state.will_auto_renew, v_out);

  -- Downgrade scheduled (Team -> Starter at renewal): current plan unchanged.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T2','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'signedDate',v_ms_now + 3000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.starter.monthly','signedDate',v_ms_now + 3000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('A scheduled downgrade keeps Team now and reports Starter at renewal|%s|tier=%s next=%s', v_state.tier_id='team' and v_state.renews_to_tier_id='starter' and v_state.will_auto_renew, v_state.tier_id, v_state.renews_to_tier_id);

  -- Immediate upgrade (Team monthly -> Business annual): the old transaction is
  -- marked upgraded and a new one starts now.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T2','originalTransactionId','O1','productId','com.harboursouth.fieldservice.team.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 30*v_day,'isUpgraded',true,'signedDate',v_ms_now + 4000), null, 'notification');
  r := r || format('The superseded transaction of an upgrade is history only|%s|%s', v_out='upgradedAway', v_out);
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T3','originalTransactionId','O1','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 5000,'expiresDate',v_ms_now + 365*v_day,'signedDate',v_ms_now + 5000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.business.annual','signedDate',v_ms_now + 5000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Upgrade to Business annual applies immediately, uncapped|%s|tier=%s period=%s limit=%s price=%s', v_state.tier_id='business' and v_state.billing_period='annual' and v_state.plan_user_limit is null and v_state.plan_price_cents = 66999, v_state.tier_id, v_state.billing_period, v_state.plan_user_limit, v_state.plan_price_cents);

  -- Billing problem: expired, Apple retrying, grace period running.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T4','originalTransactionId','O1','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 6000,'expiresDate',v_ms_now - v_day,'signedDate',v_ms_now + 6000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'isInBillingRetryPeriod',true,'gracePeriodExpiresDate',v_ms_now + 6*v_day,'signedDate',v_ms_now + 6000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Billing grace period stays entitled and reports past due|%s|out=%s status=%s', v_out='applied:gracePeriod' and v_state.has_entitlement and v_state.subscription_status='pastDue' and v_state.grace_period_ends_at is not null, v_out, v_state.subscription_status);

  -- Grace over, Apple still retrying: not entitled.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T4','originalTransactionId','O1','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 6000,'expiresDate',v_ms_now - v_day,'signedDate',v_ms_now + 7000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',1,'isInBillingRetryPeriod',true,'signedDate',v_ms_now + 7000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Billing retry after grace is not entitled|%s|out=%s', v_out='applied:billingRetry' and not v_state.has_entitlement and v_state.plan_user_limit = 1, v_out);

  -- Retry gave up: expired.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T4','originalTransactionId','O1','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 6000,'expiresDate',v_ms_now - v_day,'signedDate',v_ms_now + 8000),
    jsonb_build_object('originalTransactionId','O1','autoRenewStatus',0,'isInBillingRetryPeriod',false,'expirationIntent',2,'signedDate',v_ms_now + 8000), 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Expired subscription is not entitled|%s|out=%s status=%s', v_out='applied:expired' and not v_state.has_entitlement and v_state.subscription_status='expired', v_out, v_state.subscription_status);

  -- Resubscribe (restore of a new purchase), then refund.
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T5','originalTransactionId','O1','productId','com.harboursouth.fieldservice.starter.annual',
      'purchaseDate',v_ms_now + 9000,'expiresDate',v_ms_now + 365*v_day,'signedDate',v_ms_now + 9000), null, 'restore');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('Resubscribing (or restoring) re-entitles on Starter annual|%s|out=%s', v_out='applied:active' and v_state.tier_id='starter' and v_state.billing_period='annual' and v_state.plan_price_cents = 19199, v_out);
  v_out := public.apple_apply_transaction(v_c,
    jsonb_build_object('transactionId','T5','originalTransactionId','O1','productId','com.harboursouth.fieldservice.starter.annual',
      'purchaseDate',v_ms_now + 9000,'expiresDate',v_ms_now + 365*v_day,'revocationDate',v_ms_now + 10000,'signedDate',v_ms_now + 10000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_c);
  r := r || format('A refunded subscription is revoked immediately|%s|out=%s', v_out='applied:revoked' and not v_state.has_entitlement, v_out);

  -- Offer Codes: 30-day and 90-day free, then normal renewal.
  v_out := public.apple_apply_transaction(v_c2,
    jsonb_build_object('transactionId','U1','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now,'expiresDate',v_ms_now + 30*v_day,'offerType',3,'offerIdentifier','SPRING30','offerDiscountType','FREE_TRIAL','offerPeriod','P1M','signedDate',v_ms_now), null, 'app');
  select * into v_state from public.company_commercial_state(v_c2);
  r := r || format('A 30-day free Offer Code is an entitlement|%s|out=%s code=%s', v_out='applied:offer' and v_state.has_entitlement and v_state.offer_type = 3 and v_state.offer_identifier='SPRING30' and v_state.effective_monthly_cents = 0, v_out, v_state.offer_identifier);
  v_out := public.apple_apply_transaction(v_c2,
    jsonb_build_object('transactionId','U2','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 1000,'expiresDate',v_ms_now + 90*v_day,'offerType',3,'offerIdentifier','PARTNER90','offerDiscountType','FREE_TRIAL','offerPeriod','P3M','signedDate',v_ms_now + 1000), null, 'app');
  select * into v_state from public.company_commercial_state(v_c2);
  r := r || format('A 90-day free Offer Code is an entitlement|%s|days=%s', v_out='applied:offer' and v_state.trial_days_remaining = 90, v_state.trial_days_remaining);
  v_out := public.apple_apply_transaction(v_c2,
    jsonb_build_object('transactionId','U3','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 2000,'expiresDate',v_ms_now + 120*v_day,'signedDate',v_ms_now + 2000), null, 'notification');
  select * into v_state from public.company_commercial_state(v_c2);
  r := r || format('After an Offer Code the normal paid subscription follows|%s|out=%s', v_out='applied:active' and not v_state.is_free_offer and v_state.effective_monthly_cents=1999 and v_state.offer_type is null, v_out);

  -- One Apple subscription, one company.
  begin
    v_out := public.apple_apply_transaction(v_cb,
      jsonb_build_object('transactionId','U4','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
        'purchaseDate',v_ms_now + 3000,'expiresDate',v_ms_now + 150*v_day,'signedDate',v_ms_now + 3000), null, 'app');
    r := r || format('An App Store subscription cannot be attached to a second company|false|accepted %s', v_out);
  exception when others then
    r := r || format('An App Store subscription cannot be attached to a second company|%s|%s', sqlstate = 'TD409', sqlerrm);
  end;

  -- All six products map.
  foreach v_prod in array array['starter.monthly','starter.annual','team.monthly','team.annual','business.monthly','business.annual'] loop
    v_out := public.apple_apply_transaction(v_cb,
      jsonb_build_object('transactionId','P-' || v_prod,'originalTransactionId','O3','productId','com.harboursouth.fieldservice.' || v_prod,
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
    jsonb_build_object('transactionId','N1','originalTransactionId','O4','productId','com.harboursouth.fieldservice.starter.monthly',
      'purchaseDate',v_ms_now + 50000,'expiresDate',v_ms_now + 20*v_day,'signedDate',v_ms_now + 50000),
    jsonb_build_object('originalTransactionId','O4','autoRenewStatus',0,'autoRenewProductId','com.harboursouth.fieldservice.starter.monthly','signedDate',v_ms_now + 50000), 'app');
  select * into v_state from public.company_commercial_state(v_cb);
  r := r || format('A second Apple subscription never replaces a live, longer company plan|%s|out=%s tier=%s orig=%s renew=%s',
    v_out = 'otherSubscription' and v_state.tier_id = 'business' and v_state.apple_original_transaction_id = 'O3' and v_state.will_auto_renew,
    v_out, v_state.tier_id, v_state.apple_original_transaction_id, v_state.will_auto_renew);

  -- A family-shared copy is not the purchaser's subscription.
  v_out := public.apple_apply_transaction(v_cb,
    jsonb_build_object('transactionId','F1','originalTransactionId','O3','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 51000,'expiresDate',v_ms_now + 40*v_day,'signedDate',v_ms_now + 51000,'inAppOwnershipType','FAMILY_SHARED'), null, 'app');
  r := r || format('A family-shared transaction is not treated as a purchase|%s|%s', v_out = 'notPurchaser', v_out);

  -- The company plan lapses in favour of a longer one bought by the new owner:
  -- the company follows the subscription that actually entitles it.
  v_out := public.apple_apply_transaction(v_cb,
    jsonb_build_object('transactionId','N2','originalTransactionId','O5','productId','com.harboursouth.fieldservice.business.annual',
      'purchaseDate',v_ms_now + 52000,'expiresDate',v_ms_now + 400*v_day,'signedDate',v_ms_now + 52000),
    jsonb_build_object('originalTransactionId','O5','autoRenewStatus',1,'autoRenewProductId','com.harboursouth.fieldservice.business.annual','signedDate',v_ms_now + 52000), 'app');
  select * into v_state from public.company_commercial_state(v_cb);
  r := r || format('A longer subscription for the same company takes over cleanly|%s|out=%s orig=%s',
    v_out = 'applied:active' and v_state.apple_original_transaction_id = 'O5' and v_state.tier_id = 'business' and v_state.will_auto_renew,
    v_out, v_state.apple_original_transaction_id);

  -- A subscription a company has moved off still belongs to that company.
  begin
    v_out := public.apple_apply_transaction(v_c2,
      jsonb_build_object('transactionId','R1','originalTransactionId','O3','productId','com.harboursouth.fieldservice.business.annual',
        'purchaseDate',v_ms_now + 53000,'expiresDate',v_ms_now + 40*v_day,'signedDate',v_ms_now + 53000), null, 'restore');
    r := r || format('Restoring a superseded subscription into another company is refused|false|accepted %s', v_out);
  exception when others then
    r := r || format('Restoring a superseded subscription into another company is refused|%s|%s', sqlstate = 'TD409', sqlerrm);
  end;

  -- A purchase made for one company (appAccountToken) can never land in another.
  begin
    v_out := public.apple_apply_transaction(v_c2,
      jsonb_build_object('transactionId','K1','originalTransactionId','O6','productId','com.harboursouth.fieldservice.team.monthly',
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
  -- Only the server writes entitlement
  -- ---------------------------------------------------------------------------
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner2::text, 'role', 'authenticated')::text, true);
  begin
    perform public.apple_apply_transaction(v_c2, jsonb_build_object('transactionId','X','originalTransactionId','X','productId','com.harboursouth.fieldservice.business.annual'));
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
    jsonb_build_object('transactionId','U9','originalTransactionId','O2','productId','com.harboursouth.fieldservice.team.monthly',
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
    jsonb_build_object('transactionId','U10','originalTransactionId','O2','productId','com.harboursouth.fieldservice.starter.monthly',
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
