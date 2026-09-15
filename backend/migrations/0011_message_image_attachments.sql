-- =============================================================================
-- 0011 — Message image attachments (general + job-linked)
-- =============================================================================
--
-- WHY
-- An owner and a field worker must be able to send each other photographs in
-- any authorised conversation. Today they cannot: `job_photos.job_id` is NOT
-- NULL, so an image sent in a general conversation has nowhere to live, and the
-- composer hides its camera button rather than failing after the fact.
--
-- THE MODEL
-- One image, one object, one row — never two uploads of the same picture.
--
--   general message image   job_id = null            thread_id = the thread
--   job-linked message image job_id = thread.job_id  thread_id = the thread
--
-- A job-linked message image is therefore simultaneously the message attachment
-- AND permanent job visual evidence, because it is a `job_photos` row on that
-- job like any other. `office_messages.job_photo_ids` continues to be what ties
-- an image to a message; no second media system is introduced.
--
-- WHAT THIS DOES
--   1. Adds the evidence categories from 0010 (folded in, idempotent).
--   2. Makes `job_photos.job_id` nullable and adds `job_photos.thread_id`.
--   3. Adds a check constraint so an image is always anchored to something.
--   4. Rewrites the `job_photos` SELECT and INSERT policies so job-scoped rows
--      keep today's exact rule and thread-scoped rows are governed by thread
--      visibility. `is_assigned_to_job(null)` is never relied upon.
--   5. Validates `p_photo_ids` inside `send_office_message`, which currently
--      accepts whatever the client sends.
--   6. Lets a message carry images with no text.
--   7. Removes `anon` table grants.
--
-- WHAT THIS DOES NOT DO
-- No new bucket, no new table, no storage policy change, no data rewrite. Every
-- existing `job_photos` row has a non-null `job_id` and a null `thread_id`, so
-- it lands in the job-scoped branch of the new policies and is governed by
-- exactly the rule it is governed by today.
--
-- SAFETY
-- Idempotent throughout; re-running is harmless. Relaxing NOT NULL and adding a
-- nullable column are metadata-only operations and do not rewrite the table.
--
-- APPLY WITH, from an authenticated shell:
--   supabase db push --project-ref srfnfimskixjqjyyftak
-- or paste into the SQL editor for project srfnfimskixjqjyyftak.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Evidence categories (0010, folded in so a single file brings a database
--    that never received 0010 fully up to date).
-- -----------------------------------------------------------------------------
do $$
declare
  v_label text;
begin
  foreach v_label in array array['during', 'equipment', 'damage', 'property_condition', 'other']
  loop
    if not exists (
      select 1
        from pg_enum e
        join pg_type t on t.oid = e.enumtypid
       where t.typname = 'job_photo_kind'
         and e.enumlabel = v_label
    ) then
      execute format('alter type public.job_photo_kind add value %L', v_label);
    end if;
  end loop;
end $$;

comment on type public.job_photo_kind is
  'What a job photograph is evidence of. before/during/after describe the work; equipment, damage and property_condition describe what was found; part and proof support the invoice; signature is written by the completion flow only; other is deliberately uncategorised.';


-- -----------------------------------------------------------------------------
-- 2. Shape: a photo may be anchored to a job, to a conversation, or to both.
--
-- `on delete set null` on thread_id is deliberate and load-bearing: deleting a
-- conversation must never delete or orphan job evidence. The photo survives,
-- keeps its job_id, and remains in that job's record permanently.
-- -----------------------------------------------------------------------------
alter table public.job_photos
  alter column job_id drop not null;

alter table public.job_photos
  add column if not exists thread_id uuid
    references public.office_threads(id) on delete set null;

comment on column public.job_photos.job_id is
  'The job this image is evidence for. Null only for an image sent in a general conversation, which is not about a job.';
comment on column public.job_photos.thread_id is
  'The conversation this image was sent in, when it was sent as a message attachment. Cleared if that conversation is later deleted; the image remains job evidence.';

