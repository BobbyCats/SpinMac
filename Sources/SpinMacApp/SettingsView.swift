import AppKit
import Observation
import SpinMacCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Hashable {
    case general
    case trackpad
    case calibration
    case about

    var toolbarIdentifier: NSToolbarItem.Identifier {
        NSToolbarItem.Identifier("app.spinmac.settings.\(rawValue)")
    }

    var symbolName: String {
        switch self {
        case .general: return "command"
        case .trackpad: return "rectangle.and.hand.point.up.left"
        case .calibration: return "viewfinder"
        case .about: return "info.circle"
        }
    }

    var toolbarLabelKey: String {
        switch self {
        case .general: return "settings.toolbar.general"
        case .trackpad: return "settings.toolbar.trackpad"
        case .calibration: return "settings.toolbar.calibration"
        case .about: return "settings.toolbar.about"
        }
    }

    var windowTitleKey: String {
        switch self {
        case .general: return "settings.tab.general"
        case .trackpad: return "settings.tab.trackpad"
        case .calibration: return "settings.tab.calibration"
        case .about: return "settings.tab.about"
        }
    }

    var preferredContentSize: NSSize {
        switch self {
        case .general: return NSSize(width: 556, height: 644)
        case .trackpad: return NSSize(width: 556, height: 592)
        case .calibration: return NSSize(width: 556, height: 500)
        case .about: return NSSize(width: 520, height: 516)
        }
    }

    static func from(toolbarIdentifier: NSToolbarItem.Identifier) -> SettingsTab? {
        allCases.first { $0.toolbarIdentifier == toolbarIdentifier }
    }
}

@MainActor
@Observable
final class SettingsNavigationState {
    var selectedTab: SettingsTab = .general
}

struct SettingsView: View {
    @Bindable var coordinator: SpinCoordinator
    @Bindable var navigation: SettingsNavigationState

    var body: some View {
        let l10n = coordinator.l10n

        Group {
            switch navigation.selectedTab {
            case .general:
                GeneralSettingsTab(coordinator: coordinator)
            case .trackpad:
                TrackpadSettingsTab(coordinator: coordinator)
            case .calibration:
                CalibrationSettingsTab(coordinator: coordinator, feed: coordinator.calibrationFeed)
            case .about:
                AboutSettingsTab(coordinator: coordinator)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.locale, l10n.resolvedLocale)
        .sheet(isPresented: $coordinator.isUpdateSheetPresented) {
            UpdateSheetView(coordinator: coordinator)
        }
        .onAppear {
            coordinator.refreshPermissions()
        }
    }
}
