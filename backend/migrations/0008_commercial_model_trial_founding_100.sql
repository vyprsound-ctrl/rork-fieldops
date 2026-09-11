-- =============================================================================
-- 0008 - COMMERCIAL MODEL: 14-day trial, Founding 100, payment model, business
--        email identity
-- =============================================================================
--
-- WHAT THIS ADDS, AND WHY IT EXTENDS RATHER THAN REPLACES
--
--   There is already exactly one billing architecture in this database:
--   `company_subscriptions` (one row per company) priced by
--   `subscription_quote()` from `subscription_tiers`, plus
--   `stripe_connect_accounts` for the trade business's own Stripe account and
--   `platform_settings.application_fee_bps` for Harbour South's fee. NOTHING
--   here duplicates any of that. This migration:
--
--     1. gives `company_subscriptions` a `payment_model` column, so the
--        company's chosen commercial model is a column on the billing row it
--        already has rather than a second billing system;
--     2. makes the 14-day trial authoritative by giving `trial_ends_at` a
--        default and backfilling the rows that never got one;
--     3. adds ONE new table, `founding_member_slots`, because a global
--        first-100 allocation is not a per-company fact and cannot be
--        expressed as a column on a tenant row without races;
--     4. adds `companies.business_email` — the trade business's own
--        customer-facing reply identity;
--     5. adds read-only, server-authoritative functions the app renders.
--
-- WHAT IT DELIBERATELY DOES NOT DO
--   * No change to Stripe Connect onboarding, PaymentIntents, the webhook,
--     `record_payment_from_stripe`, refunds, reconciliation, SMS credits,
--     recurring services, invitations, push or Engineer V1.
--   * No new fee. 0.30% is `platform_settings.application_fee_bps = 30`, which
--     already exists and is already what `invoice-payment` charges.
--   * No new pricing tier. `subscription_tiers` is untouched.
--   * No lockout. Nothing here gates access to the product; trial state is
--     information, not enforcement.
--
-- SERVER AUTHORITY
--   Founding eligibility is never a parameter. A slot is only ever granted to
--   a company whose `stripe_connect_accounts.charges_enabled` is true, and
--   that column is written exclusively by the Edge Functions from Stripe's own
--   answer under the service role. Monthly qualification is likewise computed
--   here from the `payments` table — a succeeded, customer-paid, Stripe-backed
--   row — and never accepted from a client. There is no "mark me active" path
--   in this file, by design.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Prerequisites. Refuse to build on a schema we do not recognise.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.current_company_id()') is null then
    raise exception 'current_company_id() is missing - refusing to build on an unknown schema';
  end if;
  if to_regprocedure('public.has_perm(app_permission)') is null then
    raise exception 'has_perm(app_permission) is missing - refusing to build on an unknown schema';
  end if;
  if to_regprocedure('public.commerce_company_scope(uuid)') is null then
    raise exception 'commerce_company_scope(uuid) is missing - the tenancy guard this file depends on';
  end if;
  if to_regprocedure('public.push_caller_is_service_role()') is null then
    raise exception 'push_caller_is_service_role() is missing - the service-role test this file depends on';
  end if;
  if to_regprocedure('public.subscription_quote(integer)') is null then
    raise exception 'subscription_quote(integer) is missing - the authoritative price calculation';
  end if;
  if to_regprocedure('public.company_active_paid_users_for(uuid)') is null then
    raise exception 'company_active_paid_users_for(uuid) is missing';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. The two permanent payment models.
--
--   undecided            -- in trial, or the company has not chosen yet
--   harbourSouthPayments -- MODEL A: their own connected Stripe account, with
--                           Harbour South's 0.30% platform fee
--   externalProvider     -- MODEL B: they keep their own payment provider and
--                           supply its customer-facing link. No Harbour South
--                           transaction fee, because Harbour South is not a
--                           party to that payment at all.
--
-- An enum rather than free text: these are the only two models, and a typo
-- must not be able to invent a third commercial arrangement.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'company_payment_model') then
    create type public.company_payment_model as enum
      ('undecided', 'harbourSouthPayments', 'externalProvider');
  end if;
end $$;

alter table public.company_subscriptions
  add column if not exists payment_model public.company_payment_model
    not null default 'undecided';

comment on column public.company_subscriptions.payment_model is
  'Which permanent payment model this company chose. harbourSouthPayments is set by the server when Stripe reports charges_enabled; externalProvider is the company''s own choice. Never invented by a client.';