-- An image with neither anchor would be unreachable by any policy and invisible
-- in every screen. Refuse it at the table.
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.job_photos'::regclass
       and conname  = 'job_photos_anchored'
  ) then
    alter table public.job_photos
      add constraint job_photos_anchored
      check (job_id is not null or thread_id is not null);
  end if;
end $$;

-- Reading a conversation resolves its attachments by id, and the job evidence
-- screen still reads by job. Index the new access path.
create index if not exists job_photos_thread_idx
  on public.job_photos (thread_id, captured_at desc)
  where thread_id is not null;


-- -----------------------------------------------------------------------------
-- 3. Row level security.
--
-- The existing policies cannot survive a null job_id unchanged, because
-- `is_assigned_to_job(null)` is false — a general message image would be
-- invisible to the very people in the conversation. They are rewritten as two
-- explicit branches.
--
-- JOB-SCOPED  (job_id is not null) — byte-for-byte the rule in force today:
--     company isolation + (jobsReadAll or is_assigned_to_job(job_id))
--   Nothing here is relaxed. A field worker still cannot see photographs from a
--   job they are not on.
--
-- THREAD-SCOPED  (job_id is null) — mirrors office_threads_select:
--     company isolation + (engineer_user_id = auth.uid() or is_office_user())
--
-- The existing policy names are not assumed. Every SELECT and INSERT policy on
-- the table is dropped by name and the two canonical policies are recreated, so
-- this file converges the table no matter what it was called beforehand. Names
-- are reported so the change is auditable.
-- -----------------------------------------------------------------------------
alter table public.job_photos enable row level security;

do $$
declare
  v_policy record;
begin
  for v_policy in
    select policyname, cmd
      from pg_policies
     where schemaname = 'public'
       and tablename  = 'job_photos'
       and cmd in ('SELECT', 'INSERT')
  loop
    raise notice 'job_photos: replacing % policy %', v_policy.cmd, v_policy.policyname;
    execute format('drop policy if exists %I on public.job_photos', v_policy.policyname);
  end loop;
end $$;

create policy "job photos readable with the job or the conversation"
  on public.job_photos for select
  to authenticated
  using (
    company_id = public.current_company_id()
    and public.has_perm('jobPhotosRead')
    and (
      case
        when job_id is not null then
          -- Unchanged: the job's own gate.
          public.has_perm('jobsReadAll') or public.is_assigned_to_job(job_id)
        else
          -- A general message image: visible to the two sides of that
          -- conversation and to nobody else.
          exists (
            select 1
              from public.office_threads t
             where t.id = job_photos.thread_id
               and t.company_id = public.current_company_id()
               and (t.engineer_user_id = auth.uid() or public.is_office_user())
          )
      end
    )
  );

create policy "job photos written by the person who took them"
  on public.job_photos for insert
  to authenticated
  with check (
    company_id = public.current_company_id()
    and public.has_perm('jobPhotosCreate')
    -- The uploader owns the row. Filing evidence under somebody else's name is
    -- refused here rather than trusted from the client.
    and user_id = auth.uid()
    and (
      job_id is null
      or public.has_perm('jobsReadAll')
      or public.is_assigned_to_job(job_id)
    )
    and (
      thread_id is null
      or exists (
        select 1
          from public.office_threads t
         where t.id = job_photos.thread_id
           and t.company_id = public.current_company_id()
           and (t.engineer_user_id = auth.uid() or public.is_office_user())
           -- An image filed against both must agree with the conversation it
           -- was sent in. This is what stops one job's evidence being posted
           -- into a conversation about another.
           and (job_photos.job_id is null or t.job_id is not distinct from job_photos.job_id)
      )
    )
  );


