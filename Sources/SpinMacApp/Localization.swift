import Foundation
import SpinMacCore

/// Deterministic runtime localization store backed by cached `.strings` tables inside `Bundle.module`.
/// Immune to SwiftPM lowercasing `.lproj` directories (e.g., `zh-Hans.lproj` -> `zh-hans.lproj`)
/// and supports zero-restart instant language switching across Popover, Settings, HUD, and NSMenu.
@MainActor
public struct L10n {
    public let language: AppLanguage

    private static var cachedTables: [String: [String: String]] = [:]

    public init(language: AppLanguage) {
        self.language = language
    }

    /// Resolves `.system` to either `"zh-Hans"` or `"en"`.
    public var isChinese: Bool {
        resolvedLocaleIdentifier == "zh-Hans"
    }

    public var resolvedLocaleIdentifier: String {
        switch language {
        case .en:
            return "en"
        case .zhHans:
            return "zh-Hans"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? "zh-Hans" : "en"
        }
    }

    public var resolvedLocale: Locale {
        Locale(identifier: resolvedLocaleIdentifier)
    }

    private var table: [String: String] {
        let code = resolvedLocaleIdentifier
        if let hit = Self.cachedTables[code] {
            return hit
        }
        let loaded = Self.loadStringsTable(for: code)
        Self.cachedTables[code] = loaded
        return loaded
    }

    private static func loadStringsTable(for code: String) -> [String: String] {
        let candidates: [String] = (code == "zh-Hans")
            ? ["zh-Hans", "zh-hans", "zh_CN"]
            : ["en", "Base"]

        // 1. Direct localization-aware lookup via Foundation Bundle API
        for candidate in candidates {
            if let url = Bundle.module.url(
                forResource: "Localizable",
                withExtension: "strings",
                subdirectory: nil,
                localization: candidate
            ), let dict = NSDictionary(contentsOf: url) as? [String: String] {
                return dict
            }
        }

        // 2. Direct filesystem scan inside Bundle.module (immune to CFBundle cache quirks)
        for candidate in candidates {
            let directURL = Bundle.module.bundleURL
                .appendingPathComponent("\(candidate).lproj", isDirectory: true)
                .appendingPathComponent("Localizable.strings")
            if let dict = NSDictionary(contentsOf: directURL) as? [String: String] {
                return dict
            }
        }

        // 3. Fallback to English table
        if code != "en" {
            return loadStringsTable(for: "en")
        }
        return [:]
    }

    public func t(_ key: String) -> String {
        table[key] ?? key
    }

    public func t(_ key: String, _ args: CVarArg...) -> String {
        let format = t(key)
        return String(format: format, locale: resolvedLocale, arguments: args)
    }

    public func shortName(for angle: SpinAngle) -> String {
        switch angle {
        case .deg0: return t("angle.0.short")
        case .deg90: return t("angle.90.short")
        case .deg180: return t("angle.180.short")
        case .deg270: return t("angle.270.short")
        }
    }

    public func label(for mode: TrackpadMode) -> String {
        switch mode {
        case .linked: return t("trackpad.mode.linked")
        case .independent: return t("trackpad.mode.independent")
        case .off: return t("trackpad.mode.off")
        }
    }

    public func label(for scope: TrackpadScope) -> String {
        switch scope {
        case .builtInOnly: return t("scope.builtInOnly")
        case .allTrackpads: return t("scope.allTrackpads")
        case .externalOnly: return t("scope.externalOnly")
        }
    }

    public func label(for lang: AppLanguage) -> String {
        switch lang {
        case .system: return t("lang.system")
        case .en: return t("lang.en")
        case .zhHans: return t("lang.zhHans")
        }
    }

    public var compactLanguageBadge: String {
        isChinese ? t("lang.compact.zh") : t("lang.compact.en")
    }

    public func displayName(for descriptor: DisplayDescriptor) -> String {
        if descriptor.isBuiltIn {
            return t("display.builtin")
        }
        if let raw = descriptor.rawName, !raw.isEmpty {
            return raw
        }
        return t("display.external", String(descriptor.id))
    }

    public func message(for error: SpinMacError) -> String {
        switch error {
        case .displayRotationUnsupported:
            return t("error.displayUnsupported")
        case .launchAtLoginFailed(let detail):
            return t("error.launchAtLogin", detail)
        }
    }
}
