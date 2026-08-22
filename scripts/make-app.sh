#!/bin/bash
# Builds Explorerr in release mode and assembles a launchable, ad-hoc-signed Explorerr.app
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"

APP="build/Explorerr.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
BIN=".build/$CONFIG/Explorerr"
[ -f "$BIN" ] || BIN=".build/$CONFIG/explorerr"
cp "$BIN" "$APP/Contents/MacOS/Explorerr"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
fi
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
