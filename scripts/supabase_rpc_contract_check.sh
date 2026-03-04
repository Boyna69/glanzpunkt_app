#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-${B_EMAIL:-}}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-${B_PASSWORD:-}}"

RPC_STATUS=""
RPC_BODY=""

fail() {
  echo "FAILED: $1" >&2
  exit 1
}

if [ -z "$KEY" ]; then
  fail "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ] || [ -z "$CUSTOMER_EMAIL" ] || [ -z "$CUSTOMER_PASSWORD" ]; then
  echo "Usage: OPERATOR_EMAIL=... OPERATOR_PASSWORD=... CUSTOMER_EMAIL=... CUSTOMER_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_rpc_contract_check.sh"
  echo "   or (legacy): ... SUPABASE_ANON_KEY=... scripts/supabase_rpc_contract_check.sh"
  exit 2
fi

preflight_connectivity() {
  if ! curl -sS --connect-timeout 8 --max-time 15 "$BASE/rest/v1/" >/dev/null; then
    fail "Cannot reach Supabase host ($BASE). Check DNS/network and try again."
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

extract_user_id() {
  echo "$1" | sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p'
}

parse_http_response() {
  local raw="$1"
  RPC_BODY="${raw%$'\n'__HTTP__:*}"
  RPC_STATUS="${raw##*$'\n'__HTTP__:}"
}

rpc_call() {
  local jwt="$1"
  local rpc_name="$2"
  local payload="$3"
  local raw
  raw="$(curl -sS -X POST "$BASE/rest/v1/rpc/$rpc_name" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $jwt" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    -w $'\n__HTTP__:%{http_code}')"
  parse_http_response "$raw"
}

rest_get() {
  local jwt="$1"
  local request_path="$2"
  local raw
  raw="$(curl -sS -X GET "$BASE$request_path" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $jwt" \
    -H "Content-Type: application/json" \
    -w $'\n__HTTP__:%{http_code}')"
  parse_http_response "$raw"
}

assert_not_missing() {
  local label="$1"
  if [ "$RPC_STATUS" = "404" ]; then
    fail "$label missing (HTTP 404): $RPC_BODY"
  fi
  if echo "$RPC_BODY" | grep -Eqi 'PGRST202|Could not find the function|schema cache'; then
    fail "$label missing in deployed schema: $RPC_BODY"
  fi
}

expect_forbidden() {
  local label="$1"
  assert_not_missing "$label"
  if [ "$RPC_STATUS" = "401" ] || [ "$RPC_STATUS" = "403" ]; then
    echo "PASS $label forbidden"
    return
  fi
  if echo "$RPC_BODY" | grep -Eq '"code":"42501"|"message":"forbidden"|permission denied'; then
    echo "PASS $label forbidden"
    return
  fi
  fail "$label expected forbidden, got status=$RPC_STATUS body=$RPC_BODY"
}

expect_success_contains() {
  local label="$1"
  local pattern="$2"
  assert_not_missing "$label"
  if [ "$RPC_STATUS" != "200" ]; then
    fail "$label expected HTTP 200, got $RPC_STATUS body=$RPC_BODY"
  fi
  if ! echo "$RPC_BODY" | grep -Eq "$pattern"; then
    fail "$label missing expected pattern ($pattern): $RPC_BODY"
  fi
  echo "PASS $label"
}

expect_reachable_with_error() {
  local label="$1"
  local pattern="$2"
  assert_not_missing "$label"
  if ! echo "$RPC_BODY" | grep -Eq "$pattern"; then
    fail "$label reachable check failed (pattern=$pattern): status=$RPC_STATUS body=$RPC_BODY"
  fi
  echo "PASS $label reachable"
}

preflight_connectivity

echo "== Login operator =="
OP_LOGIN="$(login "$OPERATOR_EMAIL" "$OPERATOR_PASSWORD")"
OP_JWT="$(extract_access_token "$OP_LOGIN")"
OP_UID="$(extract_user_id "$OP_LOGIN")"
if [ -z "$OP_JWT" ] || [ -z "$OP_UID" ]; then
  echo "$OP_LOGIN"
  fail "operator login failed"
fi
echo "Operator login ok: uid=$OP_UID email=$OPERATOR_EMAIL"

