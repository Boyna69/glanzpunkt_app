#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0

pass() {
  echo "PASS: $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

warn() {
  echo "WARN: $1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

fail() {
  echo "FAIL: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_file() {
  local path="$1"
  local label="$2"
  if [ -f "$path" ]; then
    pass "$label present ($path)"
  else
    fail "$label missing ($path)"
  fi
}

check_dir() {
  local path="$1"
  local label="$2"
  if [ -d "$path" ]; then
    pass "$label present ($path)"
  else
    fail "$label missing ($path)"
  fi
}

echo "== Release Readiness Snapshot =="
echo "Repo: $ROOT"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo
echo "== Security hygiene =="
if bash "$ROOT/scripts/security_secrets_check.sh" >/tmp/security_secrets_check.out 2>&1; then
  pass "security_secrets_check passed"
else
  fail "security_secrets_check failed"
  cat /tmp/security_secrets_check.out
fi

echo
echo "== Core docs =="
check_file "$ROOT/docs/release_readiness_checklist.md" "Release readiness checklist"
check_file "$ROOT/docs/security_rotation_runbook_de.md" "Security rotation runbook"
check_file "$ROOT/docs/internal_apk_distribution_runbook_de.md" "Internal APK distribution runbook"
check_file "$ROOT/docs/store_metadata_handover_de.md" "Store metadata handover"
check_file "$ROOT/docs/store_screenshot_capture_guide_de.md" "Store screenshot guide"
check_file "$ROOT/docs/pr_review_merge_quicksteps_de.md" "PR review quicksteps"

echo
echo "== Build artifacts =="
check_file "$ROOT/build/app/outputs/bundle/release/app-release.aab" "Android AAB"
check_file "$ROOT/build/app/outputs/flutter-apk/app-release.apk" "Android APK"
check_file "$ROOT/scripts/prepare_store_dry_run_bundle.sh" "Dry-run bundle script"
check_file "$ROOT/scripts/init_store_screenshot_pack.sh" "Screenshot init script"
check_file "$ROOT/scripts/validate_store_screenshot_pack.sh" "Screenshot validation script"

LATEST_DRY_RUN_DIR="$(ls -td "$ROOT"/build/store_dry_run/* 2>/dev/null | head -n 1 || true)"
if [ -n "$LATEST_DRY_RUN_DIR" ]; then
  pass "Latest store dry-run bundle found ($LATEST_DRY_RUN_DIR)"
  check_file "$LATEST_DRY_RUN_DIR/app-release.aab" "Dry-run AAB"
  check_file "$LATEST_DRY_RUN_DIR/SHA256SUMS.txt" "Dry-run SHA256 file"
  check_file "$LATEST_DRY_RUN_DIR/DRY_RUN_EVIDENCE_TEMPLATE.md" "Dry-run evidence template"
else
  warn "No store dry-run bundle found in build/store_dry_run"
fi

echo
echo "== Git/PR status =="
BRANCH="$(git branch --show-current)"
pass "Current branch: $BRANCH"
if [ "$BRANCH" = "main" ]; then
  warn "You are on main branch. Prefer PR workflow."
fi

if command -v gh >/dev/null 2>&1; then
  PR_STATE="$(gh pr view 1 --json state --jq .state 2>/dev/null || true)"
  MERGE_STATE="$(gh pr view 1 --json mergeStateStatus --jq .mergeStateStatus 2>/dev/null || true)"
  REVIEW_STATE="$(gh pr view 1 --json reviewDecision --jq .reviewDecision 2>/dev/null || true)"
  if [ -n "$PR_STATE" ]; then
    echo "PR #1: state=$PR_STATE mergeState=$MERGE_STATE review=$REVIEW_STATE"
    if [ "$PR_STATE" = "OPEN" ] && [ "$REVIEW_STATE" = "REVIEW_REQUIRED" ]; then
      warn "PR #1 needs approval from a second reviewer."
    fi
  else
    warn "Could not read PR #1 status via gh."
  fi

  LAST_RUN_STATE="$(gh run list --workflow "Release Gate" --limit 1 --json status,conclusion --jq '.[0].status + "/" + (.[0].conclusion // "null")' 2>/dev/null || true)"
  if [ -n "$LAST_RUN_STATE" ]; then
    echo "Latest Release Gate run: $LAST_RUN_STATE"
    if [ "$LAST_RUN_STATE" = "completed/success" ]; then
      pass "Latest Release Gate run succeeded"
    elif [[ "$LAST_RUN_STATE" == in_progress/* ]] || [[ "$LAST_RUN_STATE" == queued/* ]]; then
      warn "Latest Release Gate run still in progress"
    else
      fail "Latest Release Gate run not successful"
    fi
  else
    warn "Could not query latest Release Gate run."
  fi
else
  warn "GitHub CLI (gh) not found; PR/CI checks skipped."
fi

echo
echo "== Summary =="
echo "passed=$PASS_COUNT warnings=$WARN_COUNT failed=$FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo "RELEASE READINESS SNAPSHOT FAILED"
  exit 1
fi

echo "RELEASE READINESS SNAPSHOT PASSED"
