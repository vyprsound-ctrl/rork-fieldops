-- =============================================================================
-- Harbour South FieldOps — CORE FIELD-SERVICE WORKFLOW (ADDITIVE)
-- =============================================================================
--
--  STATUS: WRITTEN, NOT APPLIED.
--
--  The agent that wrote this file had no Supabase administrative credentials in
--  its environment (no SUPABASE_ACCESS_TOKEN, no SUPABASE_SERVICE_ROLE_KEY, no
--  SUPABASE_DB_URL), so it could not execute a single statement against the
--  live database, and could not read a single existing RLS policy back.
--
--  Nothing in the iOS app depends on this migration. Every screen shipped in
--  this pass runs against the schema as it already exists:
--
--    * customers / customer_contacts / addresses / equipment   — CRM writes
--    * jobs / field_worker_assignments / job_status_history    — job workflow
--    * job_notes                                               — completion
--                                                                record, parts
--                                                                and labour
--    * job_photos                                              — photos and the
--                                                                signature
--    * equipment_history                                       — asset history
--                                                                on completion
--    * invitations (+ create_invitation / accept_invitation)   — adding people
--
--  What this migration buys, once an administrator applies it:
--
--    1. A private Storage bucket for job media, so photos are uploaded as
--       objects instead of being stored with the job_photos row. The app
--       already prefers the bucket and only falls back when it is absent, so
--       applying this changes behaviour with no client release.
--    2. A `signature` member on job_photo_kind, so a signature stops sharing
--       the `proof` label with everything else.
--    3. Normalised parts and labour, which the app currently writes as a
--       structured internal note because there is nowhere else to put them.
--    4. A default-site flag on addresses, and a lifecycle status on customers
--       and equipment, none of which exist today.
--
--  APPLY WITH, from an authenticated shell:
--    supabase db push --project-ref srfnfimskixjqjyyftak
--  or paste into the SQL editor for project srfnfimskixjqjyyftak.
--
--  Every statement is guarded so re-running it is safe.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1. Storage: a private bucket for job photos and signatures
-- -----------------------------------------------------------------------------
-- Objects are keyed  <company_id>/<job_id>/<uuid>.<ext>  by the client, so the
-- first path segment is the tenant and every policy below pivots on it.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'job-media',
  'job-media',
  false,
  10485760,                                    -- 10 MB ceiling per object
  array['image/jpeg', 'image/png', 'image/heic']
)
on conflict (id) do nothing;

-- Read: anybody whose company owns the first path segment. That is the same
-- tenant boundary every table uses, expressed against the object key.
drop policy if exists "job media readable within the company" on storage.objects;
create policy "job media readable within the company"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'job-media'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.has_perm('jobPhotosRead')
  );

-- Write: the same boundary, plus the permission that already governs the
-- job_photos row the object is attached to.
drop policy if exists "job media writable within the company" on storage.objects;
create policy "job media writable within the company"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'job-media'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.has_perm('jobPhotosCreate')
  );

drop policy if exists "job media replaceable within the company" on storage.objects;
create policy "job media replaceable within the company"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'job-media'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.has_perm('jobPhotosCreate')
  );

-- Deliberately no DELETE policy. A completed job's evidence is not something a
-- field worker removes from a phone.

-- -----------------------------------------------------------------------------
-- 2. A signature is not a "proof" photo
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'job_photo_kind' and e.enumlabel = 'signature'
  ) then
    alter type public.job_photo_kind add value 'signature';
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Parts and labour as rows rather than as prose
-- -----------------------------------------------------------------------------
-- Until this exists the app records both inside a structured internal note on
-- the job. That is real, durable and readable by the office — but it is not
-- queryable, so "what did we fit last quarter" cannot be answered.

create table if not exists public.job_parts (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies(id) on delete cascade,
  job_id        uuid not null references public.jobs(id) on delete cascade,
  recorded_by_user_id uuid not null references public.app_users(id),
  name          text not null check (length(btrim(name)) > 0),
  quantity      integer not null default 1 check (quantity > 0),
  created_at    timestamptz not null default now()
);

