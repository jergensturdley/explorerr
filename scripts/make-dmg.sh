#!/bin/bash
# Packages build/Explorerr.app into a drag-to-Applications DMG.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(git describe --tags --abbrev=0 2>/dev/null | sed -E 's/^v//' || echo "1.0")"
fi

./scripts/make-app.sh release >/dev/null

STAGING="build/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R build/Explorerr.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

DMG="build/Explorerr-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
    -volname "Explorerr $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGING"
echo "Built $DMG"