-- ---------------------------------------------------------------------------
-- 2. The 14-day trial, authoritative server-side.
--
-- `is_trial`, `trial_ends_at` and `status = 'trialing'` already exist. What was
-- missing is that `trial_ends_at` had no default, so the trial end could be
-- NULL — which is not a trial window, it is an absence of one. The column now
-- defaults to 14 days from row creation, and existing NULLs are filled from
-- the row's own created_at so no company silently gains or loses days.
--
-- This is a backfill of NULLs only. No non-null value is rewritten.
-- ---------------------------------------------------------------------------
alter table public.company_subscriptions
  alter column trial_ends_at set default (now() + interval '14 days');

update public.company_subscriptions
   set trial_ends_at = created_at + interval '14 days'
 where trial_ends_at is null;

comment on column public.company_subscriptions.trial_ends_at is
  'End of the 14-day full-featured trial. Server-authoritative: the client never computes or sends this. Nothing in the product is gated on it - it is what the UI counts down.';

-- ---------------------------------------------------------------------------
-- 3. The trade business's customer-facing email identity.
--
-- The invoice a customer receives must look as though it came from the trade
-- business, not from Harbour South. This is the address the business already
-- uses — invoices@…, office@… — and it is used as the reply identity and the
-- visible sender name on invoice email.
--
-- It is deliberately NOT an email-infrastructure setting. There is no DNS,
-- SPF, DKIM, SMTP or API key here, and none is required to use the product.
-- Harbour South's own verified domain remains the transport; this column is
-- who the message is *from*, in the customer's eyes. When authenticated
-- customer-owned sending domains are added later, they attach to this column
-- rather than to invoice generation or billing.
-- ---------------------------------------------------------------------------
alter table public.companies
  add column if not exists business_email text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'companies_business_email_valid'
  ) then
    alter table public.companies
      add constraint companies_business_email_valid check (
        business_email is null
        or (
          length(business_email) between 6 and 254
          and business_email = btrim(business_email)
          and business_email !~ '\s'
          and business_email ~ '^[^@]+@[^@.]+(\.[^@.]+)+$'
        )
      );
  end if;
end $$;

comment on column public.companies.business_email is
  'The business''s own customer-facing / reply-to address. Presentation identity only: no DNS, SPF, DKIM or API key is involved, and Harbour South''s verified domain is still the transport. Extension point for authenticated sending domains later.';

-- ---------------------------------------------------------------------------
-- 4. FOUNDING 100 — the allocation table.
--
-- WHY A TABLE OF SLOTS RATHER THAN A COUNTER
--
-- "The first 100 qualifying businesses" is a global fact, not a company one.
-- A counter column somewhere would have to be read, incremented and written,
-- and two companies completing Stripe onboarding in the same instant would
-- read the same value and both believe they were #42. A column on
-- company_subscriptions has the same problem and no way to prove uniqueness
-- across tenants.
--
-- So the 100 places are 100 rows, seeded once. A claim is an UPDATE of exactly
-- one unclaimed row selected FOR UPDATE SKIP LOCKED, which is the standard
-- Postgres queue-claim: concurrent claimants skip each other's locked rows
-- instead of colliding, `company_id` is UNIQUE so one company can never hold
-- two places, and the PRIMARY KEY on `number` means one number can never be
-- held by two companies. When the 100 rows are all claimed there is simply no
-- row to select, so the offer closes itself — company #101 gets NULL, not #101.
--
-- The number is never destroyed for inactivity. Losing the *benefit* for a
-- month is a derived state (section 6); the slot row is not touched.
-- ---------------------------------------------------------------------------
create table if not exists public.founding_member_slots (
  number      integer primary key check (number between 1 and 100),
  -- Unique: one place per company, enforced by the database and not by code.
  -- ON DELETE SET NULL rather than CASCADE so deleting a company frees its
  -- place instead of deleting one of the hundred rows.
  company_id  uuid unique references public.companies(id) on delete set null,
  claimed_at  timestamptz
);

insert into public.founding_member_slots (number)
select generate_series(1, 100)
on conflict (number) do nothing;

comment on table public.founding_member_slots is
  'The hundred Founding Member places, seeded once. A place is claimed by claim_founding_member_slot() only, and only for a company Stripe has confirmed can take charges. Claimed places are never recycled for inactivity.';