create index if not exists job_parts_job_idx on public.job_parts (job_id);
create index if not exists job_parts_company_idx on public.job_parts (company_id);

create table if not exists public.job_labour (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references public.companies(id) on delete cascade,
  job_id        uuid not null references public.jobs(id) on delete cascade,
  user_id       uuid not null references public.app_users(id),
  minutes       integer not null check (minutes >= 0),
  started_at    timestamptz,
  ended_at      timestamptz,
  created_at    timestamptz not null default now()
);

create index if not exists job_labour_job_idx on public.job_labour (job_id);
create index if not exists job_labour_company_idx on public.job_labour (company_id);

alter table public.job_parts  enable row level security;
alter table public.job_labour enable row level security;

-- The row gate is the job's own gate: office roles see the company's jobs, a
-- field worker sees the ones they are assigned to. Exactly the rule job_notes
-- and job_photos already run under.
drop policy if exists "job parts readable with the job" on public.job_parts;
create policy "job parts readable with the job"
  on public.job_parts for select
  to authenticated
  using (
    company_id = public.current_company_id()
    and (public.has_perm('jobsReadAll') or public.is_assigned_to_job(job_id))
  );

drop policy if exists "job parts written by the person on site" on public.job_parts;
create policy "job parts written by the person on site"
  on public.job_parts for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and recorded_by_user_id = auth.uid()
    and (public.has_perm('jobsManage') or public.is_assigned_to_job(job_id))
  );

drop policy if exists "job labour readable with the job" on public.job_labour;
create policy "job labour readable with the job"
  on public.job_labour for select
  to authenticated
  using (
    company_id = public.current_company_id()
    and (public.has_perm('jobsReadAll') or public.is_assigned_to_job(job_id))
  );

drop policy if exists "job labour written by the person on site" on public.job_labour;
create policy "job labour written by the person on site"
  on public.job_labour for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and user_id = auth.uid()
    and (public.has_perm('jobsManage') or public.is_assigned_to_job(job_id))
  );

-- -----------------------------------------------------------------------------
-- 4. Fields the CRM screens want and the schema does not have
-- -----------------------------------------------------------------------------
-- The app currently treats the oldest address on an account as the main site,
-- because there is no flag to set. This gives the office one to choose.
alter table public.addresses
  add column if not exists is_default boolean not null default false;

-- Exactly one default per customer, when one is set at all.
create unique index if not exists addresses_one_default_per_customer
  on public.addresses (customer_id)
  where is_default;

-- The first address on each account becomes the default, matching what the app
-- already shows today.
update public.addresses a
set is_default = true
where not exists (
  select 1 from public.addresses d
  where d.customer_id = a.customer_id and d.is_default
)
and a.id = (
  select id from public.addresses x
  where x.customer_id = a.customer_id
  order by x.created_at asc, x.id asc
  limit 1
);

-- A customer is archived, not deleted, once they have history. The app refuses
-- deletion in that case today and has nowhere to record the alternative.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'customer_status') then
    create type public.customer_status as enum ('active', 'archived');
  end if;
end $$;

alter table public.customers
  add column if not exists status public.customer_status not null default 'active';

-- An asset that has been decommissioned. The app stores this in the
-- `attributes` json today because there is no column.
alter table public.equipment
  add column if not exists is_active boolean not null default true;

alter table public.equipment
  add column if not exists customer_id uuid references public.customers(id) on delete cascade;

-- Backfill the customer from the site the unit sits at.
update public.equipment e
set customer_id = a.customer_id
from public.addresses a
where e.address_id = a.id and e.customer_id is null;

create index if not exists equipment_customer_idx on public.equipment (customer_id);

commit;

-- =============================================================================
-- AFTER APPLYING
-- =============================================================================
-- 1. Regenerate backend/types.ts:
--      supabase gen types typescript --project-ref srfnfimskixjqjyyftak > backend/types.ts
-- 2. The iOS app needs no change for the bucket — it already prefers it.
-- 3. Structured parts/labour, the `signature` photo kind, the default-site flag
--    and the customer/equipment status columns are NOT yet read or written by
--    the app. Wiring them is a follow-up, and should not be described as done
--    until it is.
-- =============================================================================
