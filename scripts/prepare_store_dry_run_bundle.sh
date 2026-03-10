#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

AAB_PATH="$ROOT/build/app/outputs/bundle/release/app-release.aab"
APK_PATH="$ROOT/build/app/outputs/flutter-apk/app-release.apk"
CHECKLIST_PATH="$ROOT/docs/store_upload_dry_run_checklist.md"
METADATA_PATH="$ROOT/docs/store_metadata_release_draft_de.md"
SCREENSHOT_GUIDE_PATH="$ROOT/docs/store_screenshot_capture_guide_de.md"

OUT_ROOT="${OUT_ROOT:-$ROOT/build/store_dry_run}"
BUILD_TAG="${BUILD_TAG:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="$OUT_ROOT/$BUILD_TAG"

if [ ! -f "$AAB_PATH" ]; then
  echo "FAILED: Missing Android AAB at $AAB_PATH"
  echo "Build first with:"
  echo "  CUSTOMER_TOP_UP_ENABLED=false $ROOT/scripts/build_android_release.sh"
  exit 2
fi

mkdir -p "$OUT_DIR"

cp "$AAB_PATH" "$OUT_DIR/app-release.aab"

if [ -f "$APK_PATH" ]; then
  cp "$APK_PATH" "$OUT_DIR/app-release.apk"
fi

if [ -f "$CHECKLIST_PATH" ]; then
  cp "$CHECKLIST_PATH" "$OUT_DIR/store_upload_dry_run_checklist.md"
fi

if [ -f "$METADATA_PATH" ]; then
  cp "$METADATA_PATH" "$OUT_DIR/store_metadata_release_draft_de.md"
fi

if [ -f "$SCREENSHOT_GUIDE_PATH" ]; then
  cp "$SCREENSHOT_GUIDE_PATH" "$OUT_DIR/store_screenshot_capture_guide_de.md"
fi

if command -v shasum >/dev/null 2>&1; then
  (
    cd "$OUT_DIR"
    shasum -a 256 app-release.aab > SHA256SUMS.txt
    if [ -f app-release.apk ]; then
      shasum -a 256 app-release.apk >> SHA256SUMS.txt
    fi
  )
elif command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$OUT_DIR"
    sha256sum app-release.aab > SHA256SUMS.txt
    if [ -f app-release.apk ]; then
      sha256sum app-release.apk >> SHA256SUMS.txt
    fi
  )
else
  echo "WARN: no SHA256 tool found; SHA256SUMS.txt not created."
fi

cat > "$OUT_DIR/DRY_RUN_EVIDENCE_TEMPLATE.md" <<EOF
# Store Dry-Run Evidence ($BUILD_TAG)

## Build artifacts

- app-release.aab uploaded: [ ] yes / [ ] no
- app-release.apk uploaded (internal optional): [ ] yes / [ ] no

## Google Play Console

- Internal testing release created: [ ] yes / [ ] no
- Status screenshot captured: [ ] yes / [ ] no
- Data Safety completed: [ ] yes / [ ] no
- Content rating completed: [ ] yes / [ ] no

## App Store Connect

- Version prepared: [ ] yes / [ ] no
- Metadata entered: [ ] yes / [ ] no
- Privacy label completed: [ ] yes / [ ] no
- Status screenshot captured: [ ] yes / [ ] no

## Notes

- Tested by:
- Date/time:
- Remarks:
EOF

echo "Store dry-run bundle created:"
echo "  $OUT_DIR"
ls -lh "$OUT_DIR"
echo "PREPARE STORE DRY RUN BUNDLE PASSED"
