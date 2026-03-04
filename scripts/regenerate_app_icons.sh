#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_IMAGE="${1:-$ROOT/assets/images/glanzpunkt_logo.png}"
TMP_SWIFT="/tmp/glanzpunkt_flatten_icon.swift"
TMP_BASE_ICON="/tmp/glanzpunkt_icon_base_1024.png"
SWIFT_CACHE="/tmp/swift_module_cache"

if [ ! -f "$SOURCE_IMAGE" ]; then
  echo "Source image not found: $SOURCE_IMAGE" >&2
  exit 2
fi

cat > "$TMP_SWIFT" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

if CommandLine.arguments.count < 4 {
  fputs("usage: flatten_icon <input> <size> <output>\n", stderr)
  exit(2)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = Int(CommandLine.arguments[2]) ?? 1024
let outputURL = URL(fileURLWithPath: CommandLine.arguments[3])
let rect = CGRect(x: 0, y: 0, width: size, height: size)

guard let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fputs("failed to load input image\n", stderr)
  exit(1)
}

guard let context = CGContext(
  data: nil,
  width: size,
  height: size,
  bitsPerComponent: 8,
  bytesPerRow: size * 4,
  space: CGColorSpaceCreateDeviceRGB(),
  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
  fputs("failed to create context\n", stderr)
  exit(1)
}

context.setFillColor(red: 10.0 / 255.0, green: 26.0 / 255.0, blue: 47.0 / 255.0, alpha: 1.0)
context.fill(rect)
context.interpolationQuality = .high
context.draw(image, in: rect)

guard let composited = context.makeImage() else {
  fputs("failed to render image\n", stderr)
  exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
  outputURL as CFURL,
  UTType.png.identifier as CFString,
  1,
  nil
) else {
  fputs("failed to create output image\n", stderr)
  exit(1)
}

CGImageDestinationAddImage(destination, composited, nil)
if !CGImageDestinationFinalize(destination) {
  fputs("failed to write output image\n", stderr)
  exit(1)
}
SWIFT

mkdir -p "$SWIFT_CACHE"
CLANG_MODULE_CACHE_PATH="$SWIFT_CACHE" \
SWIFT_MODULE_CACHE_PATH="$SWIFT_CACHE" \
swift "$TMP_SWIFT" "$SOURCE_IMAGE" 1024 "$TMP_BASE_ICON"

IOS_ICON_DIR="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
ANDROID_ICON_DIR="$ROOT/android/app/src/main/res"

cp "$TMP_BASE_ICON" "$IOS_ICON_DIR/Icon-App-1024x1024@1x.png"

generate_resized() {
  local size="$1"
  local out_file="$2"
  sips -z "$size" "$size" "$TMP_BASE_ICON" --out "$out_file" >/dev/null
}

# iOS
generate_resized 20 "$IOS_ICON_DIR/Icon-App-20x20@1x.png"
generate_resized 40 "$IOS_ICON_DIR/Icon-App-20x20@2x.png"
generate_resized 60 "$IOS_ICON_DIR/Icon-App-20x20@3x.png"
generate_resized 29 "$IOS_ICON_DIR/Icon-App-29x29@1x.png"
generate_resized 58 "$IOS_ICON_DIR/Icon-App-29x29@2x.png"
generate_resized 87 "$IOS_ICON_DIR/Icon-App-29x29@3x.png"
generate_resized 40 "$IOS_ICON_DIR/Icon-App-40x40@1x.png"
generate_resized 80 "$IOS_ICON_DIR/Icon-App-40x40@2x.png"
generate_resized 120 "$IOS_ICON_DIR/Icon-App-40x40@3x.png"
generate_resized 120 "$IOS_ICON_DIR/Icon-App-60x60@2x.png"
generate_resized 180 "$IOS_ICON_DIR/Icon-App-60x60@3x.png"
generate_resized 76 "$IOS_ICON_DIR/Icon-App-76x76@1x.png"
generate_resized 152 "$IOS_ICON_DIR/Icon-App-76x76@2x.png"
generate_resized 167 "$IOS_ICON_DIR/Icon-App-83.5x83.5@2x.png"

# Android
generate_resized 48 "$ANDROID_ICON_DIR/mipmap-mdpi/ic_launcher.png"
generate_resized 72 "$ANDROID_ICON_DIR/mipmap-hdpi/ic_launcher.png"
generate_resized 96 "$ANDROID_ICON_DIR/mipmap-xhdpi/ic_launcher.png"
generate_resized 144 "$ANDROID_ICON_DIR/mipmap-xxhdpi/ic_launcher.png"
generate_resized 192 "$ANDROID_ICON_DIR/mipmap-xxxhdpi/ic_launcher.png"

echo "Done. Regenerated iOS and Android launcher icons from:"
echo "  $SOURCE_IMAGE"
echo "Check alpha (iOS marketing icon):"
sips -g hasAlpha "$IOS_ICON_DIR/Icon-App-1024x1024@1x.png"
