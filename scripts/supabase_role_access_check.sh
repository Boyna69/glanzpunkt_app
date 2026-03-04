#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$CUSTOMER_EMAIL" ] || [ -z "$CUSTOMER_PASSWORD" ] || [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ]; then
  echo "Missing credentials."
  echo "Usage: CUSTOMER_EMAIL=... CUSTOMER_PASSWORD=... OPERATOR_EMAIL=... OPERATOR_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_role_access_check.sh"
  echo "   or (legacy): ... SUPABASE_ANON_KEY=... scripts/supabase_role_access_check.sh"
  exit 2
fi

preflight_connectivity() {
  if ! curl -sS --connect-timeout 8 --max-time 15 "$BASE/rest/v1/" >/dev/null; then
    echo "FAILED: Cannot reach Supabase host ($BASE). Check DNS/network and try again." >&2
    exit 3
  fi
}

login() {
  local email="$1"
  local pass="$2"
  curl -sS -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
}

extract_access_token() {
  echo "$1" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

expect_forbidden() {
  local payload="$1"
  local label="$2"
  if echo "$payload" | grep -q '"message":"forbidden"'; then
    echo "PASS $label forbidden"
    return
  fi
  if echo "$payload" | grep -q '"code":"42501"'; then
    echo "PASS $label forbidden"
    return
  fi
  echo "FAIL $label expected forbidden but got: $payload"
  exit 1
}

expect_ok_monitoring() {
  local payload="$1"
  local label="$2"
  if echo "$payload" | grep -q '"boxes"'; then
    echo "PASS $label allowed"
    return
  fi
  echo "FAIL $label expected monitoring payload but got: $payload"
  exit 1
}

expect_ok_expire() {
  local payload="$1"
  local label="$2"
  if echo "$payload" | grep -q '"updatedBoxes"'; then
    echo "PASS $label allowed"
    return
  fi
  echo "FAIL $label expected expire payload but got: $payload"
  exit 1
}

expect_ok_cleaning_plan() {
  local payload="$1"
  local label="$2"
  if echo "$payload" | grep -q '"box_id"'; then
    echo "PASS $label allowed"
    return
  fi
  echo "FAIL $label expected cleaning plan payload but got: $payload"
  exit 1
}

expect_ok_mark_cleaned() {
  local payload="$1"
  local label="$2"
  if echo "$payload" | grep -q '"box_id"'; then
    echo "PASS $label allowed"
    return
  fi
  echo "FAIL $label expected mark cleaned payload but got: $payload"
  exit 1
}

preflight_connectivity

echo "== Login customer =="
CUSTOMER_LOGIN="$(login "$CUSTOMER_EMAIL" "$CUSTOMER_PASSWORD")"
CUSTOMER_JWT="$(extract_access_token "$CUSTOMER_LOGIN")"
if [ -z "$CUSTOMER_JWT" ]; then
  echo "FAILED: customer login failed"
  echo "$CUSTOMER_LOGIN"
  exit 3
fi

echo "== Login operator =="
OPERATOR_LOGIN="$(login "$OPERATOR_EMAIL" "$OPERATOR_PASSWORD")"
OPERATOR_JWT="$(extract_access_token "$OPERATOR_LOGIN")"
if [ -z "$OPERATOR_JWT" ]; then
  echo "FAILED: operator login failed"
  echo "$OPERATOR_LOGIN"
  exit 3
fi

customer_hdr=(
  -H "apikey: $KEY"
  -H "Authorization: Bearer $CUSTOMER_JWT"
  -H "Content-Type: application/json"
)

operator_hdr=(
  -H "apikey: $KEY"
  -H "Authorization: Bearer $OPERATOR_JWT"
  -H "Content-Type: application/json"
)

echo "== Customer calls monitoring_snapshot (must fail) =="
MON_CUSTOMER="$(curl -sS -X POST "$BASE/rest/v1/rpc/monitoring_snapshot" "${customer_hdr[@]}" -d '{}')"
echo "$MON_CUSTOMER"
expect_forbidden "$MON_CUSTOMER" "customer monitoring_snapshot"

echo "== Customer calls expire_active_sessions (must fail) =="
EXP_CUSTOMER="$(curl -sS -X POST "$BASE/rest/v1/rpc/expire_active_sessions" "${customer_hdr[@]}" -d '{}')"
echo "$EXP_CUSTOMER"
expect_forbidden "$EXP_CUSTOMER" "customer expire_active_sessions"

echo "== Customer calls expire_active_sessions_internal (must fail) =="
EXP_INTERNAL_CUSTOMER="$(curl -sS -X POST "$BASE/rest/v1/rpc/expire_active_sessions_internal" "${customer_hdr[@]}" -d '{}')"
echo "$EXP_INTERNAL_CUSTOMER"
expect_forbidden "$EXP_INTERNAL_CUSTOMER" "customer expire_active_sessions_internal"

echo "== Customer calls get_box_cleaning_plan (must fail) =="
CLEAN_PLAN_CUSTOMER="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_box_cleaning_plan" "${customer_hdr[@]}" -d '{"cleaning_interval":75}')"
echo "$CLEAN_PLAN_CUSTOMER"
expect_forbidden "$CLEAN_PLAN_CUSTOMER" "customer get_box_cleaning_plan"