echo "== Login customer =="
CU_LOGIN="$(login "$CUSTOMER_EMAIL" "$CUSTOMER_PASSWORD")"
CU_JWT="$(extract_access_token "$CU_LOGIN")"
CU_UID="$(extract_user_id "$CU_LOGIN")"
if [ -z "$CU_JWT" ] || [ -z "$CU_UID" ]; then
  echo "$CU_LOGIN"
  fail "customer login failed"
fi
echo "Customer login ok: uid=$CU_UID email=$CUSTOMER_EMAIL"

echo "== Public read contract: boxes =="
rest_get "$CU_JWT" "/rest/v1/boxes?select=id,status,remaining_seconds,updated_at&limit=1"
expect_success_contains "boxes select contract" '^(\[.*\])$'

echo "== Wash RPC contract (operator/customer) =="
rpc_call "$OP_JWT" "status" '{"box_id":1}'
expect_success_contains "rpc.status" '"state"'

rpc_call "$OP_JWT" "recent_sessions" '{"max_rows":1}'
expect_success_contains "rpc.recent_sessions" '^\['

rpc_call "$CU_JWT" "reserve" '{"box_id":-1}'
expect_reachable_with_error "rpc.reserve" 'box_not_found|box_unavailable|invalid|unauthorized|permission denied'

rpc_call "$CU_JWT" "activate" '{"box_id":1,"amount":0}'
expect_reachable_with_error "rpc.activate" 'invalid_amount|box_not_found|box_unavailable|unauthorized|permission denied'

rpc_call "$CU_JWT" "stop" '{"session_id":"invalid"}'
expect_reachable_with_error "rpc.stop" 'invalid_session_id|session_not_active|unauthorized|permission denied'

rpc_call "$OP_JWT" "expire_active_sessions" '{}'
expect_success_contains "rpc.expire_active_sessions" '"updatedBoxes"'

echo "== Operator-only RPC contract (operator allowed) =="
rpc_call "$OP_JWT" "monitoring_snapshot" '{}'
expect_success_contains "rpc.monitoring_snapshot" '"boxes"'

rpc_call "$OP_JWT" "get_box_cleaning_plan" '{"cleaning_interval":75}'
expect_success_contains "rpc.get_box_cleaning_plan" '"box_id"'

rpc_call "$OP_JWT" "get_box_cleaning_history" '{"box_id":1,"max_rows":1}'
expect_success_contains "rpc.get_box_cleaning_history" '^\['

rpc_call "$OP_JWT" "list_operator_actions_filtered" '{"max_rows":1}'
expect_success_contains "rpc.list_operator_actions_filtered" '^\['

rpc_call "$OP_JWT" "get_operator_threshold_settings" '{}'
expect_success_contains "rpc.get_operator_threshold_settings" '"cleaning_interval_washes"'

rpc_call "$OP_JWT" "kpi_export" '{"period":"day"}'
expect_success_contains "rpc.kpi_export" '"period"[[:space:]]*:[[:space:]]*"day"'

echo "== Operator-only RPC contract (customer denied) =="
rpc_call "$CU_JWT" "monitoring_snapshot" '{}'
expect_forbidden "customer rpc.monitoring_snapshot"

rpc_call "$CU_JWT" "get_box_cleaning_plan" '{"cleaning_interval":75}'
expect_forbidden "customer rpc.get_box_cleaning_plan"

rpc_call "$CU_JWT" "mark_box_cleaned" '{"box_id":1}'
expect_forbidden "customer rpc.mark_box_cleaned"

rpc_call "$CU_JWT" "list_operator_actions_filtered" '{"max_rows":1}'
expect_forbidden "customer rpc.list_operator_actions_filtered"

rpc_call "$CU_JWT" "get_operator_threshold_settings" '{}'
expect_forbidden "customer rpc.get_operator_threshold_settings"

rpc_call "$CU_JWT" "set_operator_threshold_settings" '{"cleaning_interval_washes":90,"long_active_minutes":25}'
expect_forbidden "customer rpc.set_operator_threshold_settings"

rpc_call "$CU_JWT" "kpi_export" '{"period":"day"}'
expect_forbidden "customer rpc.kpi_export"

rpc_call "$CU_JWT" "expire_active_sessions_internal" '{}'
expect_forbidden "customer rpc.expire_active_sessions_internal"

echo
echo "RPC CONTRACT CHECK PASSED"
