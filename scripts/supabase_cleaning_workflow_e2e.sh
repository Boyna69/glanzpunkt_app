#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"

OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-${B_EMAIL:-}}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-${B_PASSWORD:-}}"

BOX_ID="${BOX_ID:-1}"
CLEANING_INTERVAL="${CLEANING_INTERVAL:-75}"
MARK_NOTE="${MARK_NOTE:-E2E cleaning note}"

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ]; then
  echo "Missing operator credentials."
  echo "Usage: OPERATOR_EMAIL='mail' OPERATOR_PASSWORD='pass' SUPABASE_PUBLISHABLE_KEY='sb_publishable_...' scripts/supabase_cleaning_workflow_e2e.sh"
  echo "   or (legacy): OPERATOR_EMAIL='mail' OPERATOR_PASSWORD='pass' SUPABASE_ANON_KEY='...' scripts/supabase_cleaning_workflow_e2e.sh"
  exit 2
fi

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
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
  fail "$label expected forbidden but got: $payload"
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

extract_washes_since_cleaning() {
  local payload="$1"
  local washes
  washes="$(echo "$payload" | sed -n 's/.*"washes_since_cleaning":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  echo "$washes"
}

extract_last_cleaned_at() {
  local payload="$1"
  local last_cleaned
  last_cleaned="$(echo "$payload" | sed -n 's/.*"last_cleaned_at":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [ -n "$last_cleaned" ]; then
    echo "$last_cleaned"
    return
  fi
  if echo "$payload" | grep -q '"last_cleaned_at":[[:space:]]*null'; then
    echo "null"
    return
  fi
  echo ""
}

preflight_connectivity

echo "== Login operator =="
OP_LOGIN="$(login "$OPERATOR_EMAIL" "$OPERATOR_PASSWORD")"
OP_JWT="$(extract_access_token "$OP_LOGIN")"
if [ -z "$OP_JWT" ]; then
  echo "$OP_LOGIN"
  fail "operator login failed"
fi

op_hdr=(
  -H "apikey: $KEY"
  -H "Authorization: Bearer $OP_JWT"
  -H "Content-Type: application/json"
)

echo "== Operator reads cleaning plan for box $BOX_ID (before) =="
PLAN_BEFORE="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_box_cleaning_plan?box_id=eq.$BOX_ID" "${op_hdr[@]}" -d "{\"cleaning_interval\":$CLEANING_INTERVAL}")"
echo "$PLAN_BEFORE"
assert_no_error_code "$PLAN_BEFORE" "get_box_cleaning_plan before"
if ! echo "$PLAN_BEFORE" | grep -Eq "\"box_id\"[[:space:]]*:[[:space:]]*$BOX_ID"; then
  fail "cleaning plan before does not include box $BOX_ID"
fi

WASHES_BEFORE="$(extract_washes_since_cleaning "$PLAN_BEFORE")"
LAST_CLEANED_BEFORE="$(extract_last_cleaned_at "$PLAN_BEFORE")"
if [ -z "$WASHES_BEFORE" ]; then
  fail "could not parse washes_since_cleaning before mark"
fi
echo "Parsed before: washes_since_cleaning=$WASHES_BEFORE, last_cleaned_at=$LAST_CLEANED_BEFORE"

echo "== Operator marks box $BOX_ID as cleaned =="
MARK_NOTE_ESCAPED="$(printf '%s' "$MARK_NOTE" | sed 's/"/\\"/g')"
NOTE_SUPPORTED=1
MARK_RESULT="$(curl -sS -X POST "$BASE/rest/v1/rpc/mark_box_cleaned" "${op_hdr[@]}" -d "{\"box_id\":$BOX_ID,\"note\":\"$MARK_NOTE_ESCAPED\"}")"
if echo "$MARK_RESULT" | grep -q '"code":"PGRST202"' && \
   echo "$MARK_RESULT" | grep -q 'mark_box_cleaned(box_id, note)'; then
  echo "INFO: note parameter not available yet, fallback to mark_box_cleaned(box_id)."
  NOTE_SUPPORTED=0
  MARK_RESULT="$(curl -sS -X POST "$BASE/rest/v1/rpc/mark_box_cleaned" "${op_hdr[@]}" -d "{\"box_id\":$BOX_ID}")"
fi
echo "$MARK_RESULT"
assert_no_error_code "$MARK_RESULT" "mark_box_cleaned"
if ! echo "$MARK_RESULT" | grep -Eq "\"box_id\"[[:space:]]*:[[:space:]]*$BOX_ID"; then
  fail "mark_box_cleaned response does not include expected box_id"
fi
if [ "$NOTE_SUPPORTED" -eq 1 ] && ! echo "$MARK_RESULT" | grep -Fq "\"note\": \"$MARK_NOTE\""; then
  fail "mark_box_cleaned response does not echo expected note"