echo "== Customer calls mark_box_cleaned (must fail) =="
MARK_CLEANED_CUSTOMER="$(curl -sS -X POST "$BASE/rest/v1/rpc/mark_box_cleaned" "${customer_hdr[@]}" -d '{"box_id":1}')"
echo "$MARK_CLEANED_CUSTOMER"
expect_forbidden "$MARK_CLEANED_CUSTOMER" "customer mark_box_cleaned"

echo "== Operator calls monitoring_snapshot (must pass) =="
MON_OPERATOR="$(curl -sS -X POST "$BASE/rest/v1/rpc/monitoring_snapshot" "${operator_hdr[@]}" -d '{}')"
echo "$MON_OPERATOR"
expect_ok_monitoring "$MON_OPERATOR" "operator monitoring_snapshot"

echo "== Operator calls expire_active_sessions (must pass) =="
EXP_OPERATOR="$(curl -sS -X POST "$BASE/rest/v1/rpc/expire_active_sessions" "${operator_hdr[@]}" -d '{}')"
echo "$EXP_OPERATOR"
expect_ok_expire "$EXP_OPERATOR" "operator expire_active_sessions"

echo "== Operator calls get_box_cleaning_plan (must pass) =="
CLEAN_PLAN_OPERATOR="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_box_cleaning_plan" "${operator_hdr[@]}" -d '{"cleaning_interval":75}')"
echo "$CLEAN_PLAN_OPERATOR"
expect_ok_cleaning_plan "$CLEAN_PLAN_OPERATOR" "operator get_box_cleaning_plan"

echo "== Operator calls mark_box_cleaned (must pass) =="
MARK_CLEANED_OPERATOR="$(curl -sS -X POST "$BASE/rest/v1/rpc/mark_box_cleaned" "${operator_hdr[@]}" -d '{"box_id":1}')"
echo "$MARK_CLEANED_OPERATOR"
expect_ok_mark_cleaned "$MARK_CLEANED_OPERATOR" "operator mark_box_cleaned"

echo "== Operator calls expire_active_sessions_internal (must fail) =="
EXP_INTERNAL_OPERATOR="$(curl -sS -X POST "$BASE/rest/v1/rpc/expire_active_sessions_internal" "${operator_hdr[@]}" -d '{}')"
echo "$EXP_INTERNAL_OPERATOR"
expect_forbidden "$EXP_INTERNAL_OPERATOR" "operator expire_active_sessions_internal"

echo
echo "ROLE ACCESS CHECK PASSED"
