-- =============================================================================
-- 0007 - ENGINEER V1: office messaging + engineer duty state
-- =============================================================================
--
-- WHAT THIS ADDS, AND WHY IT COULD NOT REUSE AN EXISTING TABLE
--
--   1. office_threads / office_messages / office_thread_reads
--      Two-way Engineer <-> Office conversation. `job_notes` was considered
--      first and rejected: it is one-directional commentary bound to a single
--      job, with no thread, no counterparty, no read state and no way to carry
--      a question that is not about a specific job. A conversation is a
--      genuinely different record from a note on a work order.
--
--   2. app_users.duty_state
--      Whether an engineer is available, on a break, or off duty. This is NOT
--      a second copy of the job lifecycle: travelling / on site / working are
--      still derived from the engineer's live job status and are deliberately
--      absent from this enum. Only the part the job status cannot express is
--      stored.
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--   * No new notification system. Message alerts are written into the existing
--     `notifications` table by the existing `enqueue_push()` producer, claimed
--     by the existing `claim_push_batch()` and delivered by the existing
--     `dispatch-push` function. Nothing here talks to APNs.
--   * No change to Stripe, invoicing, recurring services, invitations, the
--     Resend path or any existing policy. Every statement below is additive.
--   * No weakening of tenancy. Every new table carries `company_id`, has RLS
--     enabled, and is readable only inside `current_company_id()`.
--
-- WRITE MODEL
--   The new tables accept NO direct client INSERT or UPDATE. There is no such
--   policy on them. Every write goes through a SECURITY DEFINER function that
--   re-derives the company from `current_company_id()` and the author from
--   `auth.uid()`, so a client cannot post as somebody else or into another
--   company even by crafting the request itself.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 0. Prerequisites.
--
-- This migration builds on functions that already exist in this database. If
-- any of them is missing the rest of the file would create objects that fail
-- at runtime instead of now, so it stops here.
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regprocedure('public.current_company_id()') is null then
    raise exception 'current_company_id() is missing - refusing to build on an unknown schema';
  end if;
  if to_regprocedure('public.has_perm(app_permission)') is null then
    raise exception 'has_perm(app_permission) is missing - refusing to build on an unknown schema';
  end if;
  if to_regprocedure('public.is_assigned_to_job(uuid)') is null then
    raise exception 'is_assigned_to_job(uuid) is missing - refusing to build on an unknown schema';
  end if;
  if to_regprocedure('public.enqueue_push(uuid,uuid,text,text,text,uuid,uuid)') is null then
    raise exception 'enqueue_push(uuid,uuid,text,text,text,uuid,uuid) is missing - message alerts would never be delivered';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Engineer duty state.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'worker_duty_state') then
    create type public.worker_duty_state as enum ('available', 'onBreak', 'offDuty');
  end if;
end $$;

alter table public.app_users
  add column if not exists duty_state public.worker_duty_state not null default 'available';

alter table public.app_users
  add column if not exists duty_state_changed_at timestamptz;

comment on column public.app_users.duty_state is
  'Availability the person sets for themselves. Travelling/on-site/working are NOT here - those are derived from the live job status.';

-- ---------------------------------------------------------------------------
-- 2. Who counts as "the office".
--
-- Derived from the existing permission matrix rather than a hard-coded list of
-- roles or people: whoever the company has granted assignment or user
-- management is who an engineer needs to reach. Today that resolves to owner,
-- admin and dispatcher; if a company's grants change, this follows them.
-- ---------------------------------------------------------------------------
create or replace function public.is_office_user()
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(
    public.has_perm('assignmentsManage'::app_permission)
      or public.has_perm('usersManage'::app_permission),
    false
  );
$$;

comment on function public.is_office_user() is
  'True when the caller holds an office-side grant (assignmentsManage or usersManage). Used to decide who an engineer message reaches.';

-- ---------------------------------------------------------------------------
-- 3. Tables.
-- ---------------------------------------------------------------------------
create table if not exists public.office_threads (
  id                   uuid primary key default gen_random_uuid(),
  company_id           uuid not null references public.companies(id) on delete cascade,
  engineer_user_id     uuid not null references public.app_users(id) on delete cascade,
  job_id               uuid references public.jobs(id) on delete set null,
  customer_id          uuid references public.customers(id) on delete set null,
  subject              text not null default '',
  created_by_user_id   uuid not null references public.app_users(id),
  created_at           timestamptz not null default now(),
  last_message_at      timestamptz not null default now(),
  last_message_preview text not null default '',
  last_sender_user_id  uuid references public.app_users(id)
);

create table if not exists public.office_messages (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies(id) on delete cascade,
  thread_id       uuid not null references public.office_threads(id) on delete cascade,
  sender_user_id  uuid not null references public.app_users(id),
  body            text not null,
  -- Images live in job_photos, which already has a bucket, an upload path and
  -- its own policies. A message references them; it does not store bytes.
  job_photo_ids   uuid[] not null default '{}',
  created_at      timestamptz not null default now()
);

