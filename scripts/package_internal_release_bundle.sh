#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APK_PATH="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
GUIDE_PATH="$ROOT/docs/internal_tester_install_guide_de.md"
OUT_ROOT="${OUT_ROOT:-$ROOT/build/internal_release}"
BUILD_TAG="${BUILD_TAG:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="$OUT_ROOT/$BUILD_TAG"

if [ ! -f "$APK_PATH" ]; then
  echo "FAILED: APK not found at $APK_PATH"
  echo "Build first with:"
  echo "  CUSTOMER_TOP_UP_ENABLED=false $ROOT/scripts/build_android_internal_apk.sh"
  exit 2
fi

mkdir -p "$OUT_DIR"
cp "$APK_PATH" "$OUT_DIR/app-release.apk"

if [ -f "$GUIDE_PATH" ]; then
  cp "$GUIDE_PATH" "$OUT_DIR/internal_tester_install_guide_de.md"
fi

if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 "$OUT_DIR/app-release.apk" > "$OUT_DIR/SHA256SUMS.txt"
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT_DIR/app-release.apk" > "$OUT_DIR/SHA256SUMS.txt"
else
  echo "WARN: no sha256 tool found; SHA256SUMS.txt not generated."
fi

cat > "$OUT_DIR/RELEASE_NOTES.txt" <<EOF
Glanzpunkt Internal Tester Build
Build tag: $BUILD_TAG
Artifact: app-release.apk

Install:
1) Open app-release.apk on Android.
2) Allow install from source if requested.
3) Start app and test core flows.

If issues occur, send:
- device + OS
- steps to reproduce
- expected vs actual behavior
- screenshot/time
EOF

echo "Internal bundle created:"
echo "  $OUT_DIR"
ls -lh "$OUT_DIR"

echo "PACKAGE INTERNAL RELEASE BUNDLE PASSED"
