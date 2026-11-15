-- =============================================================================
-- 0019 - Web subscriptions through Stripe: schema only
-- =============================================================================
-- Additive only. Nothing existing is changed:
--   * billing_store gains the value 'stripe'. Existing rows keep 'apple' or
--     'none'. The iPhone app decodes an unknown store as "none", so 1.1.0 is
--     unaffected.
--   * company_subscriptions gains four Stripe-only columns. Apple never reads
--     or writes them. They are filled only by the stripe-webhook function
--     (service role) through apply_stripe_subscription() in 0020.
--
-- The enum value is added in its own migration because Postgres does not let
-- a new enum value be used in the same transaction that adds it.

alter type public.billing_store add value if not exists 'stripe';

alter table public.company_subscriptions
  add column if not exists stripe_status               text,
  add column if not exists stripe_current_period_end   timestamptz,
  add column if not exists stripe_cancel_at_period_end boolean not null default false,
  add column if not exists stripe_synced_at            timestamptz;

create unique index if not exists company_subscriptions_stripe_subscription_idx
  on public.company_subscriptions (stripe_subscription_id)
  where stripe_subscription_id is not null;