-- -----------------------------------------------------------------------------
-- 4. Sending a message.
--
-- Two defects are fixed:
--
--   a) `p_photo_ids` was written into the row verbatim with no validation at
--      all. Cross-company reads were blocked by job_photos RLS as a side
--      effect, but an unrelated photo from the same company could be attached
--      to any conversation. Every id is now checked before the message exists.
--
--   b) A message required text, so an image could not be sent on its own. A
--      photograph of a failed part IS the message.
--
-- Everything else — thread resolution, the office/engineer authorisation rules,
-- read receipts, recipient resolution from the permission matrix, the contained
-- push block and the deep link — is preserved exactly.
-- -----------------------------------------------------------------------------
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
  v_photos     uuid[] := coalesce(p_photo_ids, '{}');
  v_photo_n    integer;
  v_matched    integer;
  v_engineer   uuid;
  v_thread     uuid;
  v_thread_job uuid;
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

  select count(distinct x) into v_photo_n from unnest(v_photos) x;

  -- A message must say something — in words, in pictures, or both.
  if v_body = '' and v_photo_n = 0 then
    raise exception 'Write a message or attach a photo.' using errcode = 'TD422';
  end if;
  if length(v_body) > 4000 then
    raise exception 'That message is too long.' using errcode = 'TD422';
  end if;
  if v_photo_n > 10 then
    raise exception 'That is too many photos for one message.' using errcode = 'TD422';
  end if;

  -- ------------------------------------------------------------------ thread
  if p_thread is not null then
    select t.engineer_user_id, t.job_id, t.customer_id
      into v_engineer, v_thread_job, v_customer
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
    p_job    := v_thread_job;
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
      left(btrim(coalesce(nullif(p_subject, ''), nullif(v_body, ''), 'Photo')), 120),
      v_uid
    )
    returning id, job_id into v_thread, v_thread_job;
  end if;

  -- ------------------------------------------------------------- attachments
  --
  -- Validated as a set: if any single id fails, the whole message is refused
  -- and nothing is written. Silently dropping an attachment would tell the
  -- sender their photo went when it did not; silently keeping an unrelated one
  -- would be a leak.
  if v_photo_n > 0 then
    select count(distinct p.id) into v_matched
      from public.job_photos p
     where p.id = any(v_photos)
       and p.company_id = v_company
       -- The sender took it. A photo id belonging to a colleague cannot be
       -- attached by guessing it.
       and p.user_id = v_uid
       -- Job alignment. A job conversation carries that job's evidence; a
       -- general conversation carries images that belong to no job at all.
       and p.job_id is not distinct from v_thread_job
       -- Either not yet attached anywhere, or already on this conversation.
       -- An image from another conversation is refused.
       and (p.thread_id is null or p.thread_id = v_thread);

    if v_matched <> v_photo_n then
      raise exception 'One of those photos could not be attached to this conversation.'
        using errcode = 'TD422';
    end if;

    -- Stamp the conversation onto images uploaded before it existed, which is
    -- the normal case when a message opens a brand new thread.
    update public.job_photos
       set thread_id = v_thread
     where id = any(v_photos)
       and company_id = v_company
       and thread_id is null;
  end if;

  -- ----------------------------------------------------------------- message
  insert into public.office_messages (company_id, thread_id, sender_user_id, body, job_photo_ids)
  values (v_company, v_thread, v_uid, v_body, v_photos);

  if v_body <> '' then
    v_preview := left(regexp_replace(v_body, '\s+', ' ', 'g'), 140);
  elsif v_photo_n = 1 then
    v_preview := 'Photo';
  else
    v_preview := v_photo_n || ' photos';
  end if;

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
  select j.number into v_job_number from public.jobs j where j.id = v_thread_job;

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
           job_id    = coalesce(job_id, v_thread_job)
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


-- -----------------------------------------------------------------------------
-- 5. Grants.
--
-- `anon` has no business reading a company's photographs or conversations. The
-- application is authenticated throughout and reaches writes through RPCs, so
-- removing these costs it nothing. RLS is not relaxed to compensate.
-- -----------------------------------------------------------------------------
revoke all on public.job_photos      from anon;
revoke all on public.office_threads  from anon;
revoke all on public.office_messages from anon;
revoke all on public.office_thread_reads from anon;

grant select, insert on public.job_photos to authenticated;
grant select on public.office_threads      to authenticated;
grant select on public.office_messages     to authenticated;
grant select on public.office_thread_reads to authenticated;

revoke all on function public.send_office_message(uuid,uuid,uuid,text,text,uuid[]) from public, anon;
grant execute on function public.send_office_message(uuid,uuid,uuid,text,text,uuid[]) to authenticated;
