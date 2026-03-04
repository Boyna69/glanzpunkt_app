#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SUPABASE_API_KEY="${SUPABASE_ANON_KEY:-${SUPABASE_PUBLISHABLE_KEY:-}}"

if [ -z "${A_EMAIL:-}" ] || [ -z "${A_PASSWORD:-}" ] || [ -z "${B_EMAIL:-}" ] || [ -z "${B_PASSWORD:-}" ]; then
  echo "FAILED: A_EMAIL/A_PASSWORD/B_EMAIL/B_PASSWORD are required." >&2
  echo "Example:"
  echo "A_EMAIL='ops@mail.de' A_PASSWORD='...' B_EMAIL='user@mail.de' B_PASSWORD='...' SUPABASE_PUBLISHABLE_KEY='sb_publishable_...' scripts/release_gate.sh"
  echo "or (legacy):"
  echo "A_EMAIL='ops@mail.de' A_PASSWORD='...' B_EMAIL='user@mail.de' B_PASSWORD='...' SUPABASE_ANON_KEY='...' scripts/release_gate.sh"
  exit 2
fi

if [ -z "$SUPABASE_API_KEY" ]; then
  echo "FAILED: SUPABASE_ANON_KEY or SUPABASE_PUBLISHABLE_KEY is required for security and box-cycle checks." >&2
  exit 2
fi

RUN_SUPABASE_SMOKE=1 \
RUN_SUPABASE_SECURITY_SUITE="${RUN_SUPABASE_SECURITY_SUITE:-1}" \
RUN_SUPABASE_TABLE_EXPOSURE_CHECK="${RUN_SUPABASE_TABLE_EXPOSURE_CHECK:-1}" \
RUN_SUPABASE_OPERATOR_HEALTH_CHECK="${RUN_SUPABASE_OPERATOR_HEALTH_CHECK:-1}" \
RUN_SUPABASE_BOX_CYCLE="${RUN_SUPABASE_BOX_CYCLE:-1}" \
SUPABASE_BOX_IDS="${SUPABASE_BOX_IDS:-1 2 3 4 5 6}" \
SUPABASE_WAIT_SECONDS="${SUPABASE_WAIT_SECONDS:-130}" \
SUPABASE_CLEANING_BOX_ID="${SUPABASE_CLEANING_BOX_ID:-1}" \
A_EMAIL="$A_EMAIL" \
A_PASSWORD="$A_PASSWORD" \
B_EMAIL="$B_EMAIL" \
B_PASSWORD="$B_PASSWORD" \
SUPABASE_ANON_KEY="$SUPABASE_API_KEY" \
"$ROOT/scripts/release_smoke.sh"
