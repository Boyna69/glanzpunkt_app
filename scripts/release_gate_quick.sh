#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Fast and reliable default gate profile for local pushes and PR checks.
RUN_SUPABASE_QUICK_FLOW_CHECK="${RUN_SUPABASE_QUICK_FLOW_CHECK:-0}" \
RUN_SUPABASE_BOX_CYCLE="${RUN_SUPABASE_BOX_CYCLE:-0}" \
RUN_SUPABASE_UAT_BACKLOG_GATE="${RUN_SUPABASE_UAT_BACKLOG_GATE:-0}" \
"$ROOT/scripts/release_gate.sh"
