#!/usr/bin/env bash
set -euo pipefail

# Updates docs/latest.json with the exact version, build, byte size, and SHA-256
# of a finalized (post-notarization, post-staple) Universal DMG.
#
# Usage:
#   ./Scripts/update_manifest.sh \
#     --version 0.2.5 \
#     --build 7 \
#     --dmg dist/SpinMac-0.2.5-universal.dmg \
#     [--mirror-base https://jclab.work/downloads/spinmac]

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST_PATH="$ROOT_DIR/docs/latest.json"

VERSION=""
BUILD_NUM=""
DMG_PATH=""
MIRROR_BASE="https://jclab.work/downloads/spinmac"

while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --build) BUILD_NUM="$2"; shift 2 ;;
        --dmg) DMG_PATH="$2"; shift 2 ;;
        --mirror-base) MIRROR_BASE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$VERSION" ] || [ -z "$BUILD_NUM" ] || [ -z "$DMG_PATH" ]; then
    echo "Usage: $0 --version <X.Y.Z> --build <N> --dmg <path-to-dmg> [--mirror-base <url>]" >&2
    exit 1
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG not found at $DMG_PATH" >&2
    exit 1
fi

DMG_NAME="$(basename "$DMG_PATH")"
SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
SIZE_BYTES="$(stat -f%z "$DMG_PATH")"
PUB_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

python3 - "$MANIFEST_PATH" "$VERSION" "$BUILD_NUM" "$PUB_DATE" "$DMG_NAME" "$SHA256" "$SIZE_BYTES" "$MIRROR_BASE" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
build = int(sys.argv[3])
pub_date = sys.argv[4]
dmg_name = sys.argv[5]
sha256 = sys.argv[6]
size_bytes = int(sys.argv[7])
mirror_base = sys.argv[8].rstrip("/")

existing = {}
if manifest_path.exists():
    existing = json.loads(manifest_path.read_text(encoding="utf-8"))

manifest = {
    "version": version,
    "build": build,
    "pubDate": pub_date,
    "minMacOS": "14.0",
    "releaseUrl": f"https://github.com/BobbyCats/SpinMac/releases/tag/v{version}",
    "dmgUrl": f"https://github.com/BobbyCats/SpinMac/releases/download/v{version}/{dmg_name}",
    "mirrorDmgUrl": f"{mirror_base}/{dmg_name}" if mirror_base else None,
    "sha256": sha256,
    "sizeBytes": size_bytes,
    "notes_en": existing.get("notes_en") or [],
    "notes_zh": existing.get("notes_zh") or [],
}
if manifest["mirrorDmgUrl"] is None:
    del manifest["mirrorDmgUrl"]

manifest_path.parent.mkdir(parents=True, exist_ok=True)
manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Updated {manifest_path}: v{version} (build {build}), {size_bytes} bytes, sha256={sha256}")
PY
