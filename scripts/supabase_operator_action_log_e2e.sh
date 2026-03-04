#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-${B_EMAIL:-}}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-${B_PASSWORD:-}}"
BOX_ID="${BOX_ID:-1}"
ACTION_NAME="${ACTION_NAME:-e2e_operator_log}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ] || [ -z "$CUSTOMER_EMAIL" ] || [ -z "$CUSTOMER_PASSWORD" ]; then
  echo "Missing credentials."
  echo "Usage: OPERATOR_EMAIL=... OPERATOR_PASSWORD=... CUSTOMER_EMAIL=... CUSTOMER_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_operator_action_log_e2e.sh"
  echo "   or (legacy): ... SUPABASE_ANON_KEY=... scripts/supabase_operator_action_log_e2e.sh"
  exit 2
fi

preflight_connectivity() {
  if ! curl -sS --connect-timeout 8 --max-time 15 "$BASE/rest/v1/" >/dev/null; then
    echo "FAILED: Cannot reach Supabase host ($BASE). Check DNS/network and try again." >&2
    exit 3
  fi
}

fail() {
  echo "FAILED: $1" >&2
  exit 1
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

assert_no_error_code() {
  local payload="$1"
  local step="$2"
  if echo "$payload" | grep -q '"code"'; then
    fail "$step returned error payload: $payload"
  fi
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
  if echo "$payload" | grep -q 'permission denied'; then
    echo "PASS $label forbidden"
    return
  fi
  fail "$label expected forbidden but got: $payload"
}

expect_write_blocked() {
  local payload="$1"
  local label="$2"
  if echo "$payload" | grep -q '"message":"forbidden"'; then
    echo "PASS $label blocked (forbidden)"
    return
  fi
  if echo "$payload" | grep -q '"code":"42501"'; then
    echo "PASS $label blocked (42501)"
    return
  fi
  if echo "$payload" | grep -q 'permission denied'; then
    echo "PASS $label blocked (permission denied)"
    return
  fi
  if [ "$(echo "$payload" | tr -d '[:space:]')" = "[]" ]; then
    echo "PASS $label blocked (0 affected rows)"
    return
  fi
  fail "$label expected blocked write but got: $payload"
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

op_hdr=(
  -H "apikey: $KEY"
  -H "Authorization: Bearer $OP_JWT"
  -H "Content-Type: application/json"
)

cu_hdr=(
  -H "apikey: $KEY"
  -H "Authorization: Bearer $CU_JWT"
  -H "Content-Type: application/json"
)

echo "== Operator logs action =="
LOG_RESULT="$(curl -sS -X POST "$BASE/rest/v1/rpc/log_operator_action" "${op_hdr[@]}" -d "{\"action_name\":\"$ACTION_NAME\",\"action_status\":\"success\",\"box_id\":$BOX_ID,\"source\":\"app\",\"details\":{\"kind\":\"e2e\",\"note\":\"operator_action_log\"}}")"
echo "$LOG_RESULT"
assert_no_error_code "$LOG_RESULT" "log_operator_action as operator"
if ! echo "$LOG_RESULT" | grep -Eq "\"action_name\"[[:space:]]*:[[:space:]]*\"$ACTION_NAME\""; then
  fail "log_operator_action did not return expected action_name"
fi
LOG_ID="$(echo "$LOG_RESULT" | sed -n 's/.*"id":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
if [ -z "$LOG_ID" ]; then
  fail "log_operator_action did not return a valid id"
fi

echo "== Operator reads filtered action log =="
LIST_OPERATOR="$(curl -sS -X POST "$BASE/rest/v1/rpc/list_operator_actions_filtered" "${op_hdr[@]}" -d "{\"max_rows\":30,\"offset_rows\":0,\"filter_status\":\"success\",\"filter_box_id\":$BOX_ID,\"search_query\":\"$ACTION_NAME\"}")"
echo "$LIST_OPERATOR"
assert_no_error_code "$LIST_OPERATOR" "list_operator_actions_filtered as operator"
if ! echo "$LIST_OPERATOR" | grep -Eq "\"action_name\"[[:space:]]*:[[:space:]]*\"$ACTION_NAME\""; then
  fail "list_operator_actions_filtered does not include expected action"
fi
if ! echo "$LIST_OPERATOR" | grep -Eq "\"action_status\"[[:space:]]*:[[:space:]]*\"success\""; then
  fail "list_operator_actions_filtered does not include expected action status"
fi

echo "== Customer tries to read action log (must fail) =="
LIST_CUSTOMER="$(curl -sS -X POST "$BASE/rest/v1/rpc/list_operator_actions_filtered" "${cu_hdr[@]}" -d '{"max_rows":5}')"
echo "$LIST_CUSTOMER"
expect_forbidden "$LIST_CUSTOMER" "customer list_operator_actions_filtered"

echo "== Customer tries to write action log (must fail) =="
LOG_CUSTOMER="$(curl -sS -X POST "$BASE/rest/v1/rpc/log_operator_action" "${cu_hdr[@]}" -d "{\"action_name\":\"$ACTION_NAME\",\"action_status\":\"success\",\"box_id\":$BOX_ID,\"source\":\"app\",\"details\":{\"kind\":\"e2e\"}}")"
echo "$LOG_CUSTOMER"
expect_forbidden "$LOG_CUSTOMER" "customer log_operator_action"

echo "== Operator tries direct PATCH on operator_action_log (must fail) =="
PATCH_OPERATOR="$(curl -sS -X PATCH "$BASE/rest/v1/operator_action_log?id=eq.$LOG_ID" "${op_hdr[@]}" -H 'Prefer: return=representation' -d '{"action_status":"failed"}')"
echo "$PATCH_OPERATOR"
expect_write_blocked "$PATCH_OPERATOR" "operator direct patch operator_action_log"

echo "== Operator tries direct DELETE on operator_action_log (must fail) =="
DELETE_OPERATOR="$(curl -sS -X DELETE "$BASE/rest/v1/operator_action_log?id=eq.$LOG_ID" "${op_hdr[@]}" -H 'Prefer: return=representation')"
echo "$DELETE_OPERATOR"
expect_write_blocked "$DELETE_OPERATOR" "operator direct delete operator_action_log"

echo
echo "OPERATOR ACTION LOG E2E PASSED"
