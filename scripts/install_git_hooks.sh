#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -d ".git" ]; then
  echo "FAILED: .git directory not found. Run inside repository root."
  exit 2
fi

mkdir -p .githooks
chmod +x .githooks/pre-push
git config core.hooksPath .githooks

echo "Git hooks installed."
echo "core.hooksPath=$(git config --get core.hooksPath)"
echo "pre-push hook: ${ROOT}/.githooks/pre-push"
