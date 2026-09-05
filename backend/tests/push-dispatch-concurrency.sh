#!/usr/bin/env bash
# =============================================================================
# TradeDesk — concurrent dispatcher safety (DEVELOPMENT TOOLING)
# =============================================================================
#
# The scheduler fires every thirty seconds and an operator can invoke the
# dispatcher by hand at any moment, so two runs overlapping is a normal event,
# not an exotic one. The guarantee that matters is that overlapping runs never
# deliver the same notification twice.
#
# A single database session cannot prove this: `FOR UPDATE ... SKIP LOCKED`
# only does anything when a second session is genuinely holding the row. So
# this test opens two real connections and has them claim at the same instant,
# then checks the two batches for any notification that appears in both.
#
# It also proves that a settlement racing another settlement of the same row
# produces one recorded outcome, not two.
#
# Fixtures are created for real and removed at the end — this test cannot use
# the roll-back trick the SQL suites rely on, because the work has to be
# visible to a second connection.
#
# Usage: bash backend/tests/push-dispatch-concurrency.sh
# =============================================================================

set -uo pipefail

REF="srfnfimskixjqjyyftak"
API="https://api.supabase.com/v1/projects/${REF}/database/query"
MARK="CONCTEST"
PASS=0
FAIL=0

q() {
  # Runs SQL and prints the JSON result.
  printf '%s' "$1" | jq -Rs '{query: .}' > /tmp/_cq.json
  curl -s -X POST "$API" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @/tmp/_cq.json
}

check() {
  # check <name> <condition-bool> <detail>
  if [ "$2" = "true" ]; then
    PASS=$((PASS + 1)); echo "PASS  $1  [$3]"
  else
    FAIL=$((FAIL + 1)); echo "FAIL  $1  [$3]"
  fi
}

echo "--- setting up fixtures"
q "
do \$\$
declare
  v_company uuid;
  v_user uuid := gen_random_uuid();
  v_device uuid;
begin
  insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                          email_confirmed_at, created_at, updated_at,
                          raw_app_meta_data, raw_user_meta_data, is_super_admin)
  values ('00000000-0000-0000-0000-000000000000', v_user, 'authenticated','authenticated',
          'conc@${MARK}.invalid','x', now(), now(), now(),
          '{\"provider\":\"email\"}'::jsonb, '{}'::jsonb, false);

  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('${MARK} Co','hvac','US','USD','America/New_York') returning id into v_company;

  insert into public.app_users (id, company_id, name, email, role)
  values (v_user, v_company, '${MARK} Worker','conc@${MARK}.invalid','fieldWorker');

  insert into public.push_devices (company_id, user_id, token, environment, bundle_id)
  values (v_company, v_user, repeat('cd', 32), 'production', 'app.rork.test')
  returning id into v_device;

  -- Forty alerts waiting: enough that two overlapping runs would collide
  -- constantly if the claim were not exclusive.
  insert into public.notifications (company_id, channel, template, recipient, status,
                                    target_user_id, push_device_id, title, body, deep_link)
  select v_company, 'push', 'job.assigned', 'ios ${MARK}', 'queued',
         v_user, v_device, '${MARK} ' || g, 'body', 'tradedesk://jobs'
  from generate_series(1, 40) g;
end \$\$;
" > /dev/null

TOTAL=$(q "select count(*)::text as c from public.notifications where recipient = 'ios ${MARK}';" | jq -r '.[0].c')
check "Forty alerts are waiting to be delivered" "$([ "$TOTAL" = "40" ] && echo true || echo false)" "queued=$TOTAL"

echo "--- two dispatchers claiming while the first still holds its rows"
# Run A claims a batch and then sleeps *inside the same transaction*, so its
# row locks are still held when run B arrives. That is the only way to put two
# dispatchers inside the claim at once, and therefore the only way to find out
# whether SKIP LOCKED really keeps their batches apart.
CLAIM_HOLD="select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);
with c as (select notification_id from public.claim_push_batch(10))
select coalesce(string_agg(notification_id::text, ','), '') as ids,
       pg_sleep(4)::text as held
from c;"

CLAIM_NOW="select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);
with c as (select notification_id from public.claim_push_batch(10))
select coalesce(string_agg(notification_id::text, ','), '') as ids from c;"

