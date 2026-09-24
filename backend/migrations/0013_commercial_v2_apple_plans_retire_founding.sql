-- =============================================================================
-- 0013 - COMMERCIAL MODEL V2
--        Founding programme retired · three Apple-billed plans · server-side
--        Apple entitlement · plan-controlled user seats
-- =============================================================================
--
-- DECISIONS THIS MIGRATION IMPLEMENTS
--
--   1. The Founding Member programme is abandoned. No company receives free
--      Harbour South service for being early or for connecting Stripe.
--   2. Three plans, the same for every customer:
--        Starter   $19.99/mo  $191.99/yr   1 user
--        Team      $39.99/mo  $384.99/yr   up to 5 users
--        Business  $69.99/mo  $669.99/yr   10+ users, NO plan cap
--   3. Harbour South's own subscription is billed ONLY by Apple (auto-renewable
--      subscriptions). The 14-day free trial is Apple's introductory offer and
--      30/90-day promotions are Apple Offer Codes. There is no Harbour South
--      trial clock any more, so the two can never stack.
--   4. The server is the authority on entitlement. It is written only by the
--      `apple-subscription` and `app-store-notifications` Edge Functions, after
--      they have verified Apple's JWS signatures, and it is re-evaluated against
--      the database clock on every read — so an expiry takes effect without
--      waiting for any notification.
--   5. The plan controls how many ACTIVE people a company can have. Existing
--      users are never suspended automatically; adding or reactivating somebody
--      beyond the plan is refused.
--
-- WHAT IS RETIRED, AND WHAT IS DELIBERATELY KEPT
--
--   Dropped:  claim_founding_member_slot(uuid), founding_activity(uuid), and the
--             founding columns of company_commercial_state().
--   Kept:     the founding_member_slots TABLE and its guard trigger, as inert
--             history. Zero places were ever claimed. It is no longer readable by
--             app users and nothing reads or writes it. Migrations 0008 and 0012
--             stay in the repository unchanged: they are applied history, and
--             rewriting applied migrations is how environments drift apart.
--   Kept:     the legacy subscription_tiers rows (solo/growing/larger) with
--             is_active = false, because company_subscriptions.tier_id has a
--             foreign key to that table.
--
-- WHAT THIS DOES NOT TOUCH
--   Stripe Connect, PaymentIntents, the 0.3% application fee
--   (platform_settings.application_fee_bps = 30), record_payment_from_stripe,
--   payments, invoices, Storage, photos, messaging, jobs, roles or tenancy.
--
-- BUILD 19 COMPATIBILITY
--   Build 19 decodes every company_commercial_state() column as optional and
--   reads only active subscription_tiers rows with non-null min/max users, so
--   the shipped TestFlight build keeps working against this schema.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Prerequisites.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.commerce_company_scope(uuid)') is null then
    raise exception 'commerce_company_scope(uuid) is missing';
  end if;
  if to_regprocedure('public.push_caller_is_service_role()') is null then
    raise exception 'push_caller_is_service_role() is missing';
  end if;
  if to_regclass('public.subscription_tiers') is null then
    raise exception 'subscription_tiers is missing - apply 0004 first';
  end if;
  if exists (select 1 from public.founding_member_slots where claimed_at is not null) then
    raise exception 'A founding place has been claimed - retiring the programme needs a decision about that company first';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Retire the Founding Member programme.
-- ---------------------------------------------------------------------------
drop function if exists public.claim_founding_member_slot(uuid);
drop function if exists public.founding_activity(uuid);

drop policy if exists founding_member_slots_select on public.founding_member_slots;
revoke all on public.founding_member_slots from anon, authenticated;

comment on table public.founding_member_slots is
  'RETIRED (migration 0013). The Founding Member programme was abandoned before any place was claimed. Kept as inert history only; nothing reads or writes it.';

