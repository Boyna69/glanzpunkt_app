#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
MAX_ROWS="${UAT_CLEANUP_MAX_ROWS:-200}"
SEARCH_QUERY="${UAT_CLEANUP_SEARCH_QUERY:-E2E UAT Ticket}"
TARGET_SUMMARY="${UAT_CLEANUP_TARGET_SUMMARY:-E2E UAT Ticket}"
NOTE="${UAT_CLEANUP_NOTE:-cleanup: close stale E2E UAT ticket}"
APPLY="${APPLY:-0}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ]; then
  echo "Missing operator credentials."
  echo "Usage: OPERATOR_EMAIL=... OPERATOR_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_uat_cleanup_e2e_tickets.sh"
  echo "   or (legacy): ... SUPABASE_ANON_KEY=... scripts/supabase_uat_cleanup_e2e_tickets.sh"
  exit 2
fi

if ! [[ "$MAX_ROWS" =~ '^[0-9]+$' ]]; then
  echo "Invalid UAT_CLEANUP_MAX_ROWS: $MAX_ROWS"
  exit 2
fi
if [ "$MAX_ROWS" -lt 1 ]; then
  MAX_ROWS=1
fi
if [ "$MAX_ROWS" -gt 200 ]; then
  MAX_ROWS=200
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

normalize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r'
}

extract_top_level_id() {
  echo "$1" | sed -n 's/^[[:space:]]*{[[:space:]]*"id":[[:space:]]*\([0-9][0-9]*\).*/\1/p'
}

extract_top_level_text() {
  local row="$1"
  local key="$2"
  echo "$row" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n1
}

extract_detail_text() {
  local row="$1"
  local key="$2"
  echo "$row" | sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n1
}

extract_ticket_id_from_details() {
  local row="$1"
  local ticket_id
  ticket_id="$(echo "$row" | sed -n 's/.*"ticket_id"[[:space:]]*:[[:space:]]*"\([0-9][0-9]*\)".*/\1/p' | head -n1)"
  if [ -z "$ticket_id" ]; then
    ticket_id="$(echo "$row" | sed -n 's/.*"ticket_id"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  fi
  echo "$ticket_id"
}

is_uat_update_action() {
  local action_name
  action_name="$(normalize "$1")"
  case "$action_name" in
    uat_ticket_status_updated|uat_ticket_owner_assigned|uat_ticket_owner_cleared)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

map_status() {
  local raw_status
  raw_status="$(normalize "$1")"
  local action_status
  action_status="$(normalize "$2")"

  case "$raw_status" in
    open)
      echo "open"
      return
      ;;
    in_progress|inprogress)
      echo "in_progress"
      return
      ;;
    fixed)
      echo "fixed"
      return
      ;;
    retest)
      echo "retest"
      return
      ;;
    closed)
      echo "closed"
      return
      ;;
  esac

  case "$action_status" in
    success)
      echo "closed"
      ;;
    partial|warning)
      echo "in_progress"
      ;;
    *)
      echo "open"
      ;;
  esac
}

is_open_status() {
  case "$1" in
    open|in_progress|retest)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

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

echo "== Read candidate UAT actions =="
RAW_PAYLOAD="$(curl -sS -X POST "$BASE/rest/v1/rpc/list_operator_actions_filtered" "${op_hdr[@]}" -d "{\"max_rows\":$MAX_ROWS,\"offset_rows\":0,\"search_query\":\"$SEARCH_QUERY\"}")"
if echo "$RAW_PAYLOAD" | grep -q '"code"'; then
  fail "list_operator_actions_filtered returned error payload: $RAW_PAYLOAD"
fi

RAW_FLAT="$(echo "$RAW_PAYLOAD" | tr '\n' ' ' | sed -e 's/^[[:space:]]*\[//' -e 's/\][[:space:]]*$//')"
if [ -z "${RAW_FLAT// }" ]; then
  echo "No matching UAT actions found."
  exit 0
fi

ROWS="$(echo "$RAW_FLAT" | sed -e 's/},[[:space:]]*{/}\n{/g')"

typeset -A status_overrides=()
typeset -a close_ticket_ids=()

while IFS= read -r row; do
  [ -z "${row// }" ] && continue
  action_name="$(extract_top_level_text "$row" "action_name")"
  if ! is_uat_update_action "$action_name"; then
    continue
  fi
  if [ "$(normalize "$action_name")" != "uat_ticket_status_updated" ]; then
    continue
  fi
  ticket_id="$(extract_ticket_id_from_details "$row")"
  if [ -z "$ticket_id" ] || [ -n "${status_overrides[$ticket_id]:-}" ]; then
    continue
  fi
  raw_status="$(extract_detail_text "$row" "uat_status")"
  action_status="$(extract_top_level_text "$row" "action_status")"
  status_overrides[$ticket_id]="$(map_status "$raw_status" "$action_status")"
done <<< "$ROWS"

while IFS= read -r row; do
  [ -z "${row// }" ] && continue
  action_name="$(extract_top_level_text "$row" "action_name")"
  if is_uat_update_action "$action_name"; then
    continue
  fi
  ticket_id="$(extract_top_level_id "$row")"
  [ -z "$ticket_id" ] && continue

  summary="$(extract_detail_text "$row" "summary")"
  [ -z "$summary" ] && continue
  if [ "$summary" != "$TARGET_SUMMARY" ]; then
    continue
  fi

  raw_status="$(extract_detail_text "$row" "uat_status")"
  action_status="$(extract_top_level_text "$row" "action_status")"
  ticket_status="$(map_status "$raw_status" "$action_status")"
  if [ -n "${status_overrides[$ticket_id]:-}" ]; then
    ticket_status="${status_overrides[$ticket_id]}"
  fi

  if is_open_status "$ticket_status"; then
    close_ticket_ids+=("$ticket_id")
  fi
done <<< "$ROWS"

if [ "${#close_ticket_ids[@]}" -eq 0 ]; then
  echo "No open E2E UAT tickets to close."
  exit 0
fi

echo "Found ${#close_ticket_ids[@]} open E2E UAT tickets:"
for tid in "${close_ticket_ids[@]}"; do
  echo " - ticket_id=$tid"
done

if [ "$APPLY" != "1" ]; then
  echo "DRY RUN only. Re-run with APPLY=1 to close these tickets."
  exit 0
fi

echo "== Closing tickets =="
for tid in "${close_ticket_ids[@]}"; do
  payload="$(curl -sS -X POST "$BASE/rest/v1/rpc/set_uat_ticket_status" "${op_hdr[@]}" -d "{\"ticket_id\":$tid,\"uat_status\":\"closed\",\"note\":\"$NOTE\"}")"
  if echo "$payload" | grep -q '"code"'; then
    fail "close ticket $tid failed: $payload"
  fi
  echo "closed ticket_id=$tid"
done

echo "UAT E2E CLEANUP COMPLETED"
