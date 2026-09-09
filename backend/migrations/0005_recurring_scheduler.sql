-- =============================================================================
-- 0005 — RECURRING SERVICE SCHEDULER
-- =============================================================================
-- WHAT WAS MISSING.
--
-- 0004 defined `generate_due_recurring_jobs`, and the `recurring-tick` Edge
-- Function calls it correctly. Nothing ever called the Edge Function. A
-- maintenance contract that only produces its next visit when somebody happens
-- to open the app is not a maintenance contract, so recurring service was
-- effectively inert in production.
--
-- WHAT THIS MIGRATION DOES.
--
-- Adds the missing trigger, and nothing else. It does NOT define a second
-- generator: `run_recurring_tick` delegates to the existing
-- `generate_due_recurring_jobs`, which keeps sole ownership of what a due
-- visit is, how it is numbered, and how duplicates are prevented.
--
-- WHY IN-DATABASE RATHER THAN AN HTTP CALL TO THE EDGE FUNCTION.
--
-- pg_cron runs inside Postgres, so the tick needs no shared secret, no
-- outbound network call, and no public endpoint. Scheduling an HTTP POST to
-- `recurring-tick` would mean pg_net plus a CRON_SECRET stored in the
-- database — a second copy of a credential, and a new failure mode (network),
-- for a job whose entire body is one SQL function call. The Edge Function
-- stays deployed and useful for manual/backfill runs; this is the unattended
-- path.
--
-- IDEMPOTENCY IS UNCHANGED. Duplicate prevention still lives where it did: the
-- partial unique index on (service_agreement_id, generated_for_date) and the
-- ON CONFLICT DO NOTHING inside generate_due_recurring_jobs. This migration
-- adds no new duplicate-prevention logic because none is needed.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. The scheduled entry point
-- -----------------------------------------------------------------------------
-- A thin, auditable wrapper. Its only additions over calling the generator
-- directly are (a) an advisory lock, and (b) a counted summary that lands in
-- cron.job_run_details so a silent no-op is distinguishable from a silent
-- failure after the fact.
create or replace function public.run_recurring_tick(p_horizon_days integer default 0)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  r           record;
  v_considered integer := 0;
  v_generated  integer := 0;
  v_already    integer := 0;
  v_failed     integer := 0;
  v_failures   text[]  := array[]::text[];
begin
  -- CONCURRENCY. Overlapping ticks are already incapable of producing a
  -- duplicate visit — the unique index arbitrates that. What they DO produce
  -- is wasted job numbers: the loser of the race has already allocated a
  -- number from the company's sequence before its insert loses, leaving a gap
  -- in that company's job numbering. Taking the lock means a second tick that
  -- starts while one is still running returns immediately instead of burning
  -- numbers. Transaction-scoped, so it is released even if this raises.
  if not pg_try_advisory_xact_lock(hashtext('harbour_south_recurring_tick')) then
    return jsonb_build_object(
      'ran', false,
      'skipped', 'a recurring tick was already running'
    );
  end if;

  -- Every company, in one pass. Company scoping is not this function's job and
  -- is deliberately not re-implemented here: the generator selects agreements
  -- by their own company_id and writes each job into that same company, so
  -- isolation is a property of the row being copied, not of a filter applied
  -- by the caller.
  for r in select * from public.generate_due_recurring_jobs(null, p_horizon_days) loop
    v_considered := v_considered + 1;

    if r.outcome = 'generated' then
      v_generated := v_generated + 1;
    elsif r.outcome = 'alreadyGenerated' then
      v_already := v_already + 1;
    else
      -- A failure on one agreement must not abandon the others: the generator
      -- already caught it per-row and reported it as a 'failed: ...' outcome.
      -- Surfacing it as a warning puts it in the Postgres log and in this
      -- run's return value rather than losing it.
      v_failed := v_failed + 1;
      v_failures := v_failures || (r.service_agreement_id::text || ': ' || r.outcome);
      raise warning '[recurring-tick] agreement % did not generate: %',
        r.service_agreement_id, r.outcome;
    end if;
  end loop;

  return jsonb_build_object(
    'ran', true,
    'at', now(),
    'horizonDays', greatest(coalesce(p_horizon_days, 0), 0),
    'considered', v_considered,
    'generated', v_generated,
    'alreadyGenerated', v_already,
    'failed', v_failed,
    'failures', to_jsonb(v_failures)
  );
end $$;

-- -----------------------------------------------------------------------------
-- 2. EXECUTE privileges
-- -----------------------------------------------------------------------------
-- Same model as section 9 of 0004: strip the PUBLIC default that CREATE
-- FUNCTION grants automatically, then grant only to the roles with a reason to
-- call it. This function generates jobs across EVERY company, so an app user
-- must never be able to invoke it — over PostgREST or otherwise.
revoke execute on function public.run_recurring_tick(integer) from public;
revoke execute on function public.run_recurring_tick(integer) from anon, authenticated;

-- service_role: the recurring-tick Edge Function, for a manual or backfill run.
grant execute on function public.run_recurring_tick(integer) to service_role;
-- postgres: the identity pg_cron runs the schedule as.
grant execute on function public.run_recurring_tick(integer) to postgres;

commit;
