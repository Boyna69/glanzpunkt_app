#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ -z "${SUPABASE_DB_URL:-}" ]; then
  echo "FAILED: SUPABASE_DB_URL is required." >&2
  echo "Example:"
  echo "SUPABASE_DB_URL='postgresql://postgres:<password>@db.<project-ref>.supabase.co:6543/postgres?sslmode=require' scripts/supabase_db_parity_gate.sh"
  exit 2
fi

if ! command -v psql >/dev/null 2>&1; then
  echo "FAILED: psql is not installed." >&2
  exit 2
fi

echo "== Supabase DB migration parity gate =="
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f "$ROOT/supabase/migration_parity_gate.sql"
echo "SUPABASE DB PARITY GATE PASSED"
