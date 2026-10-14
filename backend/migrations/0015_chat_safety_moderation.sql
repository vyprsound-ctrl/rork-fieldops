-- =============================================================================
-- 0015 - CHAT SAFETY: reporting, moderation, chat suspension, content filter
-- =============================================================================
--
-- App Review Guideline 1.2 support for the two places people see messages:
--   * office chat        (office_threads / office_messages)
--   * customer SMS reply (sms_inbound_messages)
--
-- WHAT THIS ADDS (all additive; no existing table, column, policy or function
-- body is changed):
--   1. message_reports      - one report per reporter per message (or per
--                             person, for a block). Holds an evidence snapshot.
--   2. moderation_actions   - append-only audit trail of every report and
--                             every moderation decision.
--   3. chat_restrictions    - "chat suspension": the person keeps working but
--                             cannot send office-chat messages.
--   4. chat_blocks          - personal block list (see BLOCKING below).
--   5. chat_blocked_terms   - platform-managed objectionable-content list.
--   6. moderation_alerts    - outbox; every report emails Harbour South support
--                             through the `moderation-notify` Edge Function.
--   7. Triggers             - content filter + chat-suspension check on every
--                             office-chat insert; retaliation hold on app_users.
--   8. RPCs                 - report_office_message, report_sms_message,
--                             block_chat_user, unblock_chat_user,
--                             moderate_message_report.
--
-- WRITE MODEL
--   No client INSERT/UPDATE/DELETE policy exists on any new table. Every write
--   goes through a SECURITY DEFINER function that derives the company from
--   current_company_id() and the actor from auth.uid().
--
-- VISIBILITY
--   * A reporter sees their own reports.
--   * Owner/Admin (usersManage) in the same company see reports, EXCEPT any
--     report about themselves.
--   * The reported person never sees a report about them, its details, or who
--     filed it.
--   * Reports about an Owner (or where the company has no other moderator) are
--     escalated: only Harbour South (service role) can act on them.
--
-- BLOCKING (field-service design)
--   A block never stops delivery. Office chat is how engineers receive dispatch
--   questions and instructions, so silently dropping messages would be a safety
--   problem. A block (a) files a report that reaches the company's moderators
--   and Harbour South, and (b) is recorded privately for the blocker so the app
--   can collapse that sender's messages behind "Hidden - tap to show". Job
--   assignments, schedules and push alerts are untouched. Removing someone's
--   ability to message is a moderator decision (chat restriction), not a
--   unilateral one.
--
-- ACCOUNT SUSPENSION
--   Already enforced server-side: current_company_id() only resolves for
--   app_users.status = 'active', so a suspended person fails every RLS check
--   and every RPC. moderate_message_report(..., 'suspend_account') uses it.
-- =============================================================================

do $$
begin
  if to_regprocedure('public.current_company_id()') is null
     or to_regprocedure('public.has_perm(app_permission)') is null
     or to_regprocedure('public.is_office_user()') is null
     or to_regprocedure('public.push_caller_is_service_role()') is null
     or to_regclass('public.office_messages') is null
     or to_regclass('public.sms_inbound_messages') is null then
    raise exception '0015 prerequisites missing - refusing to build on an unknown schema';
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------
create table if not exists public.message_reports (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references public.companies(id) on delete cascade,
  source                text not null check (source in ('office', 'sms', 'user')),
  office_message_id     uuid references public.office_messages(id) on delete set null,
  office_thread_id      uuid references public.office_threads(id) on delete set null,
  sms_message_id        uuid references public.sms_inbound_messages(id) on delete set null,
  sms_conversation_id   uuid references public.sms_conversations(id) on delete set null,
  reporter_user_id      uuid references public.app_users(id) on delete set null,
  reported_user_id      uuid references public.app_users(id) on delete set null,
  reason                text not null check (reason in
                          ('harassment', 'hate', 'threat', 'sexual', 'spam', 'illegal', 'self_harm', 'other')),
  details               text check (details is null or length(details) <= 1000),
  -- Evidence, copied at report time so removing the message never destroys it.
  snapshot_body         text,
  snapshot_photo_ids    uuid[] not null default '{}',
  snapshot_sent_at      timestamptz,
  snapshot_meta         jsonb not null default '{}'::jsonb,
  status                text not null default 'open'
                          check (status in ('open', 'under_review', 'actioned', 'dismissed')),
  escalated_to_platform boolean not null default false,
  created_at            timestamptz not null default now(),
  resolved_at           timestamptz,
  resolved_by_user_id   uuid references public.app_users(id) on delete set null,
  resolution            text,
  resolution_note       text check (resolution_note is null or length(resolution_note) <= 1000)
);

