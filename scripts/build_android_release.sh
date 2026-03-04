#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_PRECHECKS="${SKIP_PRECHECKS:-0}"
RUN_CLEAN="${RUN_CLEAN:-0}"
USE_MOCK_BACKEND_VALUE="${USE_MOCK_BACKEND_VALUE:-false}"

if [ "$USE_MOCK_BACKEND_VALUE" != "false" ]; then
  echo "FAILED: release build requires USE_MOCK_BACKEND=false"
  exit 2
fi

if [ ! -f "$ROOT/android/key.properties" ]; then
  echo "FAILED: android/key.properties is missing."
  echo "Create it from android/key.properties.example and set store/key passwords."
  exit 2
fi

if [ "$RUN_CLEAN" = "1" ]; then
  echo "== flutter clean =="
  flutter clean
fi

echo "== flutter pub get =="
flutter pub get

if [ "$SKIP_PRECHECKS" != "1" ]; then
  echo "== flutter analyze =="
  flutter analyze
  echo "== flutter test =="
  flutter test
fi

BUILD_ARGS=(
  build
  appbundle
  --release
  --dart-define=USE_MOCK_BACKEND=false
)

if [ -n "${SUPABASE_URL:-}" ]; then
  BUILD_ARGS+=(--dart-define="SUPABASE_URL=$SUPABASE_URL")
fi
if [ -n "${SUPABASE_PUBLISHABLE_KEY:-}" ]; then
  BUILD_ARGS+=(--dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY")
fi
if [ -n "${BACKEND_BASE_URL_DEV:-}" ]; then
  BUILD_ARGS+=(--dart-define="BACKEND_BASE_URL_DEV=$BACKEND_BASE_URL_DEV")
fi
if [ -n "${LEGAL_PRIVACY_URL:-}" ]; then
  BUILD_ARGS+=(--dart-define="LEGAL_PRIVACY_URL=$LEGAL_PRIVACY_URL")
fi
if [ -n "${LEGAL_IMPRINT_URL:-}" ]; then
  BUILD_ARGS+=(--dart-define="LEGAL_IMPRINT_URL=$LEGAL_IMPRINT_URL")
fi
if [ -n "${SUPPORT_EMAIL:-}" ]; then
  BUILD_ARGS+=(--dart-define="SUPPORT_EMAIL=$SUPPORT_EMAIL")
fi

echo "== flutter ${BUILD_ARGS[*]} =="
flutter "${BUILD_ARGS[@]}"

echo "ANDROID RELEASE BUILD PASSED"
