#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
EMAIL="${A_EMAIL:-}"
PASSWORD="${A_PASSWORD:-}"
AMOUNT="${AMOUNT:-1}"
BOX_IDS_RAW="${BOX_IDS:-1 2 3 4 5 6}"
AUTO_TOP_UP="${AUTO_TOP_UP:-1}"
TOP_UP_AMOUNT="${TOP_UP_AMOUNT:-}"
STOP_MODE="${STOP_MODE:-rpc_stop}" # rpc_stop | auto_expire
WAIT_SECONDS="${WAIT_SECONDS:-}"
WAIT_GRACE_SECONDS="${WAIT_GRACE_SECONDS:-10}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Missing credentials."
  echo "Usage: A_EMAIL='mail' A_PASSWORD='pass' SUPABASE_PUBLISHABLE_KEY='sb_publishable_...' scripts/supabase_box_cycle_e2e.sh"
  echo "   or (legacy): A_EMAIL='mail' A_PASSWORD='pass' SUPABASE_ANON_KEY='...' scripts/supabase_box_cycle_e2e.sh"
  exit 2
fi

preflight_connectivity() {
  if ! curl -sS --connect-timeout 8 --max-time 15 "$BASE/rest/v1/" >/dev/null; then
    echo "FAILED: Cannot reach Supabase host ($BASE). Check DNS/network and try again." >&2
    exit 3
  fi
}

login() {
  curl -sS -X POST "$BASE/auth/v1/token?grant_type=password" \
    -H "apikey: $KEY" \
    -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}"
}

extract_access_token() {
  echo "$1" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p'
}

json_has_error_code() {
  echo "$1" | grep -q '"code"'
}

json_value() {
  local payload="$1"
  local key="$2"
  echo "$payload" | sed -n "s/.*\"$key\":[[:space:]]*\"\\{0,1\\}\\([^\",}]*\\)\"\\{0,1\\}.*/\\1/p" | head -n1
}

preflight_connectivity

echo "== Login =="
LOGIN_JSON="$(login)"
JWT="$(extract_access_token "$LOGIN_JSON")"
if [ -z "$JWT" ]; then
  echo "FAILED: Login unsuccessful"
  echo "$LOGIN_JSON"
  exit 3
fi

auth_hdr=(
  -H "apikey: $KEY"
  -H "Authorization: Bearer $JWT"
  -H "Content-Type: application/json"
)

