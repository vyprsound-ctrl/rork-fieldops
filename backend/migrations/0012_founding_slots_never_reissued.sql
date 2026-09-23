-- =============================================================================
-- 0012 - FOUNDING 100: a claimed place is never reissued
-- =============================================================================
--
-- THE DEFECT
--
--   0008 declared `founding_member_slots.company_id ... on delete set null`
--   and `claim_founding_member_slot()` treated any row with
--   `company_id is null` as free. So if the company holding place 37 was ever
--   deleted, place 37 went back into the pool and the next qualifying company
--   - which could be the 101st, 150th or 400th - became a Founding Member.
--   `company_commercial_state()` counted "claimed" the same way, so a deletion
--   also re-opened the offer to everybody.
--
-- THE RULE THIS MIGRATION ENFORCES
--
--   The hundred places are the first hundred founding ALLOCATIONS EVER MADE,
--   not the first hundred companies that currently exist. Once a place has
--   been claimed it is permanently retired: `claimed_at` is the permanent
--   record that it was allocated, and it is never cleared.
--
-- WHAT CHANGES - founding-member claim logic only
--
--   1. `claim_founding_member_slot()` only ever takes a place whose
--      `claimed_at is null` (never allocated), serialises claims for the same
--      company so a duplicate simultaneous claim returns the existing number
--      instead of failing, and is otherwise unchanged: same signature, same
--      eligibility test (`charges_enabled`), same SKIP LOCKED queue claim,
--      same payment-model follow-through.
--   2. `company_commercial_state()` counts places taken by `claimed_at`, so a
--      deleted founding company's place still counts as taken and the offer
--      closes after the hundredth allocation ever. Every other line of the
--      function is reproduced exactly as deployed.
--   3. A guard trigger on `founding_member_slots` refuses any write that would
--      un-claim, reassign or delete an allocated place. The only write it
--      permits on an allocated row is the `on delete set null` the foreign
--      key itself performs when the holding company is deleted.
--
-- WHAT IT DOES NOT TOUCH
--   No table or column is added, altered or dropped. No RLS policy, grant,
--   Stripe table, payment, fee, `platform_settings` row, Storage object or
--   Edge Function changes. The qualification requirement for a place is
--   unchanged. The Edge Functions call the same function with the same
--   argument and get the same kind of answer.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Prerequisites and data sanity.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.founding_member_slots') is null then
    raise exception 'founding_member_slots is missing - apply 0008 first';
  end if;
  if to_regprocedure('public.claim_founding_member_slot(uuid)') is null then
    raise exception 'claim_founding_member_slot(uuid) is missing - apply 0008 first';
  end if;
  if to_regprocedure('public.company_commercial_state(uuid)') is null then
    raise exception 'company_commercial_state(uuid) is missing - apply 0008 first';
  end if;
  -- A held place with no claim time would be invisible to the new count.
  -- 0008 always wrote both together, so this is a refusal to guess, not a
  -- state expected to exist.
  if exists (
    select 1 from public.founding_member_slots
     where company_id is not null and claimed_at is null
  ) then
    raise exception 'A founding place is held without a claim time - refusing to reinterpret it';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Claiming a place.
-- ---------------------------------------------------------------------------
create or replace function public.claim_founding_member_slot(p_company uuid default null)
returns integer
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_company  uuid;
  v_number   integer;
  v_eligible boolean;
