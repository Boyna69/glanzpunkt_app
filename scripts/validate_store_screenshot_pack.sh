#!/bin/zsh
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: /Users/fynn-olegottsch/glanzpunkt_app/scripts/validate_store_screenshot_pack.sh <pack_dir>"
  exit 2
fi

PACK_DIR="$1"
ANDROID_DIR="$PACK_DIR/android_phone"
IOS_DIR="$PACK_DIR/ios_phone"

REQUIRED_FILES=(
  "01_login_guest.png"
  "02_home_live_boxes.png"
  "03_start_flow.png"
  "04_loyalty_reward.png"
  "05_wallet_history.png"
  "06_operator_dashboard.png"
)

fail=0

check_target() {
  local target_dir="$1"
  local target_name="$2"

  if [ ! -d "$target_dir" ]; then
    echo "FAILED: $target_name directory missing: $target_dir"
    fail=1
    return
  fi

  for file in "${REQUIRED_FILES[@]}"; do
    if [ ! -f "$target_dir/$file" ]; then
      echo "MISSING: $target_name/$file"
      fail=1
    fi
  done
}

check_target "$ANDROID_DIR" "android_phone"
check_target "$IOS_DIR" "ios_phone"

if [ "$fail" -ne 0 ]; then
  echo "STORE SCREENSHOT PACK VALIDATION FAILED"
  exit 1
fi

echo "STORE SCREENSHOT PACK VALIDATION PASSED"
