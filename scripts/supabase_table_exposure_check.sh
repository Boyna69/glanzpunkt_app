#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-${B_EMAIL:-}}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-${B_PASSWORD:-}}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$CUSTOMER_EMAIL" ] || [ -z "$CUSTOMER_PASSWORD" ]; then
  echo "Missing customer credentials."
  echo "Usage: CUSTOMER_EMAIL=... CUSTOMER_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_table_exposure_check.sh"
  exit 2
fi

login() {
  curl -sS -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$CUSTOMER_EMAIL\",\"password\":\"$CUSTOMER_PASSWORD\"}"
}

extract_access_token() {
  echo "$1" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

fetch_status() {
  local table="$1"
  local token="$2"
  curl -sS -o /tmp/supabase_table_exposure_${table}.json -w "%{http_code}" \
    "$BASE/rest/v1/$table?select=*&limit=1" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $token"
}

assert_code() {
  local label="$1"
  local got="$2"
  local expected="$3"
  if [ "$got" = "$expected" ]; then
    echo "PASS $label ($got)"
    return
  fi
  echo "FAIL $label expected $expected got $got"
  FAILED=$((FAILED + 1))
}

FAILED=0

echo "== Login customer =="
LOGIN_JSON="$(login)"
CUSTOMER_JWT="$(extract_access_token "$LOGIN_JSON")"
if [ -z "$CUSTOMER_JWT" ]; then
  echo "FAILED: customer login failed"
  echo "$LOGIN_JSON"
  exit 1
fi

echo "== Anon table access checks =="
ANON_BOXES="$(fetch_status "boxes" "$KEY")"
assert_code "anon boxes select" "$ANON_BOXES" "401"

echo "== Customer allowed table checks =="
for table in profiles boxes wash_sessions transactions; do
  STATUS="$(fetch_status "$table" "$CUSTOMER_JWT")"
  assert_code "customer $table select" "$STATUS" "200"
done

echo "== Customer forbidden table checks =="
for table in box_reservations loyalty_wallets ops_runtime_state box_cleaning_state box_cleaning_events wash_sessions_legacy_backup sessions_backup operator_action_log operator_threshold_settings; do
  STATUS="$(fetch_status "$table" "$CUSTOMER_JWT")"
  if [ "$STATUS" = "401" ] || [ "$STATUS" = "403" ]; then
    echo "PASS customer $table blocked ($STATUS)"
  else
    echo "FAIL customer $table expected 401/403 got $STATUS"
    FAILED=$((FAILED + 1))
  fi
done

echo
echo "== Summary =="
echo "failed=$FAILED"

if [ "$FAILED" -gt 0 ]; then
  exit 1
fi

echo "TABLE EXPOSURE CHECK PASSED"
