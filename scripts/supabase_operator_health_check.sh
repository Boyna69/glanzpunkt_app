#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ]; then
  echo "Missing operator credentials."
  echo "Usage: OPERATOR_EMAIL=... OPERATOR_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_operator_health_check.sh"
  exit 2
fi

login() {
  curl -sS -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$OPERATOR_EMAIL\",\"password\":\"$OPERATOR_PASSWORD\"}"
}

extract_access_token() {
  echo "$1" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

assert_no_error_code() {
  local payload="$1"
  local step="$2"
  if echo "$payload" | grep -q '"code"'; then
    echo "FAILED: $step returned error payload: $payload"
    exit 1
  fi
}

require_field() {
  local payload="$1"
  local field="$2"
  local step="$3"
  if ! echo "$payload" | grep -Eq "\"$field\"[[:space:]]*:"; then
    echo "FAILED: $step missing field '$field'"
    echo "$payload"
    exit 1
  fi
}

echo "== Login operator =="
LOGIN_JSON="$(login)"
JWT="$(extract_access_token "$LOGIN_JSON")"
if [ -z "$JWT" ]; then
  echo "FAILED: operator login failed"
  echo "$LOGIN_JSON"
  exit 1
fi

auth_hdr=(
  -H "apikey: $KEY"
  -H "Authorization: Bearer $JWT"
  -H "Content-Type: application/json"
)

echo "== monitoring_snapshot =="
SNAPSHOT="$(curl -sS -X POST "$BASE/rest/v1/rpc/monitoring_snapshot" "${auth_hdr[@]}" -d '{}')"
echo "$SNAPSHOT"
assert_no_error_code "$SNAPSHOT" "monitoring_snapshot"
for field in timestamp boxes activeSessions openReservations staleReservations; do
  require_field "$SNAPSHOT" "$field" "monitoring_snapshot"
done

echo "== kpi_export(day) =="
KPI_DAY="$(curl -sS -X POST "$BASE/rest/v1/rpc/kpi_export" "${auth_hdr[@]}" -d '{"period":"day"}')"
echo "$KPI_DAY"
assert_no_error_code "$KPI_DAY" "kpi_export(day)"
for field in period window_start window_end generated_at sessions_started wash_revenue_eur; do
  require_field "$KPI_DAY" "$field" "kpi_export(day)"
done
if ! echo "$KPI_DAY" | grep -q '"period"[[:space:]]*:[[:space:]]*"day"'; then
  echo "FAILED: kpi_export(day) returned unexpected period"
  echo "$KPI_DAY"
  exit 1
fi

echo "== kpi_export(week) =="
KPI_WEEK="$(curl -sS -X POST "$BASE/rest/v1/rpc/kpi_export" "${auth_hdr[@]}" -d '{"period":"week"}')"
echo "$KPI_WEEK"
assert_no_error_code "$KPI_WEEK" "kpi_export(week)"
for field in period window_start window_end generated_at sessions_started wash_revenue_eur; do
  require_field "$KPI_WEEK" "$field" "kpi_export(week)"
done
if ! echo "$KPI_WEEK" | grep -q '"period"[[:space:]]*:[[:space:]]*"week"'; then
  echo "FAILED: kpi_export(week) returned unexpected period"
  echo "$KPI_WEEK"
  exit 1
fi

echo "OPERATOR HEALTH CHECK PASSED"
