-- =============================================================================
-- Harbour South FieldOps — PHASE 2 PREREQUISITE: ENUM VALUES
-- =============================================================================
--
--  STATUS: WRITTEN, NOT APPLIED.
--
--  WHY THIS IS A MIGRATION OF ITS OWN, AND NOT THE TOP OF 0004.
--
--  PostgreSQL will not let a newly added enum value be *used* in the same
--  transaction that added it. The value exists in the catalogue immediately,
--  but any attempt to evaluate the label — a cast, a DEFAULT, a CHECK
--  constraint, an index predicate, a seed INSERT, or the parse analysis of a
--  `language sql` function body — raises SQLSTATE 55P04:
--
--      ERROR:  unsafe use of new value "stripe" of enum type payment_method
--      HINT:   New enum values must be committed before they can be used.
--
--  (Before PostgreSQL 12 it was stricter still: ALTER TYPE ... ADD VALUE could
--  not run inside a transaction block at all. Supabase runs 15+, so the
--  statements below are legal inside a transaction; only their *use* is not.)
--
--  Every migration file is applied as one transaction, so the only structural
--  fix is a transaction boundary between adding the labels and using them —
--  i.e. a separate migration that commits first. This is exactly what
--  Supabase's own schema-diff tooling does: it splits ALTER TYPE ... ADD VALUE
--  and any later statement into separate migration units specifically to avoid
--  55P04.
--
--  The alternative — one file, with a manual "run section 0 on its own first"
--  instruction — is not a migration. It cannot be replayed onto a fresh
--  database, a second environment or a restored backup without a human
--  remembering the pre-step, and a half-applied 0004 is the worst outcome
--  available. Hence: two files, applied in order, by the normal mechanism.
--
--  ORDER: 0002 -> 0003 (this file) -> 0004.
--  This file depends on nothing in 0002 and 0002 references none of these
--  labels, so the two are independent; the numbering simply keeps them in
--  order for any tool that applies migrations by filename.
--
--  APPLY WITH, from an authenticated shell:
--    supabase db push --project-ref srfnfimskixjqjyyftak
--
--  ADDING A VALUE IS PERMANENT. PostgreSQL has no ALTER TYPE ... DROP VALUE.
--  Every label below is therefore additive by design: no existing label is
--  renamed or removed, and every row already in the database stays valid.
--
--  IF NOT EXISTS makes each statement a no-op on a database that already has
--  the label, so re-running this file cannot duplicate a value or fail.
-- =============================================================================

-- Deliberately no BEGIN/COMMIT in this file. It carries no dependent objects,
-- so it is correct whether the applying tool wraps it in a transaction or not.

do $$
begin
  if current_setting('server_version_num')::integer < 120000 then
    raise exception
      'This migration requires PostgreSQL 12 or later (found %)',
      current_setting('server_version')
      using hint = 'Before 12, ALTER TYPE ... ADD VALUE cannot run inside a '
                   'transaction block at all, so each statement below would '
                   'have to be sent on its own.';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- subscription_plan — two more tiers
-- -----------------------------------------------------------------------------
-- Phase 1 shipped soloTrader / team / business, which is three names for a
-- four-tier price list. 'business' is NOT removed: existing rows keep it and
-- the seat calculator in 0004 treats it as a synonym for 'growingBusiness'.
alter type public.subscription_plan add value if not exists 'growingBusiness';
alter type public.subscription_plan add value if not exists 'largerBusiness';

-- -----------------------------------------------------------------------------
-- notification_status — the Twilio states Phase 1 could not record
-- -----------------------------------------------------------------------------
-- Twilio reports more than "sent" and "delivered". Without these two labels an
-- undelivered message has to be recorded as a plain failure, which loses the
-- distinction that decides whether an SMS credit is refunded.
--   accepted    — Twilio has the message but has not attempted the carrier yet.
--   undelivered — the carrier rejected it. Refundable; not a system failure.
alter type public.notification_status add value if not exists 'accepted';
alter type public.notification_status add value if not exists 'undelivered';

-- -----------------------------------------------------------------------------
-- payment_status — a card payment is not instantaneous
-- -----------------------------------------------------------------------------
--   processing — confirmed with Stripe, webhook not yet received.
--   cancelled  — an abandoned intent.
-- Neither is a failure, and neither may be allowed to look like success.
alter type public.payment_status add value if not exists 'processing';
alter type public.payment_status add value if not exists 'cancelled';

-- -----------------------------------------------------------------------------
-- payment_method — how customer card money actually arrives
-- -----------------------------------------------------------------------------
-- Neither card-on-file taken by the office nor cash in hand. Used by
-- record_payment_from_stripe() in 0004.
alter type public.payment_method add value if not exists 'stripe';

-- -----------------------------------------------------------------------------
-- service_frequency — a period the four fixed options cannot express
-- -----------------------------------------------------------------------------
-- Paired with service_agreements.interval_days, added in 0004.
alter type public.service_frequency add value if not exists 'custom';


-- =============================================================================
-- VERIFICATION — run after this migration and BEFORE 0004
-- =============================================================================
--
-- 1. All eight labels present. Expect eight rows:
--
--      select t.typname, e.enumlabel
--      from pg_enum e
--      join pg_type t on t.oid = e.enumtypid
--      join pg_namespace n on n.oid = t.typnamespace
--      where n.nspname = 'public'
--        and (t.typname, e.enumlabel) in (
--          ('subscription_plan',   'growingBusiness'),
--          ('subscription_plan',   'largerBusiness'),
--          ('notification_status', 'accepted'),
--          ('notification_status', 'undelivered'),
--          ('payment_status',      'processing'),
--          ('payment_status',      'cancelled'),
--          ('payment_method',      'stripe'),
--          ('service_frequency',   'custom')
--        )
--      order by 1, 2;
--
-- 2. Nothing pre-existing was disturbed. These must all still be listed:
--
--      select t.typname, array_agg(e.enumlabel order by e.enumsortorder)
--      from pg_enum e
--      join pg_type t on t.oid = e.enumtypid
--      where t.typname in ('subscription_plan','notification_status',
--                          'payment_status','payment_method','service_frequency')
--      group by 1;
--
--    subscription_plan must still contain soloTrader, team and business.
--
-- 3. The labels are COMMITTED and therefore usable. In a NEW session, all four
--    of these must return a value rather than SQLSTATE 55P04:
--
--      select 'stripe'::text::public.payment_method,
--             'custom'::text::public.service_frequency,
--             'undelivered'::text::public.notification_status,
--             'growingBusiness'::text::public.subscription_plan;
--
--    0004 begins by running exactly this check and refuses to apply if it
--    fails, so a mis-ordered deployment stops before it creates anything.
-- =============================================================================
