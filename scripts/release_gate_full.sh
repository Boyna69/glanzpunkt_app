#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Full gate profile with quick flow and 1-6 box cycle enabled.
RUN_SUPABASE_QUICK_FLOW_CHECK=1 \
RUN_SUPABASE_BOX_CYCLE=1 \
RUN_SUPABASE_UAT_BACKLOG_GATE=1 \
"$ROOT/scripts/release_gate.sh"