create unique index if not exists message_reports_one_per_office_message
  on public.message_reports (reporter_user_id, office_message_id)
  where office_message_id is not null and reporter_user_id is not null;
create unique index if not exists message_reports_one_per_sms_message
  on public.message_reports (reporter_user_id, sms_message_id)
  where sms_message_id is not null and reporter_user_id is not null;
create index if not exists message_reports_company_status_idx
  on public.message_reports (company_id, status, created_at desc);
create index if not exists message_reports_reported_open_idx
  on public.message_reports (reported_user_id, status);

create table if not exists public.moderation_actions (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references public.companies(id) on delete cascade,
  report_id       uuid references public.message_reports(id) on delete set null,
  actor_user_id   uuid references public.app_users(id) on delete set null, -- null = Harbour South
  action          text not null check (action in (
                    'report_filed', 'block', 'unblock', 'start_review', 'dismiss', 'remove_message',
                    'restrict_chat', 'lift_chat_restriction', 'suspend_account')),
  target_user_id  uuid references public.app_users(id) on delete set null,
  note            text,
  created_at      timestamptz not null default now()
);
create index if not exists moderation_actions_company_idx
  on public.moderation_actions (company_id, created_at desc);

create table if not exists public.chat_restrictions (
  user_id              uuid primary key references public.app_users(id) on delete cascade,
  company_id           uuid not null references public.companies(id) on delete cascade,
  report_id            uuid references public.message_reports(id) on delete set null,
  restricted_by_user_id uuid references public.app_users(id) on delete set null,
  reason               text,
  created_at           timestamptz not null default now(),
  expires_at           timestamptz,
  lifted_at            timestamptz,
  lifted_by_user_id    uuid references public.app_users(id) on delete set null
);

create table if not exists public.chat_blocks (
  blocker_user_id uuid not null references public.app_users(id) on delete cascade,
  blocked_user_id uuid not null references public.app_users(id) on delete cascade,
  company_id      uuid not null references public.companies(id) on delete cascade,
  report_id       uuid references public.message_reports(id) on delete set null,
  created_at      timestamptz not null default now(),
  primary key (blocker_user_id, blocked_user_id),
  check (blocker_user_id <> blocked_user_id)
);