SUCCESS_COUNT=0
FAIL_COUNT=0
BOX_IDS=(${=BOX_IDS_RAW})
BOX_COUNT=${#BOX_IDS[@]}

if [ "$BOX_COUNT" -eq 0 ]; then
  echo "No box ids configured."
  exit 2
fi

if [ "$AUTO_TOP_UP" = "1" ]; then
  REQUIRED_TOP_UP=$((BOX_COUNT * AMOUNT))
  EFFECTIVE_TOP_UP="${TOP_UP_AMOUNT:-$REQUIRED_TOP_UP}"
  if [ "$EFFECTIVE_TOP_UP" -gt 0 ]; then
    echo "== Top-up before cycle (amount=$EFFECTIVE_TOP_UP) =="
    TOP_UP="$(curl -sS -X POST "$BASE/rest/v1/rpc/top_up" "${auth_hdr[@]}" -d "{\"amount\":$EFFECTIVE_TOP_UP}")"
    echo "top_up: $TOP_UP"
    if json_has_error_code "$TOP_UP"; then
      echo "FAILED: top_up returned error payload"
      exit 1
    fi
  fi
fi

for BOX_ID in "${BOX_IDS[@]}"; do
  echo
  echo "== Box $BOX_ID =="

  # Best effort cleanup before start.
  curl -sS -X POST "$BASE/rest/v1/rpc/cancel_reservation" "${auth_hdr[@]}" \
    -d "{\"box_id\":$BOX_ID}" >/dev/null || true

  RESERVE="$(curl -sS -X POST "$BASE/rest/v1/rpc/reserve" "${auth_hdr[@]}" -d "{\"box_id\":$BOX_ID}")"
  echo "reserve: $RESERVE"
  if json_has_error_code "$RESERVE"; then
    echo "FAIL reserve box $BOX_ID"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  RESERVATION_TOKEN="$(json_value "$RESERVE" "reservation_token")"
  if [ -z "$RESERVATION_TOKEN" ]; then
    echo "FAIL reserve box $BOX_ID (missing reservation_token)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  ACTIVATE="$(curl -sS -X POST "$BASE/rest/v1/rpc/activate" "${auth_hdr[@]}" -d "{\"box_id\":$BOX_ID,\"amount\":$AMOUNT}")"
  echo "activate: $ACTIVATE"
  if json_has_error_code "$ACTIVATE"; then
    curl -sS -X POST "$BASE/rest/v1/rpc/cancel_reservation" "${auth_hdr[@]}" \
      -d "{\"box_id\":$BOX_ID}" >/dev/null || true
    echo "FAIL activate box $BOX_ID"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  SESSION_ID="$(json_value "$ACTIVATE" "session_id")"
  if [ -z "$SESSION_ID" ]; then
    SESSION_ID="$(json_value "$ACTIVATE" "sessionId")"
  fi
  RUNTIME_SECONDS="$(json_value "$ACTIVATE" "runtime_seconds")"
  if [ -z "$RUNTIME_SECONDS" ]; then
    RUNTIME_SECONDS="$(json_value "$ACTIVATE" "runtimeSeconds")"
  fi
  if [ -z "$SESSION_ID" ]; then
    echo "FAIL activate box $BOX_ID (missing session_id)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  STATUS_ACTIVE="$(curl -sS -X POST "$BASE/rest/v1/rpc/status" "${auth_hdr[@]}" -d "{\"box_id\":$BOX_ID}")"
  echo "status(active): $STATUS_ACTIVE"
  if json_has_error_code "$STATUS_ACTIVE" || ! echo "$STATUS_ACTIVE" | grep -q '"state":[[:space:]]*"active"'; then
    echo "FAIL status active box $BOX_ID"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  if [ "$STOP_MODE" = "auto_expire" ]; then
    if [ -z "$RUNTIME_SECONDS" ]; then
      echo "FAIL activate box $BOX_ID (missing runtime_seconds for auto_expire)"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi
    MIN_WAIT_SECONDS=$((RUNTIME_SECONDS + WAIT_GRACE_SECONDS))
    if [ -z "$WAIT_SECONDS" ]; then
      EFFECTIVE_WAIT_SECONDS="$MIN_WAIT_SECONDS"
    else
      EFFECTIVE_WAIT_SECONDS="$WAIT_SECONDS"
    fi
    if [ "$EFFECTIVE_WAIT_SECONDS" -lt "$MIN_WAIT_SECONDS" ]; then
      echo "INFO box $BOX_ID: WAIT_SECONDS=$EFFECTIVE_WAIT_SECONDS < runtime+grace ($MIN_WAIT_SECONDS), auto-adjust."
      EFFECTIVE_WAIT_SECONDS="$MIN_WAIT_SECONDS"
    fi
    echo "wait: $EFFECTIVE_WAIT_SECONDS s (runtime=$RUNTIME_SECONDS, grace=$WAIT_GRACE_SECONDS)"
    sleep "$EFFECTIVE_WAIT_SECONDS"

    EXPIRE_RESULT="$(curl -sS -X POST "$BASE/rest/v1/rpc/expire_active_sessions" "${auth_hdr[@]}" -d '{}')"
    echo "expire: $EXPIRE_RESULT"
    if echo "$EXPIRE_RESULT" | grep -q '"message":"forbidden"'; then
      echo "INFO box $BOX_ID: expire_active_sessions forbidden for this role, continue."
    elif json_has_error_code "$EXPIRE_RESULT"; then
      echo "FAIL expire box $BOX_ID"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi
  else
    STOP="$(curl -sS -X POST "$BASE/rest/v1/rpc/stop" "${auth_hdr[@]}" -d "{\"session_id\":\"$SESSION_ID\"}")"
    echo "stop: $STOP"
    if json_has_error_code "$STOP"; then
      echo "FAIL stop box $BOX_ID"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      continue
    fi
  fi

  STATUS_END="$(curl -sS -X POST "$BASE/rest/v1/rpc/status" "${auth_hdr[@]}" -d "{\"box_id\":$BOX_ID}")"
  echo "status(final): $STATUS_END"
  if json_has_error_code "$STATUS_END" || ! echo "$STATUS_END" | grep -q '"state":[[:space:]]*"available"'; then
    echo "FAIL final status box $BOX_ID"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  echo "PASS box $BOX_ID"
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
done

echo
echo "== Summary =="
echo "passed=$SUCCESS_COUNT failed=$FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