begin
  -- Same tenancy guard every commerce helper uses.
  v_company := public.commerce_company_scope(p_company);
  if v_company is null then
    return null;
  end if;

  -- One claim at a time PER COMPANY. `stripe-connect` and the
  -- `account.updated` webhook can both arrive for the same company in the
  -- same instant. Without this, each would take a different free place and
  -- the second would then fail on the unique `company_id`. Holding a
  -- transaction-scoped lock keyed on the company means the second waits,
  -- then sees the first's committed place below and returns it. Different
  -- companies never contend on this lock.
  perform pg_advisory_xact_lock(hashtextextended('founding_member_slot:' || v_company::text, 0));

  -- Already holds one. The number is stable for the life of the company.
  select number into v_number
    from public.founding_member_slots
   where company_id = v_company;

  if v_number is not null then
    return v_number;
  end if;

  -- THE ELIGIBILITY TEST - unchanged from 0008.
  select charges_enabled into v_eligible
    from public.stripe_connect_accounts
   where company_id = v_company;

  if not coalesce(v_eligible, false) then
    return null;
  end if;

  -- Claim exactly one NEVER-ALLOCATED place. `claimed_at is null` - not
  -- `company_id is null` - is the test: a place whose company was deleted
  -- keeps its claim time and is permanently retired. SKIP LOCKED is what
  -- makes two simultaneous qualifying companies take two different numbers.
  with slot as (
    select s.number
      from public.founding_member_slots s
     where s.claimed_at is null
       and s.company_id is null
     order by s.number
       for update skip locked
     limit 1
  )
  update public.founding_member_slots t
     set company_id = v_company,
         claimed_at = now()
    from slot
   where t.number = slot.number
  returning t.number into v_number;

  -- Completing Stripe onboarding IS the act of choosing Model A - unchanged.
  update public.company_subscriptions
     set payment_model = 'harbourSouthPayments',
         updated_at    = now()
   where company_id = v_company
     and payment_model <> 'harbourSouthPayments';

  return v_number;
exception
  -- Belt and braces behind the advisory lock: if the unique `company_id`
  -- ever trips, this company already holds a place, so return it.
  when unique_violation then
    select number into v_number
      from public.founding_member_slots
     where company_id = v_company;
    return v_number;
end $$;

comment on function public.claim_founding_member_slot(uuid) is
  'Grants the next never-allocated Founding Member number to a company Stripe has confirmed can take charges. A place, once claimed, is never reissued - not even after its company is deleted. Concurrency-safe (per-company advisory lock + FOR UPDATE SKIP LOCKED + unique company_id + primary key number). Idempotent. Returns NULL when not eligible or all 100 places have ever been claimed.';

