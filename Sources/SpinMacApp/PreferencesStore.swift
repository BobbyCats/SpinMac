import Foundation
import SpinMacCore

/// Backward-compatible UserDefaults persistence for SpinMac preferences.
public struct SpinMacPreferences: Codable, Equatable, Sendable {
    public var preferredVerticalAngle: SpinAngle = .deg270
    public var trackpadMode: TrackpadMode = .linked
    public var independentTrackpadAngle: SpinAngle = .deg270
    public var safetyRollbackEnabled: Bool = true
    public var language: AppLanguage = .system
    public var trackpadConfig: TrackpadConfig = TrackpadConfig()
    public var autoCheckUpdates: Bool = true
    public var skippedUpdateVersion: String? = nil
    public var lastUpdateCheckTimestamp: TimeInterval? = nil

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case preferredVerticalAngle
        case trackpadMode
        case independentTrackpadAngle
        case safetyRollbackEnabled
        case language
        case trackpadConfig
        case autoCheckUpdates
        case skippedUpdateVersion
        case lastUpdateCheckTimestamp
        // Legacy v1 key for seamless upgrade
        case linkTrackpad
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preferredVerticalAngle = try c.decodeIfPresent(SpinAngle.self, forKey: .preferredVerticalAngle) ?? .deg270
        if let mode = try c.decodeIfPresent(TrackpadMode.self, forKey: .trackpadMode) {
            trackpadMode = mode
        } else if let legacyLink = try c.decodeIfPresent(Bool.self, forKey: .linkTrackpad) {
            trackpadMode = legacyLink ? .linked : .off
        } else {
            trackpadMode = .linked
        }
        independentTrackpadAngle = try c.decodeIfPresent(SpinAngle.self, forKey: .independentTrackpadAngle) ?? .deg270
        safetyRollbackEnabled = try c.decodeIfPresent(Bool.self, forKey: .safetyRollbackEnabled) ?? true
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        trackpadConfig = try c.decodeIfPresent(TrackpadConfig.self, forKey: .trackpadConfig) ?? TrackpadConfig()
        autoCheckUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? true
        skippedUpdateVersion = try c.decodeIfPresent(String.self, forKey: .skippedUpdateVersion)
        lastUpdateCheckTimestamp = try c.decodeIfPresent(TimeInterval.self, forKey: .lastUpdateCheckTimestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preferredVerticalAngle, forKey: .preferredVerticalAngle)
        try c.encode(trackpadMode, forKey: .trackpadMode)
        try c.encode(independentTrackpadAngle, forKey: .independentTrackpadAngle)
        try c.encode(safetyRollbackEnabled, forKey: .safetyRollbackEnabled)
        try c.encode(language, forKey: .language)
        try c.encode(trackpadConfig, forKey: .trackpadConfig)
        try c.encode(autoCheckUpdates, forKey: .autoCheckUpdates)
        try c.encodeIfPresent(skippedUpdateVersion, forKey: .skippedUpdateVersion)
        try c.encodeIfPresent(lastUpdateCheckTimestamp, forKey: .lastUpdateCheckTimestamp)
    }
}

public enum PreferencesStore {
    private static let storageKey = "SpinMac.Preferences.v2"

    public static func load(from defaults: UserDefaults = .standard) -> SpinMacPreferences {
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(SpinMacPreferences.self, from: data) {
            return decoded
        }
        return SpinMacPreferences()
    }

    public static func save(_ prefs: SpinMacPreferences, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(prefs) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
