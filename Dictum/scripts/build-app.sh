#!/usr/bin/env bash
# Builds Dictum with SwiftPM and wraps the binary in a proper .app bundle so macOS shows the
# microphone / accessibility prompts against "Dictum" instead of your terminal.
#
#   ./scripts/build-app.sh                 # release build -> build/Dictum.app
#   CONFIG=debug ./scripts/build-app.sh    # debug build
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
  echo "swift not found. Install Xcode (or the Command Line Tools: xcode-select --install) first." >&2
  exit 1
fi

echo "==> Building ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
[ -x "$BIN" ] || { echo "Build output not found at $BIN" >&2; exit 1; }

echo "==> Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
fi
# SwiftPM resource bundles (if any dependency ships some) must sit next to the executable
# or in Resources; copy both ways to be safe.
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
  cp -R "$bundle" "$APP/Contents/MacOS/"
done
shopt -u nullglob

echo "==> Signing ($IDENTITY)…"
codesign --force --deep --sign "$IDENTITY" --entitlements Resources/Dictum.entitlements "$APP"
codesign --verify --verbose=1 "$APP" >/dev/null

echo
echo "Done: $APP"
echo "Run it with:  open $APP"
echo "Install with: make install   (copies to /Applications)"
