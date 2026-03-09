#!/bin/zsh
set -euo pipefail

BASE="${SUPABASE_URL:-https://ucnvzrpcjkpaltuylvbv.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"
OPERATOR_EMAIL="${OPERATOR_EMAIL:-${A_EMAIL:-}}"
OPERATOR_PASSWORD="${OPERATOR_PASSWORD:-${A_PASSWORD:-}}"
MAX_ROWS="${UAT_GATE_MAX_ROWS:-200}"
SEARCH_QUERY="${UAT_GATE_SEARCH_QUERY:-uat_}"
OPEN_STATUSES="${UAT_GATE_OPEN_STATUSES:-open in_progress retest}"
BLOCK_SEVERITIES="${UAT_GATE_BLOCK_SEVERITIES:-critical high}"

if [ -z "$KEY" ]; then
  echo "Missing SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY."
  exit 2
fi

if [ -z "$OPERATOR_EMAIL" ] || [ -z "$OPERATOR_PASSWORD" ]; then
  echo "Missing operator credentials."
  echo "Usage: OPERATOR_EMAIL=... OPERATOR_PASSWORD=... SUPABASE_PUBLISHABLE_KEY=sb_publishable_... scripts/supabase_uat_backlog_gate.sh"
  echo "   or (legacy): ... SUPABASE_ANON_KEY=... scripts/supabase_uat_backlog_gate.sh"
  exit 2
fi

if ! [[ "$MAX_ROWS" =~ '^[0-9]+$' ]]; then
  echo "Invalid UAT_GATE_MAX_ROWS: $MAX_ROWS"
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

contains_word() {
  local haystack="$1"
  local needle="$2"
  case " $haystack " in
    *" $needle "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
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

map_severity() {
  local raw_severity
  raw_severity="$(normalize "$1")"
  local action_status
  action_status="$(normalize "$2")"

  case "$raw_severity" in
    critical|p0)
      echo "critical"
      return
      ;;
    high|p1)
      echo "high"
      return
      ;;
    medium|p2)
      echo "medium"
      return
      ;;
    low|p3)
      echo "low"
      return
      ;;
  esac

  case "$action_status" in
    failed|error|forbidden|timeout)
      echo "high"
      ;;
    partial|warning)
      echo "medium"
      ;;
    *)
      echo "low"
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

echo "== Read UAT actions =="
RAW_PAYLOAD="$(curl -sS -X POST "$BASE/rest/v1/rpc/list_operator_actions_filtered" "${op_hdr[@]}" -d "{\"max_rows\":$MAX_ROWS,\"offset_rows\":0,\"search_query\":\"$SEARCH_QUERY\"}")"
if echo "$RAW_PAYLOAD" | grep -q '"code"'; then
  fail "list_operator_actions_filtered returned error payload: $RAW_PAYLOAD"
fi

RAW_FLAT="$(echo "$RAW_PAYLOAD" | tr '\n' ' ' | sed -e 's/^[[:space:]]*\[//' -e 's/\][[:space:]]*$//')"
if [ -z "${RAW_FLAT// }" ]; then
  echo "PASS no UAT actions found in the selected window (max_rows=$MAX_ROWS)."
  exit 0
fi

ROWS="$(echo "$RAW_FLAT" | sed -e 's/},[[:space:]]*{/}\n{/g')"

typeset -A status_overrides=()
typeset -a blocking_lines=()
typeset -i open_total=0

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
  if [ -z "$ticket_id" ]; then
    continue
  fi
  if [ -n "${status_overrides[$ticket_id]:-}" ]; then
    continue
  fi
  raw_status="$(extract_detail_text "$row" "uat_status")"
  if [ -z "$raw_status" ]; then
    raw_status="$(extract_detail_text "$row" "status")"
  fi
  action_status="$(extract_top_level_text "$row" "action_status")"
  status_overrides[$ticket_id]="$(map_status "$raw_status" "$action_status")"
done <<< "$ROWS"

while IFS= read -r row; do
  [ -z "${row// }" ] && continue
  action_name="$(extract_top_level_text "$row" "action_name")"
  if is_uat_update_action "$action_name"; then
    continue
  fi

  log_id="$(extract_top_level_id "$row")"
  if [ -z "$log_id" ]; then
    continue
  fi

  raw_status="$(extract_detail_text "$row" "uat_status")"
  action_status="$(extract_top_level_text "$row" "action_status")"
  ticket_status="$(map_status "$raw_status" "$action_status")"
  if [ -n "${status_overrides[$log_id]:-}" ]; then
    ticket_status="${status_overrides[$log_id]}"
  fi

  raw_severity="$(extract_detail_text "$row" "severity")"
  if [ -z "$raw_severity" ]; then
    raw_severity="$(extract_detail_text "$row" "priority")"
  fi
  severity="$(map_severity "$raw_severity" "$action_status")"

  if contains_word "$OPEN_STATUSES" "$ticket_status"; then
    open_total=$((open_total + 1))
    if contains_word "$BLOCK_SEVERITIES" "$severity"; then
      summary="$(extract_detail_text "$row" "summary")"
      area="$(extract_detail_text "$row" "area")"
      [ -z "$summary" ] && summary="$action_name"
      [ -z "$area" ] && area="-"
      blocking_lines+=("ticket_id=$log_id status=$ticket_status severity=$severity area=$area summary=$summary")
    fi
  fi
done <<< "$ROWS"

echo "Open tickets considered: $open_total"
echo "Blocking severities: $BLOCK_SEVERITIES"

if [ "${#blocking_lines[@]}" -gt 0 ]; then
  echo "Blocking UAT tickets found (${#blocking_lines[@]}):"
  for line in "${blocking_lines[@]}"; do
    echo " - $line"
  done
  fail "UAT backlog gate failed (open critical/high tickets exist)."
fi

echo "UAT BACKLOG GATE PASSED"
