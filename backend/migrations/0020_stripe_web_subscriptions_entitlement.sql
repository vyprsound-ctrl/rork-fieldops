-- =============================================================================
-- 0020 - Web subscriptions through Stripe: entitlement
-- =============================================================================
-- Apple behaviour is unchanged. Every change below is a branch taken ONLY when
-- company_subscriptions.store = 'stripe'. For every Apple or 'none' row the
-- functions run exactly the code they ran before (bodies copied from the live
-- definitions and extended, not rewritten). subscription_entitlement_state()
-- and the Apple apply function are NOT touched.
--
--   1. stripe_entitlement_state(): Stripe's subscription status mapped onto the
--      same states the iPhone app already understands.
--   2. company_entitlement_for(): stripe branch.
--   3. company_commercial_state(): period end / auto-renew / store for stripe.
--   4. apply_stripe_subscription(): the only writer of Stripe subscription
--      state, called by the stripe-webhook function with the service role.
--      It never takes a company away from a live Apple subscription.

begin;

-- 1 --------------------------------------------------------------------------
create or replace function public.stripe_entitlement_state(
  p_status        text,
  p_period_end    timestamptz,
  p_cancel_at_end boolean,
  p_now           timestamptz default now()
) returns text
language sql
stable
as $function$
  -- A small allowance on the period end covers a renewal webhook that arrives
  -- a little late. A failed renewal keeps access for 14 days while Stripe
  -- retries the card (the same promise as Apple's grace period).
  select case
    when p_status is null or p_period_end is null                         then 'none'
    when p_status in ('active', 'trialing')
         and p_period_end + interval '2 days' > p_now
         and coalesce(p_cancel_at_end, false)                              then 'cancelling'
    when p_status in ('active', 'trialing')
         and p_period_end + interval '2 days' > p_now                      then 'active'
    when p_status = 'past_due' and p_period_end + interval '14 days' > p_now then 'gracePeriod'
    when p_status in ('past_due', 'unpaid')                                then 'billingRetry'
    else 'expired'
  end;
$function$;

revoke all on function public.stripe_entitlement_state(text, timestamptz, boolean, timestamptz) from public, anon;

-- 2 --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_entitlement_for(p_company uuid)
 RETURNS TABLE(has_entitlement boolean, entitlement_state text, tier_id text, tier_name text, billing_period text, user_limit integer, included_users integer, monthly_cents integer, annual_cents integer, active_users integer, open_invitations integer, pending_tier_id text, pending_user_limit integer, seat_ceiling integer, seats_over_limit boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sub   public.company_subscriptions%rowtype;
  v_tier  public.subscription_tiers%rowtype;
  v_next  public.subscription_tiers%rowtype;
  v_fallback integer;
  v_stripe boolean;
begin
  select * into v_sub from public.company_subscriptions s where s.company_id = p_company;
  v_stripe := coalesce(v_sub.store::text, 'none') = 'stripe';

  if v_stripe then
    -- 0020: a web subscription billed through Stripe.
    entitlement_state := public.stripe_entitlement_state(
      v_sub.stripe_status, v_sub.stripe_current_period_end, v_sub.stripe_cancel_at_period_end
    );
  else
    entitlement_state := public.subscription_entitlement_state(
      v_sub.store::text, v_sub.apple_expires_at, v_sub.apple_revoked_at, v_sub.apple_auto_renew,
      v_sub.apple_grace_period_expires_at, v_sub.apple_in_billing_retry,
      coalesce(v_sub.apple_is_free_offer, false), v_sub.apple_offer_type
    );
  end if;
  has_entitlement := public.subscription_state_is_entitled(entitlement_state);

  select count(*)::integer into active_users
    from public.app_users u where u.company_id = p_company and u.status = 'active';
  select count(*)::integer into open_invitations
    from public.invitations i
   where i.company_id = p_company and i.accepted_at is null
     and i.revoked_at is null and i.expires_at > now();

  if has_entitlement then
    select * into v_tier from public.subscription_tiers t where t.id = v_sub.tier_id;
    tier_id        := v_tier.id;
    tier_name      := v_tier.display_name;
    billing_period := v_sub.billing_period::text;
    user_limit     := v_tier.user_limit;
    included_users := v_tier.included_users;
    monthly_cents  := v_tier.base_cents;
    annual_cents   := v_tier.annual_cents;

    -- A plan change Apple has scheduled for the next renewal (a downgrade).
    -- It is not in force yet, but the company may not grow beyond it.
    -- (Apple only: a Stripe plan change applies immediately.)
    if not v_stripe and coalesce(v_sub.apple_auto_renew, true) and v_sub.apple_auto_renew_product_id is not null then
      select * into v_next from public.subscription_tiers t
       where v_sub.apple_auto_renew_product_id in (t.apple_product_monthly, t.apple_product_annual);
      if found and v_next.id is distinct from v_tier.id then
        pending_tier_id    := v_next.id;
        pending_user_limit := v_next.user_limit;
      end if;
    end if;
  else
    select (value #>> '{}')::integer into v_fallback
      from public.platform_settings where key = 'unsubscribed_user_limit';
    tier_id := null; tier_name := null; billing_period := null;
    user_limit := greatest(coalesce(v_fallback, 1), 1);
    included_users := user_limit;
    monthly_cents := 0; annual_cents := 0;
  end if;

  seat_ceiling := case
    when user_limit is null then pending_user_limit
    when pending_user_limit is null then user_limit
    else least(user_limit, pending_user_limit) end;
  seats_over_limit := has_entitlement
                      and public.seat_limits_enforced()
                      and user_limit is not null
                      and active_users > user_limit;

  return next;
end $function$;

revoke all on function public.company_entitlement_for(uuid) from public, anon, authenticated;

-- 3 --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.company_commercial_state(p_company uuid DEFAULT NULL::uuid)
 RETURNS TABLE(payment_model text, subscription_status text, trial_ends_at timestamp with time zone, trial_days_remaining integer, is_trial_active boolean, stripe_connected boolean, charges_enabled boolean, payouts_enabled boolean, details_submitted boolean, requirements_due text[], disabled_reason text, stripe_account_id text, tier_id text, tier_name text, subscription_monthly_cents integer, effective_monthly_cents integer, platform_fee_bps integer, external_payment_url text, business_email text, has_entitlement boolean, entitlement_state text, billing_period text, plan_price_cents integer, plan_user_limit integer, plan_included_users integer, active_users integer, open_invitations integer, can_add_user boolean, period_ends_at timestamp with time zone, will_auto_renew boolean, renews_to_tier_id text, renews_to_period text, offer_type integer, offer_identifier text, is_free_offer boolean, grace_period_ends_at timestamp with time zone, billing_store text, apple_environment text, seat_limits_enforced boolean, apple_original_transaction_id text, seats_over_limit boolean, users_to_deactivate integer, pending_user_limit integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_company     uuid;
  v_sub         public.company_subscriptions%rowtype;
  v_connect     public.stripe_connect_accounts%rowtype;
  v_company_row public.companies%rowtype;
  v_ent         record;
  v_fee_bps     integer;
  v_fee_on      boolean;
begin
  if not (
    public.push_caller_is_service_role()
    or coalesce(public.has_perm('saasBillingRead'::app_permission), false)
    or coalesce(public.has_perm('saasBillingManage'::app_permission), false)
  ) then
    raise exception 'Billing details are restricted to the account owner.'
      using errcode = 'TD403';
  end if;

  v_company := public.commerce_company_scope(p_company);
  if v_company is null then
    raise exception 'No company in context.' using errcode = 'TD404';
  end if;

  select * into v_company_row from public.companies c where c.id = v_company;
  select * into v_sub from public.company_subscriptions s where s.company_id = v_company;
  select * into v_connect from public.stripe_connect_accounts a where a.company_id = v_company;
  select * into v_ent from public.company_entitlement_for(v_company);

  select (value #>> '{}')::integer into v_fee_bps from public.platform_settings where key = 'application_fee_bps';
  select (value #>> '{}')::boolean into v_fee_on  from public.platform_settings where key = 'application_fee_enabled';

  payment_model := coalesce(v_sub.payment_model::text, 'undecided');

  has_entitlement   := v_ent.has_entitlement;
  entitlement_state := v_ent.entitlement_state;
  subscription_status := case entitlement_state
    when 'trial' then 'trialing' when 'offer' then 'trialing'
    when 'active' then 'active' when 'cancelling' then 'active'
    when 'gracePeriod' then 'pastDue' when 'billingRetry' then 'pastDue'
    when 'revoked' then 'cancelled' else 'expired' end;

  is_free_offer   := coalesce(v_sub.apple_is_free_offer, false) and has_entitlement;
  is_trial_active := is_free_offer;
  trial_ends_at   := case when is_free_offer then v_sub.apple_expires_at end;
  trial_days_remaining := case when is_free_offer
    then greatest(0, ceil(extract(epoch from (v_sub.apple_expires_at - now())) / 86400.0)::integer) else 0 end;

  stripe_connected  := v_connect.stripe_account_id is not null;
  charges_enabled   := coalesce(v_connect.charges_enabled, false);
  payouts_enabled   := coalesce(v_connect.payouts_enabled, false);
  details_submitted := coalesce(v_connect.details_submitted, false);
  requirements_due  := coalesce(v_connect.requirements_due, '{}'::text[]);
  disabled_reason   := v_connect.disabled_reason;
  stripe_account_id := v_connect.stripe_account_id;

  tier_id        := v_ent.tier_id;
  tier_name      := coalesce(v_ent.tier_name, 'No plan');
  billing_period := v_ent.billing_period;
  subscription_monthly_cents := coalesce(v_ent.monthly_cents, 0);
  plan_price_cents := case when v_ent.billing_period = 'annual' then v_ent.annual_cents else v_ent.monthly_cents end;
  -- What the company pays Harbour South right now: nothing during a free
  -- Apple offer, the plan price otherwise. Never a programme discount.
  effective_monthly_cents := case when is_free_offer then 0 else coalesce(v_ent.monthly_cents, 0) end;

  plan_user_limit     := v_ent.user_limit;
  plan_included_users := v_ent.included_users;
  active_users        := v_ent.active_users;
  open_invitations    := v_ent.open_invitations;
  seat_limits_enforced := public.seat_limits_enforced();
  can_add_user        := not seat_limits_enforced
                         or v_ent.seat_ceiling is null
                         or v_ent.active_users + v_ent.open_invitations < v_ent.seat_ceiling;
  seats_over_limit    := coalesce(v_ent.seats_over_limit, false);
  users_to_deactivate := case when seats_over_limit then v_ent.active_users - v_ent.user_limit else 0 end;
  pending_user_limit  := v_ent.pending_user_limit;

  period_ends_at       := case when v_sub.store = 'apple' then v_sub.apple_expires_at end;
  will_auto_renew      := case when v_sub.store = 'apple' then coalesce(v_sub.apple_auto_renew, true) end;
  grace_period_ends_at := v_sub.apple_grace_period_expires_at;
  offer_type           := v_sub.apple_offer_type;
  offer_identifier     := v_sub.apple_offer_identifier;
  billing_store        := coalesce(v_sub.store::text, 'none');
  apple_environment    := v_sub.apple_environment;
  -- Lets the owner's app tell whether THIS Apple ID holds the company's
  -- subscription, so a second owner is never sold a second subscription.
  apple_original_transaction_id := v_sub.apple_original_transaction_id;

  select t.id, case when t.apple_product_annual = v_sub.apple_auto_renew_product_id then 'annual' else 'monthly' end
    into renews_to_tier_id, renews_to_period
    from public.subscription_tiers t
   where v_sub.apple_auto_renew_product_id is not null
     and v_sub.apple_auto_renew_product_id in (t.apple_product_monthly, t.apple_product_annual);

  -- 0020: a web subscription billed through Stripe. Apple-only fields are
  -- cleared so a company that once had Apple never shows stale Apple details.
  if billing_store = 'stripe' then
    is_free_offer := false; is_trial_active := false; trial_ends_at := null; trial_days_remaining := 0;
    effective_monthly_cents := coalesce(v_ent.monthly_cents, 0);
    period_ends_at       := v_sub.stripe_current_period_end;
    will_auto_renew      := not coalesce(v_sub.stripe_cancel_at_period_end, false)
                            and coalesce(v_sub.stripe_status, '') in ('active', 'trialing', 'past_due');
    grace_period_ends_at := case when entitlement_state = 'gracePeriod'
                                 then v_sub.stripe_current_period_end + interval '14 days' end;
    offer_type := null; offer_identifier := null;
    renews_to_tier_id := null; renews_to_period := null;
    apple_environment := null; apple_original_transaction_id := null;
  end if;

  platform_fee_bps := case
    when coalesce(v_sub.payment_model, 'undecided') = 'externalProvider' then 0
    when coalesce(v_fee_on, true) = false then 0
    else coalesce(v_fee_bps, 0)
  end;

  external_payment_url := v_company_row.online_payment_link_url;
  business_email       := v_company_row.business_email;

  return next;
end $function$;

-- 4 --------------------------------------------------------------------------
create or replace function public.apply_stripe_subscription(
  p_company       uuid,
  p_customer      text,
  p_subscription  text,
  p_price         text,
  p_status        text,
  p_period_start  timestamptz,
  p_period_end    timestamptz,
  p_cancel_at_end boolean,
  p_tier          text,
  p_period        text
) returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_sub        public.company_subscriptions%rowtype;
  v_tier       public.subscription_tiers%rowtype;
  v_state      text;
  v_old_state  text;
  v_apple_live boolean;
  v_status     text;
begin
  if not public.push_caller_is_service_role() then
    raise exception 'Only the server can apply a Stripe subscription.' using errcode = 'TD403';
  end if;
  if p_company is null or p_subscription is null then
    raise exception 'Missing company or subscription.' using errcode = 'P0001';
  end if;

  select * into v_sub from public.company_subscriptions s where s.company_id = p_company for update;
  if not found then
    insert into public.company_subscriptions (company_id) values (p_company) returning * into v_sub;
  end if;

  v_state := public.stripe_entitlement_state(p_status, p_period_end, p_cancel_at_end);

  -- A different Stripe subscription that is still live wins over one that
  -- isn't (e.g. an abandoned or replaced checkout). Nothing is written.
  if v_sub.stripe_subscription_id is not null and v_sub.stripe_subscription_id <> p_subscription then
    v_old_state := public.stripe_entitlement_state(
      v_sub.stripe_status, v_sub.stripe_current_period_end, v_sub.stripe_cancel_at_period_end);
    if public.subscription_state_is_entitled(v_old_state)
       and not public.subscription_state_is_entitled(v_state) then
      return 'otherSubscription';
    end if;
  end if;

  update public.company_subscriptions s set
    stripe_customer_id          = coalesce(p_customer, s.stripe_customer_id),
    stripe_subscription_id      = p_subscription,
    stripe_price_id             = coalesce(p_price, s.stripe_price_id),
    stripe_status               = p_status,
    stripe_current_period_end   = p_period_end,
    stripe_cancel_at_period_end = coalesce(p_cancel_at_end, false),
    stripe_synced_at            = now()
  where s.company_id = p_company;

  -- Never take a company away from a live Apple subscription. The Stripe
  -- facts are recorded above; the company keeps following Apple.
  v_apple_live := coalesce(v_sub.store::text, 'none') = 'apple'
    and public.subscription_state_is_entitled(public.subscription_entitlement_state(
      'apple', v_sub.apple_expires_at, v_sub.apple_revoked_at, v_sub.apple_auto_renew,
      v_sub.apple_grace_period_expires_at, v_sub.apple_in_billing_retry,
      coalesce(v_sub.apple_is_free_offer, false), v_sub.apple_offer_type));
  if v_apple_live then
    return 'appleActive:' || v_state;
  end if;

  -- A checkout that was never paid does not move the company off its store.
  if coalesce(v_sub.store::text, 'none') <> 'stripe' and p_status in ('incomplete', 'incomplete_expired') then
    return 'notStarted:' || v_state;
  end if;

  select * into v_tier from public.subscription_tiers t where t.id = p_tier;

  v_status := case v_state
    when 'active' then 'active' when 'cancelling' then 'active'
    when 'gracePeriod' then 'pastDue' when 'billingRetry' then 'pastDue'
    else case when p_status = 'canceled' then 'cancelled' else 'expired' end end;

  update public.company_subscriptions s set
    store                 = 'stripe',
    tier_id               = coalesce(v_tier.id, s.tier_id),
    billing_period        = coalesce(nullif(p_period, '')::public.billing_period, s.billing_period),
    plan                  = case when v_tier.id is null then s.plan else
                              (case v_tier.id when 'starter' then 'soloTrader' when 'team' then 'team' else 'business' end)::public.subscription_plan
                            end,
    status                = v_status::public.subscription_status,
    current_period_start  = coalesce(p_period_start, s.current_period_start),
    current_period_end    = coalesce(p_period_end, s.current_period_end),
    renewal_date          = coalesce(p_period_end, s.renewal_date),
    is_trial              = false,
    trial_ends_at         = null,
    cancelled_at          = case when v_state in ('cancelling', 'expired') then coalesce(s.cancelled_at, now()) else null end,
    past_due_since        = case when v_state in ('gracePeriod', 'billingRetry') then coalesce(s.past_due_since, now()) else null end,
    seat_count            = (select count(*) from public.app_users u where u.company_id = p_company and u.status = 'active'),
    active_paid_users     = (select count(*) from public.app_users u where u.company_id = p_company and u.status = 'active'),
    included_users        = coalesce(v_tier.included_users, s.included_users),
    additional_users      = 0,
    base_cents            = coalesce(v_tier.base_cents, s.base_cents),
    monthly_price_cents   = coalesce(v_tier.base_cents, s.monthly_price_cents),
    additional_user_cents = 0,
    updated_at            = now()
  where s.company_id = p_company;

  return 'applied:' || v_state;
end $function$;

revoke all on function public.apply_stripe_subscription(uuid, text, text, text, text, timestamptz, timestamptz, boolean, text, text) from public, anon, authenticated;
grant execute on function public.apply_stripe_subscription(uuid, text, text, text, text, timestamptz, timestamptz, boolean, text, text) to service_role;

commit;
