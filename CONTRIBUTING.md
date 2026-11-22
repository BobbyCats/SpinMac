# Contributing to SpinMac

Thank you for your interest in improving SpinMac!

## Development Requirements

- macOS 14.0+ (Sonoma, Sequoia, or macOS 26 Tahoe)
- Xcode 16+ or Swift 6.0+ toolchain (`swift --version`)

## Quick Local Workflow

```bash
# Run unit tests
swift test

# Build a local .app bundle (ad-hoc signed, installed to dist/SpinMac.app)
INSTALL_TO_APPLICATIONS=0 ./Scripts/build_app.sh
```

If you have an Apple Developer ID certificate and want macOS Accessibility / Input Monitoring permissions to persist across local rebuilds:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/build_app.sh
```

## Architecture Boundaries

- **`Sources/CMultitouch`**: Minimal dynamic loader for `MultitouchSupport.framework`. Keep C code strictly thread-safe and free of UI concerns.
- **`Sources/SpinMacCore`**: Pure Swift orientation math, `DisplayEngine`, `TrackpadEngine`, `HIDEventRewriter`, and `MultitouchMonitor`. **Do not add localized UI strings here** — return typed enums/errors instead.
- **`Sources/SpinMacApp`**: SwiftUI/AppKit menu bar UI, `SpinCoordinator`, `CalibrationFeed`, preferences, and `Resources/{en,zh-Hans}.lproj` localization tables.

## Core Invariants to Preserve

1. **Zero Idle Overhead**: At `0°` (with no axis overrides) or in `.off` mode, both `CGEventTap`s must be disabled and `MultitouchMonitor` must hold zero active leases.
2. **Unconditional Cursor Safety**: `CGAssociateMouseAndMouseCursorPosition(1)` must always be restored on deactivation, tap timeout, or termination.
3. **External Mice Untouched**: Only trackpad touches matching the configured `TrackpadScope` are remapped; external mice always pass through untouched.
4. **Full Localization**: Every user-facing string added in PRs must be added to both `en.lproj/Localizable.strings` and `zh-Hans.lproj/Localizable.strings`.

## Pull Requests

1. Ensure `swift test` passes with new tests covering any math, state-machine, or clamping changes.
2. Verify `swift build -c release` compiles with zero warnings.
3. Include macOS version and hardware model (Apple Silicon / Intel) when reporting or fixing private-framework behavior.
