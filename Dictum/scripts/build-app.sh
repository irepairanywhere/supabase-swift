#!/usr/bin/env bash
# Builds Dictum with SwiftPM and wraps the binary in a proper .app bundle so macOS shows the
# microphone / accessibility prompts against "Dictum" instead of your terminal.
#
#   ./scripts/build-app.sh                 # release build -> build/Dictum.app
#   CONFIG=debug ./scripts/build-app.sh    # debug build
#   UNIVERSAL=1 ./scripts/build-app.sh       # runs on Apple Silicon and Intel Macs
#   CODESIGN_IDENTITY="Developer ID Application: You" ./scripts/build-app.sh
#
# Ad-hoc signing ("-") is the default. It works, but macOS forgets the Accessibility grant every
# time the signature changes, so after rebuilding you may need to toggle Dictum off/on in
# System Settings > Privacy & Security > Accessibility. Signing with a real identity avoids that.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP_NAME="Dictum"
OUT_DIR="build"
APP="$OUT_DIR/$APP_NAME.app"

if ! command -v swift >/dev/null 2>&1; then
  echo "==> swift not found. Install Apple's Command Line Tools first:  xcode-select --install" >&2
  exit 1
fi

# The full Xcode is not needed; the Command Line Tools are enough. They must bring Swift 6 or newer.
SWIFT_LINE="$(swift --version 2>&1 | grep -m1 -i 'swift version' || true)"
echo "==> Using ${SWIFT_LINE:-an unknown Swift version}"
SWIFT_MAJOR="$(printf '%s' "$SWIFT_LINE" | sed -nE 's/.*[Ss]wift version ([0-9]+)\..*/\1/p')"
if [ -n "$SWIFT_MAJOR" ] && [ "$SWIFT_MAJOR" -lt 6 ]; then
  echo "==> Swift 6 or newer is needed. Update the Command Line Tools with:" >&2
  echo "==>   sudo rm -rf /Library/Developer/CommandLineTools && xcode-select --install" >&2
  exit 1
fi

# UNIVERSAL=1 builds one binary that runs on both Apple Silicon and Intel Macs (roughly doubles
# compile time). Without it, the app runs only on the kind of Mac that built it.
# (Plain string, not an array: macOS ships bash 3.2, where an empty array trips `set -u`.)
ARCH_FLAGS=""
if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

echo "==> Building ($CONFIG${ARCH_FLAGS:+, universal})..."
# shellcheck disable=SC2086
swift build -c "$CONFIG" --product "$APP_NAME" $ARCH_FLAGS
# shellcheck disable=SC2086
BIN_DIR="$(swift build -c "$CONFIG" --product "$APP_NAME" $ARCH_FLAGS --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
if [ ! -x "$BIN" ]; then
  # Newer SwiftPM versions use a different build system whose output lands elsewhere under .build.
  BIN="$(find .build -type f -perm +111 -name "$APP_NAME" -not -path "*/Intermediates*" 2>/dev/null | head -1 || true)"
  [ -n "$BIN" ] && BIN_DIR="$(dirname "$BIN")"
fi
[ -n "$BIN" ] && [ -x "$BIN" ] || { echo "Build output not found under .build (expected $BIN_DIR/$APP_NAME)" >&2; exit 1; }

echo "==> Assembling ${APP}..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# App icon: build an .icns from the 1024px PNG with the tools that ship with macOS.
if [ -f Resources/AppIcon.png ] && command -v iconutil >/dev/null 2>&1; then
  ICONSET="$OUT_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi
# SwiftPM resource bundles (if any dependency ships some) must sit next to the executable
# or in Resources; copy both ways to be safe.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
  cp -R "$bundle" "$APP/Contents/MacOS/"
done
shopt -u nullglob

echo "==> Signing ($IDENTITY)..."
codesign --force --deep --sign "$IDENTITY" --entitlements Resources/Dictum.entitlements "$APP"
codesign --verify --verbose=1 "$APP" >/dev/null

echo
echo "Done: $APP"
echo "Run it with:  open $APP"
echo "Install with: make install   (copies to /Applications)"
