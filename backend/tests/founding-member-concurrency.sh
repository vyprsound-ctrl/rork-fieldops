#!/usr/bin/env bash
# =============================================================================
# Harbour South FieldOps — simultaneous Founding claims (DEVELOPMENT TOOLING)
# =============================================================================
#
# One database session cannot prove concurrency safety: SKIP LOCKED and the
# per-company advisory lock only do anything when a second session is
# genuinely inside the claim at the same moment. So this opens two real
# connections and has them claim at once.
#
# IT NEVER SPENDS A REAL FOUNDING PLACE. Every claim runs inside a
# transaction that ends in `raise exception`, so the allocation is rolled
# back and the claimed number comes back in the error text. Only the fixture
# companies are committed (a second connection has to be able to see them),
# and they are deleted at the end. They never hold a place, so deleting them
# retires nothing.
#
#   1. Two DIFFERENT companies claiming at once get two different places.
#   2. The SAME company claiming twice at once (stripe-connect and the
#      account.updated webhook arriving together) never takes a second place
#      and never errors: the second claim waits for the first.
#
# Usage: SUPABASE_ACCESS_TOKEN=... bash backend/tests/founding-member-concurrency.sh
# =============================================================================

set -uo pipefail

REF="srfnfimskixjqjyyftak"
API="https://api.supabase.com/v1/projects/${REF}/database/query"
MARK="FOUNDCONC"
PASS=0
FAIL=0

q() {
  local f; f=$(mktemp /tmp/_fq.XXXXXX)
  printf '%s' "$1" | jq -Rs '{query: .}' > "$f"
  curl -s -X POST "$API" \
    -H "Authorization: Bearer ${SUPABASE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    --data-binary @"$f"
  rm -f "$f"
}

check() {
  if [ "$2" = "true" ]; then
    PASS=$((PASS + 1)); echo "PASS  $1  [$3]"
  else
    FAIL=$((FAIL + 1)); echo "FAIL  $1  [$3]"
  fi
}

# A claim that reports its number and ALWAYS rolls back. Optionally holds its
# locks for a few seconds first so a second connection arrives mid-claim.
claim_sql() {
  local company_name="$1" hold="$2"
  cat <<SQL
select set_config('request.jwt.claims','{"role":"service_role"}',true);
do \$\$
declare n integer; t0 timestamptz := clock_timestamp();
begin
  n := public.claim_founding_member_slot(
         (select id from public.companies where name = '${company_name}'));
  perform pg_sleep(${hold});
  raise exception 'RESULT=% WAITED_MS=%', coalesce(n::text,'null'),
    (extract(epoch from clock_timestamp() - t0) * 1000)::int;
end \$\$;
SQL
}

result_of() { jq -r '.message // ""' "$1" | grep -o 'RESULT=[^ ]*' | cut -d= -f2; }
waited_of() { jq -r '.message // ""' "$1" | grep -o 'WAITED_MS=[0-9]*' | cut -d= -f2; }

BEFORE=$(q "select count(*)::text as c from public.founding_member_slots where claimed_at is not null;" | jq -r '.[0].c')
check "Precondition: no place allocated yet" "$([ "$BEFORE" = "0" ] && echo true || echo false)" "allocated=$BEFORE"
[ "$BEFORE" = "0" ] || { echo "Refusing to run against allocated places."; exit 1; }

echo "--- fixtures (committed, so both connections can see them)"
q "
do \$\$
declare v uuid;
begin
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('${MARK} A','hvac','US','USD','America/New_York') returning id into v;
  insert into public.stripe_connect_accounts (company_id, stripe_account_id, charges_enabled)
  values (v, 'acct_${MARK}_A', true);
  insert into public.companies (name, trade, country_code, currency_code, time_zone_identifier)
  values ('${MARK} B','hvac','US','USD','America/New_York') returning id into v;
  insert into public.stripe_connect_accounts (company_id, stripe_account_id, charges_enabled)
  values (v, 'acct_${MARK}_B', true);
end \$\$;" > /dev/null

N=$(q "select count(*)::text as c from public.companies where name like '${MARK} %';" | jq -r '.[0].c')
check "Two charge-ready fixture companies exist" "$([ "$N" = "2" ] && echo true || echo false)" "companies=$N"

echo "--- 1. two different companies claiming at the same moment"
q "$(claim_sql "${MARK} A" 4)" > /tmp/_f1.json &
P1=$!
sleep 1.5
q "$(claim_sql "${MARK} B" 0)" > /tmp/_f2.json &
P2=$!
wait $P1 $P2
R1=$(result_of /tmp/_f1.json); R2=$(result_of /tmp/_f2.json); W2=$(waited_of /tmp/_f2.json)
check "Both companies were given a place" \
  "$([ "$R1" != "null" ] && [ -n "$R1" ] && [ "$R2" != "null" ] && [ -n "$R2" ] && echo true || echo false)" "A=$R1 B=$R2"
check "They were given different places" \
  "$([ -n "$R1" ] && [ "$R1" != "$R2" ] && echo true || echo false)" "A=$R1 B=$R2"
check "B did not queue behind A (different companies never contend)" \
  "$([ -n "$W2" ] && [ "$W2" -lt 2000 ] && echo true || echo false)" "B waited ${W2}ms"

echo "--- 2. the same company claiming twice at the same moment"
q "$(claim_sql "${MARK} A" 4)" > /tmp/_f3.json &
P3=$!
sleep 1.5
q "$(claim_sql "${MARK} A" 0)" > /tmp/_f4.json &
P4=$!
wait $P3 $P4
R3=$(result_of /tmp/_f3.json); R4=$(result_of /tmp/_f4.json); W4=$(waited_of /tmp/_f4.json)
check "Neither claim errored" \
  "$([ -n "$R3" ] && [ -n "$R4" ] && echo true || echo false)" "first=$(jq -c . /tmp/_f3.json | cut -c1-80) second=$(jq -c . /tmp/_f4.json | cut -c1-80)"
check "The second claim waited for the first instead of racing it" \
  "$([ -n "$W4" ] && [ "$W4" -ge 1500 ] && echo true || echo false)" "second waited ${W4}ms"
# The first rolled back, so the waiting claim legitimately takes place 1 for
# itself. Under the old function it would have skipped the locked place 1
# and taken place 2 — a second place for one company.
check "The same company never reached for a second place" \
  "$([ "$R3" = "1" ] && [ "$R4" = "1" ] && echo true || echo false)" "first=$R3 second=$R4"

echo "--- cleaning up"
q "delete from public.companies where name like '${MARK} %';" > /dev/null
LEFT=$(q "select ((select count(*) from public.companies where name like '${MARK} %')
             + (select count(*) from public.stripe_connect_accounts where stripe_account_id like 'acct_${MARK}_%'))::text as c;" | jq -r '.[0].c')
check "Every fixture is gone" "$([ "$LEFT" = "0" ] && echo true || echo false)" "rows left=$LEFT"
AFTER=$(q "select count(*)::text as c from public.founding_member_slots where claimed_at is not null;" | jq -r '.[0].c')
check "No real founding place was spent" "$([ "$AFTER" = "0" ] && echo true || echo false)" "allocated=$AFTER"

echo
echo "FOUNDING CONCURRENCY TEST — PASS=${PASS} FAIL=${FAIL}"
[ "$FAIL" = "0" ]
