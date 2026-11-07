-- =============================================================================
-- 0017 - Apple Sandbox purchases for App Review (switch starts OFF)
-- =============================================================================
-- Why: App Review buys with Apple Sandbox accounts, and may create a brand-new
-- company to do it. Today a Sandbox purchase is applied only to companies on
-- the server-only allowlist (apple_sandbox_companies), so a reviewer's new
-- company stays read-only after a successful purchase (Guideline 2.1(b)).
--
-- What changes:
--   1. platform_settings.apple_sandbox_any_company (boolean, starts FALSE).
--      Server-only: platform_settings has row-level security ON and NO
--      policies, so signed-in and anonymous users see and change 0 rows.
--   2. apple_apply_transaction: ONE block changes (the Sandbox check). With the
--      switch ON, a Sandbox purchase may also apply to a non-allowlisted
--      company, but still never when the company has ANY Production history:
--        - current link is Production (active or expired), or
--        - any Production row in apple_transactions for the company.
--      Unchanged: Production always replaces Sandbox; the environment comes
--      only from Apple's verified signed transaction; ownership (TD409),
--      appAccountToken, upgrade/downgrade/renewal handling, idempotency.
--   3. sms_company_entitled: a Sandbox-only entitlement never unlocks SMS
--      (provisioning start, number purchase, sending, credit use) unless the
--      company is allowlisted. Production and allowlisted companies are
--      unchanged. This one function gates sms-setup "start",
--      sms_send_blocker, consume_sms_credit and sms_messaging_status.
--
-- With the switch OFF this migration changes NOTHING observable except the
-- extra Production-ledger refusal (no company has Production history today).
-- Enable later, only after approval:
--   update public.platform_settings set value = 'true'::jsonb, updated_at = now()
--    where key = 'apple_sandbox_any_company';
-- Rollback: migrations/rollback/0017_rollback_restore_pre_0017.sql
-- CREATE OR REPLACE keeps existing EXECUTE grants (postgres + service_role).
-- No data is changed: no subscription, ledger or allowlist row is touched.
-- =============================================================================

begin;

-- 1. Switch (OFF)
insert into public.platform_settings (key, value, description)
values ('apple_sandbox_any_company', 'false'::jsonb,
        'When true, a verified Apple Sandbox purchase may apply to any company with no Production history (App Review). Server-only. Default false.')
on conflict (key) do nothing;

