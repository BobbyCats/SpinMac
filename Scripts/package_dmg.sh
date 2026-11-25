#!/usr/bin/env bash
set -euo pipefail

# Builds a Universal (arm64 + x86_64) SpinMac.app and packages it into a
# drag-to-Applications .dmg archive under dist/.
#
# Usage:
#   ./Scripts/package_dmg.sh
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/package_dmg.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.2.6}"
UNIVERSAL="${UNIVERSAL:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/SpinMac.app"
STAGE_DIR="$DIST_DIR/dmg-stage"

if [ "$UNIVERSAL" = "1" ]; then
    DMG_PATH="$DIST_DIR/SpinMac-${VERSION}-universal.dmg"
else
    DMG_PATH="$DIST_DIR/SpinMac-${VERSION}-$(uname -m).dmg"
fi

INSTALL_TO_APPLICATIONS=0 \
UNIVERSAL="$UNIVERSAL" \
SIGN_IDENTITY="$SIGN_IDENTITY" \
VERSION="$VERSION" \
"$ROOT_DIR/Scripts/build_app.sh"

echo "==> Staging drag-to-Applications DMG..."
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
ditto "$APP_BUNDLE" "$STAGE_DIR/SpinMac.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> Creating compressed DMG: $DMG_PATH"
hdiutil create \
    -volname "SpinMac" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

rm -rf "$STAGE_DIR" "$APP_BUNDLE"

if [ "$SIGN_IDENTITY" != "-" ]; then
    echo "==> Signing DMG with Developer ID..."
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH"
echo "==> DMG ready: $DMG_PATH"
