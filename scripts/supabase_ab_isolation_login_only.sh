#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"

A_EMAIL="${A_EMAIL:-}"
A_PASSWORD="${A_PASSWORD:-}"
B_EMAIL="${B_EMAIL:-}"
B_PASSWORD="${B_PASSWORD:-}"

if [ -z "$A_EMAIL" ] || [ -z "$A_PASSWORD" ] || [ -z "$B_EMAIL" ] || [ -z "$B_PASSWORD" ]; then
  echo "Missing credentials."
  echo "Usage:"
  echo "  A_EMAIL='a@domain.tld' A_PASSWORD='***' B_EMAIL='b@domain.tld' B_PASSWORD='***' SUPABASE_PUBLISHABLE_KEY='sb_publishable_...' scripts/supabase_ab_isolation_login_only.sh"
  echo "  or (legacy):"
  echo "  ... SUPABASE_ANON_KEY='...' scripts/supabase_ab_isolation_login_only.sh"
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

login() {
  local email="$1"
  local pass="$2"
  curl -sS -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$email\",\"password\":\"$pass\"}"
}

print_login_summary() {
  local payload="$1"
  local label="$2"
  local uid email expires
  uid="$(echo "$payload" | sed -n 's/.*"user":{[^}]*"id":"\([^"]*\)".*/\1/p' | head -n1)"
  email="$(echo "$payload" | sed -n 's/.*"user":{[^}]*"email":"\([^"]*\)".*/\1/p' | head -n1)"
  expires="$(echo "$payload" | sed -n 's/.*"expires_in":[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  echo "$label login ok: uid=${uid:-n/a} email=${email:-n/a} expires_in=${expires:-n/a}s"
}

expect_forbidden() {
  local payload="$1"
  local label="$2"
  if echo "$payload" | grep -q '"code":"42501"'; then
    echo "PASS $label forbidden"
    return
  fi
  if echo "$payload" | grep -q 'permission denied'; then
    echo "PASS $label forbidden"
    return
  fi
  echo "FAIL $label expected forbidden but got: $payload" >&2
  exit 1
}

preflight_connectivity

echo "== Login A =="
LOGIN_A="$(login "$A_EMAIL" "$A_PASSWORD")"

echo "== Login B =="
LOGIN_B="$(login "$B_EMAIL" "$B_PASSWORD")"

JWT_A="$(echo "$LOGIN_A" | sed -n "s/.*\"access_token\":\"\([^\"]*\)\".*/\1/p")"
JWT_B="$(echo "$LOGIN_B" | sed -n "s/.*\"access_token\":\"\([^\"]*\)\".*/\1/p")"
UID_A="$(echo "$LOGIN_A" | sed -n "s/.*\"user\":{[^}]*\"id\":\"\([^\"]*\)\".*/\1/p")"
UID_B="$(echo "$LOGIN_B" | sed -n "s/.*\"user\":{[^}]*\"id\":\"\([^\"]*\)\".*/\1/p")"

if [ -z "$JWT_A" ] || [ -z "$JWT_B" ] || [ -z "$UID_A" ] || [ -z "$UID_B" ]; then
  echo "FAILED: Login for A or B unsuccessful."
  echo "$LOGIN_A"
  echo "$LOGIN_B"
  exit 3
fi

print_login_summary "$LOGIN_A" "A"
print_login_summary "$LOGIN_B" "B"

echo "UID_A=$UID_A"
echo "UID_B=$UID_B"

NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "== A tries direct session insert (must fail) =="
INSERT_SESSION_RES="$(curl -sS -i -X POST "$BASE/rest/v1/wash_sessions" \
  -H "apikey: $KEY" \
  -H "Authorization: Bearer $JWT_A" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "[{\"user_id\":\"$UID_A\",\"box_id\":1,\"amount\":5,\"started_at\":\"$NOW_ISO\",\"ends_at\":\"$NOW_ISO\"}]")"
echo "$INSERT_SESSION_RES"
expect_forbidden "$INSERT_SESSION_RES" "direct wash_sessions insert"
echo

echo "== A tries direct transaction insert (must fail) =="
INSERT_TX_RES="$(curl -sS -i -X POST "$BASE/rest/v1/transactions" \
  -H "apikey: $KEY" \
  -H "Authorization: Bearer $JWT_A" \
  -H "Content-Type: application/json" \
  -H "Prefer: return=representation" \
  -d "[{\"user_id\":\"$UID_A\",\"amount\":5}]")"
echo "$INSERT_TX_RES"
expect_forbidden "$INSERT_TX_RES" "direct transactions insert"
echo

echo "== B tries to read A sessions (must be empty/forbidden) =="
curl -sS -i "$BASE/rest/v1/wash_sessions?select=id,user_id,box_id,amount&user_id=eq.$UID_A" \
  -H "apikey: $KEY" \
  -H "Authorization: Bearer $JWT_B"
echo

echo "== B reads own sessions only =="
curl -sS -i "$BASE/rest/v1/wash_sessions?select=id,user_id,box_id,amount&user_id=eq.$UID_B" \
  -H "apikey: $KEY" \
  -H "Authorization: Bearer $JWT_B"
echo

echo "== B tries to read A transactions (must be empty/forbidden) =="
curl -sS -i "$BASE/rest/v1/transactions?select=*&user_id=eq.$UID_A" \
  -H "apikey: $KEY" \
  -H "Authorization: Bearer $JWT_B"
echo

echo "== B reads own transactions only =="
curl -sS -i "$BASE/rest/v1/transactions?select=*&user_id=eq.$UID_B" \
  -H "apikey: $KEY" \
  -H "Authorization: Bearer $JWT_B"
echo
