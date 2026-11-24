import CoreGraphics
import Foundation

/// Display or trackpad rotation angle in degrees, aligned with macOS CoreGraphics / MonitorPanel convention.
public enum SpinAngle: Int32, CaseIterable, Codable, Sendable, Identifiable {
    case deg0 = 0
    case deg90 = 90
    case deg180 = 180
    case deg270 = 270

    public var id: Int32 { rawValue }

    public var label: String {
        "\(rawValue)°"
    }

    public var isPortrait: Bool {
        self == .deg90 || self == .deg270
    }

    /// Physical clockwise visual rotation in degrees per Apple `CGDisplayRotation` convention.
    public var visualRotationDegrees: Double {
        switch self {
        case .deg0: return 0
        case .deg90: return 90
        case .deg180: return 180
        case .deg270: return -90
        }
    }

    /// Clockwise arrow angle on a flat laptop chassis pointing toward the physical edge that becomes visual TOP.
    /// Aligned 1:1 with Apple `CGDisplayRotation` + `kIOScaleRotate*` (`90°` -> left edge `-90°`, `270°` -> right edge `+90°`).
    public var contentTopDegrees: Double {
        switch self {
        case .deg0: return 0
        case .deg90: return -90
        case .deg180: return 180
        case .deg270: return 90
        }
    }

    public static func from(degrees: Double) -> SpinAngle {
        let normalized = ((Int(degrees.rounded()) % 360) + 360) % 360
        return SpinAngle(rawValue: Int32(normalized)) ?? .deg0
    }
}

/// Controls how trackpad orientation relates to display orientation.
public enum TrackpadMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Trackpad automatically follows the selected display's rotation (with built-in isolation).
    case linked
    /// Trackpad uses its own independent angle, completely decoupled from display rotation.
    case independent
    /// Trackpad rotation disabled (0° pass-through, event taps suspended).
    case off

    public var id: String { rawValue }
}

/// Filters which physical trackpad devices SpinMac remaps. External mice are never remapped.
public enum TrackpadScope: String, CaseIterable, Codable, Sendable, Identifiable {
    case builtInOnly
    case allTrackpads
    case externalOnly

    public var id: String { rawValue }

    public func matches(isBuiltIn: Bool) -> Bool {
        switch self {
        case .builtInOnly: return isBuiltIn
        case .allTrackpads: return true
        case .externalOnly: return !isBuiltIn
        }
    }
}

/// In-app language preference (supports instant switching without relaunching).
public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case en
    case zhHans = "zh-Hans"

    public var id: String { rawValue }
}

/// Pure display descriptor emitted by DisplayEngine (presentation names are localized in SpinMacApp).
public struct DisplayDescriptor: Identifiable, Equatable, Sendable {
    public let id: CGDirectDisplayID
    public let rawName: String?
    public let isBuiltIn: Bool
    public let canChangeOrientation: Bool
    public let currentAngle: SpinAngle
    public let bounds: CGRect

    public init(
        id: CGDirectDisplayID,
        rawName: String?,
        isBuiltIn: Bool,
        canChangeOrientation: Bool,
        currentAngle: SpinAngle,
        bounds: CGRect
    ) {
        self.id = id
        self.rawName = rawName
        self.isBuiltIn = isBuiltIn
        self.canChangeOrientation = canChangeOrientation
        self.currentAngle = currentAngle
        self.bounds = bounds
    }
}

/// Pure configuration state consumed by TrackpadEngine.
public struct TrackpadConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var angle: SpinAngle = .deg0
    public var scope: TrackpadScope = .builtInOnly
    public var remapPointer: Bool = true
    public var remapScroll: Bool = true
    public var remapPageSwipes: Bool = true
    public var remapDockSwipes: Bool = true
    public var pointerSpeed: Double = 1.0
    public var scrollSpeed: Double = 1.0
    public var swapXYOverride: Bool = false
    public var invertXOverride: Bool = false
    public var invertYOverride: Bool = false

    public init() {}

    /// True iff TrackpadEngine must actively intercept and transform events.
    public var isActive: Bool {
        enabled && (angle != .deg0 || swapXYOverride || invertXOverride || invertYOverride)
    }

    public var hasAxisOverrides: Bool {
        swapXYOverride || invertXOverride || invertYOverride
    }

    /// Single source of truth for resolving effective trackpad rotation angle across modes.
    public static func resolveEffectiveAngle(
        displayAngle: SpinAngle,
        isSelectedDisplayBuiltIn: Bool,
        mode: TrackpadMode,
        independentAngle: SpinAngle,
        scope: TrackpadScope
    ) -> SpinAngle {
        switch mode {
        case .off:
            return .deg0
        case .independent:
            return independentAngle
        case .linked:
            // Invariant: rotating an external display never accidentally rotates the built-in trackpad.
            if !isSelectedDisplayBuiltIn && scope == .builtInOnly {
                return .deg0
            }
            return displayAngle
        }
    }
}

/// Real-time normalized finger contact for the live calibration canvas.
public struct TouchPointSnapshot: Identifiable, Equatable, Sendable {
    public let id: Int32
    /// Normalized 0...1, Y-down for SwiftUI Canvas display.
    public let rawPoint: CGPoint
    /// Normalized 0...1, Y-down after applying SpinMac orientation transform.
    public let mappedPoint: CGPoint

    public init(id: Int32, rawPoint: CGPoint, mappedPoint: CGPoint) {
        self.id = id
        self.rawPoint = rawPoint
        self.mappedPoint = mappedPoint
    }
}

/// Typed core error surfaced to the presentation layer for localized messaging.
public enum SpinMacError: Equatable, Sendable {
    case displayRotationUnsupported
    case launchAtLoginFailed(String)
}