-- 2. Sandbox rule
CREATE OR REPLACE FUNCTION public.apple_apply_transaction(p_company uuid, p_transaction jsonb, p_renewal jsonb DEFAULT NULL::jsonb, p_source text DEFAULT 'app'::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tx_id     text := p_transaction->>'transactionId';
  v_orig      text := p_transaction->>'originalTransactionId';
  v_product   text := p_transaction->>'productId';
  v_purchase  timestamptz := public.apple_ms(p_transaction->>'purchaseDate');
  v_expires   timestamptz := public.apple_ms(p_transaction->>'expiresDate');
  v_revoked   timestamptz := public.apple_ms(p_transaction->>'revocationDate');
  v_signed    timestamptz := public.apple_ms(p_transaction->>'signedDate');
  v_offer     integer := nullif(p_transaction->>'offerType', '')::integer;
  v_discount  text := p_transaction->>'offerDiscountType';
  v_free      boolean;
  v_tier      public.subscription_tiers%rowtype;
  v_period    text;
  v_sub       public.company_subscriptions%rowtype;
  v_apply_tx  boolean;
  v_apply_rn  boolean;
  v_rn_signed timestamptz := public.apple_ms(p_renewal->>'signedDate');
  v_state     text;
  v_status    text;
  v_new_tx    boolean;
  v_token     text := lower(nullif(p_transaction->>'appAccountToken', ''));
  v_switch    boolean := false;
  v_env       text := p_transaction->>'environment';
  v_found     boolean;
begin
  if not public.push_caller_is_service_role() then
    raise exception 'Apple entitlement is written by the server only.' using errcode = 'TD403';
  end if;
  if p_company is null or v_tx_id is null or v_orig is null or v_product is null then
    return 'invalidPayload';
  end if;

  -- Apple's signed environment decides what a purchase may do. Only Apple's
  -- two server environments are accepted. Xcode StoreKit-testing purchases are
  -- signed by a local certificate and are refused before they get here;
  -- anything else ('Xcode', 'LocalTesting', missing, unknown) is refused here,
  -- without a ledger row.
  if v_env is null or v_env not in ('Production', 'Sandbox') then
    return 'unsupportedEnvironment';
  end if;

  select * into v_tier from public.subscription_tiers t where t.apple_product_monthly = v_product;
  if found then
    v_period := 'monthly';
  else
    select * into v_tier from public.subscription_tiers t where t.apple_product_annual = v_product;
    if not found then return 'unknownProduct'; end if;
    v_period := 'annual';
  end if;

  -- Only the purchaser's own transaction carries the company's subscription.
  -- A family-shared copy is not a purchase (Family Sharing is off for every
  -- plan, so this is defence in depth).
  if coalesce(p_transaction->>'inAppOwnershipType', 'PURCHASED') <> 'PURCHASED' then
    return 'notPurchaser';
  end if;

  -- A free offer: Apple's introductory trial, or a free Offer Code / promo.
  v_free := v_offer is not null
            and (v_discount = 'FREE_TRIAL'
                 or (v_discount is null and coalesce(p_transaction->>'price', '') = '0'));

  -- The app sets appAccountToken to the company id at purchase. A purchase
  -- made for one company can never be applied to another.
  if v_token ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     and v_token::uuid <> p_company then
    raise exception 'This App Store subscription was bought for another Harbour South company.'
      using errcode = 'TD409';
  end if;

  -- One Apple subscription belongs to one company, for ever: checked against
  -- the current link AND the ledger, so a subscription a company has since
  -- replaced still cannot be attached to somebody else.
  -- Scoped to the environment: test and Production ids are separate identities.
  if exists (
    select 1 from public.company_subscriptions s
     where s.apple_environment = v_env and s.apple_original_transaction_id = v_orig and s.company_id <> p_company
  ) or exists (
    select 1 from public.apple_transactions t
     where t.environment = v_env and t.original_transaction_id = v_orig
       and t.company_id is not null and t.company_id <> p_company
  ) then
    raise exception 'This App Store subscription already belongs to another Harbour South company.'
      using errcode = 'TD409';
  end if;

  insert into public.apple_transactions as t (
    transaction_id, original_transaction_id, company_id, product_id, purchase_at, expires_at,
    revoked_at, offer_type, offer_identifier, offer_discount_type, environment, signed_at, source
  ) values (
    v_tx_id, v_orig, p_company, v_product, v_purchase, v_expires, v_revoked, v_offer,
    p_transaction->>'offerIdentifier', v_discount, v_env, v_signed, p_source
  )
  on conflict (environment, transaction_id) do update set
    revoked_at = coalesce(excluded.revoked_at, t.revoked_at),
    signed_at  = greatest(excluded.signed_at, t.signed_at),
    company_id = coalesce(t.company_id, excluded.company_id),
    updated_at = now();

  -- A transaction superseded by an immediate upgrade is history, not state.
  if coalesce((p_transaction->>'isUpgraded')::boolean, false) then
    return 'upgradedAway';
  end if;

  select * into v_sub from public.company_subscriptions s where s.company_id = p_company for update;
  v_found := found;

  -- A test purchase (Sandbox: TestFlight, App Review, sandbox Apple ID) is
  -- recorded above. It is applied only when ALL of these hold:
  --   * the company has never had a Production subscription - neither the
  --     current link (active OR expired) nor any Production row in the ledger;
  --   * the company is on the test-company allowlist, OR the server-only
  --     switch platform_settings.apple_sandbox_any_company is true (0017:
  --     lets App Review buy a plan for any brand-new company).
  -- Otherwise the company's real entitlement is not touched. v_env is Apple's
  -- verified signed environment, never a client value.
  if v_env = 'Sandbox' and (
       v_sub.apple_environment = 'Production'
       or exists (select 1 from public.apple_transactions t
                   where t.company_id = p_company and t.environment = 'Production')
       or not (
            exists (select 1 from public.apple_sandbox_companies a where a.company_id = p_company)
            or coalesce((select (ps.value #>> '{}')::boolean from public.platform_settings ps
                          where ps.key = 'apple_sandbox_any_company'), false)
          )
     ) then
    return 'sandboxNotApplied';
  end if;

  if not v_found then
    insert into public.company_subscriptions (company_id) values (p_company)
    returning * into v_sub;
  end if;

  -- A DIFFERENT Apple subscription for the same company (e.g. a new owner
  -- subscribed on their own Apple ID). The company row follows exactly one
  -- subscription: the new one takes over only when the current one no longer
  -- entitles the company, or the new one runs longer. Otherwise it is kept in
  -- the ledger and nothing about the current subscription changes — in
  -- particular, renewal info (cancellation, billing retry) from one
  -- subscription is never written onto another.
  -- A Production purchase always takes over from a test one.
  if v_sub.apple_original_transaction_id is not null
     and (v_sub.apple_original_transaction_id <> v_orig or v_sub.apple_environment is distinct from v_env) then
    v_switch := v_revoked is null
                and v_expires is not null
                and (
                  (v_env = 'Production' and v_sub.apple_environment is distinct from 'Production')
                  or not public.subscription_state_is_entitled(public.subscription_entitlement_state(
                    v_sub.store::text, v_sub.apple_expires_at, v_sub.apple_revoked_at, v_sub.apple_auto_renew,
                    v_sub.apple_grace_period_expires_at, v_sub.apple_in_billing_retry,
                    coalesce(v_sub.apple_is_free_offer, false), v_sub.apple_offer_type))
                  or v_expires > coalesce(v_sub.apple_expires_at, '-infinity'::timestamptz)
                );
    if not v_switch then
      return 'otherSubscription';
    end if;
  end if;

  v_apply_tx := v_switch
                or v_sub.apple_last_transaction_id is null
                or v_sub.apple_last_transaction_id = v_tx_id
                or v_sub.apple_purchase_at is null
                or v_purchase >= v_sub.apple_purchase_at;
  v_apply_rn := p_renewal is not null
                and coalesce(p_renewal->>'originalTransactionId', v_orig) = v_orig
                and coalesce(p_renewal->>'environment', v_env) = v_env
                and (v_switch or v_sub.apple_renewal_signed_at is null or v_rn_signed >= v_sub.apple_renewal_signed_at);

  if not v_apply_tx and not v_apply_rn then
    return 'stale';
  end if;

  -- A newer transaction (renewal, resubscribe, plan change) that arrives with
  -- no renewal info means Apple billed successfully: whatever billing-retry,
  -- grace or cancellation state the previous period ended in no longer holds.
  v_new_tx := v_apply_tx and not v_apply_rn
              and v_sub.apple_last_transaction_id is distinct from v_tx_id;

  update public.company_subscriptions s set
    store                         = 'apple',
    apple_original_transaction_id = case when v_apply_tx then v_orig else s.apple_original_transaction_id end,
    apple_last_transaction_id     = case when v_apply_tx then v_tx_id else s.apple_last_transaction_id end,
    apple_product_id              = case when v_apply_tx then v_product else s.apple_product_id end,
    apple_environment             = case when v_apply_tx then v_env else s.apple_environment end,
    apple_purchase_at             = case when v_apply_tx then v_purchase else s.apple_purchase_at end,
    apple_expires_at              = case when v_apply_tx then v_expires else s.apple_expires_at end,
    apple_revoked_at              = case when v_apply_tx then v_revoked else s.apple_revoked_at end,
    apple_offer_type              = case when v_apply_tx then v_offer else s.apple_offer_type end,
    apple_offer_identifier        = case when v_apply_tx then p_transaction->>'offerIdentifier' else s.apple_offer_identifier end,
    apple_offer_discount_type     = case when v_apply_tx then v_discount else s.apple_offer_discount_type end,
    apple_offer_period            = case when v_apply_tx then p_transaction->>'offerPeriod' else s.apple_offer_period end,
    apple_is_free_offer           = case when v_apply_tx then v_free else s.apple_is_free_offer end,
    tier_id                       = case when v_apply_tx then v_tier.id else s.tier_id end,
    billing_period                = case when v_apply_tx then v_period::public.billing_period else s.billing_period end,
    plan                          = case when v_apply_tx then
                                      (case v_tier.id when 'starter' then 'soloTrader' when 'team' then 'team' else 'business' end)::public.subscription_plan
                                    else s.plan end,
    current_period_start          = case when v_apply_tx and v_purchase is not null then v_purchase else s.current_period_start end,
    current_period_end            = case when v_apply_tx and v_expires is not null then v_expires else s.current_period_end end,
    renewal_date                  = case when v_apply_tx and v_expires is not null then v_expires else s.renewal_date end,
    apple_auto_renew              = case when v_apply_rn then (p_renewal->>'autoRenewStatus')::integer = 1
                                         when v_new_tx then null else s.apple_auto_renew end,
    apple_auto_renew_product_id   = case when v_apply_rn then p_renewal->>'autoRenewProductId'
                                         when v_switch or v_new_tx then null else s.apple_auto_renew_product_id end,
    apple_grace_period_expires_at = case when v_apply_rn then public.apple_ms(p_renewal->>'gracePeriodExpiresDate')
                                         when v_new_tx then null else s.apple_grace_period_expires_at end,
    apple_in_billing_retry        = case when v_apply_rn then coalesce((p_renewal->>'isInBillingRetryPeriod')::boolean, false)
                                         when v_new_tx then false else s.apple_in_billing_retry end,
    apple_expiration_intent       = case when v_apply_rn then nullif(p_renewal->>'expirationIntent', '')::integer
                                         when v_switch then null else s.apple_expiration_intent end,
    apple_renewal_signed_at       = case when v_apply_rn then v_rn_signed
                                         when v_switch then null else s.apple_renewal_signed_at end,
    apple_synced_at               = now(),
    updated_at                    = now()
  where s.company_id = p_company
  returning * into v_sub;

  v_state := public.subscription_entitlement_state(
    'apple', v_sub.apple_expires_at, v_sub.apple_revoked_at, v_sub.apple_auto_renew,
    v_sub.apple_grace_period_expires_at, v_sub.apple_in_billing_retry,
    v_sub.apple_is_free_offer, v_sub.apple_offer_type
  );
  v_status := case v_state
    when 'trial' then 'trialing' when 'offer' then 'trialing'
    when 'active' then 'active'  when 'cancelling' then 'active'
    when 'gracePeriod' then 'pastDue' when 'billingRetry' then 'pastDue'
    when 'revoked' then 'cancelled'
    else 'expired' end;

  update public.company_subscriptions s set
    status         = v_status::public.subscription_status,
    is_trial       = v_sub.apple_is_free_offer and v_state in ('trial', 'offer', 'cancelling'),
    trial_ends_at  = case when v_sub.apple_is_free_offer then v_sub.apple_expires_at else null end,
    cancelled_at   = case when v_state in ('cancelling', 'expired', 'revoked') and coalesce(v_sub.apple_auto_renew, true) = false
                          then coalesce(s.cancelled_at, now())
                          when v_state = 'revoked' then coalesce(s.cancelled_at, now())
                          else null end,
    past_due_since = case when v_state in ('gracePeriod', 'billingRetry') then coalesce(s.past_due_since, now()) else null end,
    seat_count     = (select count(*) from public.app_users u where u.company_id = p_company and u.status = 'active'),
    active_paid_users = (select count(*) from public.app_users u where u.company_id = p_company and u.status = 'active'),
    included_users = coalesce(v_tier.included_users, 1),
    additional_users = 0,
    base_cents     = v_tier.base_cents,
    monthly_price_cents = v_tier.base_cents,
    additional_user_cents = 0
  where s.company_id = p_company;

  return 'applied:' || v_state;
end $function$;

-- 3. SMS safeguard
CREATE OR REPLACE FUNCTION public.sms_company_entitled(p_company uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select c.closed_at is null from public.companies c where c.id = p_company), false)
     and coalesce((select e.has_entitlement from public.company_entitlement_for(p_company) e), false)
     -- 0017: an entitlement that comes only from an Apple Sandbox (test)
     -- purchase never unlocks SMS - no provisioning, no number purchase, no
     -- sending - unless the company is on the test-company allowlist.
     and (
          (select s.apple_environment from public.company_subscriptions s where s.company_id = p_company)
            is distinct from 'Sandbox'
          or exists (select 1 from public.apple_sandbox_companies a where a.company_id = p_company)
         )
$function$;

commit;