create table if not exists public.office_thread_reads (
  thread_id    uuid not null references public.office_threads(id) on delete cascade,
  user_id      uuid not null references public.app_users(id) on delete cascade,
  company_id   uuid not null references public.companies(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

create index if not exists office_threads_company_engineer_idx
  on public.office_threads (company_id, engineer_user_id, last_message_at desc);
create index if not exists office_threads_company_recent_idx
  on public.office_threads (company_id, last_message_at desc);
create index if not exists office_messages_thread_idx
  on public.office_messages (thread_id, created_at);
create index if not exists office_thread_reads_user_idx
  on public.office_thread_reads (user_id, thread_id);

-- ---------------------------------------------------------------------------
-- 4. Row level security.
--
-- SELECT only. There is deliberately no INSERT or UPDATE policy on threads or
-- messages: the only way to write one is the SECURITY DEFINER function below,
-- which decides the company and the author itself.
-- ---------------------------------------------------------------------------
alter table public.office_threads      enable row level security;
alter table public.office_messages     enable row level security;
alter table public.office_thread_reads enable row level security;

drop policy if exists office_threads_select on public.office_threads;
create policy office_threads_select on public.office_threads
  for select using (
    company_id = public.current_company_id()
    and (engineer_user_id = auth.uid() or public.is_office_user())
  );

drop policy if exists office_messages_select on public.office_messages;
create policy office_messages_select on public.office_messages
  for select using (
    company_id = public.current_company_id()
    and exists (
      select 1
        from public.office_threads t
       where t.id = office_messages.thread_id
         and t.company_id = public.current_company_id()
         and (t.engineer_user_id = auth.uid() or public.is_office_user())
    )
  );

drop policy if exists office_thread_reads_select on public.office_thread_reads;
create policy office_thread_reads_select on public.office_thread_reads
  for select using (
    company_id = public.current_company_id() and user_id = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- 5. Sending a message.
--
-- The company comes from current_company_id(), the author from auth.uid(), and
-- the recipients from the permission matrix. None of the three is a parameter,
-- so none of them can be forged by the caller.
-- ---------------------------------------------------------------------------
create or replace function public.send_office_message(
  p_thread    uuid default null,
  p_job       uuid default null,
  p_engineer  uuid default null,
  p_subject   text default '',
  p_body      text default '',
  p_photo_ids uuid[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid        uuid := auth.uid();
  v_company    uuid := public.current_company_id();
  v_is_office  boolean := public.is_office_user();
  v_body       text := btrim(coalesce(p_body, ''));
  v_engineer   uuid;
  v_thread     uuid;
  v_customer   uuid;
  v_job_number text;
  v_sender     text;
  v_preview    text;
  v_title      text;
  v_deep_link  text;
  v_mark       timestamptz := clock_timestamp();
  v_recipient  uuid;
begin
  if v_uid is null or v_company is null then
    raise exception 'Not signed in' using errcode = 'TD401', message = 'jobsReadAssignedOnly';
  end if;

  if v_body = '' then
    raise exception 'A message needs some text.' using errcode = 'TD422';
  end if;
  if length(v_body) > 4000 then
    raise exception 'That message is too long.' using errcode = 'TD422';
  end if;

  -- ------------------------------------------------------------------ thread
  if p_thread is not null then
    select t.engineer_user_id, t.job_id, t.customer_id
      into v_engineer, p_job, v_customer
      from public.office_threads t
     where t.id = p_thread
       and t.company_id = v_company;

    if v_engineer is null then
      raise exception 'Conversation not found.' using errcode = 'TD404';
    end if;
    -- Posting into somebody else's conversation is refused even though the
    -- company matches.
    if not v_is_office and v_engineer <> v_uid then
      raise exception 'Not your conversation.' using errcode = 'TD401', message = 'jobsReadAssignedOnly';
    end if;
    v_thread := p_thread;
  else
    -- A new conversation. An engineer always opens their own; an office user
    -- has to say which engineer they are opening one with.
    v_engineer := case when v_is_office then p_engineer else v_uid end;
    if v_engineer is null then
      raise exception 'Choose who this message is for.' using errcode = 'TD422';
    end if;

    perform 1 from public.app_users u
      where u.id = v_engineer and u.company_id = v_company and u.status = 'active';
    if not found then
      raise exception 'That person is not on this company.' using errcode = 'TD404';
    end if;

    if p_job is not null then
      -- The job must be in this company, and an engineer may only raise a
      -- conversation about a job they are actually on.
      select j.customer_id into v_customer
        from public.jobs j
       where j.id = p_job and j.company_id = v_company;
      if v_customer is null then
        raise exception 'Job not found.' using errcode = 'TD404';
      end if;
      if not v_is_office and not public.is_assigned_to_job(p_job) then
        raise exception 'Not your job.' using errcode = 'TD401', message = 'jobsReadAssignedOnly';
      end if;
    end if;

    insert into public.office_threads (
      company_id, engineer_user_id, job_id, customer_id, subject, created_by_user_id
    )
    values (
      v_company, v_engineer, p_job, v_customer,
      left(btrim(coalesce(nullif(p_subject, ''), v_body)), 120),
      v_uid
    )
    returning id into v_thread;
  end if;

  -- ----------------------------------------------------------------- message
  insert into public.office_messages (company_id, thread_id, sender_user_id, body, job_photo_ids)
  values (v_company, v_thread, v_uid, v_body, coalesce(p_photo_ids, '{}'));

  v_preview := left(regexp_replace(v_body, '\s+', ' ', 'g'), 140);

  update public.office_threads
     set last_message_at      = now(),
         last_message_preview = v_preview,
         last_sender_user_id  = v_uid
   where id = v_thread;

  -- The sender has, by definition, read their own message.
  insert into public.office_thread_reads (thread_id, user_id, company_id, last_read_at)
  values (v_thread, v_uid, v_company, now())
  on conflict (thread_id, user_id) do update set last_read_at = now();

  -- ------------------------------------------------------------------ alerts
  select u.name into v_sender from public.app_users u where u.id = v_uid;
  select j.number into v_job_number from public.jobs j where j.id = p_job;

  v_title := coalesce(nullif(v_sender, ''), 'A colleague');
  if v_job_number is not null then
    v_title := v_title || ' · ' || v_job_number;
  end if;

  v_deep_link := 'tradedesk://message/' || v_thread::text;

  -- The message is already committed to by this point. Alerting is a best
  -- effort on top of it: a push that cannot be raised must never discard a
  -- message the engineer believes they have sent, so the whole alert block is
  -- contained. A failure is recorded in the server log, and the message still
  -- appears in the conversation for both sides.
  begin
    for v_recipient in
      -- An engineer's message goes to the office; an office reply goes back to
      -- that one engineer. Recipients are read from the permission matrix, so
      -- no individual is hard-coded anywhere in this function.
      select u.id
        from public.app_users u
       where u.company_id = v_company
         and u.status = 'active'
         and u.id <> v_uid
         and (
           case
             when v_is_office then u.id = v_engineer
             else exists (
               select 1 from public.role_permissions rp
                where rp.role = u.role
                  and rp.permission in ('assignmentsManage'::app_permission,
                                        'usersManage'::app_permission)
             )
           end
         )
    loop
      perform public.enqueue_push(
        v_company, v_recipient, 'office.message', v_title, v_preview, null, null
      );
    end loop;

    -- enqueue_push owns the device fan-out and the queued row. The destination
    -- of a tap is this feature's business, so it is stamped on afterwards.
    update public.notifications
       set deep_link = v_deep_link,
           job_id    = coalesce(job_id, p_job)
     where template = 'office.message'
       and company_id = v_company
       and created_at >= v_mark
       and deep_link is null;
  exception when others then
    raise warning 'office message % saved, but its alert could not be raised: %', v_thread, sqlerrm;
  end;

  return v_thread;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Read receipts.
-- ---------------------------------------------------------------------------
create or replace function public.mark_office_thread_read(p_thread uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_company uuid := public.current_company_id();
  v_ok      boolean;
begin
  if v_uid is null or v_company is null then
    raise exception 'Not signed in' using errcode = 'TD401', message = 'jobsReadAssignedOnly';
  end if;

  select (t.engineer_user_id = v_uid or public.is_office_user())
    into v_ok
    from public.office_threads t
   where t.id = p_thread and t.company_id = v_company;

  if not coalesce(v_ok, false) then
    raise exception 'Conversation not found.' using errcode = 'TD404';
  end if;

  insert into public.office_thread_reads (thread_id, user_id, company_id, last_read_at)
  values (p_thread, v_uid, v_company, now())
  on conflict (thread_id, user_id) do update set last_read_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Setting your own availability.
--
-- Scoped to auth.uid() inside the function. There is no user parameter, so an
-- engineer cannot set anybody else's state, and this touches no other column
-- on the row - notably not `role`.
-- ---------------------------------------------------------------------------
create or replace function public.set_my_duty_state(p_state public.worker_duty_state)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not signed in' using errcode = 'TD401', message = 'jobsReadAssignedOnly';
  end if;

  update public.app_users
     set duty_state = p_state,
         duty_state_changed_at = now(),
         updated_at = now()
   where id = v_uid;

  if not found then
    raise exception 'No membership for this account.' using errcode = 'TD404';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. Grants.
--
-- `anon` gets nothing. Only a signed-in caller may send, read or set state,
-- and each function re-derives who that caller is.
-- ---------------------------------------------------------------------------
revoke all on function public.send_office_message(uuid,uuid,uuid,text,text,uuid[]) from public, anon;
revoke all on function public.mark_office_thread_read(uuid) from public, anon;
revoke all on function public.set_my_duty_state(public.worker_duty_state) from public, anon;
revoke all on function public.is_office_user() from public, anon;

grant execute on function public.send_office_message(uuid,uuid,uuid,text,text,uuid[]) to authenticated;
grant execute on function public.mark_office_thread_read(uuid) to authenticated;
grant execute on function public.set_my_duty_state(public.worker_duty_state) to authenticated;
grant execute on function public.is_office_user() to authenticated;

grant select on public.office_threads      to authenticated;
grant select on public.office_messages     to authenticated;
grant select on public.office_thread_reads to authenticated;
