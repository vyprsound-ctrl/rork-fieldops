-- =============================================================================
-- 0006 — FIX: generate_due_recurring_jobs could never generate anything
-- =============================================================================
-- THE BUG.
--
-- 0004 declared the generator with OUT parameters named after the columns it
-- queries:
--
--   returns table (service_agreement_id uuid, job_id uuid, ...)
--
-- and then, inside the body, tested the already-generated case with:
--
--   if exists (select 1 from public.jobs
--              where service_agreement_id = r.id
--                and generated_for_date   = r.next_due_date)
--
-- In PL/pgSQL `service_agreement_id` there is BOTH an OUT parameter and a
-- column of public.jobs, so the reference is ambiguous and Postgres raises
--
--   42702: column reference "service_agreement_id" is ambiguous
--
-- That IF sits before the per-agreement BEGIN/EXCEPTION block, so the error is
-- not caught and reported as a 'failed:' row — it aborts the entire function.
-- The failure is also invisible until an agreement is actually due: with no due
-- agreements the loop body never executes and the function returns cleanly.
--
-- CONSEQUENCE. Recurring generation has never worked. Every call with at least
-- one due agreement raised 42702 and created no job. It went unnoticed because
-- 0005 was the first thing ever to call it on a schedule; before that nothing
-- invoked it at all.
--
-- THE FIX. One line: `#variable_conflict use_column`, which tells PL/pgSQL to
-- resolve an ambiguous name to the COLUMN rather than the variable. That is the
-- correct reading at every ambiguous site in this function:
--
--   * the `if exists (...)` probe above, and
--   * the ON CONFLICT index-inference predicate, which restates the partial
--     index's `service_agreement_id is not null and generated_for_date is not
--     null` and is ambiguous for exactly the same reason.
--
-- The body is otherwise reproduced from 0004 unchanged, deliberately: the
-- generation rules, the numbering, the duplicate prevention and the returned
-- outcomes are all as they were. Renaming the OUT parameters would have been
-- the other fix, but those names are the function's public result columns —
-- the recurring-tick Edge Function and run_recurring_tick both read them — so
-- renaming would have broken callers to work around a name collision.
-- =============================================================================

begin;

create or replace function public.generate_due_recurring_jobs(
  p_company uuid default null,
  p_horizon_days integer default 0
)
returns table (
  service_agreement_id uuid,
  job_id               uuid,
  scheduled_for        date,
  outcome              text
)
language plpgsql
volatile
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  r          record;
  v_job      uuid;
  v_number   text;
  v_horizon  date := current_date + (greatest(coalesce(p_horizon_days, 0), 0) || ' days')::interval;
begin
  for r in
    select a.*, c.time_zone_identifier
    from public.service_agreements a
    join public.companies c on c.id = a.company_id
    where a.is_active
      and a.next_due_date <= v_horizon::date
      and (p_company is null or a.company_id = p_company)
    order by a.next_due_date
  loop
    v_job := null;
    v_number := null;

    -- Already generated for this period by an earlier run. Checked BEFORE a
    -- number is allocated: the unique index would swallow the insert, but it
    -- would not give the number back, and every no-op run would leave a gap in
    -- the company's job numbering. Advance anyway so the agreement does not get
    -- stuck retrying the same period forever.
    if exists (
      select 1 from public.jobs
      where service_agreement_id = r.id
        and generated_for_date   = r.next_due_date
    ) then
      update public.service_agreements
      set next_due_date = public.next_service_date(next_due_date, frequency, interval_days),
          updated_at = now()
      where id = r.id;

      service_agreement_id := r.id; job_id := null;
      scheduled_for := r.next_due_date; outcome := 'alreadyGenerated';
      return next;
      continue;
    end if;

    -- A job number still comes from the company's own sequence, so recurring
    -- work is numbered indistinguishably from work booked by hand. jobs.number
    -- is NOT NULL with no default: without this the insert below cannot succeed
    -- at all, and every agreement would report 'failed: null value in column
    -- "number"' forever.
    begin
      v_number := public.next_document_number_for_company(r.company_id, 'job');

      insert into public.jobs (
        company_id, number, customer_id, address_id, equipment_id,
        title, job_description, kind, priority, status,
        scheduled_start, scheduled_end,
        service_agreement_id, generated_for_date
      )
      values (
        r.company_id, v_number, r.customer_id, r.address_id, r.equipment_id,
        coalesce(nullif(r.template_title, ''), 'Scheduled service'),
        coalesce(r.template_description, ''),
        r.template_job_kind, 'standard', 'scheduled',
        (r.next_due_date::timestamp at time zone coalesce(r.time_zone_identifier, 'UTC')) + interval '9 hours',
        (r.next_due_date::timestamp at time zone coalesce(r.time_zone_identifier, 'UTC')) + interval '11 hours',
        r.id, r.next_due_date
      )
      -- The WHERE repeats jobs_recurring_period_idx's predicate verbatim, and is
      -- NOT optional. That index is PARTIAL, and PostgreSQL will only infer a
      -- partial index as the ON CONFLICT arbiter when the statement restates
      -- its predicate. Without it every insert here raises 42P10, 'there is no
      -- unique or exclusion constraint matching the ON CONFLICT specification'
      -- — which the handler below would have turned into a 'failed:' row, so
      -- recurring generation would have reported itself as running while never
      -- creating a single job.
      on conflict (service_agreement_id, generated_for_date)
        where service_agreement_id is not null and generated_for_date is not null
      do nothing
      returning id into v_job;
    exception when others then
      service_agreement_id := r.id; job_id := null;
      scheduled_for := r.next_due_date; outcome := 'failed: ' || sqlerrm;
      return next;
      continue;
    end;

    if v_job is null then
      -- Lost a race: a concurrent run generated this same period between the
      -- check above and the insert. The unique index arbitrated correctly and
      -- one number is spent for nothing — a gap, never a duplicate visit.
      update public.service_agreements
      set next_due_date = public.next_service_date(next_due_date, frequency, interval_days),
          updated_at = now()
      where id = r.id;

      service_agreement_id := r.id; job_id := null;
      scheduled_for := r.next_due_date; outcome := 'alreadyGenerated';
      return next;
      continue;
    end if;

    update public.service_agreements
    set last_generated_job_id = v_job,
        last_generated_on     = r.next_due_date,
        next_due_date         = public.next_service_date(r.next_due_date, r.frequency, r.interval_days),
        updated_at            = now()
    where id = r.id;

    service_agreement_id := r.id; job_id := v_job;
    scheduled_for := r.next_due_date; outcome := 'generated';
    return next;
  end loop;
end $$;

-- CREATE OR REPLACE resets privileges to the CREATE default (EXECUTE to
-- PUBLIC), so 0004 section 9's lockdown is reapplied here. Without this the
-- replace above would quietly hand every signed-in user the ability to
-- generate jobs into every company.
revoke execute on function public.generate_due_recurring_jobs(uuid, integer) from public;
revoke execute on function public.generate_due_recurring_jobs(uuid, integer) from anon, authenticated;
grant  execute on function public.generate_due_recurring_jobs(uuid, integer) to service_role;

commit;
