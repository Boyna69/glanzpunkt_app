#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-${B_EMAIL:-}}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-${B_PASSWORD:-}}"
BOX_ID="${BOX_ID:-1}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ] || [ -z "$CUSTOMER_EMAIL" ] || [ -z "$CUSTOMER_PASSWORD" ]; then
  echo "Missing credentials."
  echo "Usage: OPERATOR_EMAIL=... OPERATOR_PASSWORD=... CUSTOMER_EMAIL=... CUSTOMER_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_uat_ticket_update_e2e.sh"
  echo "   or (legacy): ... SUPABASE_ANON_KEY=... scripts/supabase_uat_ticket_update_e2e.sh"
  exit 2
fi

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

extract_int_field() {
  local payload="$1"
  local field="$2"
  echo "$payload" | sed -n "s/.*\"$field\":[[:space:]]*\([0-9][0-9]*\).*/\1/p" | head -n1
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

echo "== Login operator =="
OP_LOGIN="$(login "$OPERATOR_EMAIL" "$OPERATOR_PASSWORD")"
OP_JWT="$(extract_access_token "$OP_LOGIN")"
if [ -z "$OP_JWT" ]; then
  echo "$OP_LOGIN"
  fail "operator login failed"
fi

echo "== Login customer =="
CU_LOGIN="$(login "$CUSTOMER_EMAIL" "$CUSTOMER_PASSWORD")"
CU_JWT="$(extract_access_token "$CU_LOGIN")"
if [ -z "$CU_JWT" ]; then
  echo "$CU_LOGIN"
  fail "customer login failed"
fi

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

echo "== Operator creates UAT ticket =="
CREATE_PAYLOAD="$(curl -sS -X POST "$BASE/rest/v1/rpc/log_operator_action" "${op_hdr[@]}" -d "{\"action_name\":\"uat_manual_report\",\"action_status\":\"failed\",\"box_id\":$BOX_ID,\"source\":\"app\",\"details\":{\"summary\":\"E2E UAT Ticket\",\"area\":\"wallet\",\"uat_status\":\"open\",\"severity\":\"high\",\"target_build\":\"e2e\"}}")"
echo "$CREATE_PAYLOAD"
assert_no_error_code "$CREATE_PAYLOAD" "log_operator_action"
TICKET_ID="$(extract_int_field "$CREATE_PAYLOAD" "id")"
if [ -z "$TICKET_ID" ]; then
  fail "ticket id missing"
fi

echo "== Operator sets ticket status to in_progress =="
STATUS_PAYLOAD="$(curl -sS -X POST "$BASE/rest/v1/rpc/set_uat_ticket_status" "${op_hdr[@]}" -d "{\"ticket_id\":$TICKET_ID,\"uat_status\":\"in_progress\",\"note\":\"E2E status update\"}")"
echo "$STATUS_PAYLOAD"
assert_no_error_code "$STATUS_PAYLOAD" "set_uat_ticket_status"
if ! echo "$STATUS_PAYLOAD" | grep -Eq "\"ticket_id\"[[:space:]]*:[[:space:]]*$TICKET_ID"; then
  fail "set_uat_ticket_status response does not contain ticket_id"
fi
if ! echo "$STATUS_PAYLOAD" | grep -Eq '"uat_status"[[:space:]]*:[[:space:]]*"in_progress"'; then
  fail "set_uat_ticket_status response does not contain in_progress"
fi

echo "== Operator assigns ticket owner =="
OWNER_PAYLOAD="$(curl -sS -X POST "$BASE/rest/v1/rpc/assign_uat_ticket_owner" "${op_hdr[@]}" -d "{\"ticket_id\":$TICKET_ID,\"owner_email\":\"$OPERATOR_EMAIL\",\"note\":\"E2E owner assign\"}")"
echo "$OWNER_PAYLOAD"
assert_no_error_code "$OWNER_PAYLOAD" "assign_uat_ticket_owner"
if ! echo "$OWNER_PAYLOAD" | grep -Eq "\"ticket_id\"[[:space:]]*:[[:space:]]*$TICKET_ID"; then
  fail "assign_uat_ticket_owner response does not contain ticket_id"
fi
if ! echo "$OWNER_PAYLOAD" | grep -Eq "\"owner_email\"[[:space:]]*:[[:space:]]*\"$OPERATOR_EMAIL\""; then
  fail "assign_uat_ticket_owner response does not contain expected owner_email"
fi

echo "== Operator reads audit updates =="
LIST_PAYLOAD="$(curl -sS -X POST "$BASE/rest/v1/rpc/list_operator_actions_filtered" "${op_hdr[@]}" -d "{\"max_rows\":40,\"search_query\":\"$TICKET_ID\"}")"
echo "$LIST_PAYLOAD"
assert_no_error_code "$LIST_PAYLOAD" "list_operator_actions_filtered"
if ! echo "$LIST_PAYLOAD" | grep -q '"action_name":"uat_ticket_status_updated"'; then
  fail "missing uat_ticket_status_updated audit entry"
fi
if ! echo "$LIST_PAYLOAD" | grep -q '"action_name":"uat_ticket_owner_assigned"'; then
  fail "missing uat_ticket_owner_assigned audit entry"
fi

echo "== Customer tries set_uat_ticket_status (must fail) =="
CU_STATUS="$(curl -sS -X POST "$BASE/rest/v1/rpc/set_uat_ticket_status" "${cu_hdr[@]}" -d "{\"ticket_id\":$TICKET_ID,\"uat_status\":\"closed\"}")"
echo "$CU_STATUS"
expect_forbidden "$CU_STATUS" "customer set_uat_ticket_status"

echo "== Customer tries assign_uat_ticket_owner (must fail) =="
CU_OWNER="$(curl -sS -X POST "$BASE/rest/v1/rpc/assign_uat_ticket_owner" "${cu_hdr[@]}" -d "{\"ticket_id\":$TICKET_ID,\"owner_email\":\"$CUSTOMER_EMAIL\"}")"
echo "$CU_OWNER"
expect_forbidden "$CU_OWNER" "customer assign_uat_ticket_owner"

echo

echo "UAT TICKET UPDATE E2E PASSED"