q "$CLAIM_HOLD" > /tmp/_c1.json &
P1=$!
sleep 1.5           # let run A get inside the claim and hold its locks
q "$CLAIM_NOW" > /tmp/_c2.json &
P2=$!
wait $P1 $P2

jq -r '.[0].ids // empty' /tmp/_c1.json | tr ',' '\n' | sed '/^$/d' | sort > /tmp/_c1.txt
jq -r '.[0].ids // empty' /tmp/_c2.json | tr ',' '\n' | sed '/^$/d' | sort > /tmp/_c2.txt
N1=$(wc -l < /tmp/_c1.txt | tr -d ' ')
N2=$(wc -l < /tmp/_c2.txt | tr -d ' ')
BOTH=$(comm -12 /tmp/_c1.txt /tmp/_c2.txt | wc -l | tr -d ' ')
UNION=$(cat /tmp/_c1.txt /tmp/_c2.txt | sort -u | wc -l | tr -d ' ')

check "Both runs did real work (the race actually happened)" \
  "$([ "$N1" -gt 0 ] && [ "$N2" -gt 0 ] && echo true || echo false)" \
  "run A=$N1 run B=$N2"

check "No notification was handed to two dispatchers at once" \
  "$([ "$BOTH" = "0" ] && echo true || echo false)" \
  "claimed by both=$BOTH"

check "Between them they claimed each alert exactly once" \
  "$([ "$UNION" = "$((N1 + N2))" ] && echo true || echo false)" \
  "distinct=$UNION total handed out=$((N1 + N2))"

echo "--- two settlements racing on the same alert"
TARGET=$(head -1 /tmp/_c1.txt)
SETTLE="select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);
select pg_sleep(1);
select public.settle_push_delivery('${TARGET}'::uuid, true, 'apns-race', null, false) as outcome;"

q "$SETTLE" > /tmp/_s1.json &
S1=$!
q "$SETTLE" > /tmp/_s2.json &
S2=$!
wait $S1 $S2

O1=$(jq -r '.[0].outcome // "error"' /tmp/_s1.json)
O2=$(jq -r '.[0].outcome // "error"' /tmp/_s2.json)
SETTLED=$( { [ "$O1" = "sent" ] && [ "$O2" = "alreadySettled" ]; } || { [ "$O2" = "sent" ] && [ "$O1" = "alreadySettled" ]; } && echo true || echo false)
check "One settlement records the delivery, the other is inert" "$SETTLED" "A=$O1 B=$O2"

SENT=$(q "select count(*)::text as c from public.notifications where recipient = 'ios ${MARK}' and status = 'sent';" | jq -r '.[0].c')
check "The alert is recorded as delivered exactly once" \
  "$([ "$SENT" = "1" ] && echo true || echo false)" "sent rows=$SENT"

echo "--- a third run finds only what is genuinely left"
# Both earlier runs have committed, so their twenty rows are marked claimed and
# must not be offered again. The remaining twenty should be.
THIRD=$(q "select set_config('request.jwt.claims','{\"role\":\"service_role\"}',true);
select count(*)::text as c from public.claim_push_batch(100);" | jq -r '.[0].c')
check "A later run is offered only the alerts nobody has taken" \
  "$([ "$THIRD" = "20" ] && echo true || echo false)" "third run claimed=$THIRD of 20 remaining"

echo "--- cleaning up"
q "
alter table public.app_users disable trigger app_users_delete_protection;
delete from public.notifications where recipient = 'ios ${MARK}';
delete from public.push_devices where company_id in (select id from public.companies where name = '${MARK} Co');
delete from public.app_users where company_id in (select id from public.companies where name = '${MARK} Co');
delete from public.companies where name = '${MARK} Co';
delete from auth.users where email = 'conc@${MARK}.invalid';
alter table public.app_users enable trigger app_users_delete_protection;
" > /dev/null

LEFT=$(q "select (
  (select count(*) from public.companies where name = '${MARK} Co') +
  (select count(*) from public.notifications where recipient = 'ios ${MARK}') +
  (select count(*) from auth.users where email = 'conc@${MARK}.invalid')
)::text as c;" | jq -r '.[0].c')
check "Every fixture this test created is gone" \
  "$([ "$LEFT" = "0" ] && echo true || echo false)" "rows left behind=$LEFT"

echo
echo "CONCURRENT DISPATCHER TEST — PASS=${PASS} FAIL=${FAIL}"
[ "$FAIL" = "0" ]
