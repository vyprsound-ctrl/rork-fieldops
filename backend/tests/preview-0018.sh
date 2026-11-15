#!/bin/bash
# Preview migration 0018 against the live database WITHOUT deploying it.
# Each batch = 0018 body + one suite. Every suite ends in `raise exception`, so
# the batch is always rolled back: no migration, fixture or row persists.
# Usage (Rork sandbox): backend/tests/preview-0018.sh
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
MIG="$DIR/migrations/0018_engineer_financial_permissions_and_business_types.sql"
TYPES="${TMPDIR:-/tmp}/types-preview.ts"

for suite in engineer-financial-permissions-suite write-lifecycle-suite backend-security-suite invitation-suite; do
  echo "=== 0018 + $suite"
  cat "$MIG" "$DIR/tests/$suite.sql" \
    | rork supabase migrate - --name "preview_0018" --types "$TYPES" --json \
    | grep -oE "(PASS|pass)=[0-9]+ (FAIL|fail)=[0-9]+" || echo "(no suite report - inspect output)"
done
