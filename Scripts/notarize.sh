#!/usr/bin/env bash
set -euo pipefail

# Builds a Universal (arm64 + x86_64) SpinMac.dmg signed with Developer ID,
# submits it to Apple's Notary Service, staples the notarization ticket, and
# verifies Gatekeeper readiness.
#
# One-time setup:
#   xcrun notarytool store-credentials "spinmac-notary" \
#     --apple-id "you@example.com" \
#     --team-id "YOURTEAMID" \
#     --password "xxxx-xxxx-xxxx-xxxx"
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE="spinmac-notary" \
#   ./Scripts/notarize.sh

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.2.4}"
DMG_PATH="$ROOT_DIR/dist/SpinMac-${VERSION}-universal.dmg"

if [ -z "${SIGN_IDENTITY:-}" ] || [ "$SIGN_IDENTITY" = "-" ]; then
    echo "Error: SIGN_IDENTITY must be set to a valid Developer ID Application identity." >&2
    exit 1
fi

if [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "Error: NOTARY_PROFILE must be set (created with 'xcrun notarytool store-credentials')." >&2
    exit 1
fi

UNIVERSAL=1 \
SIGN_IDENTITY="$SIGN_IDENTITY" \
VERSION="$VERSION" \
"$ROOT_DIR/Scripts/package_dmg.sh"

echo "==> Submitting DMG to Apple Notary Service..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "==> Stapling notarization ticket to DMG..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> Assessing DMG signature..."
spctl --assess -vv --type open --context context:primary-signature "$DMG_PATH" || true

shasum -a 256 "$DMG_PATH"
echo "==> Notarized universal DMG ready: $DMG_PATH"