fi

echo "== Operator reads cleaning plan for box $BOX_ID (after) =="
PLAN_AFTER="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_box_cleaning_plan?box_id=eq.$BOX_ID" "${op_hdr[@]}" -d "{\"cleaning_interval\":$CLEANING_INTERVAL}")"
echo "$PLAN_AFTER"
assert_no_error_code "$PLAN_AFTER" "get_box_cleaning_plan after"
if ! echo "$PLAN_AFTER" | grep -Eq "\"box_id\"[[:space:]]*:[[:space:]]*$BOX_ID"; then
  fail "cleaning plan after does not include box $BOX_ID"
fi

WASHES_AFTER="$(extract_washes_since_cleaning "$PLAN_AFTER")"
LAST_CLEANED_AFTER="$(extract_last_cleaned_at "$PLAN_AFTER")"
if [ -z "$WASHES_AFTER" ]; then
  fail "could not parse washes_since_cleaning after mark"
fi
if [ "$WASHES_AFTER" -ne 0 ]; then
  fail "expected washes_since_cleaning=0 after mark, got $WASHES_AFTER"
fi
if [ -z "$LAST_CLEANED_AFTER" ] || [ "$LAST_CLEANED_AFTER" = "null" ]; then
  fail "expected non-null last_cleaned_at after mark"
fi
echo "Parsed after: washes_since_cleaning=$WASHES_AFTER, last_cleaned_at=$LAST_CLEANED_AFTER"

echo "== Operator reads cleaning history for box $BOX_ID =="
HISTORY_PAYLOAD="{\"box_id\":$BOX_ID,\"max_rows\":5}"
HISTORY_RESULT="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_box_cleaning_history" "${op_hdr[@]}" -d "$HISTORY_PAYLOAD")"
HISTORY_SUPPORTED=1
if echo "$HISTORY_RESULT" | grep -q '"code":"PGRST202"' && \
   echo "$HISTORY_RESULT" | grep -q 'get_box_cleaning_history'; then
  HISTORY_SUPPORTED=0
  echo "INFO: get_box_cleaning_history is not available yet in current schema cache."
else
  echo "$HISTORY_RESULT"
  assert_no_error_code "$HISTORY_RESULT" "get_box_cleaning_history"
  if ! echo "$HISTORY_RESULT" | grep -Eq "\"box_id\"[[:space:]]*:[[:space:]]*$BOX_ID"; then
    fail "cleaning history does not include expected box_id"
  fi
  if [ "$NOTE_SUPPORTED" -eq 1 ] && ! echo "$HISTORY_RESULT" | grep -Fq "\"note\":\"$MARK_NOTE\""; then
    fail "cleaning history does not include expected note"
  fi
fi

if [ -n "$CUSTOMER_EMAIL" ] && [ -n "$CUSTOMER_PASSWORD" ]; then
  echo "== Login customer (negative security checks) =="
  CU_LOGIN="$(login "$CUSTOMER_EMAIL" "$CUSTOMER_PASSWORD")"
  CU_JWT="$(extract_access_token "$CU_LOGIN")"
  if [ -z "$CU_JWT" ]; then
    echo "$CU_LOGIN"
    fail "customer login failed for negative checks"
  fi
  cu_hdr=(
    -H "apikey: $KEY"
    -H "Authorization: Bearer $CU_JWT"
    -H "Content-Type: application/json"
  )

  echo "== Customer calls get_box_cleaning_plan (must fail) =="
  CU_PLAN="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_box_cleaning_plan" "${cu_hdr[@]}" -d "{\"cleaning_interval\":$CLEANING_INTERVAL}")"
  echo "$CU_PLAN"
  expect_forbidden "$CU_PLAN" "customer get_box_cleaning_plan"

  echo "== Customer calls mark_box_cleaned (must fail) =="
  CU_MARK="$(curl -sS -X POST "$BASE/rest/v1/rpc/mark_box_cleaned" "${cu_hdr[@]}" -d "{\"box_id\":$BOX_ID}")"
  echo "$CU_MARK"
  expect_forbidden "$CU_MARK" "customer mark_box_cleaned"

  if [ "$HISTORY_SUPPORTED" -eq 1 ]; then
    echo "== Customer calls get_box_cleaning_history (must fail) =="
    CU_HISTORY="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_box_cleaning_history" "${cu_hdr[@]}" -d "$HISTORY_PAYLOAD")"
    echo "$CU_HISTORY"
    expect_forbidden "$CU_HISTORY" "customer get_box_cleaning_history"
  fi
fi

echo
echo "CLEANING WORKFLOW E2E PASSED"
