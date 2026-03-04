#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
EMAIL="${A_EMAIL:-}"
PASSWORD="${A_PASSWORD:-}"
BOX_ID="${BOX_ID:-1}"
AMOUNT="${AMOUNT:-1}"
WAIT_SECONDS="${WAIT_SECONDS:-}"
WAIT_GRACE_SECONDS="${WAIT_GRACE_SECONDS:-10}"
AUTO_TOP_UP="${AUTO_TOP_UP:-1}"
TOP_UP_AMOUNT="${TOP_UP_AMOUNT:-}"

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Missing credentials."
  echo "Usage: A_EMAIL='mail' A_PASSWORD='pass' SUPABASE_PUBLISHABLE_KEY='sb_publishable_...' scripts/supabase_activate_countdown_e2e.sh"
  echo "   or (legacy): A_EMAIL='mail' A_PASSWORD='pass' SUPABASE_ANON_KEY='...' scripts/supabase_activate_countdown_e2e.sh"
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

login() {
  curl -sS -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
}

print_login_summary() {
  local payload="$1"
  local uid email expires
  uid="$(echo "$payload" | sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' | head -n1)"
  email="$(echo "$payload" | sed -n 's/.*"user":{[^}]*"email":"\([^"]*\)".*/\1/p' | head -n1)"
  expires="$(echo "$payload" | sed -n 's/.*"expires_in":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  echo "Login ok: uid=${uid:-n/a} email=${email:-n/a} expires_in=${expires:-n/a}s"
}

preflight_connectivity

echo "== Login =="
LOGIN_JSON="$(login)"

JWT="$(echo "$LOGIN_JSON" | grep -o '\"access_token\":\"[^\"]*\"' | head -n1 | cut -d'"' -f4)"
USER_UUID="$(echo "$LOGIN_JSON" | grep -o '\"id\":\"[^\"]*\"' | head -n1 | cut -d'"' -f4)"

if [ -z "$JWT" ] || [ -z "$USER_UUID" ]; then
  echo "FAILED: Login unsuccessful"
  echo "$LOGIN_JSON"
  exit 3
fi

print_login_summary "$LOGIN_JSON"

auth_hdr=(
  -H "apikey: $KEY"
  -H "Authorization: Bearer $JWT"
  -H "Content-Type: application/json"
)

if [ "$AUTO_TOP_UP" = "1" ]; then
  EFFECTIVE_TOP_UP="${TOP_UP_AMOUNT:-$AMOUNT}"
  if [ "$EFFECTIVE_TOP_UP" -gt 0 ]; then
    echo "== Top-up before activate (amount=$EFFECTIVE_TOP_UP) =="
    TOP_UP="$(curl -sS -X POST "$BASE/rest/v1/rpc/top_up" "${auth_hdr[@]}" -d "{\"amount\":$EFFECTIVE_TOP_UP}")"
    echo "$TOP_UP"
    assert_no_error_code "$TOP_UP" "top_up"
  fi
fi

echo "== Reserve box $BOX_ID =="
RESERVE="$(curl -sS -X POST "$BASE/rest/v1/rpc/reserve" "${auth_hdr[@]}" -d "{\"box_id\":$BOX_ID}")"
echo "$RESERVE"
assert_no_error_code "$RESERVE" "reserve"
if ! echo "$RESERVE" | grep -q '"reservation_token"'; then
  fail "reserve did not return reservation_token"
fi

echo "== Activate box $BOX_ID (amount=$AMOUNT) =="
ACTIVATE="$(curl -sS -X POST "$BASE/rest/v1/rpc/activate" "${auth_hdr[@]}" -d "{\"box_id\":$BOX_ID,\"amount\":$AMOUNT}")"
echo "$ACTIVATE"
assert_no_error_code "$ACTIVATE" "activate"

SESSION_ID="$(echo "$ACTIVATE" | grep -o '"session_id":[[:space:]]*[0-9]\+' | head -n1 | grep -o '[0-9]\+')"
if [ -z "$SESSION_ID" ]; then
  SESSION_ID="$(echo "$ACTIVATE" | sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p')"
fi

RUNTIME_SECONDS="$(echo "$ACTIVATE" | grep -o '"runtime_seconds":[[:space:]]*[0-9]\+' | head -n1 | grep -o '[0-9]\+')"
if [ -z "$RUNTIME_SECONDS" ]; then
  RUNTIME_SECONDS="$(echo "$ACTIVATE" | grep -o '"runtimeSeconds":[[:space:]]*[0-9]\+' | head -n1 | grep -o '[0-9]\+')"
fi

echo "SESSION_ID=$SESSION_ID"
if [ -z "$SESSION_ID" ]; then
  fail "activate did not return session_id"
fi
if [ -z "$RUNTIME_SECONDS" ]; then
  fail "activate did not return runtime_seconds"
fi

MIN_WAIT_SECONDS=$((RUNTIME_SECONDS + WAIT_GRACE_SECONDS))
if [ -z "$WAIT_SECONDS" ]; then
  EFFECTIVE_WAIT_SECONDS="$MIN_WAIT_SECONDS"
else
  EFFECTIVE_WAIT_SECONDS="$WAIT_SECONDS"
fi
if [ "$EFFECTIVE_WAIT_SECONDS" -lt "$MIN_WAIT_SECONDS" ]; then
  echo "INFO: WAIT_SECONDS=$EFFECTIVE_WAIT_SECONDS is below runtime+grace ($MIN_WAIT_SECONDS); auto-adjusting."
  EFFECTIVE_WAIT_SECONDS="$MIN_WAIT_SECONDS"
fi

echo "== Status immediately after activate =="
STATUS_NOW="$(curl -sS -X POST "$BASE/rest/v1/rpc/status" "${auth_hdr[@]}" -d "{\"box_id\":$BOX_ID}")"
echo "$STATUS_NOW"
assert_no_error_code "$STATUS_NOW" "status after activate"
if ! echo "$STATUS_NOW" | grep -q '"state":[[:space:]]*"active"'; then
  fail "status after activate is not active: $STATUS_NOW"
fi
echo

echo "== Wait $EFFECTIVE_WAIT_SECONDS seconds (runtime=$RUNTIME_SECONDS, grace=$WAIT_GRACE_SECONDS) =="
sleep "$EFFECTIVE_WAIT_SECONDS"

echo "== Trigger expiry reconciliation =="
EXPIRE_RESULT="$(curl -sS -X POST "$BASE/rest/v1/rpc/expire_active_sessions" "${auth_hdr[@]}" -d '{}')"
echo "$EXPIRE_RESULT"
if echo "$EXPIRE_RESULT" | grep -q '"message":"forbidden"'; then
  echo "INFO: expire_active_sessions forbidden for this role; continuing with status reconciliation."
else
  assert_no_error_code "$EXPIRE_RESULT" "expire_active_sessions"
fi
echo

echo "== Status after wait =="
STATUS_END="$(curl -sS -X POST "$BASE/rest/v1/rpc/status" "${auth_hdr[@]}" -d "{\"box_id\":$BOX_ID}")"
echo "$STATUS_END"
assert_no_error_code "$STATUS_END" "status after wait"
if ! echo "$STATUS_END" | grep -q '"state":[[:space:]]*"available"'; then
  fail "status after wait is not available: $STATUS_END"
fi
echo

echo "== Recent sessions (own user) =="
curl -sS "$BASE/rest/v1/wash_sessions?select=id,user_id,box_id,amount,started_at,ends_at&user_id=eq.$USER_UUID&order=started_at.desc&limit=5" \
  -H "apikey: $KEY" \
  -H "Authorization: Bearer $JWT"
echo