alter table public.founding_member_slots enable row level security;

-- A company may read its OWN place and nothing else. There is no INSERT,
-- UPDATE or DELETE policy at all: the only writer is the SECURITY DEFINER
-- function below, so a user cannot assign themselves a place, change their
-- number, or take another company's.
drop policy if exists founding_member_slots_select on public.founding_member_slots;
create policy founding_member_slots_select on public.founding_member_slots
  for select to authenticated
  using (company_id = public.current_company_id());

grant select on public.founding_member_slots to authenticated;

-- ---------------------------------------------------------------------------
-- 5. Claiming a place.
--
-- Called by `stripe-connect` and by the `account.updated` webhook handler,
-- under the service role, once Stripe itself has said the account can take
-- charges. Eligibility is re-checked HERE from `stripe_connect_accounts`, so
-- the decision does not rest on the caller having checked it.
--
-- Idempotent: a company that already holds a place gets the same number back
-- and nothing is written.
--
-- Returns NULL for "no place" — not connected yet, or all hundred taken.
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
  -- Same tenancy guard every commerce helper uses: the service role may name a
  -- company, a signed-in caller may only ever mean their own, and anything
  -- else resolves to NULL and does nothing.
  v_company := public.commerce_company_scope(p_company);
  if v_company is null then
    return null;
  end if;

  -- Already holds one. The number is stable for the life of the company.
  select number into v_number
    from public.founding_member_slots
   where company_id = v_company;

  if v_number is not null then
    return v_number;
  end if;

  -- THE ELIGIBILITY TEST. `charges_enabled` is written only by the Edge
  -- Functions from Stripe's own account object, under the service role, so it
  -- is not something a client can set, and connecting-but-not-completing
  -- onboarding does not qualify.
  select charges_enabled into v_eligible
    from public.stripe_connect_accounts
   where company_id = v_company;

  if not coalesce(v_eligible, false) then
    return null;
  end if;

  -- Claim exactly one place. SKIP LOCKED is what makes two simultaneous
  -- qualifying companies take two different numbers instead of one.
  with slot as (
    select s.number
      from public.founding_member_slots s
     where s.company_id is null
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

  -- Completing Stripe onboarding IS the act of choosing Model A, so the
  -- company's payment model follows the fact rather than a second question.
  -- Done whether or not a place was available: #101 is still a Harbour South
  -- Payments company, just not a Founding Member.
  update public.company_subscriptions
     set payment_model = 'harbourSouthPayments',
         updated_at    = now()
   where company_id = v_company
     and payment_model <> 'harbourSouthPayments';

  return v_number;
end $$;

comment on function public.claim_founding_member_slot(uuid) is
  'Grants the next Founding Member number to a company Stripe has confirmed can take charges. Concurrency-safe (FOR UPDATE SKIP LOCKED + unique company_id + primary key number). Idempotent. Returns NULL when not eligible or all 100 places are claimed.';

-- ---------------------------------------------------------------------------
-- 6. Monthly qualifying activity.
--
-- A Founding Member keeps the $0/month benefit in any calendar month in which
-- at least ONE customer payment was successfully processed through Harbour
-- South on its connected Stripe account. There is deliberately no minimum
-- amount.
--
-- WHAT QUALIFIES, read from the `payments` table:
--   status = 'succeeded'            -- a payment that actually completed
--   paid_by_customer = true         -- the business's customer paid, not an
--                                      office user typing in a cheque
--   stripe_payment_intent_id not null and stripe_account_id not null
--                                   -- through Harbour South, on their
--                                      connected account
--
-- WHAT DOES NOT QUALIFY, and why it cannot:
--   * connecting Stripe, or opening onboarding — writes no payments row;
--   * creating a PaymentIntent — lives in `payment_intents`, which this does
--     not read;
--   * a failed or cancelled payment — the webhook updates `payment_intents`
--     and deliberately writes no payments row at all;
--   * a refunded payment — its row moves to status 'refunded', so it stops
--     counting here exactly as it stops counting towards the invoice;
--   * a manually recorded payment — paid_by_customer is false and there is no
--     intent id, so cash and cheques do not keep the benefit alive.
--
-- The month boundary is computed in the COMPANY'S OWN timezone, from the
-- database clock. The client never says what month it is.
-- ---------------------------------------------------------------------------
create or replace function public.founding_activity(p_company uuid default null)
returns table (
  month_start                timestamptz,
  qualifying_payments        integer,
  last_qualifying_payment_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_company uuid;
  v_zone    text;
  v_start   timestamptz;
begin
  v_company := public.commerce_company_scope(p_company);

  if v_company is null then
    month_start := null; qualifying_payments := 0; last_qualifying_payment_at := null;
    return next; return;
  end if;

  select c.time_zone_identifier into v_zone from public.companies c where c.id = v_company;
  v_zone := coalesce(nullif(btrim(coalesce(v_zone, '')), ''), 'UTC');

  -- First instant of the current calendar month where the business trades.
  begin
    v_start := (date_trunc('month', (now() at time zone v_zone)))::timestamp at time zone v_zone;
  exception when others then
    -- An unrecognised timezone must not make the whole commercial state fail.
    v_start := date_trunc('month', now());
  end;

  select count(*)::integer, max(p.received_at)
    into qualifying_payments, last_qualifying_payment_at
    from public.payments p
   where p.company_id = v_company
     and p.status = 'succeeded'
     and p.paid_by_customer
     and p.stripe_payment_intent_id is not null
     and p.stripe_account_id is not null
     and p.received_at >= v_start;

  month_start         := v_start;
  qualifying_payments := coalesce(qualifying_payments, 0);
  return next;
end $$;

comment on function public.founding_activity(uuid) is
  'Counts this calendar month''s qualifying customer payments (succeeded, paid_by_customer, through a connected Stripe account) in the company''s own timezone. Failed, cancelled, refunded and manually recorded payments do not qualify.';

-- ---------------------------------------------------------------------------
-- 7. The company's whole commercial state, in one authoritative read.
--
-- Every commercial decision the UI shows is made here, server-side: trial
-- window, Stripe readiness, founding number, whether the founding benefit is
-- active this month, the applicable subscription tier and price, and the
-- platform fee that applies to the company's model. The app renders these
-- values and derives none of them.
--
-- SECURITY DEFINER, so it must do its own permission check — RLS does not
-- apply inside it. Gated on the SaaS billing grants, which in the shipped
-- matrix only the owner holds. No other role gains billing visibility.
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
  v_company  uuid;
  v_sub      public.company_subscriptions%rowtype;
  v_connect  public.stripe_connect_accounts%rowtype;
  v_company_row public.companies%rowtype;
  v_quote    record;
  v_activity record;
  v_fee_bps  integer;
  v_fee_on   boolean;
  v_claimed  integer;
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

  select * into v_company_row from public.companies      where id = v_company;
  select * into v_sub        from public.company_subscriptions where company_id = v_company;
  select * into v_connect    from public.stripe_connect_accounts where company_id = v_company;

  -- Price for the live head count, from the existing authoritative calculator.
  select * into v_quote
    from public.subscription_quote(public.company_active_paid_users_for(v_company));

  select * into v_activity from public.founding_activity(v_company);

  select (value #>> '{}')::integer into v_fee_bps
    from public.platform_settings where key = 'application_fee_bps';
  select (value #>> '{}')::boolean into v_fee_on
    from public.platform_settings where key = 'application_fee_enabled';

  select number, claimed_at into founding_member_number, founding_claimed_at
    from public.founding_member_slots where company_id = v_company;

  select count(*)::integer into v_claimed
    from public.founding_member_slots where company_id is not null;

  payment_model       := coalesce(v_sub.payment_model::text, 'undecided');
  subscription_status := coalesce(v_sub.status::text, 'trialing');

  -- TRIAL. Falls back to the company's own creation date when no subscription
  -- row exists yet, so a company mid-signup still sees a truthful countdown
  -- rather than nothing.
  trial_ends_at := coalesce(
    v_sub.trial_ends_at,
    v_company_row.created_at + interval '14 days'
  );
  is_trial_active := coalesce(v_sub.is_trial, true) and trial_ends_at > now();
  trial_days_remaining := greatest(
    0,
    ceil(extract(epoch from (trial_ends_at - now())) / 86400.0)::integer
  );

  -- STRIPE. Straight from the columns the Edge Functions sync from Stripe.
  stripe_connected  := v_connect.stripe_account_id is not null;
  charges_enabled   := coalesce(v_connect.charges_enabled, false);
  payouts_enabled   := coalesce(v_connect.payouts_enabled, false);
  details_submitted := coalesce(v_connect.details_submitted, false);
  requirements_due  := coalesce(v_connect.requirements_due, '{}'::text[]);
  disabled_reason   := v_connect.disabled_reason;
  stripe_account_id := v_connect.stripe_account_id;

  -- FOUNDING 100.
  founding_places_claimed   := coalesce(v_claimed, 0);
  founding_places_remaining := greatest(0, 100 - founding_places_claimed);
  -- The offer is open while a place remains, OR to the company that already
  -- holds one (so its own screen never reads "offer closed" at itself).
  founding_offer_open := founding_places_remaining > 0
                         or founding_member_number is not null;

  activity_month_start           := v_activity.month_start;
  qualifying_payments_this_month := coalesce(v_activity.qualifying_payments, 0);
  last_qualifying_payment_at     := v_activity.last_qualifying_payment_at;

  -- THE BENEFIT. Holding a number is not enough: the month needs a qualifying
  -- payment. The number itself is unaffected either way.
  founding_benefit_active := founding_member_number is not null
                             and qualifying_payments_this_month > 0;

  tier_id                    := v_quote.tier_id;
  tier_name                  := v_quote.tier_name;
  subscription_monthly_cents := v_quote.monthly_price_cents;

  -- $0/month while the benefit is live; the company's real tier price
  -- otherwise. This is not a discount on a price — it is the Founding Member
  -- commercial status, and it is computed here rather than in the app.
  effective_monthly_cents := case
    when founding_benefit_active then 0
    else v_quote.monthly_price_cents
  end;

  -- MODEL B pays no Harbour South transaction fee, because Harbour South never
  -- touches that payment. MODEL A pays the platform rate, which lives in
  -- platform_settings and is not compiled into anything.
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
  'One authoritative read of the company''s commercial position: trial window, Stripe readiness, Founding Member number and monthly benefit, tier price, effective price and applicable platform fee. Owner-gated. The client renders this and computes none of it.';

-- ---------------------------------------------------------------------------
-- 8. Choosing MODEL B (or going back to undecided).
--
-- A company may declare that it keeps its own payment provider. It may NOT
-- declare itself a Harbour South Payments company: that follows from Stripe
-- reporting charges_enabled, and is set by claim_founding_member_slot() under
-- the service role. Refusing it here is what stops "set my model to Stripe"
-- from being a way to reach for a fee change or a founding place.
-- ---------------------------------------------------------------------------
create or replace function public.set_company_payment_model(p_model public.company_payment_model)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_company uuid := public.current_company_id();
begin
  if v_company is null then
    raise exception 'Not signed in.' using errcode = 'TD401', message = 'saasBillingManage';
  end if;
  if not coalesce(public.has_perm('saasBillingManage'::app_permission), false) then
    raise exception 'Only the account owner can change the payment model.'
      using errcode = 'TD403', message = 'saasBillingManage';
  end if;
  if p_model = 'harbourSouthPayments' then
    raise exception 'Connect Stripe to move onto Harbour South Payments.'
      using errcode = 'TD422';
  end if;

  update public.company_subscriptions
     set payment_model = p_model,
         updated_at    = now()
   where company_id = v_company;

  if not found then
    raise exception 'No subscription record for this company.' using errcode = 'TD404';
  end if;
end $$;

comment on function public.set_company_payment_model(public.company_payment_model) is
  'Owner-only. Records that the company keeps its own payment provider, or clears the choice. Cannot be used to claim Harbour South Payments - that is set server-side from Stripe.';

-- ---------------------------------------------------------------------------
-- 9. Grants.
--
-- `anon` gets nothing. `claim_founding_member_slot` is service-role only: it
-- is called by the Stripe Edge Functions after Stripe has confirmed the
-- account, and is not something a signed-in user may invoke at all.
-- ---------------------------------------------------------------------------
revoke all on function public.claim_founding_member_slot(uuid)                      from public, anon, authenticated;
revoke all on function public.founding_activity(uuid)                               from public, anon;
revoke all on function public.company_commercial_state(uuid)                        from public, anon;
revoke all on function public.set_company_payment_model(public.company_payment_model) from public, anon;

grant execute on function public.founding_activity(uuid)                               to authenticated;
grant execute on function public.company_commercial_state(uuid)                        to authenticated;
grant execute on function public.set_company_payment_model(public.company_payment_model) to authenticated;