-- Grants are preserved by CREATE OR REPLACE; restated so this file is
-- self-describing. Service role only, exactly as 0008.
revoke all on function public.claim_founding_member_slot(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. The commercial state read.
--
-- Reproduced exactly as deployed, with ONE change: places taken are counted
-- by `claimed_at is not null` instead of `company_id is not null`.
-- ---------------------------------------------------------------------------
create or replace function public.company_commercial_state(p_company uuid default null)
returns table (
  payment_model                  text,
  subscription_status            text,
  trial_ends_at                  timestamptz,
  trial_days_remaining           integer,
  is_trial_active                boolean,
  stripe_connected               boolean,
  charges_enabled                boolean,
  payouts_enabled                boolean,
  details_submitted              boolean,
  requirements_due               text[],
  disabled_reason                text,
  stripe_account_id              text,
  founding_member_number         integer,
  founding_claimed_at            timestamptz,
  founding_places_claimed        integer,
  founding_places_remaining      integer,
  founding_offer_open            boolean,
  founding_benefit_active        boolean,
  qualifying_payments_this_month integer,
  last_qualifying_payment_at     timestamptz,
  activity_month_start           timestamptz,
  tier_id                        text,
  tier_name                      text,
  subscription_monthly_cents     integer,
  effective_monthly_cents        integer,
  platform_fee_bps               integer,
  external_payment_url           text,
  business_email                 text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_company     uuid;
  v_sub         public.company_subscriptions%rowtype;
  v_connect     public.stripe_connect_accounts%rowtype;
  v_company_row public.companies%rowtype;
  v_quote       record;
  v_activity    record;
  v_fee_bps     integer;
  v_fee_on      boolean;
  v_claimed     integer;
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

  select * into v_company_row from public.companies where id = v_company;
  select * into v_sub from public.company_subscriptions where company_id = v_company;
  select * into v_connect from public.stripe_connect_accounts where company_id = v_company;

  select * into v_quote
    from public.subscription_quote(public.company_active_paid_users_for(v_company));

  select * into v_activity from public.founding_activity(v_company);

  select (value #>> '{}')::integer into v_fee_bps
    from public.platform_settings where key = 'application_fee_bps';
  select (value #>> '{}')::boolean into v_fee_on
    from public.platform_settings where key = 'application_fee_enabled';

  select number, claimed_at into founding_member_number, founding_claimed_at
    from public.founding_member_slots where company_id = v_company;

  -- 0012: every place EVER allocated counts, including one whose company has
  -- since been deleted. That is what closes the offer after the hundredth
  -- allocation rather than re-opening it on a deletion.
  select count(*)::integer into v_claimed
    from public.founding_member_slots where claimed_at is not null;

  payment_model       := coalesce(v_sub.payment_model::text, 'undecided');
  subscription_status := coalesce(v_sub.status::text, 'trialing');

  trial_ends_at := coalesce(
    v_sub.trial_ends_at,
    v_company_row.created_at + interval '14 days'
  );
  is_trial_active := coalesce(v_sub.is_trial, true) and trial_ends_at > now();
  trial_days_remaining := greatest(
    0,
    ceil(extract(epoch from (trial_ends_at - now())) / 86400.0)::integer
  );

  stripe_connected  := v_connect.stripe_account_id is not null;
  charges_enabled   := coalesce(v_connect.charges_enabled, false);
  payouts_enabled   := coalesce(v_connect.payouts_enabled, false);
  details_submitted := coalesce(v_connect.details_submitted, false);
  requirements_due  := coalesce(v_connect.requirements_due, '{}'::text[]);
  disabled_reason   := v_connect.disabled_reason;
  stripe_account_id := v_connect.stripe_account_id;

  founding_places_claimed   := coalesce(v_claimed, 0);
  founding_places_remaining := greatest(0, 100 - founding_places_claimed);
  founding_offer_open := founding_places_remaining > 0
                         or founding_member_number is not null;

  activity_month_start           := v_activity.month_start;
  qualifying_payments_this_month := coalesce(v_activity.qualifying_payments, 0);
  last_qualifying_payment_at     := v_activity.last_qualifying_payment_at;

  founding_benefit_active := founding_member_number is not null
                             and qualifying_payments_this_month > 0;

  tier_id                    := v_quote.tier_id;
  tier_name                  := v_quote.tier_name;
  subscription_monthly_cents := v_quote.monthly_price_cents;

  effective_monthly_cents := case
    when founding_benefit_active then 0
    else v_quote.monthly_price_cents
  end;

  platform_fee_bps := case
    when coalesce(v_sub.payment_model, 'undecided') = 'externalProvider' then 0
    when coalesce(v_fee_on, true) = false then 0
    else coalesce(v_fee_bps, 0)
  end;

  external_payment_url := v_company_row.online_payment_link_url;
  business_email       := v_company_row.business_email;

  return next;
end $$;

-- ---------------------------------------------------------------------------
-- 3. An allocated place is immutable.
--
-- The claim function is the only writer, and it only ever writes a
-- never-allocated row. This trigger makes that a database guarantee rather
-- than a convention, so no future function, script or console session can
-- recycle a place by accident.
--
-- Permitted on an allocated row: `company_id` becoming NULL with `claimed_at`
-- unchanged - which is exactly the `on delete set null` performed when the
-- holding company is deleted. The place stays retired.
-- ---------------------------------------------------------------------------
create or replace function public.founding_member_slots_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Founding Member places are permanent and cannot be deleted (place %).', old.number
      using errcode = 'TD409';
  end if;

  if old.claimed_at is not null then
    if new.number is distinct from old.number
       or new.claimed_at is distinct from old.claimed_at
       or (new.company_id is not null and new.company_id is distinct from old.company_id) then
      raise exception 'Founding Member place % has been allocated and can never be reissued.', old.number
        using errcode = 'TD409';
    end if;
  end if;

  return new;
end $$;

revoke all on function public.founding_member_slots_guard() from public, anon, authenticated;

drop trigger if exists founding_member_slots_guard on public.founding_member_slots;
create trigger founding_member_slots_guard
  before update or delete on public.founding_member_slots
  for each row execute function public.founding_member_slots_guard();

comment on table public.founding_member_slots is
  'The hundred Founding Member places, seeded once. A place is claimed by claim_founding_member_slot() only, and only for a company Stripe has confirmed can take charges. Once claimed (claimed_at set) a place is permanently retired: never recycled for inactivity and never reissued, even if its company is deleted.';
