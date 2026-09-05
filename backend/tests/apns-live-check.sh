#!/usr/bin/env bash
# =============================================================================
# TradeDesk — live APNs check for one real handset (OPERATOR TOOLING)
# =============================================================================
#
# Steps 1-3 and 9-12 of the real-device checklist happen on the phone itself and
# can only be confirmed by holding it. Everything in between leaves a trace in
# the database, and this reads that trace back so you are never guessing about
# whether a push actually went out.
#
# It is READ-ONLY. It creates nothing, delivers nothing and changes no row, so
# it is safe to run against production while somebody is using the app.
#
# No device token is ever printed in full — only the last six characters, which
# is the same masking the notification ledger itself uses.
#
# Usage:
#   bash backend/tests/apns-live-check.sh someone@company.com
# =============================================================================

set -uo pipefail

REF="srfnfimskixjqjyyftak"
API="https://api.supabase.com/v1/projects/${REF}/database/query"
EMAIL="${1:-}"

if [ -z "$EMAIL" ]; then
  echo "Usage: bash backend/tests/apns-live-check.sh <email of the signed-in user>"
  exit 2
fi

q() {
  printf '%s' "$1" | jq -Rs '{query: .}' > /tmp/_lq.json
  curl -s -X POST "$API" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/_lq.json
}

SAFE_EMAIL=${EMAIL//\'/\'\'}

echo "== Is APNs configured on the dispatcher?"
echo "   (the dispatcher answers this itself; it never reveals the credentials)"
# A 401 means this shell holds no service-role key, which says nothing at all
# about whether APNs is configured. The two are reported separately so this can
# never read as 'not configured' when it really means 'not authenticated'.
RESPONSE=$(curl -s -w '\n%{http_code}' -X POST "https://${REF}.supabase.co/functions/v1/dispatch-push" \
  -H "Authorization: Bearer ${SUPABASE_SERVICE_ROLE_KEY:-none}" \
  -H "Content-Type: application/json" -d '{"limit":1}' 2>/dev/null)
STATUS=$(printf '%s' "$RESPONSE" | tail -1)
BODY=$(printf '%s' "$RESPONSE" | sed '$d')

if [ "$STATUS" = "401" ]; then
  echo "   unknown — this shell holds no service-role key, so the dispatcher"
  echo "   declined to answer. Export SUPABASE_SERVICE_ROLE_KEY to ask it."
elif [ "$STATUS" = "200" ]; then
  ANSWER=$(printf '%s' "$BODY" | jq -r 'if .configured == true then "yes — APNs credentials are present" else "no — " + (.detail // "no detail given") end' 2>/dev/null)
  echo "   ${ANSWER:-the dispatcher answered in a shape this check did not expect}"
else
  echo "   could not reach the dispatcher (HTTP ${STATUS:-none})"
fi

echo
echo "== Step 4 — is this person's handset registered?"
q "
select coalesce(string_agg(line, E'\n'), '   none — no device has been registered for this address')
       as report
from (
  select format('   %s  env=%s  bundle=%s  app=%s  %s  last registered %s',
                '••••' || right(d.token, 6), d.environment, d.bundle_id,
                nullif(d.app_version,''),
                case when d.revoked_at is null then 'LIVE' else 'revoked: ' || coalesce(d.revoked_reason,'') end,
                to_char(d.last_registered_at, 'YYYY-MM-DD HH24:MI')) as line
  from push_devices d
  join app_users u on u.id = d.user_id
  where lower(u.email) = lower('${SAFE_EMAIL}')
  order by d.last_registered_at desc
) s;" | jq -r '.[0].report // "   (query failed)"'

echo
echo "== Steps 5-8 — the ten most recent alerts addressed to this person"
q "
select coalesce(string_agg(line, E'\n'), '   none — no alert has been raised for this person yet')
       as report
from (
  select format('   %-16s %-9s %s%s',
                n.template, n.status,
                to_char(n.created_at, 'MM-DD HH24:MI'),
                case
                  when n.status = 'sent' then '  delivered to Apple' ||
                       coalesce(' (apns-id ' || left(n.provider_reference, 12) || ')', '')
                  when n.status = 'failed' then '  ' || coalesce(n.failure_reason, 'no reason recorded')
                  when n.claimed_at is not null then '  claimed, awaiting Apple''s answer'
                  else '  waiting for the dispatcher'
                end) as line
  from notifications n
  join app_users u on u.id = n.target_user_id
  where n.channel = 'push' and lower(u.email) = lower('${SAFE_EMAIL}')
  order by n.created_at desc
  limit 10
) s;" | jq -r '.[0].report // "   (query failed)"'

echo
echo "== Is the scheduler actually running?"
q "
select format('   last run %s (%s), %s run(s) recorded',
              coalesce(to_char(max(d.start_time), 'YYYY-MM-DD HH24:MI:SS'), 'never'),
              coalesce(max(d.status), 'n/a'), count(*)) as report
from cron.job_run_details d
join cron.job j on j.jobid = d.jobid
where j.jobname = 'push-dispatch';" | jq -r '.[0].report // "   (query failed)"'

echo
echo "Steps 1-3 (sign in, enable job alerts, accept the iOS prompt), 9 (tapping"
echo "opens the right job) and 10-12 (another person's alert, sign-out, re-login)"
echo "are confirmed on the handset — this only shows what reached the server."
