#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-${B_EMAIL:-}}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-${B_PASSWORD:-}}"
NON_OWNER_EMAIL="${NON_OWNER_EMAIL:-}"
NON_OWNER_PASSWORD="${NON_OWNER_PASSWORD:-}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ] || [ -z "$CUSTOMER_EMAIL" ] || [ -z "$CUSTOMER_PASSWORD" ]; then
  echo "Missing credentials."
  echo "Usage: OPERATOR_EMAIL=... OPERATOR_PASSWORD=... CUSTOMER_EMAIL=... CUSTOMER_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_operator_threshold_settings_e2e.sh"
  echo "       Optional owner-only negative check: NON_OWNER_EMAIL=... NON_OWNER_PASSWORD=..."
  echo "   or (legacy): ... SUPABASE_ANON_KEY=... scripts/supabase_operator_threshold_settings_e2e.sh"
  exit 2
fi

fail() {
  echo "FAILED: $1" >&2
  exit 1
}

ORIGINAL_SAVED=0
RESTORE_DONE=0

restore_original_thresholds() {
  if [ "${ORIGINAL_SAVED:-0}" != "1" ] || [ "${RESTORE_DONE:-0}" = "1" ]; then
    return
  fi
  if [ -z "${OLD_CLEANING_INTERVAL:-}" ] || [ -z "${OLD_LONG_ACTIVE:-}" ] || [ -z "${OP_JWT:-}" ]; then
    return
  fi
  local restore_payload
  restore_payload="$(curl -sS -X POST "$BASE/rest/v1/rpc/set_operator_threshold_settings" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $OP_JWT" \
    -H "Content-Type: application/json" \
    -d "{\"cleaning_interval_washes\":$OLD_CLEANING_INTERVAL,\"long_active_minutes\":$OLD_LONG_ACTIVE}" || true)"
  if echo "$restore_payload" | grep -q '"code"'; then
    echo "WARN: automatic restore failed: $restore_payload" >&2
  fi
  RESTORE_DONE=1
}

trap restore_original_thresholds EXIT

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

extract_int_field() {
  local payload="$1"
  local field="$2"
  echo "$payload" | sed -n "s/.*\"$field\":[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p"
}

expect_threshold_payload() {
  local payload="$1"
  local label="$2"
  assert_no_error_code "$payload" "$label"
  for field in cleaning_interval_washes long_active_minutes updated_at; do
    if ! echo "$payload" | grep -Eq "\"$field\"[[:space:]]*:"; then
      fail "$label missing field: $field"
    fi
  done
}

preflight_connectivity

echo "== Login owner (threshold writer) =="
OP_LOGIN="$(login "$OPERATOR_EMAIL" "$OPERATOR_PASSWORD")"
OP_JWT="$(extract_access_token "$OP_LOGIN")"
if [ -z "$OP_JWT" ]; then
  echo "$OP_LOGIN"
  fail "owner login failed"
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

echo "== Owner reads threshold settings (before) =="
BEFORE="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_operator_threshold_settings" "${op_hdr[@]}" -d '{}')"
echo "$BEFORE"
expect_threshold_payload "$BEFORE" "owner get before"

OLD_CLEANING_INTERVAL="$(extract_int_field "$BEFORE" "cleaning_interval_washes")"
OLD_LONG_ACTIVE="$(extract_int_field "$BEFORE" "long_active_minutes")"
if [ -z "$OLD_CLEANING_INTERVAL" ] || [ -z "$OLD_LONG_ACTIVE" ]; then
  fail "could not parse previous thresholds"
fi
ORIGINAL_SAVED=1
echo "Parsed before: cleaning_interval_washes=$OLD_CLEANING_INTERVAL long_active_minutes=$OLD_LONG_ACTIVE"

TARGET_CLEANING_INTERVAL="${TARGET_CLEANING_INTERVAL:-}"
TARGET_LONG_ACTIVE_MINUTES="${TARGET_LONG_ACTIVE_MINUTES:-}"
if [ -z "$TARGET_CLEANING_INTERVAL" ]; then
  if [ "$OLD_CLEANING_INTERVAL" -eq 90 ]; then
    TARGET_CLEANING_INTERVAL=91
  else
    TARGET_CLEANING_INTERVAL=90
  fi
fi
if [ -z "$TARGET_LONG_ACTIVE_MINUTES" ]; then
  if [ "$OLD_LONG_ACTIVE" -eq 25 ]; then
    TARGET_LONG_ACTIVE_MINUTES=26
  else
    TARGET_LONG_ACTIVE_MINUTES=25
  fi
fi

echo "== Owner updates thresholds =="
SET_PAYLOAD="$(curl -sS -X POST "$BASE/rest/v1/rpc/set_operator_threshold_settings" "${op_hdr[@]}" -d "{\"cleaning_interval_washes\":$TARGET_CLEANING_INTERVAL,\"long_active_minutes\":$TARGET_LONG_ACTIVE_MINUTES}")"
echo "$SET_PAYLOAD"
expect_threshold_payload "$SET_PAYLOAD" "owner set thresholds"

