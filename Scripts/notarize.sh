#!/usr/bin/env bash
set -euo pipefail

# Optional release packaging script: builds, signs with Developer ID,
# notarizes via Apple notarytool, staples the ticket, and emits a release ZIP.
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="AC_PASSWORD_KEYCHAIN_PROFILE" \
#   ./Scripts/notarize.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.2.1}"
APP_BUNDLE="$ROOT_DIR/dist/SpinMac.app"
ZIP_PATH="$ROOT_DIR/dist/SpinMac-${VERSION}-macos.zip"

if [ -z "${SIGN_IDENTITY:-}" ] || [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Error: SIGN_IDENTITY must be set to a valid Developer ID Application identity." >&2
    exit 1
fi

if [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "Error: NOTARY_PROFILE must be set (created with 'xcrun notarytool store-credentials')." >&2
    exit 1
fi

INSTALL_TO_APPLICATIONS=0 SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" "$ROOT_DIR/Scripts/build_app.sh"

echo "==> Creating notarization archive..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Submitting to Apple Notary Service..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
shasum -a 256 "$ZIP_PATH"
echo "==> Release archive ready: $ZIP_PATH"
