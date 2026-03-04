#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-${B_EMAIL:-}}"
CUSTOMER_PASSWORD="${CUSTOMER_PASSWORD:-${B_PASSWORD:-}}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ] || [ -z "$CUSTOMER_EMAIL" ] || [ -z "$CUSTOMER_PASSWORD" ]; then
  echo "Missing credentials."
  echo "Usage: OPERATOR_EMAIL=... OPERATOR_PASSWORD=... CUSTOMER_EMAIL=... CUSTOMER_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_operator_kpi_export_e2e.sh"
  echo "   or (legacy): ... SUPABASE_ANON_KEY=... scripts/supabase_operator_kpi_export_e2e.sh"
  exit 2
fi

fail() {
  echo "FAILED: $1" >&2
  exit 1
}

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

expect_invalid_period() {
  local payload="$1"
  if echo "$payload" | grep -q 'invalid_period'; then
    echo "PASS invalid period rejected"
    return
  fi
  fail "kpi_export invalid period should fail, got: $payload"
}

assert_export_payload() {
  local payload="$1"
  local period="$2"
  assert_no_error_code "$payload" "kpi_export period=$period"
  if ! echo "$payload" | grep -Eq "\"period\"[[:space:]]*:[[:space:]]*\"$period\""; then
    fail "kpi_export period=$period missing period field"
  fi
  for field in boxes_total sessions_started wash_revenue_eur top_up_revenue_eur active_sessions generated_at; do
    if ! echo "$payload" | grep -Eq "\"$field\"[[:space:]]*:"; then
      fail "kpi_export period=$period missing field: $field"
    fi
  done
  for field in previous_window_start previous_window_end delta_sessions_started delta_wash_revenue_eur delta_top_up_revenue_eur; do
    if ! echo "$payload" | grep -Eq "\"$field\"[[:space:]]*:"; then
      fail "kpi_export period=$period missing delta field: $field"
    fi
  done
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

echo "== Operator calls kpi_export (day/week/month) =="
KPI_DAY="$(curl -sS -X POST "$BASE/rest/v1/rpc/kpi_export" "${op_hdr[@]}" -d '{"period":"day"}')"
echo "$KPI_DAY"
assert_export_payload "$KPI_DAY" "day"

KPI_WEEK="$(curl -sS -X POST "$BASE/rest/v1/rpc/kpi_export" "${op_hdr[@]}" -d '{"period":"week"}')"
echo "$KPI_WEEK"
assert_export_payload "$KPI_WEEK" "week"

KPI_MONTH="$(curl -sS -X POST "$BASE/rest/v1/rpc/kpi_export" "${op_hdr[@]}" -d '{"period":"month"}')"
echo "$KPI_MONTH"
assert_export_payload "$KPI_MONTH" "month"

echo "== Operator calls kpi_export with invalid period (must fail) =="
KPI_INVALID="$(curl -sS -X POST "$BASE/rest/v1/rpc/kpi_export" "${op_hdr[@]}" -d '{"period":"year"}')"
echo "$KPI_INVALID"
expect_invalid_period "$KPI_INVALID"

echo "== Customer calls kpi_export (must fail) =="
KPI_CUSTOMER="$(curl -sS -X POST "$BASE/rest/v1/rpc/kpi_export" "${cu_hdr[@]}" -d '{"period":"day"}')"
echo "$KPI_CUSTOMER"
expect_forbidden "$KPI_CUSTOMER" "customer kpi_export"

echo
echo "KPI EXPORT E2E PASSED"
