-- 0009 — Correction pass after the Build 10 forensic audit.
--
-- Two changes, both surgical. No table, column, tier, price, trial or
-- Founding-100 rule is touched.
--
-- 1. public.subscription_quote(integer) has raised SQLSTATE 42702 —
--    'column reference "max_users" is ambiguous' — since migration 0004.
--    The function declares an OUT column named max_users in its
--    `returns table (...)` clause AND reads subscription_tiers.max_users in
--    two tier-lookup SELECTs. Inside PL/pgSQL both names are in scope, so
--    PostgreSQL refuses to guess.
--
--    This broke the Subscription screen from the day 0004 shipped. Migration
--    0008 widened the blast radius by having company_commercial_state() call
--    subscription_quote(), so the trial card, the Founding Member badge and
--    the Payments screen inherited the same failure.
--
--    The fix is the narrowest one available: alias the table as `t` and
--    qualify the two column reads. The function's signature, its output
--    column names, its ordering and every value it computes are unchanged,
--    so nothing that consumes it has to change.
--
-- 2. Revoke EXECUTE from `anon` on RPCs that already require a signed-in
--    caller. Every one of them derefences auth.uid() or current_company_id()
--    and is useless to an anonymous caller; the grant was surplus.
--
--    Deliberately NOT revoked: has_perm, current_company_id, current_app_role,
--    is_assigned_to_job, commerce_company_scope, company_active_paid_users
--    and the trigger functions. Those are evaluated INSIDE RLS policies, and
--    removing anon's EXECUTE would turn a policy that currently returns zero
--    rows into a hard permission error. RLS already yields nothing to anon,
--    so there is no privilege to withdraw there.

-- ---------------------------------------------------------------------------
-- 1. subscription_quote — remove the max_users ambiguity
-- ---------------------------------------------------------------------------

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
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_users   integer;
  v_max     integer;
  v_tier    public.subscription_tiers%rowtype;
  v_next    public.subscription_tiers%rowtype;
  v_addl    integer;
begin
  v_users := greatest(coalesce(p_users, public.company_active_paid_users()), 1);

  select (value #>> '{}')::integer into v_max
  from public.platform_settings where key = 'subscription_max_users';
  v_max := coalesce(v_max, 100);

  -- Clamp tier lookup to the supported band so a company that has somehow
  -- exceeded the ceiling still gets a truthful price rather than nothing.
  --
  -- `t.` is the whole fix: without the alias, `max_users` here resolves
  -- ambiguously against this function's OUT parameter of the same name.
  select * into v_tier
  from public.subscription_tiers t
  where t.is_active and least(v_users, v_max) between t.min_users and t.max_users
  order by t.sort_order
  limit 1;

  if not found then
    select * into v_tier from public.subscription_tiers t
    where t.is_active order by t.sort_order desc limit 1;
  end if;

  v_addl := greatest(v_users - 1, 0);

  -- The rate for the seat *after* this one, which may sit in the next tier and
  -- is what the "add a user" price in the app must show.
  select * into v_next
  from public.subscription_tiers t
  where t.is_active and least(v_users + 1, v_max) between t.min_users and t.max_users
  order by t.sort_order
  limit 1;

  active_paid_users     := v_users;
  tier_id               := v_tier.id;
  tier_name             := v_tier.display_name;
  base_cents            := v_tier.base_cents;
  additional_users      := v_addl;
  additional_user_cents := v_tier.additional_user_cents;
  additional_cents      := v_addl * v_tier.additional_user_cents;
  monthly_price_cents   := v_tier.base_cents + (v_addl * v_tier.additional_user_cents);
  max_users             := v_max;
  is_over_capacity      := v_users > v_max;
  -- Price of the next seat = new total minus current total, so a tier change
  -- shows its true (possibly negative) marginal cost rather than a sticker rate.
  next_user_cents       := case
                             when v_users >= v_max then null
                             else (v_next.base_cents + (v_users * v_next.additional_user_cents))
                                  - (v_tier.base_cents + (v_addl * v_tier.additional_user_cents))
                           end;
  return next;
end $$;

-- ---------------------------------------------------------------------------
-- 2. Withdraw the surplus anon EXECUTE grants
-- ---------------------------------------------------------------------------

do $$
declare
  v_name text;
  v_sig  text;
begin
  foreach v_name in array array[
    'create_job',
    'create_company_and_owner',
    'accept_invitation',
    'create_invitation',
    'revoke_invitation',
    'issue_invoice_share_token',
    'revoke_invoice_share_tokens',
    'consume_sms_credit',
    'sms_credit_balance',
    'register_push_device',
    'unregister_push_device',
    'subscription_quote'
  ]
  loop
    for v_sig in
      select p.oid::regprocedure::text
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = v_name
    loop
      execute format('revoke execute on function %s from anon', v_sig);
    end loop;
  end loop;
end $$;

-- `authenticated` must keep every one of those grants. This proves it rather
-- than assuming it: if the revoke above ever over-reaches, the migration fails
-- here instead of shipping a silently broken app.
do $$
declare
  v_missing text;
begin
  select string_agg(p.proname, ', ')
  into v_missing
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'create_job', 'create_company_and_owner', 'accept_invitation',
      'create_invitation', 'revoke_invitation', 'issue_invoice_share_token',
      'revoke_invoice_share_tokens', 'consume_sms_credit', 'sms_credit_balance',
      'register_push_device', 'unregister_push_device', 'subscription_quote'
    )
    and not has_function_privilege('authenticated', p.oid, 'EXECUTE');

  if v_missing is not null then
    raise exception 'authenticated lost EXECUTE on: %', v_missing;
  end if;
end $$;
