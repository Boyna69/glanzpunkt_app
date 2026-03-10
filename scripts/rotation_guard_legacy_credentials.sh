#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
LEGACY_KEY="${LEGACY_SUPABASE_KEY:-}"
LEGACY_OPERATOR_EMAIL="${LEGACY_OPERATOR_EMAIL:-}"
LEGACY_OPERATOR_PASSWORD="${LEGACY_OPERATOR_PASSWORD:-}"
LEGACY_CUSTOMER_EMAIL="${LEGACY_CUSTOMER_EMAIL:-}"
LEGACY_CUSTOMER_PASSWORD="${LEGACY_CUSTOMER_PASSWORD:-}"

if [ -z "$LEGACY_KEY" ] || [ -z "$LEGACY_OPERATOR_EMAIL" ] || [ -z "$LEGACY_OPERATOR_PASSWORD" ] || [ -z "$LEGACY_CUSTOMER_EMAIL" ] || [ -z "$LEGACY_CUSTOMER_PASSWORD" ]; then
  echo "Missing required legacy inputs."
  echo "Usage:"
  echo "  LEGACY_SUPABASE_KEY='sb_publishable_...' \\"
  echo "  LEGACY_OPERATOR_EMAIL='old-operator@example.com' LEGACY_OPERATOR_PASSWORD='old-password' \\"
  echo "  LEGACY_CUSTOMER_EMAIL='old-customer@example.com' LEGACY_CUSTOMER_PASSWORD='old-password' \\"
  echo "  /Users/fynn-olegottsch/glanzpunkt_app/scripts/rotation_guard_legacy_credentials.sh"
  exit 2
fi

fail_count=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1"
  fail_count=$((fail_count + 1))
}

auth_with_legacy() {
  local email="$1"
  local pass="$2"
  curl -sS -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $LEGACY_KEY" \
    -H "Authorization: Bearer $LEGACY_KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
}

assert_legacy_login_blocked() {
  local label="$1"
  local email="$2"
  local pass="$3"
  local payload
  payload="$(auth_with_legacy "$email" "$pass")"

  if echo "$payload" | grep -q '"access_token"'; then
    fail "$label legacy login still works; rotation incomplete."
    return
  fi

  if echo "$payload" | grep -q '"error_code":"invalid_credentials"'; then
    pass "$label legacy credentials rejected (invalid_credentials)."
    return
  fi

  if echo "$payload" | grep -q 'Invalid API key'; then
    pass "$label legacy key rejected (invalid API key)."
    return
  fi

  fail "$label returned unexpected response: $payload"
}

echo "== Rotation guard: legacy credential rejection =="
assert_legacy_login_blocked "Operator" "$LEGACY_OPERATOR_EMAIL" "$LEGACY_OPERATOR_PASSWORD"
assert_legacy_login_blocked "Customer" "$LEGACY_CUSTOMER_EMAIL" "$LEGACY_CUSTOMER_PASSWORD"

if [ "$fail_count" -gt 0 ]; then
  echo "ROTATION GUARD FAILED (legacy credentials still usable or unknown response)"
  exit 1
fi

echo "ROTATION GUARD PASSED"
