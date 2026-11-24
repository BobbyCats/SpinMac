#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="SpinMac"
BUNDLE_ID="${BUNDLE_ID:-app.spinmac.SpinMac}"
VERSION="${VERSION:-0.2.3}"
BUILD_NUM="${BUILD_NUM:-5}"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
# Defaults to ad-hoc signing (`-`) for open-source contributors.
# Pass SIGN_IDENTITY="Developer ID Application: ..." for stable TCC permissions & notarization.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
INSTALL_TO_APPLICATIONS="${INSTALL_TO_APPLICATIONS:-1}"
# Set UNIVERSAL=1 to emit a fat arm64 + x86_64 binary for Apple Silicon & Intel Macs.
UNIVERSAL="${UNIVERSAL:-0}"
SKIP_TESTS="${SKIP_TESTS:-0}"

cd "$ROOT_DIR"

if [ "$SKIP_TESTS" != "1" ]; then
    echo "==> Running unit tests..."
    swift test
fi

if [ "$UNIVERSAL" = "1" ]; then
    echo "==> Building universal release binary (arm64 + x86_64 via separate slices + lipo)..."
    swift build -c release --arch arm64
    swift build -c release --arch x86_64
    ARM64_BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
    X64_BIN_DIR="$(swift build -c release --arch x86_64 --show-bin-path)"
    UNIVERSAL_OUT_DIR="$ROOT_DIR/.build/universal-release"
    mkdir -p "$UNIVERSAL_OUT_DIR"
    BIN_PATH="$UNIVERSAL_OUT_DIR/$APP_NAME"
    lipo -create "$ARM64_BIN_DIR/$APP_NAME" "$X64_BIN_DIR/$APP_NAME" -output "$BIN_PATH"
    BIN_DIR="$ARM64_BIN_DIR"
else
    echo "==> Building native release binary..."
    swift build -c release
    BIN_DIR="$(swift build -c release --show-bin-path)"
    BIN_PATH="$BIN_DIR/$APP_NAME"
fi
test -x "$BIN_PATH"

if [ "$UNIVERSAL" = "1" ]; then
    ARCHS="$(lipo -archs "$BIN_PATH")"
    echo "==> Verified binary architectures: $ARCHS"
    case "$ARCHS" in
        *arm64*x86_64*|*x86_64*arm64*) ;;
        *)
            echo "Error: Expected universal arm64 + x86_64 binary, got: $ARCHS" >&2
            exit 1
            ;;
    esac
fi

echo "==> Generating AppIcon.icns..."
ICONSET_DIR="$ROOT_DIR/.build/SpinMac.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

swift - "$ICONSET_DIR" <<'SWIFT'
import AppKit
import Foundation

let outDir = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func renderIcon(px: Int) -> Data {
    let size = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px,
        pixelsHigh: px,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    let inset = size * 0.08
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let bgPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Deep obsidian-slate gradient backdrop
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let colors = [
        CGColor(red: 0.14, green: 0.17, blue: 0.22, alpha: 1.0),
        CGColor(red: 0.06, green: 0.08, blue: 0.11, alpha: 1.0),
    ] as CFArray
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: size / 2, y: size), end: CGPoint(x: size / 2, y: 0), options: [])
    ctx.restoreGState()

    // Specular inner rim
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.16))
    ctx.setLineWidth(max(1.0, size * 0.012))
    ctx.addPath(bgPath)
    ctx.strokePath()

    // Crisp portrait display glyph
    let center = CGPoint(x: size / 2, y: size / 2)
    let screenW = size * 0.30
    let screenH = size * 0.44
    let screenRect = CGRect(x: center.x - screenW / 2, y: center.y - screenH / 2, width: screenW, height: screenH)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: size * 0.048, cornerHeight: size * 0.048, transform: nil)

    ctx.setFillColor(CGColor(red: 0.20, green: 0.62, blue: 1.0, alpha: 0.24))
    ctx.addPath(screenPath)
    ctx.fillPath()

    ctx.setStrokeColor(CGColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 0.95))
    ctx.setLineWidth(max(1.5, size * 0.032))
    ctx.addPath(screenPath)
    ctx.strokePath()

    // Dual-tone orbital rotation arcs (Display blue + Trackpad teal)
    let arcR = size * 0.34
    ctx.setLineWidth(max(1.5, size * 0.030))
    ctx.setLineCap(.round)

    ctx.setStrokeColor(CGColor(red: 0.28, green: 0.66, blue: 1.0, alpha: 0.96))
    ctx.addArc(center: center, radius: arcR, startAngle: 0.25, endAngle: 1.90, clockwise: false)
    ctx.strokePath()

    ctx.setStrokeColor(CGColor(red: 0.20, green: 0.84, blue: 0.78, alpha: 0.95))
    ctx.addArc(center: center, radius: arcR, startAngle: .pi + 0.25, endAngle: .pi + 1.90, clockwise: false)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (px, name) in sizes {
    let data = renderIcon(px: px)
    try data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
SWIFT

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy SwiftPM resource bundles (SpinMac localization + KeyboardShortcuts localization)
for bundle in "$BIN_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then
        echo "==> Bundling resource: $(basename "$bundle")"
        ditto "$bundle" "$APP_BUNDLE/Contents/Resources/$(basename "$bundle")"
    fi
done

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUM</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "==> Verifying bundled localization parity (en + zh-Hans)..."
swift - "$APP_BUNDLE/Contents/Resources/SpinMac_SpinMacApp.bundle" <<'SWIFT'
import Foundation

let bundlePath = CommandLine.arguments[1]
guard let bundle = Bundle(path: bundlePath) else {
    fputs("FAIL: Missing SpinMacApp resource bundle at \(bundlePath)\n", stderr)
    exit(1)
}
func load(_ candidates: [String]) -> [String: String] {
    for c in candidates {
        if let url = bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: c),
           let dict = NSDictionary(contentsOf: url) as? [String: String], !dict.isEmpty {
            return dict
        }
    }
    return [:]
}
let en = load(["en"])
let zh = load(["zh-Hans", "zh-hans"])
guard !en.isEmpty, !zh.isEmpty else {
    fputs("FAIL: Empty localization table (en=\(en.count), zh=\(zh.count))\n", stderr)
    exit(1)
}
let missingInZh = Set(en.keys).subtracting(zh.keys)
let missingInEn = Set(zh.keys).subtracting(en.keys)
guard missingInZh.isEmpty && missingInEn.isEmpty else {
    fputs("FAIL: Key mismatch missingInZh=\(missingInZh) missingInEn=\(missingInEn)\n", stderr)
    exit(1)
}
guard zh["settings.tab.general"] == "通用与快捷键", en["settings.tab.general"] == "General" else {
    fputs("FAIL: Unexpected sample strings zh=\(zh["settings.tab.general"] ?? "nil") en=\(en["settings.tab.general"] ?? "nil")\n", stderr)
    exit(1)
}
print("Localization gate OK: \(en.count) keys verified across en & zh-Hans")
SWIFT

echo "==> Code signing with identity: $SIGN_IDENTITY"
if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --deep --sign - "$APP_BUNDLE"
else
    codesign --force --deep --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
fi
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

if [ "$INSTALL_TO_APPLICATIONS" = "1" ]; then
    echo "==> Installing to /Applications/$APP_NAME.app"
    rm -rf "/Applications/$APP_NAME.app"
    ditto "$APP_BUNDLE" "/Applications/$APP_NAME.app"
    codesign --verify --deep --strict "/Applications/$APP_NAME.app"
    echo "==> DONE: /Applications/$APP_NAME.app"
else
    echo "==> DONE: $APP_BUNDLE"
fi