echo "== Owner reads threshold settings (after) =="
AFTER="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_operator_threshold_settings" "${op_hdr[@]}" -d '{}')"
echo "$AFTER"
expect_threshold_payload "$AFTER" "owner get after"
if ! echo "$AFTER" | grep -Eq "\"cleaning_interval_washes\"[[:space:]]*:[[:space:]]*$TARGET_CLEANING_INTERVAL"; then
  fail "cleaning_interval_washes not updated to $TARGET_CLEANING_INTERVAL"
fi
if ! echo "$AFTER" | grep -Eq "\"long_active_minutes\"[[:space:]]*:[[:space:]]*$TARGET_LONG_ACTIVE_MINUTES"; then
  fail "long_active_minutes not updated to $TARGET_LONG_ACTIVE_MINUTES"
fi

echo "== Owner audit log contains update_thresholds =="
AUDIT_ROWS="$(curl -sS -X POST "$BASE/rest/v1/rpc/list_operator_actions_filtered" "${op_hdr[@]}" -d '{"max_rows":20,"filter_status":"success","search_query":"update_thresholds"}')"
echo "$AUDIT_ROWS"
assert_no_error_code "$AUDIT_ROWS" "owner audit log read"
if ! echo "$AUDIT_ROWS" | grep -q '"action_name":"update_thresholds"'; then
  fail "owner audit log is missing update_thresholds entry"
fi
if ! echo "$AUDIT_ROWS" | grep -q '"source":"rpc"'; then
  fail "owner audit update_thresholds entry should be source=rpc"
fi

echo "== Customer calls get_operator_threshold_settings (must fail) =="
CU_GET="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_operator_threshold_settings" "${cu_hdr[@]}" -d '{}')"
echo "$CU_GET"
expect_forbidden "$CU_GET" "customer get_operator_threshold_settings"

echo "== Customer calls set_operator_threshold_settings (must fail) =="
CU_SET="$(curl -sS -X POST "$BASE/rest/v1/rpc/set_operator_threshold_settings" "${cu_hdr[@]}" -d '{"cleaning_interval_washes":80,"long_active_minutes":30}')"
echo "$CU_SET"
expect_forbidden "$CU_SET" "customer set_operator_threshold_settings"

if [ -n "$NON_OWNER_EMAIL" ] || [ -n "$NON_OWNER_PASSWORD" ]; then
  if [ -z "$NON_OWNER_EMAIL" ] || [ -z "$NON_OWNER_PASSWORD" ]; then
    fail "Both NON_OWNER_EMAIL and NON_OWNER_PASSWORD are required for non-owner check."
  fi
  echo "== Login non-owner operator (optional negative check) =="
  NO_LOGIN="$(login "$NON_OWNER_EMAIL" "$NON_OWNER_PASSWORD")"
  NO_JWT="$(extract_access_token "$NO_LOGIN")"
  if [ -z "$NO_JWT" ]; then
    echo "$NO_LOGIN"
    fail "non-owner login failed"
  fi
  no_hdr=(
    -H "apikey: $KEY"
    -H "Authorization: Bearer $NO_JWT"
    -H "Content-Type: application/json"
  )
  echo "== Non-owner calls set_operator_threshold_settings (must fail) =="
  NO_SET="$(curl -sS -X POST "$BASE/rest/v1/rpc/set_operator_threshold_settings" "${no_hdr[@]}" -d '{"cleaning_interval_washes":88,"long_active_minutes":22}')"
  echo "$NO_SET"
  expect_forbidden "$NO_SET" "non-owner set_operator_threshold_settings"
fi

echo "== Owner restores previous thresholds =="
RESTORE_PAYLOAD="$(curl -sS -X POST "$BASE/rest/v1/rpc/set_operator_threshold_settings" "${op_hdr[@]}" -d "{\"cleaning_interval_washes\":$OLD_CLEANING_INTERVAL,\"long_active_minutes\":$OLD_LONG_ACTIVE}")"
echo "$RESTORE_PAYLOAD"
expect_threshold_payload "$RESTORE_PAYLOAD" "owner restore thresholds"

RESTORED="$(curl -sS -X POST "$BASE/rest/v1/rpc/get_operator_threshold_settings" "${op_hdr[@]}" -d '{}')"
echo "$RESTORED"
expect_threshold_payload "$RESTORED" "owner get restored"
if ! echo "$RESTORED" | grep -Eq "\"cleaning_interval_washes\"[[:space:]]*:[[:space:]]*$OLD_CLEANING_INTERVAL"; then
  fail "restore failed for cleaning_interval_washes"
fi
if ! echo "$RESTORED" | grep -Eq "\"long_active_minutes\"[[:space:]]*:[[:space:]]*$OLD_LONG_ACTIVE"; then
  fail "restore failed for long_active_minutes"
fi
RESTORE_DONE=1

echo
echo "THRESHOLD SETTINGS E2E PASSED"
