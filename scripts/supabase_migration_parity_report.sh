#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SUPABASE_API_KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-${B_EMAIL:-}}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-${B_PASSWORD:-}}"

if [ -z "$SUPABASE_API_KEY" ]; then
  echo "FAILED: SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY is required."
  exit 2
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ] || [ -z "$CUSTOMER_EMAIL" ] || [ -z "$CUSTOMER_PASSWORD" ]; then
  echo "FAILED: operator/customer credentials are required."
  echo "Usage:"
  echo "  OPERATOR_EMAIL=... OPERATOR_PASSWORD=... CUSTOMER_EMAIL=... CUSTOMER_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=... scripts/supabase_migration_parity_report.sh"
  echo "Or shorthand:"
  echo "  A_EMAIL=... A_PASSWORD=... B_EMAIL=... B_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=... scripts/supabase_migration_parity_report.sh"
  exit 2
fi

echo "== Migration parity report: RPC contract =="
OPERATOR_EMAIL="$OPERATOR_EMAIL" OPERATOR_PASSWORD="$OPERATOR_PASSWORD" \
CUSTOMER_EMAIL="$CUSTOMER_EMAIL" CUSTOMER_PASSWORD="$CUSTOMER_PASSWORD" \
SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
"$ROOT/scripts/supabase_rpc_contract_check.sh"

echo "== Migration parity report: role access =="
OPERATOR_EMAIL="$OPERATOR_EMAIL" OPERATOR_PASSWORD="$OPERATOR_PASSWORD" \
CUSTOMER_EMAIL="$CUSTOMER_EMAIL" CUSTOMER_PASSWORD="$CUSTOMER_PASSWORD" \
SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
"$ROOT/scripts/supabase_role_access_check.sh"

echo "== Migration parity report: table exposure =="
CUSTOMER_EMAIL="$CUSTOMER_EMAIL" CUSTOMER_PASSWORD="$CUSTOMER_PASSWORD" \
SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
"$ROOT/scripts/supabase_table_exposure_check.sh"

echo "== Migration parity report: operator health =="
OPERATOR_EMAIL="$OPERATOR_EMAIL" OPERATOR_PASSWORD="$OPERATOR_PASSWORD" \
SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
"$ROOT/scripts/supabase_operator_health_check.sh"

echo "MIGRATION PARITY REPORT PASSED"
