-- 0016 Moderation alert hardening (backend only, additive)
--
--   1. Test alerts: kind = 'test', no report attached. Queued only by the
--      service role through moderation_queue_test_alert(); clearly labelled
--      "TEST - no action needed" by the moderation-notify Edge Function.
--   2. Exhausted alerts: an alert that fails its 10th attempt (or whose final
--      attempt never reported back) is stamped exhausted_at, logged as a
--      Postgres warning, and listed in moderation_alerts_attention for support.
--      moderation_retry_alert() puts it back in the queue.
--   3. Recipient handling lives in the Edge Function (MODERATION_ALERT_EMAIL
--      only, blank = unset). The address is never stored in the database.
--
-- Nothing here is readable by anon or authenticated users.

alter table public.moderation_alerts add column if not exists exhausted_at timestamptz;
alter table public.moderation_alerts add column if not exists note text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'moderation_alerts_kind_check') then
    alter table public.moderation_alerts
      add constraint moderation_alerts_kind_check
      check ((kind = 'report' and report_id is not null) or (kind = 'test' and report_id is null));
  end if;
end $$;

create index if not exists moderation_alerts_exhausted_idx
  on public.moderation_alerts (exhausted_at) where exhausted_at is not null and sent_at is null;

-- ---------------------------------------------------------------------------
-- Claim: left joins so test alerts (no report/company) are returned too.
-- Return shape changes, so drop and recreate.
-- ---------------------------------------------------------------------------
drop function if exists public.moderation_claim_alerts(integer);
create function public.moderation_claim_alerts(p_limit integer default 20)
returns table (
  alert_id uuid, report_id uuid, kind text, company_name text, source text, reason text, details text,
  status text, escalated boolean, reporter_name text, reporter_role text, reported_name text,
  reported_role text, snapshot_body text, photo_count integer, snapshot_meta jsonb, created_at timestamptz,
  note text, attempt integer
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
     where a.sent_at is null and a.exhausted_at is null and a.attempts < 10 and a.next_attempt_at <= now()
     order by a.created_at
     limit greatest(1, least(coalesce(p_limit, 20), 50))
     for update skip locked
  ), claimed as (
    update public.moderation_alerts a
       set attempts = a.attempts + 1,
           next_attempt_at = now() + make_interval(mins => least(60, (2 ^ a.attempts)::int))
      from due where a.id = due.id
    returning a.id, a.report_id, a.kind, a.note, a.attempts, a.created_at
  )
  select c.id, r.id, c.kind, co.name, r.source, r.reason, r.details, r.status,
         coalesce(r.escalated_to_platform, false),
         rep.name, rep.role::text, tgt.name, tgt.role::text,
         r.snapshot_body, coalesce(cardinality(r.snapshot_photo_ids), 0), r.snapshot_meta,
         coalesce(r.created_at, c.created_at), c.note, c.attempts
    from claimed c
    left join public.message_reports r on r.id = c.report_id
    left join public.companies co on co.id = r.company_id
    left join public.app_users rep on rep.id = r.reporter_user_id
    left join public.app_users tgt on tgt.id = r.reported_user_id
   where c.kind = 'test' or r.id is not null;
end $$;

-- ---------------------------------------------------------------------------
-- Mark: a failure on the 10th attempt flags the alert as exhausted.
-- ---------------------------------------------------------------------------
create or replace function public.moderation_mark_alert(p_alert uuid, p_ok boolean, p_error text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_attempts integer;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  update public.moderation_alerts
     set sent_at      = case when p_ok then now() else null end,
         last_error   = case when p_ok then null else left(coalesce(p_error, 'Unknown delivery failure'), 500) end,
         exhausted_at = case when p_ok then null
                             when attempts >= 10 then coalesce(exhausted_at, now())
                             else exhausted_at end
   where id = p_alert
   returning attempts into v_attempts;
  if not p_ok and coalesce(v_attempts, 0) >= 10 then
    raise warning 'moderation alert % exhausted after % attempts; see moderation_alerts_attention', p_alert, v_attempts;
  end if;
end $$;

-- Flags alerts whose final attempt never reported back (function crashed or
-- timed out), so nothing can sit silently with attempts = 10.
create or replace function public.moderation_flag_stalled_alerts()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare v_count integer;
begin
  update public.moderation_alerts
     set exhausted_at = now(),
         last_error = coalesce(last_error, 'Final attempt did not report a result')
   where sent_at is null and exhausted_at is null and attempts >= 10 and next_attempt_at <= now();
  get diagnostics v_count = row_count;
  if v_count > 0 then
    raise warning 'moderation alerts: % newly exhausted; see moderation_alerts_attention', v_count;
  end if;
  return v_count;
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
  perform public.moderation_flag_stalled_alerts();
  return public.moderation_post_dispatch();
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
                  where sent_at is null and exhausted_at is null and attempts < 10 and next_attempt_at <= now()) then
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

-- ---------------------------------------------------------------------------
-- Support follow-up (service role only).
-- ---------------------------------------------------------------------------
create or replace view public.moderation_alerts_attention
with (security_invoker = true) as
select a.id            as alert_id,
       a.kind,
       a.report_id,
       co.name         as company_name,
       r.reason,
       r.status        as report_status,
       coalesce(r.escalated_to_platform, false) as escalated,
       a.attempts,
       a.last_error,
       a.created_at,
       a.exhausted_at
  from public.moderation_alerts a
  left join public.message_reports r on r.id = a.report_id
  left join public.companies co on co.id = r.company_id
 where a.sent_at is null and a.exhausted_at is not null;

create or replace function public.moderation_retry_alert(p_alert uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare v_found boolean;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  update public.moderation_alerts
     set attempts = 0, next_attempt_at = now(), exhausted_at = null
   where id = p_alert and sent_at is null
   returning true into v_found;
  if coalesce(v_found, false) then perform public.moderation_post_dispatch(); end if;
  return coalesce(v_found, false);
end $$;

create or replace function public.moderation_queue_test_alert(p_note text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not public.push_caller_is_service_role() then raise exception 'Service role only' using errcode = 'TD403'; end if;
  insert into public.moderation_alerts (company_id, report_id, kind, note)
  values (null, null, 'test', left(nullif(btrim(coalesce(p_note, '')), ''), 300))
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------------
-- Privileges.
-- ---------------------------------------------------------------------------
revoke all on public.moderation_alerts_attention from public, anon, authenticated;
grant select on public.moderation_alerts_attention to service_role;

revoke all on function public.moderation_claim_alerts(integer)           from public, anon, authenticated;
revoke all on function public.moderation_mark_alert(uuid, boolean, text) from public, anon, authenticated;
revoke all on function public.moderation_flag_stalled_alerts()           from public, anon, authenticated;
revoke all on function public.moderation_dispatch_tick()                 from public, anon, authenticated;
revoke all on function public.moderation_post_dispatch()                 from public, anon, authenticated;
revoke all on function public.moderation_retry_alert(uuid)               from public, anon, authenticated;
revoke all on function public.moderation_queue_test_alert(text)          from public, anon, authenticated;

grant execute on function public.moderation_claim_alerts(integer)           to service_role;
grant execute on function public.moderation_mark_alert(uuid, boolean, text) to service_role;
grant execute on function public.moderation_dispatch_tick()                 to service_role;
grant execute on function public.moderation_retry_alert(uuid)               to service_role;
grant execute on function public.moderation_queue_test_alert(text)          to service_role;