-- ---------------------------------------------------------------------------
-- 2. The three plans.
--
--   included_users  users covered by the price.
--   user_limit      hard cap on active users; NULL = no plan cap. Business is
--                   NULL on purpose: it is a "10+" tier, not "maximum 10".
--   additional_user_cents stays 0 for every plan in this revision. It is the
--                   extension point for future seat pricing above
--                   included_users, alongside Apple multi-seat purchasing.
-- ---------------------------------------------------------------------------
alter table public.subscription_tiers
  add column if not exists included_users        integer,
  add column if not exists user_limit            integer,
  add column if not exists annual_cents          integer,
  add column if not exists apple_product_monthly text,
  add column if not exists apple_product_annual  text,
  add column if not exists tagline               text not null default '';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'subscription_tiers_user_limit_valid') then
    alter table public.subscription_tiers
      add constraint subscription_tiers_user_limit_valid
      check (user_limit is null or user_limit >= 1);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'subscription_tiers_annual_valid') then
    alter table public.subscription_tiers
      add constraint subscription_tiers_annual_valid
      check (annual_cents is null or annual_cents >= 0);
  end if;
end $$;

create unique index if not exists subscription_tiers_apple_monthly_idx
  on public.subscription_tiers (apple_product_monthly) where apple_product_monthly is not null;
create unique index if not exists subscription_tiers_apple_annual_idx
  on public.subscription_tiers (apple_product_annual) where apple_product_annual is not null;

-- Legacy head-count bands: retired, kept for the foreign key.
update public.subscription_tiers
   set is_active = false, updated_at = now()
 where id in ('solo', 'growing', 'larger');

