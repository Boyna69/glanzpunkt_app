#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT_ROOT="${OUT_ROOT:-$ROOT/build/store_assets}"
PACK_TAG="${PACK_TAG:-$(date +%Y%m%d-%H%M%S)}"
OUT_DIR="$OUT_ROOT/$PACK_TAG"

mkdir -p "$OUT_DIR/android_phone"
mkdir -p "$OUT_DIR/ios_phone"

REQUIRED_FILES=(
  "01_login_guest.png"
  "02_home_live_boxes.png"
  "03_start_flow.png"
  "04_loyalty_reward.png"
  "05_wallet_history.png"
  "06_operator_dashboard.png"
)

for file in "${REQUIRED_FILES[@]}"; do
  : > "$OUT_DIR/android_phone/$file.todo"
  : > "$OUT_DIR/ios_phone/$file.todo"
done

cat > "$OUT_DIR/README.md" <<EOF
# Store Screenshot Pack ($PACK_TAG)

Generated at: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

This folder contains placeholders for required screenshot names.
Replace each *.todo file with a real PNG of the same base name.

## Android targets

- Directory: android_phone/
- Expected files:
$(for file in "${REQUIRED_FILES[@]}"; do echo "- $file"; done)

## iOS targets

- Directory: ios_phone/
- Expected files:
$(for file in "${REQUIRED_FILES[@]}"; do echo "- $file"; done)

## Validation

Use:

\`\`\`bash
/Users/fynn-olegottsch/glanzpunkt_app/scripts/validate_store_screenshot_pack.sh "$OUT_DIR"
\`\`\`
EOF

echo "Store screenshot pack initialized:"
echo "  $OUT_DIR"
ls -R "$OUT_DIR"

echo "INIT STORE SCREENSHOT PACK PASSED"