create table if not exists public.chat_blocked_terms (
  term       text primary key,
  category   text not null default 'abuse',
  active     boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.moderation_alerts (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid references public.companies(id) on delete cascade,
  report_id       uuid references public.message_reports(id) on delete cascade,
  kind            text not null,
  created_at      timestamptz not null default now(),
  attempts        integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  sent_at         timestamptz,
  last_error      text
);
create index if not exists moderation_alerts_pending_idx
  on public.moderation_alerts (next_attempt_at) where sent_at is null;

-- ---------------------------------------------------------------------------
-- 2. RLS + grants. SELECT only, and only where described above.
-- ---------------------------------------------------------------------------
alter table public.message_reports    enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.chat_restrictions  enable row level security;
alter table public.chat_blocks        enable row level security;
alter table public.chat_blocked_terms enable row level security;
alter table public.moderation_alerts  enable row level security;

drop policy if exists message_reports_select on public.message_reports;
create policy message_reports_select on public.message_reports
  for select using (
    company_id = public.current_company_id()
    and (
      reporter_user_id = auth.uid()
      or (public.has_perm('usersManage'::app_permission)
          and reported_user_id is distinct from auth.uid())
    )
  );

drop policy if exists moderation_actions_select on public.moderation_actions;
create policy moderation_actions_select on public.moderation_actions
  for select using (
    company_id = public.current_company_id()
    and public.has_perm('usersManage'::app_permission)
    and target_user_id is distinct from auth.uid()
  );

drop policy if exists chat_restrictions_select on public.chat_restrictions;
create policy chat_restrictions_select on public.chat_restrictions
  for select using (
    company_id = public.current_company_id()
    and public.has_perm('usersManage'::app_permission)
    and user_id <> auth.uid()
  );

drop policy if exists chat_blocks_select on public.chat_blocks;
create policy chat_blocks_select on public.chat_blocks
  for select using (
    company_id = public.current_company_id() and blocker_user_id = auth.uid()
  );

revoke all on public.message_reports, public.moderation_actions, public.chat_restrictions,
              public.chat_blocks, public.chat_blocked_terms, public.moderation_alerts
  from public, anon, authenticated;
grant select on public.message_reports, public.moderation_actions, public.chat_restrictions,
                public.chat_blocks
  to authenticated;
grant all on public.message_reports, public.moderation_actions, public.chat_restrictions,
             public.chat_blocks, public.chat_blocked_terms, public.moderation_alerts
  to service_role;

-- ---------------------------------------------------------------------------
-- 3. Content filter
-- ---------------------------------------------------------------------------
create or replace function public.chat_normalize(p_text text)
returns text
language sql
immutable
set search_path = public
as $$
  select btrim(regexp_replace(
           regexp_replace(translate(lower(coalesce(p_text, '')), '0134579@$!', 'oieastgasi'),
                          '[^a-z]+', ' ', 'g'),
           '\s+', ' ', 'g'));
$$;

-- Returns the category of the first blocked term found, or null.
create or replace function public.chat_content_violation(p_text text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select t.category
    from public.chat_blocked_terms t
   where t.active
     and (' ' || public.chat_normalize(p_text) || ' ') like ('% ' || t.term || ' %')
   limit 1;
$$;

-- Conservative starter list: unambiguous slurs, direct threats and sexual
-- solicitation. Harbour South extends it with SQL (service role); companies
-- cannot see or edit it. Terms are stored normalised.
insert into public.chat_blocked_terms (term, category)
select public.chat_normalize(x.term), x.category
  from (values
    ('nigger', 'hate'), ('niggers', 'hate'), ('nigga', 'hate'), ('faggot', 'hate'), ('faggots', 'hate'),
    -- Words with everyday trade meanings (e.g. 'chink' in a wall, 'tranny' for
    -- a transmission, 'Spic and Span') are deliberately left out.
    ('kike', 'hate'), ('wetback', 'hate'), ('raghead', 'hate'), ('towelhead', 'hate'),
    ('i will kill you', 'threat'), ('i ll kill you', 'threat'), ('im going to kill you', 'threat'),
    ('i m going to kill you', 'threat'), ('gonna kill you', 'threat'), ('kill yourself', 'threat'),
    ('kys', 'threat'), ('i will hurt you', 'threat'), ('i know where you live', 'threat'),
    ('send nudes', 'sexual'), ('send me nudes', 'sexual')
  ) as x(term, category)
on conflict (term) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Enforcement on every office-chat write (covers send_office_message and
--    anything else that ever inserts). A raise rolls back the whole send,
--    including a brand-new thread. TD422 reaches Build 20 as plain text.
-- ---------------------------------------------------------------------------
create or replace function public.chat_user_is_restricted(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.chat_restrictions r
     where r.user_id = p_user
       and r.lifted_at is null
       and (r.expires_at is null or r.expires_at > now())
  );
$$;

create or replace function public.office_message_safety_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.chat_user_is_restricted(new.sender_user_id) then
    raise exception 'Your chat messaging is paused while your company reviews a report. For anything urgent about a job, phone the office.'
      using errcode = 'TD422';
  end if;
  if public.chat_content_violation(new.body) is not null then
    raise exception 'This message wasn''t sent because it contains language that isn''t allowed in Harbour South FieldOps. Please rephrase it.'
      using errcode = 'TD422';
  end if;
  return new;
end $$;

drop trigger if exists office_message_safety on public.office_messages;
create trigger office_message_safety
  before insert on public.office_messages
  for each row execute function public.office_message_safety_guard();

create or replace function public.office_thread_subject_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if public.chat_content_violation(new.subject) is not null then
    raise exception 'This message wasn''t sent because it contains language that isn''t allowed in Harbour South FieldOps. Please rephrase it.'
      using errcode = 'TD422';
  end if;
  return new;
end $$;

drop trigger if exists office_thread_subject_safety on public.office_threads;
create trigger office_thread_subject_safety
  before insert on public.office_threads
  for each row execute function public.office_thread_subject_guard();

-- ---------------------------------------------------------------------------
-- 5. Retaliation hold. While someone has an open report about them, they
--    cannot suspend, demote/re-role or remove any team member. The hold is
--    deliberately not limited to the reporter, so it never points at who
--    filed the report, and the wording does not mention reports at all.
--    Reactivating someone is never held. Harbour South (service role) is not
--    affected.
-- ---------------------------------------------------------------------------
create or replace function public.app_users_retaliation_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_sensitive boolean;
begin
  if v_actor is null or v_actor = old.id then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  v_sensitive := tg_op = 'DELETE'
              or new.role is distinct from old.role
              or (new.status = 'suspended' and old.status is distinct from 'suspended');

  if v_sensitive and exists (
       select 1 from public.message_reports r
        where r.reported_user_id = v_actor
          and r.status in ('open', 'under_review')
          and r.created_at > now() - interval '30 days'
     ) then
    raise exception 'Team changes from your account are temporarily paused for a Harbour South review. Contact Harbour South support if this is urgent.'
      using errcode = 'TD422';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end $$;

drop trigger if exists app_users_retaliation_hold on public.app_users;
create trigger app_users_retaliation_hold
  before update of role, status or delete on public.app_users
  for each row execute function public.app_users_retaliation_guard();

-- ---------------------------------------------------------------------------
-- 6. Internal: record a report + audit row + support alert.
-- ---------------------------------------------------------------------------
create or replace function public.moderation_record_report(
  p_company          uuid,
  p_source           text,
  p_reporter         uuid,
  p_reported         uuid,
  p_reason           text,
  p_details          text,
  p_office_message   uuid,
  p_office_thread    uuid,
  p_sms_message      uuid,
  p_sms_conversation uuid,
  p_body             text,
  p_photos           uuid[],
  p_sent_at          timestamptz,
  p_meta             jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reason   text := lower(btrim(coalesce(p_reason, '')));
  v_details  text := nullif(btrim(coalesce(p_details, '')), '');
  v_escalate boolean;
  v_id       uuid;
begin
  if v_reason not in ('harassment', 'hate', 'threat', 'sexual', 'spam', 'illegal', 'self_harm', 'other') then
    raise exception 'Choose a reason for the report.' using errcode = 'TD422';
  end if;
  if v_details is not null and length(v_details) > 1000 then
    raise exception 'Please keep the report details under 1,000 characters.' using errcode = 'TD422';
  end if;
  if (select count(*) from public.message_reports
       where reporter_user_id = p_reporter and created_at > now() - interval '1 day') >= 50 then
    raise exception 'You''ve sent a lot of reports today. Harbour South support can help with anything more.'
      using errcode = 'TD422';
  end if;

  -- Owners, and anyone in a company with no other moderator, are reviewed by
  -- Harbour South rather than by a colleague.
  v_escalate := p_reported is not null and (
    exists (select 1 from public.app_users u where u.id = p_reported and u.role = 'owner')
    or not exists (
      select 1 from public.app_users u
        join public.role_permissions rp on rp.role = u.role and rp.permission = 'usersManage'::app_permission
       where u.company_id = p_company and u.status = 'active' and u.id <> p_reported
    )
  );

  insert into public.message_reports (
    company_id, source, office_message_id, office_thread_id, sms_message_id, sms_conversation_id,
    reporter_user_id, reported_user_id, reason, details,
    snapshot_body, snapshot_photo_ids, snapshot_sent_at, snapshot_meta, escalated_to_platform
  ) values (
    p_company, p_source, p_office_message, p_office_thread, p_sms_message, p_sms_conversation,
    p_reporter, p_reported, v_reason, v_details,
    p_body, coalesce(p_photos, '{}'), p_sent_at, coalesce(p_meta, '{}'::jsonb), v_escalate
  ) returning id into v_id;

  insert into public.moderation_actions (company_id, report_id, actor_user_id, action, target_user_id)
  values (p_company, v_id, p_reporter, case when p_source = 'user' then 'block' else 'report_filed' end, p_reported);

  insert into public.moderation_alerts (company_id, report_id, kind)
  values (p_company, v_id, 'report');

  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- 7. Client RPCs: reporting and blocking. Every staff role can report any
--    message it can already read; access is re-checked here, not trusted.
-- ---------------------------------------------------------------------------
create or replace function public.report_office_message(
  p_message uuid,
  p_reason  text,
  p_details text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_company uuid := public.current_company_id();
  v_msg     record;
  v_id      uuid;
begin
  if v_uid is null or v_company is null then
    raise exception using errcode = 'TD401', message = 'jobsReadAssignedOnly';
  end if;

  select m.id, m.thread_id, m.sender_user_id, m.body, m.job_photo_ids, m.created_at
    into v_msg
    from public.office_messages m
    join public.office_threads t on t.id = m.thread_id
   where m.id = p_message
     and m.company_id = v_company
     and t.company_id = v_company
     and (t.engineer_user_id = v_uid or public.is_office_user());

  if v_msg.id is null then
    raise exception 'Message not found.' using errcode = 'TD404';
  end if;
  if v_msg.sender_user_id = v_uid then
    raise exception 'You can''t report your own message.' using errcode = 'TD422';
  end if;

  select r.id into v_id from public.message_reports r
   where r.reporter_user_id = v_uid and r.office_message_id = p_message;
  if v_id is not null then
    return v_id; -- already reported: idempotent
  end if;

  return public.moderation_record_report(
    v_company, 'office', v_uid, v_msg.sender_user_id, p_reason, p_details,
    v_msg.id, v_msg.thread_id, null, null,
    v_msg.body, v_msg.job_photo_ids, v_msg.created_at, '{}'::jsonb
  );
end $$;

create or replace function public.report_sms_message(
  p_message uuid,
  p_reason  text,
  p_details text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_company uuid := public.current_company_id();
  v_msg     record;
  v_id      uuid;
begin
  if v_uid is null or v_company is null then
    raise exception using errcode = 'TD401', message = 'jobsReadAssignedOnly';
  end if;
  -- Same rule as the sim_select policy: whoever can read customer replies can
  -- report them.
  if not (public.has_perm('customersReadAll'::app_permission)
          and (public.has_perm('smsCreditsConsume'::app_permission)
               or public.has_perm('smsLedgerRead'::app_permission))) then
    raise exception 'Message not found.' using errcode = 'TD404';
  end if;

  select m.id, m.conversation_id, m.body, m.received_at, m.from_number, m.customer_id
    into v_msg
    from public.sms_inbound_messages m
   where m.id = p_message and m.company_id = v_company;

  if v_msg.id is null then
    raise exception 'Message not found.' using errcode = 'TD404';
  end if;

  select r.id into v_id from public.message_reports r
   where r.reporter_user_id = v_uid and r.sms_message_id = p_message;
  if v_id is not null then
    return v_id;
  end if;

  return public.moderation_record_report(
    v_company, 'sms', v_uid, null, p_reason, p_details,
    null, null, v_msg.id, v_msg.conversation_id,
    v_msg.body, '{}', v_msg.received_at,
    jsonb_build_object('from_number', v_msg.from_number, 'customer_id', v_msg.customer_id)
  );
end $$;

create or replace function public.block_chat_user(
  p_user    uuid,
  p_reason  text default 'harassment',
  p_details text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_company uuid := public.current_company_id();
  v_report  uuid;
begin
  if v_uid is null or v_company is null then
    raise exception using errcode = 'TD401', message = 'jobsReadAssignedOnly';
  end if;
  if p_user is null or p_user = v_uid then
    raise exception 'Choose someone else to block.' using errcode = 'TD422';
  end if;
  perform 1 from public.app_users u where u.id = p_user and u.company_id = v_company;
  if not found then
    raise exception 'That person is not on this company.' using errcode = 'TD404';
  end if;

  select b.report_id into v_report from public.chat_blocks b
   where b.blocker_user_id = v_uid and b.blocked_user_id = p_user;
  if found then
    return v_report;
  end if;

  v_report := public.moderation_record_report(
    v_company, 'user', v_uid, p_user, p_reason, p_details,
    null, null, null, null, null, '{}', null, jsonb_build_object('kind', 'block')
  );

  insert into public.chat_blocks (blocker_user_id, blocked_user_id, company_id, report_id)
  values (v_uid, p_user, v_company, v_report);

  return v_report;
end $$;

create or replace function public.unblock_chat_user(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_company uuid := public.current_company_id();
begin
  if v_uid is null or v_company is null then
    raise exception using errcode = 'TD401', message = 'jobsReadAssignedOnly';
  end if;
  delete from public.chat_blocks
   where blocker_user_id = v_uid and blocked_user_id = p_user and company_id = v_company;
  if found then
    insert into public.moderation_actions (company_id, actor_user_id, action, target_user_id)
    values (v_company, v_uid, 'unblock', p_user);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 8. Moderation. Company Owner/Admin, or Harbour South via the service role.
--    Nobody can act on a report about themselves; reports about an Owner are
--    Harbour South's alone.
-- ---------------------------------------------------------------------------
create or replace function public.moderate_message_report(
  p_report uuid,
  p_action text,
  p_note   text default null,
  p_days   integer default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_platform boolean := auth.uid() is null and public.push_caller_is_service_role();
  v_company  uuid;
  v_r        public.message_reports%rowtype;
  v_action   text := lower(btrim(coalesce(p_action, '')));
  v_note     text := nullif(btrim(coalesce(p_note, '')), '');
  v_removed  constant text := '[Removed by a moderator]';
  v_status   text;
begin
  if not v_platform then
    v_company := public.current_company_id();
    if v_uid is null or v_company is null then
      raise exception using errcode = 'TD401', message = 'usersManage';
    end if;
    if not public.has_perm('usersManage'::app_permission) then
      raise exception using errcode = 'TD401', message = 'usersManage';
    end if;
  end if;

  select * into v_r from public.message_reports where id = p_report for update;

  if v_r.id is null
     or (not v_platform and (v_r.company_id <> v_company or v_r.reported_user_id = v_uid)) then
    raise exception 'Report not found.' using errcode = 'TD404';
  end if;
  if not v_platform and v_r.escalated_to_platform then
    raise exception 'This report is being reviewed by Harbour South support.' using errcode = 'TD422';
  end if;
  if v_note is not null and length(v_note) > 1000 then
    raise exception 'Please keep the note under 1,000 characters.' using errcode = 'TD422';
  end if;

  case v_action
    when 'start_review' then
      if v_r.status <> 'open' then
        raise exception 'This report is already being handled.' using errcode = 'TD422';
      end if;
      update public.message_reports set status = 'under_review' where id = v_r.id;

    when 'dismiss' then
      update public.message_reports
         set status = 'dismissed', resolved_at = now(), resolved_by_user_id = v_uid,
             resolution = 'dismiss', resolution_note = v_note
       where id = v_r.id;

    when 'remove_message' then
      if v_r.office_message_id is not null then
        update public.office_messages
           set body = v_removed, job_photo_ids = '{}'
         where id = v_r.office_message_id;
        update public.office_threads t
           set last_message_preview = v_removed
         where t.id = v_r.office_thread_id
           and not exists (
             select 1 from public.office_messages m
              where m.thread_id = t.id
                and m.created_at > (select created_at from public.office_messages where id = v_r.office_message_id)
           );
      elsif v_r.sms_message_id is not null then
        update public.sms_inbound_messages set body = v_removed where id = v_r.sms_message_id;
        update public.sms_conversations c
           set last_preview = v_removed
         where c.id = v_r.sms_conversation_id
           and c.last_direction = 'inbound'
           and c.last_message_at <= (select received_at from public.sms_inbound_messages where id = v_r.sms_message_id);
      else
        raise exception 'This report is not about a single message.' using errcode = 'TD422';
      end if;
      -- Every open report on the same message is resolved by the removal.
      update public.message_reports
         set status = 'actioned', resolved_at = now(), resolved_by_user_id = v_uid,
             resolution = 'remove_message', resolution_note = coalesce(resolution_note, v_note)
       where status in ('open', 'under_review')
         and ((v_r.office_message_id is not null and office_message_id = v_r.office_message_id)
           or (v_r.sms_message_id is not null and sms_message_id = v_r.sms_message_id));

    when 'restrict_chat' then
      if v_r.reported_user_id is null then
        raise exception 'Customer texts can''t be paused here; remove the message instead.' using errcode = 'TD422';
      end if;
      if p_days is not null and (p_days < 1 or p_days > 365) then
        raise exception 'Choose between 1 and 365 days, or leave it open-ended.' using errcode = 'TD422';
      end if;
      insert into public.chat_restrictions (user_id, company_id, report_id, restricted_by_user_id, reason, expires_at)
      values (v_r.reported_user_id, v_r.company_id, v_r.id, v_uid, v_note,
              case when p_days is null then null else now() + make_interval(days => p_days) end)
      on conflict (user_id) do update
        set report_id = excluded.report_id, restricted_by_user_id = excluded.restricted_by_user_id,
            reason = excluded.reason, created_at = now(), expires_at = excluded.expires_at,
            lifted_at = null, lifted_by_user_id = null;
      update public.message_reports
         set status = 'actioned', resolved_at = now(), resolved_by_user_id = v_uid,
             resolution = 'restrict_chat', resolution_note = v_note
       where id = v_r.id;

    when 'lift_chat_restriction' then
      update public.chat_restrictions
         set lifted_at = now(), lifted_by_user_id = v_uid
       where user_id = v_r.reported_user_id and lifted_at is null;

    when 'suspend_account' then
      if v_r.reported_user_id is null then
        raise exception 'There is no team member to suspend on this report.' using errcode = 'TD422';
      end if;
      update public.app_users
         set status = 'suspended', updated_at = now()
       where id = v_r.reported_user_id and company_id = v_r.company_id;
      update public.message_reports
         set status = 'actioned', resolved_at = now(), resolved_by_user_id = v_uid,
             resolution = 'suspend_account', resolution_note = v_note
       where id = v_r.id;

    else
      raise exception 'Unknown moderation action.' using errcode = 'TD422';
  end case;

  insert into public.moderation_actions (company_id, report_id, actor_user_id, action, target_user_id, note)
  values (v_r.company_id, v_r.id, v_uid, v_action, v_r.reported_user_id, v_note);

  select status into v_status from public.message_reports where id = v_r.id;
  return v_status;
end $$;

-- ---------------------------------------------------------------------------
-- 9. Support alerts: outbox -> pg_net -> moderation-notify (HMAC-signed).
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from vault.secrets where name = 'moderation_notify_signing_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'hex'),
      'moderation_notify_signing_key',
      'HMAC key for pg_net -> moderation-notify Edge Function'
    );
  end if;
end $$;

create or replace function public.moderation_post_dispatch()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare v_key text; v_ts text; v_sig text; v_request bigint;
begin
  if not exists (select 1 from public.moderation_alerts
                  where sent_at is null and attempts < 10 and next_attempt_at <= now()) then
    return null;
  end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'moderation_notify_signing_key';
  if v_key is null then raise warning 'moderation notify: no signing key'; return null; end if;
  v_ts := extract(epoch from clock_timestamp())::bigint::text;
  v_sig := encode(extensions.hmac(v_ts, v_key, 'sha256'), 'hex');
  select net.http_post(
    url := 'https://srfnfimskixjqjyyftak.supabase.co/functions/v1/moderation-notify',
    headers := jsonb_build_object('Content-Type', 'application/json',
                                  'x-moderation-timestamp', v_ts, 'x-moderation-signature', v_sig),
    body := jsonb_build_object('source', 'db'),
    timeout_milliseconds := 30000
  ) into v_request;
  return v_request;
end $$;

create or replace function public.moderation_dispatch_tick()
returns bigint
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') in ('authenticated', 'anon') then
    raise exception 'Service role only' using errcode = 'TD403';
  end if;
  return public.moderation_post_dispatch();
end $$;

-- Immediate attempt when a report arrives. pg_net queues the request and sends
-- it after commit; a failure here never blocks the report.
create or replace function public.moderation_alert_kick()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  begin
    perform public.moderation_post_dispatch();
  exception when others then
    raise warning 'moderation alert % queued; immediate dispatch failed: %', new.id, sqlerrm;
  end;
  return new;
end $$;

drop trigger if exists moderation_alert_dispatch on public.moderation_alerts;
create trigger moderation_alert_dispatch
  after insert on public.moderation_alerts
  for each row execute function public.moderation_alert_kick();

create or replace function public.moderation_verify_signature(p_timestamp text, p_signature text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare v_key text;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  if coalesce(p_timestamp, '') !~ '^[0-9]{9,12}$' then return false; end if;
  if abs(extract(epoch from clock_timestamp()) - p_timestamp::bigint) > 300 then return false; end if;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'moderation_notify_signing_key';
  if v_key is null then return false; end if;
  return encode(extensions.hmac(p_timestamp, v_key, 'sha256'), 'hex') = coalesce(p_signature, '');
end $$;

-- Claims due alerts (backoff on every claim) and returns what support needs.
create or replace function public.moderation_claim_alerts(p_limit integer default 20)
returns table (
  alert_id uuid, report_id uuid, kind text, company_name text, source text, reason text, details text,
  status text, escalated boolean, reporter_name text, reporter_role text, reported_name text,
  reported_role text, snapshot_body text, photo_count integer, snapshot_meta jsonb, created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  return query
  with due as (
    select a.id from public.moderation_alerts a
     where a.sent_at is null and a.attempts < 10 and a.next_attempt_at <= now()
     order by a.created_at
     limit greatest(1, least(coalesce(p_limit, 20), 50))
     for update skip locked
  ), claimed as (
    update public.moderation_alerts a
       set attempts = a.attempts + 1,
           next_attempt_at = now() + make_interval(mins => least(60, (2 ^ a.attempts)::int))
      from due where a.id = due.id
    returning a.id, a.report_id, a.kind
  )
  select c.id, r.id, c.kind, co.name, r.source, r.reason, r.details, r.status, r.escalated_to_platform,
         rep.name, rep.role::text, tgt.name, tgt.role::text,
         r.snapshot_body, coalesce(cardinality(r.snapshot_photo_ids), 0), r.snapshot_meta, r.created_at
    from claimed c
    join public.message_reports r on r.id = c.report_id
    join public.companies co on co.id = r.company_id
    left join public.app_users rep on rep.id = r.reporter_user_id
    left join public.app_users tgt on tgt.id = r.reported_user_id;
end $$;

create or replace function public.moderation_mark_alert(p_alert uuid, p_ok boolean, p_error text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  update public.moderation_alerts
     set sent_at = case when p_ok then now() else null end,
         last_error = case when p_ok then null else left(p_error, 500) end
   where id = p_alert;
end $$;

-- Retry sweep for alerts whose immediate attempt failed.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'moderation-notify') then
    perform cron.unschedule('moderation-notify');
  end if;
  perform cron.schedule('moderation-notify', '*/2 * * * *', 'select public.moderation_dispatch_tick();');
end $$;

-- ---------------------------------------------------------------------------
-- 10. Function privileges. Supabase grants EXECUTE to anon/authenticated by
--     default, so everything is revoked first and re-granted deliberately.
-- ---------------------------------------------------------------------------
revoke all on function public.chat_normalize(text)                       from public, anon;
revoke all on function public.chat_content_violation(text)               from public, anon, authenticated;
revoke all on function public.chat_user_is_restricted(uuid)              from public, anon, authenticated;
revoke all on function public.office_message_safety_guard()              from public, anon, authenticated;
revoke all on function public.office_thread_subject_guard()              from public, anon, authenticated;
revoke all on function public.app_users_retaliation_guard()              from public, anon, authenticated;
revoke all on function public.moderation_record_report(uuid, text, uuid, uuid, text, text, uuid, uuid, uuid, uuid, text, uuid[], timestamptz, jsonb)
                                                                          from public, anon, authenticated;
revoke all on function public.report_office_message(uuid, text, text)    from public, anon;
revoke all on function public.report_sms_message(uuid, text, text)       from public, anon;
revoke all on function public.block_chat_user(uuid, text, text)          from public, anon;
revoke all on function public.unblock_chat_user(uuid)                    from public, anon;
revoke all on function public.moderate_message_report(uuid, text, text, integer) from public, anon;
revoke all on function public.moderation_post_dispatch()                 from public, anon, authenticated;
revoke all on function public.moderation_dispatch_tick()                 from public, anon, authenticated;
revoke all on function public.moderation_alert_kick()                    from public, anon, authenticated;
revoke all on function public.moderation_verify_signature(text, text)    from public, anon, authenticated;
revoke all on function public.moderation_claim_alerts(integer)           from public, anon, authenticated;
revoke all on function public.moderation_mark_alert(uuid, boolean, text) from public, anon, authenticated;

grant execute on function public.report_office_message(uuid, text, text)           to authenticated;
grant execute on function public.report_sms_message(uuid, text, text)              to authenticated;
grant execute on function public.block_chat_user(uuid, text, text)                 to authenticated;
grant execute on function public.unblock_chat_user(uuid)                           to authenticated;
grant execute on function public.moderate_message_report(uuid, text, text, integer) to authenticated, service_role;
grant execute on function public.moderation_dispatch_tick()                        to service_role;
grant execute on function public.moderation_verify_signature(text, text)           to service_role;
grant execute on function public.moderation_claim_alerts(integer)                  to service_role;
grant execute on function public.moderation_mark_alert(uuid, boolean, text)        to service_role;