-- min_users/max_users are now only the RECOMMENDATION band ("which plan fits a
-- company this size") and exist for Build 19; the entitlement uses user_limit.
insert into public.subscription_tiers
  (id, display_name, min_users, max_users, base_cents, additional_user_cents, sort_order, is_active,
   included_users, user_limit, annual_cents, apple_product_monthly, apple_product_annual, tagline)
values
  ('starter',  'Starter',  1, 1,    1999, 0, 1, true, 1,  1,    19199,
   'com.harboursouth.fieldservice.starter.monthly',  'com.harboursouth.fieldservice.starter.annual',  'Just me'),
  ('team',     'Team',     2, 5,    3999, 0, 2, true, 5,  5,    38499,
   'com.harboursouth.fieldservice.team.monthly',     'com.harboursouth.fieldservice.team.annual',     'My small team'),
  ('business', 'Business', 6, 9999, 6999, 0, 3, true, 10, null, 66999,
   'com.harboursouth.fieldservice.business.monthly', 'com.harboursouth.fieldservice.business.annual', 'My business, 10+ people')
on conflict (id) do update set
  display_name          = excluded.display_name,
  min_users             = excluded.min_users,
  max_users             = excluded.max_users,
  base_cents            = excluded.base_cents,
  additional_user_cents = excluded.additional_user_cents,
  sort_order            = excluded.sort_order,
  is_active             = excluded.is_active,
  included_users        = excluded.included_users,
  user_limit            = excluded.user_limit,
  annual_cents          = excluded.annual_cents,
  apple_product_monthly = excluded.apple_product_monthly,
  apple_product_annual  = excluded.apple_product_annual,
  tagline               = excluded.tagline,
  updated_at            = now();

comment on column public.subscription_tiers.user_limit is
  'Hard cap on ACTIVE users for this plan. NULL means the plan has no cap (Business is 10+, not maximum 10).';
comment on column public.subscription_tiers.included_users is
  'Users covered by the plan price. Extension point: additional_user_cents above this is 0 in every plan today.';

insert into public.platform_settings (key, value, description) values
  ('unsubscribed_user_limit', '1'::jsonb,
   'Active users a company may have while it holds no Apple subscription entitlement. Existing users are never suspended by this; it only stops more being added.'),
  ('seat_limits_enforced', 'false'::jsonb,
   'Master switch for the plan user limits. Off until the Apple subscription products are live, so no company is blocked from adding people before it is able to buy a plan. Turn on in the same release that ships StoreKit purchasing.')
on conflict (key) do nothing;

create or replace function public.seat_limits_enforced()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce((select (value #>> '{}')::boolean from public.platform_settings where key = 'seat_limits_enforced'), false);
$$;

revoke all on function public.seat_limits_enforced() from public, anon;

-- ---------------------------------------------------------------------------
-- 3. company_subscriptions: Apple is the store, and there is no local trial.
-- ---------------------------------------------------------------------------
alter table public.company_subscriptions
  add column if not exists apple_product_id              text,
  add column if not exists apple_environment             text,
  add column if not exists apple_last_transaction_id     text,
  add column if not exists apple_purchase_at             timestamptz,
  add column if not exists apple_expires_at              timestamptz,
  add column if not exists apple_revoked_at              timestamptz,
  add column if not exists apple_auto_renew              boolean,
  add column if not exists apple_auto_renew_product_id   text,
  add column if not exists apple_grace_period_expires_at timestamptz,
  add column if not exists apple_in_billing_retry        boolean not null default false,
  add column if not exists apple_expiration_intent       integer,
  add column if not exists apple_offer_type              integer,
  add column if not exists apple_offer_identifier        text,
  add column if not exists apple_offer_discount_type     text,
  add column if not exists apple_offer_period            text,
  add column if not exists apple_is_free_offer           boolean not null default false,
  add column if not exists apple_renewal_signed_at       timestamptz,
  add column if not exists apple_synced_at               timestamptz;

create unique index if not exists company_subscriptions_apple_original_idx
  on public.company_subscriptions (apple_original_transaction_id)
  where apple_original_transaction_id is not null;

-- No Harbour South trial clock. A company with no Apple subscription is
-- store = 'none', status = 'expired' ("never subscribed / not entitled").
alter table public.company_subscriptions alter column status               set default 'expired';
alter table public.company_subscriptions alter column is_trial             set default false;
alter table public.company_subscriptions alter column trial_ends_at        drop default;
alter table public.company_subscriptions alter column current_period_end   set default now();
alter table public.company_subscriptions alter column renewal_date         set default now();

update public.company_subscriptions
   set status        = 'expired',
       is_trial      = false,
       trial_ends_at = null,
       tier_id       = null,
       updated_at    = now()
 where store <> 'apple';

comment on column public.company_subscriptions.trial_ends_at is
  'End of an Apple free offer (introductory trial or free Offer Code) while one is running. There is no Harbour South trial clock.';

-- ---------------------------------------------------------------------------
-- 4. Apple ledgers. Service role only: no policies for app users.
-- ---------------------------------------------------------------------------
create table if not exists public.apple_transactions (
  transaction_id          text primary key,
  original_transaction_id text not null,
  company_id              uuid references public.companies(id) on delete set null,
  product_id              text not null,
  purchase_at             timestamptz,
  expires_at              timestamptz,
  revoked_at              timestamptz,
  offer_type              integer,
  offer_identifier        text,
  offer_discount_type     text,
  environment             text,
  signed_at               timestamptz,
  source                  text not null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now()
);
create index if not exists apple_transactions_original_idx on public.apple_transactions (original_transaction_id);
alter table public.apple_transactions enable row level security;

create table if not exists public.apple_notifications (
  notification_uuid       text primary key,
  notification_type       text not null,
  subtype                 text,
  environment             text,
  original_transaction_id text,
  company_id              uuid references public.companies(id) on delete set null,
  outcome                 text,
  signed_at               timestamptz,
  received_at             timestamptz not null default now()
);
alter table public.apple_notifications enable row level security;

revoke all on public.apple_transactions  from anon, authenticated;
revoke all on public.apple_notifications from anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Entitlement, evaluated against the database clock.
-- ---------------------------------------------------------------------------

-- Apple milliseconds (as JSON text) -> timestamptz.
create or replace function public.apple_ms(p text)
returns timestamptz
language sql immutable
as $$
  select case when p is null or p = '' then null
              else to_timestamp(p::numeric / 1000.0) end;
$$;

-- The one definition of "where does this subscription stand right now".
--   entitled: trial, offer, active, cancelling, gracePeriod
--   not:      none, billingRetry, expired, revoked
create or replace function public.subscription_entitlement_state(
  p_store       text,
  p_expires     timestamptz,
  p_revoked     timestamptz,
  p_auto_renew  boolean,
  p_grace       timestamptz,
  p_retry       boolean,
  p_free_offer  boolean,
  p_offer_type  integer,
  p_now         timestamptz default now()
)
returns text
language sql stable
as $$
  select case
    when coalesce(p_store, 'none') <> 'apple' or p_expires is null then 'none'
    when p_revoked is not null                                     then 'revoked'
    when p_expires > p_now and coalesce(p_auto_renew, true) = false then 'cancelling'
    when p_expires > p_now and p_free_offer and p_offer_type = 1   then 'trial'
    when p_expires > p_now and p_free_offer                        then 'offer'
    when p_expires > p_now                                         then 'active'
    when p_grace is not null and p_grace > p_now                   then 'gracePeriod'
    when coalesce(p_retry, false)                                  then 'billingRetry'
    else 'expired'
  end;
$$;

create or replace function public.subscription_state_is_entitled(p_state text)
returns boolean
language sql immutable
as $$
  select p_state in ('trial', 'offer', 'active', 'cancelling', 'gracePeriod');
$$;

-- Everything the seat rule and the commercial read need, for one company.
-- Internal: takes the company as given; granted to nobody.
create or replace function public.company_entitlement_for(p_company uuid)
returns table (
  has_entitlement      boolean,
  entitlement_state    text,
  tier_id              text,
  tier_name            text,
  billing_period       text,
  user_limit           integer,
  included_users       integer,
  monthly_cents        integer,
  annual_cents         integer,
  active_users         integer,
  open_invitations     integer
)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_sub   public.company_subscriptions%rowtype;
  v_tier  public.subscription_tiers%rowtype;
  v_fallback integer;
begin
  select * into v_sub from public.company_subscriptions s where s.company_id = p_company;

  entitlement_state := public.subscription_entitlement_state(
    v_sub.store::text, v_sub.apple_expires_at, v_sub.apple_revoked_at, v_sub.apple_auto_renew,
    v_sub.apple_grace_period_expires_at, v_sub.apple_in_billing_retry,
    coalesce(v_sub.apple_is_free_offer, false), v_sub.apple_offer_type
  );
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
  else
    select (value #>> '{}')::integer into v_fallback
      from public.platform_settings where key = 'unsubscribed_user_limit';
    tier_id := null; tier_name := null; billing_period := null;
    user_limit := greatest(coalesce(v_fallback, 1), 1);
    included_users := user_limit;
    monthly_cents := 0; annual_cents := 0;
  end if;

  return next;
end $$;

revoke all on function public.company_entitlement_for(uuid) from public, anon, authenticated;

-- The sentence a refused seat produces, so every door says the same thing.
create or replace function public.company_seat_refusal(p_company uuid)
returns text
language plpgsql stable security definer
set search_path = public
as $$
declare
  e    record;
  v_next text;
begin
  select * into e from public.company_entitlement_for(p_company);
  if not e.has_entitlement then
    return format('Choose a Harbour South plan to add more people. Without a plan your company can have %s active %s.',
                  e.user_limit, case when e.user_limit = 1 then 'user' else 'users' end);
  end if;
  select display_name into v_next
    from public.subscription_tiers t
   where t.is_active and (t.user_limit is null or t.user_limit > e.user_limit)
   order by t.sort_order limit 1;
  return format('Your %s plan includes up to %s %s. Move to %s to add more people.',
                e.tier_name, e.user_limit, case when e.user_limit = 1 then 'user' else 'users' end,
                coalesce(v_next, 'a larger plan'));
end $$;

revoke all on function public.company_seat_refusal(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 6. The seat rule.
--
-- Enforced for end-user calls (auth.role() = 'authenticated'), which covers
-- accepting an invitation and reactivating a suspended person. The service
-- role and maintenance scripts are not limited. Nobody is ever suspended by
-- this: a company over its plan after a downgrade keeps everyone it has.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_company_seat_limit()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  v_limit  integer;
  v_active integer;
begin
  if new.status is distinct from 'active' then return new; end if;
  if tg_op = 'UPDATE' and old.status = 'active' and old.company_id = new.company_id then return new; end if;
  if coalesce(auth.role(), '') <> 'authenticated' then return new; end if;
  if not public.seat_limits_enforced() then return new; end if;

  select user_limit into v_limit from public.company_entitlement_for(new.company_id);
  if v_limit is null then return new; end if;

  select count(*)::integer into v_active
    from public.app_users u
   where u.company_id = new.company_id and u.status = 'active' and u.id <> new.id;

  if v_active >= v_limit then
    raise exception '%', public.company_seat_refusal(new.company_id) using errcode = 'P0001';
  end if;
  return new;
end $$;

revoke all on function public.enforce_company_seat_limit() from public, anon, authenticated;

drop trigger if exists app_users_seat_limit on public.app_users;
create trigger app_users_seat_limit
  before insert or update of status, company_id on public.app_users
  for each row execute function public.enforce_company_seat_limit();

-- create_invitation, reproduced exactly as deployed with ONE addition: an
-- invitation reserves a seat, so active people + open invitations must leave
-- room under the plan. Refusing here is kinder than refusing at acceptance.
create or replace function public.create_invitation(p_email text, p_role app_role, p_expires_in_days integer default 7)
returns table(invitation_id uuid, invitation_token text)
language plpgsql
security definer
set search_path to 'public', 'extensions'
as $function$
declare
  v_uid uuid := auth.uid();
  v_company uuid := public.current_company_id();
  v_actor_role app_role := public.current_app_role();
  v_token text;
  v_id uuid;
  v_seats record;
begin
  if v_uid is null or v_company is null then
    raise exception 'You must belong to a company to invite users'
      using errcode = '28000';
  end if;

  if not public.has_perm('usersManage') then
    raise exception 'You do not have permission to invite users'
      using errcode = '42501';
  end if;

  -- Only an Owner may create another Owner, by invitation or otherwise.
  if p_role = 'owner' and v_actor_role is distinct from 'owner' then
    raise exception 'Only an Owner can invite another Owner'
      using errcode = '42501';
  end if;

  if p_expires_in_days is null or p_expires_in_days < 1 or p_expires_in_days > 90 then
    raise exception 'Invitation expiry must be between 1 and 90 days'
      using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.app_users
    where company_id = v_company and lower(email) = lower(btrim(p_email))
  ) then
    raise exception 'That person is already a member of this company'
      using errcode = 'P0001';
  end if;

  -- 0013: the plan's seat rule.
  select * into v_seats from public.company_entitlement_for(v_company);
  if public.seat_limits_enforced()
     and v_seats.user_limit is not null
     and v_seats.active_users + v_seats.open_invitations >= v_seats.user_limit then
    raise exception '%', public.company_seat_refusal(v_company) using errcode = 'P0001';
  end if;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.invitations (
    company_id, email, role, token, invited_by_user_id, expires_at
  )
  values (
    v_company, lower(btrim(p_email)), p_role, v_token, v_uid,
    now() + make_interval(days => p_expires_in_days)
  )
  returning id into v_id;

  return query select v_id, v_token;
end;
$function$;

-- ---------------------------------------------------------------------------
-- 7. Applying a VERIFIED Apple transaction.
--
-- Called only by the Edge Functions under the service role, after they have
-- verified the JWS chain to Apple Root CA - G3 and checked the bundle id. The
-- payloads are Apple's decoded JWSTransactionDecodedPayload and
-- JWSRenewalInfoDecodedPayload, unmodified.
--
-- Ordering: Apple can deliver out of order, so a transaction only replaces the
-- stored one when it is the same transaction (e.g. now revoked) or purchased no
-- earlier; renewal info only when signed no earlier. Replays are idempotent.
-- ---------------------------------------------------------------------------
create or replace function public.apple_apply_transaction(
  p_company     uuid,
  p_transaction jsonb,
  p_renewal     jsonb default null,
  p_source      text  default 'app'
)
returns text
language plpgsql volatile security definer
set search_path = public
as $$
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
begin
  if not public.push_caller_is_service_role() then
    raise exception 'Apple entitlement is written by the server only.' using errcode = 'TD403';
  end if;
  if p_company is null or v_tx_id is null or v_orig is null or v_product is null then
    return 'invalidPayload';
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
  if exists (
    select 1 from public.company_subscriptions s
     where s.apple_original_transaction_id = v_orig and s.company_id <> p_company
  ) or exists (
    select 1 from public.apple_transactions t
     where t.original_transaction_id = v_orig and t.company_id is not null and t.company_id <> p_company
  ) then
    raise exception 'This App Store subscription already belongs to another Harbour South company.'
      using errcode = 'TD409';
  end if;

  insert into public.apple_transactions as t (
    transaction_id, original_transaction_id, company_id, product_id, purchase_at, expires_at,
    revoked_at, offer_type, offer_identifier, offer_discount_type, environment, signed_at, source
  ) values (
    v_tx_id, v_orig, p_company, v_product, v_purchase, v_expires, v_revoked, v_offer,
    p_transaction->>'offerIdentifier', v_discount, p_transaction->>'environment', v_signed, p_source
  )
  on conflict (transaction_id) do update set
    revoked_at = coalesce(excluded.revoked_at, t.revoked_at),
    signed_at  = greatest(excluded.signed_at, t.signed_at),
    company_id = coalesce(t.company_id, excluded.company_id),
    updated_at = now();

  -- A transaction superseded by an immediate upgrade is history, not state.
  if coalesce((p_transaction->>'isUpgraded')::boolean, false) then
    return 'upgradedAway';
  end if;

  select * into v_sub from public.company_subscriptions s where s.company_id = p_company for update;
  if not found then
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
  if v_sub.apple_original_transaction_id is not null and v_sub.apple_original_transaction_id <> v_orig then
    v_switch := v_revoked is null
                and v_expires is not null
                and (
                  not public.subscription_state_is_entitled(public.subscription_entitlement_state(
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
    apple_environment             = case when v_apply_tx then p_transaction->>'environment' else s.apple_environment end,
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
                                         when v_switch then null else s.apple_auto_renew_product_id end,
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
end $$;

revoke all on function public.apple_apply_transaction(uuid, jsonb, jsonb, text) from public, anon, authenticated;
grant execute on function public.apple_apply_transaction(uuid, jsonb, jsonb, text) to service_role;

-- ---------------------------------------------------------------------------
-- 8. Harbour South Payments follows from Stripe — no longer via a founding
--    claim. Same eligibility test and same effect the old claim function had
--    on payment_model, and nothing else.
-- ---------------------------------------------------------------------------
create or replace function public.adopt_harbour_south_payments(p_company uuid)
returns boolean
language plpgsql volatile security definer
set search_path = public
as $$
begin
  if not public.push_caller_is_service_role() then
    raise exception 'Set by the server from Stripe only.' using errcode = 'TD403';
  end if;
  if not exists (
    select 1 from public.stripe_connect_accounts a where a.company_id = p_company and a.charges_enabled
  ) then
    return false;
  end if;
  update public.company_subscriptions
     set payment_model = 'harbourSouthPayments', updated_at = now()
   where company_id = p_company and payment_model <> 'harbourSouthPayments';
  return true;
end $$;

revoke all on function public.adopt_harbour_south_payments(uuid) from public, anon, authenticated;
grant execute on function public.adopt_harbour_south_payments(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 9. The commercial read, rebuilt without the founding programme.
--
-- Column names that Build 19 reads keep their meaning where they still have
-- one (trial_* now describe an Apple free offer; tier_* the entitled plan).
-- ---------------------------------------------------------------------------
drop function if exists public.company_commercial_state(uuid);

create function public.company_commercial_state(p_company uuid default null)
returns table (
  payment_model              text,
  subscription_status        text,
  trial_ends_at              timestamptz,
  trial_days_remaining       integer,
  is_trial_active            boolean,
  stripe_connected           boolean,
  charges_enabled            boolean,
  payouts_enabled            boolean,
  details_submitted          boolean,
  requirements_due           text[],
  disabled_reason            text,
  stripe_account_id          text,
  tier_id                    text,
  tier_name                  text,
  subscription_monthly_cents integer,
  effective_monthly_cents    integer,
  platform_fee_bps           integer,
  external_payment_url       text,
  business_email             text,
  has_entitlement            boolean,
  entitlement_state          text,
  billing_period             text,
  plan_price_cents           integer,
  plan_user_limit            integer,
  plan_included_users        integer,
  active_users               integer,
  open_invitations           integer,
  can_add_user               boolean,
  period_ends_at             timestamptz,
  will_auto_renew            boolean,
  renews_to_tier_id          text,
  renews_to_period           text,
  offer_type                 integer,
  offer_identifier           text,
  is_free_offer              boolean,
  grace_period_ends_at       timestamptz,
  billing_store              text,
  apple_environment          text,
  seat_limits_enforced       boolean,
  apple_original_transaction_id text
)
language plpgsql stable security definer
set search_path = public
as $$
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
      using errcode = 'TD403', message = 'saasBillingRead';
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
                         or v_ent.user_limit is null
                         or v_ent.active_users + v_ent.open_invitations < v_ent.user_limit;

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

  platform_fee_bps := case
    when coalesce(v_sub.payment_model, 'undecided') = 'externalProvider' then 0
    when coalesce(v_fee_on, true) = false then 0
    else coalesce(v_fee_bps, 0)
  end;

  external_payment_url := v_company_row.online_payment_link_url;
  business_email       := v_company_row.business_email;

  return next;
end $$;

comment on function public.company_commercial_state(uuid) is
  'One authoritative read of the company''s commercial position: Apple subscription entitlement (plan, period, free offer, renewal, grace), user seats, Stripe readiness and the applicable platform fee. Owner-gated. No founding programme.';

revoke all on function public.company_commercial_state(uuid) from public, anon;
grant execute on function public.company_commercial_state(uuid) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 10. Compatibility rewrites of the two older pricing helpers.
-- ---------------------------------------------------------------------------

-- Build 19 renders this. It now recommends the plan that fits a head count.
create or replace function public.subscription_quote(p_users integer default null)
returns table (
  active_paid_users      integer,
  tier_id                text,
  tier_name              text,
  base_cents             integer,
  additional_users       integer,
  additional_user_cents  integer,
  additional_cents       integer,
  monthly_price_cents    integer,
  max_users              integer,
  is_over_capacity       boolean,
  next_user_cents        integer
)
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_users integer;
  v_tier  public.subscription_tiers%rowtype;
  v_next  public.subscription_tiers%rowtype;
begin
  v_users := greatest(coalesce(p_users, public.company_active_paid_users()), 1);

  select * into v_tier from public.subscription_tiers t
   where t.is_active and (t.user_limit is null or t.user_limit >= v_users)
   order by t.sort_order limit 1;

  select * into v_next from public.subscription_tiers t
   where t.is_active and (t.user_limit is null or t.user_limit >= v_users + 1)
   order by t.sort_order limit 1;

  active_paid_users     := v_users;
  tier_id               := v_tier.id;
  tier_name             := v_tier.display_name;
  base_cents            := v_tier.base_cents;
  additional_users      := 0;
  additional_user_cents := 0;
  additional_cents      := 0;
  monthly_price_cents   := v_tier.base_cents;
  max_users             := coalesce(v_tier.user_limit, v_tier.max_users);
  is_over_capacity      := false;
  next_user_cents       := coalesce(v_next.base_cents, v_tier.base_cents) - v_tier.base_cents;
  return next;
end $$;

-- Stores the live head count; the plan itself only ever comes from Apple.
create or replace function public.sync_subscription_seats(p_company uuid default null)
returns table (
  active_paid_users    integer,
  tier_id              text,
  monthly_price_cents  integer
)
language plpgsql volatile security definer
set search_path = public
as $$
declare
  v_company uuid := coalesce(p_company, public.current_company_id());
  v_active  integer;
  v_updated integer;
begin
  if v_company is null then
    raise exception 'No company in context';
  end if;

  select count(*)::integer into v_active
    from public.app_users u where u.company_id = v_company and u.status = 'active';

  update public.company_subscriptions s
     set seat_count = v_active, active_paid_users = v_active,
         seats_synced_at = now(), updated_at = now()
   where s.company_id = v_company;

  get diagnostics v_updated = row_count;
  if v_updated = 0 then
    raise exception 'No subscription row for company %; seats were not synced', v_company
      using errcode = 'no_data_found';
  end if;

  select s.tier_id, s.monthly_price_cents into tier_id, monthly_price_cents
    from public.company_subscriptions s where s.company_id = v_company;
  active_paid_users := v_active;
  return next;
end $$;

revoke all on function public.sync_subscription_seats(uuid) from public, anon, authenticated;
grant execute on function public.sync_subscription_seats(uuid) to service_role;

revoke all on function public.apple_ms(text) from public, anon;
revoke all on function public.subscription_entitlement_state(text, timestamptz, timestamptz, boolean, timestamptz, boolean, boolean, integer, timestamptz) from public, anon;
revoke all on function public.subscription_state_is_entitled(text) from public, anon;
