#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Secret hygiene check =="

fail=0

print_hits() {
  local label="$1"
  local pattern="$2"
  local hits
  hits="$(
    rg -n --hidden -S \
      --glob '!.git/**' \
      --glob '!.dart_tool/**' \
      --glob '!build/**' \
      --glob '!ios/Pods/**' \
      --glob '!scripts/security_secrets_check.sh' \
      --glob '!**/*.png' \
      --glob '!**/*.jpg' \
      --glob '!**/*.jpeg' \
      --glob '!**/*.ico' \
      "$pattern" . || true
  )"
  if [ -n "$hits" ]; then
    echo "FAILED: $label"
    echo "$hits"
    fail=1
  fi
}

# Hard secrets must never be committed.
print_hits "Supabase publishable key literal found" 'sb_publishable_[A-Za-z0-9_-]{20,}'
print_hits "JWT-like token found" 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
print_hits "GitHub token-like value found" 'github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}'

# Enforce safe placeholders in committed env template.
ENV_TEMPLATE=".release-gate.env.example"
if [ -f "$ENV_TEMPLATE" ]; then
  check_placeholder() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(grep -E "^${key}=" "$ENV_TEMPLATE" | head -n1 | cut -d'=' -f2- || true)"
    if [ -z "$actual" ]; then
      echo "FAILED: ${ENV_TEMPLATE} is missing ${key}"
      fail=1
      return
    fi
    if [ "$actual" != "$expected" ]; then
      echo "FAILED: ${ENV_TEMPLATE} has non-placeholder value for ${key}"
      echo "  expected: ${expected}"
      echo "  actual:   ${actual}"
      fail=1
    fi
  }

  check_placeholder "A_EMAIL" "operator@example.com"
  check_placeholder "A_PASSWORD" "change-me-operator-password"
  check_placeholder "B_EMAIL" "customer@example.com"
  check_placeholder "B_PASSWORD" "change-me-customer-password"
  check_placeholder "SUPABASE_PUBLISHABLE_KEY" "sb_publishable_replace_me"
fi

if [ "$fail" -ne 0 ]; then
  echo "SECRET HYGIENE CHECK FAILED"
  exit 1
fi

echo "SECRET HYGIENE CHECK PASSED"
