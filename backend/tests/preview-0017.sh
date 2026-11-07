#!/bin/bash
# Preview migration 0017 against the live database WITHOUT deploying it.
#
# Each batch = (optionally) the body of 0017 without begin/commit, followed by
# one test suite. Every suite ends in `raise exception`, so the management API
# runs the whole batch in one transaction that is ALWAYS rolled back: the
# migration, the switch row and every fixture disappear. Nothing persists
# (sequences may advance; replaced functions are locked for the few seconds
# the batch runs).
#
# Usage: SUPABASE_ACCESS_TOKEN=... backend/tests/preview-0017.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
REF=srfnfimskixjqjyyftak
MIG="$DIR/migrations/0017_apple_sandbox_review_access.sql"
BODY="$(sed -e '/^begin;$/d' -e '/^commit;$/d' "$MIG")"

run() { # $1 label, $2 sql
  local out
  out=$(curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
    --data-binary @<(jq -n --rawfile q <(printf '%s' "$2") '{query:$q, read_only:false}'))
  echo "=== $1"
  echo "$out" | jq -r '.message // .' | grep -E "SUITE|FAIL|ERROR|error" || echo "$out"
}

run "Baseline (live, no migration): subscription-entitlement-suite" "$(cat "$DIR/tests/subscription-entitlement-suite.sql")"
run "0017 + subscription-entitlement-suite (unchanged)" "$BODY
$(cat "$DIR/tests/subscription-entitlement-suite.sql")"
run "0017 + apple-sandbox-review-suite" "$BODY
$(cat "$DIR/tests/apple-sandbox-review-suite.sql")"
run "0017 + sms-multitenant-suite (unchanged)" "$BODY
$(cat "$DIR/tests/sms-multitenant-suite.sql")"
run "0017 + sms-credit-suite (unchanged)" "$BODY
$(cat "$DIR/tests/sms-credit-suite.sql")"
run "0017 + rollback file body + subscription-entitlement-suite" "$BODY
$(sed -e '/^begin;$/d' -e '/^commit;$/d' "$DIR/migrations/rollback/0017_rollback_restore_pre_0017.sql")
$(cat "$DIR/tests/subscription-entitlement-suite.sql")"
echo "=== Post-check: live state unchanged (read-only)"
curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg q "select (select count(*) from public.platform_settings where key='apple_sandbox_any_company') as switch_rows, (select count(*) from public.apple_transactions) as ledger_rows, (select count(*) from public.companies) as companies, (select bool_or(prosrc like '%apple_sandbox_any_company%') from pg_proc where proname='apple_apply_transaction') as live_has_0017" '{query:$q, read_only:true}')"
echo
