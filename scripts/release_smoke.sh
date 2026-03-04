#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SUPABASE_API_KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"

echo "== Flutter analyze =="
flutter analyze

echo "== Flutter test =="
flutter test

if [ "${RUN_SUPABASE_SMOKE:-0}" = "1" ]; then
  if [ -z "${A_EMAIL:-}" ] || [ -z "${A_PASSWORD:-}" ] || [ -z "${B_EMAIL:-}" ] || [ -z "${B_PASSWORD:-}" ]; then
    echo "FAILED: RUN_SUPABASE_SMOKE=1 requires A_EMAIL/A_PASSWORD/B_EMAIL/B_PASSWORD" >&2
    exit 2
  fi
  if [ -z "$SUPABASE_API_KEY" ]; then
    echo "FAILED: RUN_SUPABASE_SMOKE=1 requires SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY" >&2
    exit 2
  fi

  echo "== Supabase A/B isolation check =="
  A_EMAIL="$A_EMAIL" A_PASSWORD="$A_PASSWORD" B_EMAIL="$B_EMAIL" B_PASSWORD="$B_PASSWORD" SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
    "$ROOT/scripts/supabase_ab_isolation_login_only.sh"

  echo "== Supabase quick RPC flow check =="
  WAIT="${SUPABASE_WAIT_SECONDS:-130}"
  A_EMAIL="$A_EMAIL" A_PASSWORD="$A_PASSWORD" SUPABASE_ANON_KEY="$SUPABASE_API_KEY" BOX_ID="1" AMOUNT="1" WAIT_SECONDS="$WAIT" \
    "$ROOT/scripts/supabase_activate_countdown_e2e.sh"

  if [ "${RUN_SUPABASE_SECURITY_SUITE:-1}" = "1" ]; then
    if [ "${RUN_SUPABASE_CONTRACT_CHECK:-1}" = "1" ]; then
      echo "== Supabase RPC contract check =="
      OPERATOR_EMAIL="$A_EMAIL" OPERATOR_PASSWORD="$A_PASSWORD" \
        CUSTOMER_EMAIL="$B_EMAIL" CUSTOMER_PASSWORD="$B_PASSWORD" \
        SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
        "$ROOT/scripts/supabase_rpc_contract_check.sh"
    fi

    echo "== Supabase role access check =="
    CUSTOMER_EMAIL="$B_EMAIL" CUSTOMER_PASSWORD="$B_PASSWORD" \
      OPERATOR_EMAIL="$A_EMAIL" OPERATOR_PASSWORD="$A_PASSWORD" \
      SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
      "$ROOT/scripts/supabase_role_access_check.sh"

    if [ "${RUN_SUPABASE_TABLE_EXPOSURE_CHECK:-1}" = "1" ]; then
      echo "== Supabase table exposure check =="
      CUSTOMER_EMAIL="$B_EMAIL" CUSTOMER_PASSWORD="$B_PASSWORD" \
        SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
        "$ROOT/scripts/supabase_table_exposure_check.sh"
    fi

    if [ "${RUN_SUPABASE_OPERATOR_HEALTH_CHECK:-1}" = "1" ]; then
      echo "== Supabase operator health check =="
      OPERATOR_EMAIL="$A_EMAIL" OPERATOR_PASSWORD="$A_PASSWORD" \
        SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
        "$ROOT/scripts/supabase_operator_health_check.sh"
    fi

    echo "== Supabase cleaning workflow e2e =="
      OPERATOR_EMAIL="$A_EMAIL" OPERATOR_PASSWORD="$A_PASSWORD" \
      CUSTOMER_EMAIL="$B_EMAIL" CUSTOMER_PASSWORD="$B_PASSWORD" \
      SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
      BOX_ID="${SUPABASE_CLEANING_BOX_ID:-1}" \
      "$ROOT/scripts/supabase_cleaning_workflow_e2e.sh"

    echo "== Supabase operator action log e2e =="
      OPERATOR_EMAIL="$A_EMAIL" OPERATOR_PASSWORD="$A_PASSWORD" \
      CUSTOMER_EMAIL="$B_EMAIL" CUSTOMER_PASSWORD="$B_PASSWORD" \
      SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
      BOX_ID="${SUPABASE_OPERATOR_LOG_BOX_ID:-1}" \
      "$ROOT/scripts/supabase_operator_action_log_e2e.sh"

    echo "== Supabase KPI export e2e =="
      OPERATOR_EMAIL="$A_EMAIL" OPERATOR_PASSWORD="$A_PASSWORD" \
      CUSTOMER_EMAIL="$B_EMAIL" CUSTOMER_PASSWORD="$B_PASSWORD" \
      SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
      "$ROOT/scripts/supabase_operator_kpi_export_e2e.sh"

    echo "== Supabase operator threshold settings e2e =="
      THRESH_OWNER_EMAIL="${OWNER_EMAIL:-$A_EMAIL}"
      THRESH_OWNER_PASSWORD="${OWNER_PASSWORD:-$A_PASSWORD}"
      THRESH_NON_OWNER_EMAIL=""
      THRESH_NON_OWNER_PASSWORD=""
      if [ "${THRESH_OWNER_EMAIL}" != "${A_EMAIL}" ]; then
        THRESH_NON_OWNER_EMAIL="$A_EMAIL"
        THRESH_NON_OWNER_PASSWORD="$A_PASSWORD"
      fi
      CUSTOMER_EMAIL="$B_EMAIL" CUSTOMER_PASSWORD="$B_PASSWORD" \
      OPERATOR_EMAIL="$THRESH_OWNER_EMAIL" OPERATOR_PASSWORD="$THRESH_OWNER_PASSWORD" \
      NON_OWNER_EMAIL="$THRESH_NON_OWNER_EMAIL" NON_OWNER_PASSWORD="$THRESH_NON_OWNER_PASSWORD" \
      SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
      "$ROOT/scripts/supabase_operator_threshold_settings_e2e.sh"
  fi

  if [ "${RUN_SUPABASE_BOX_CYCLE:-0}" = "1" ]; then
    if [ -z "$SUPABASE_API_KEY" ]; then
      echo "FAILED: RUN_SUPABASE_BOX_CYCLE=1 requires SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY" >&2
      exit 2
    fi
    echo "== Supabase full box cycle check (1-6) =="
    A_EMAIL="$A_EMAIL" A_PASSWORD="$A_PASSWORD" SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
      BOX_IDS="${SUPABASE_BOX_IDS:-1 2 3 4 5 6}" AMOUNT="${SUPABASE_BOX_CYCLE_AMOUNT:-1}" \
      "$ROOT/scripts/supabase_box_cycle_e2e.sh"
  fi
fi

echo "SMOKE CHECKS PASSED"
