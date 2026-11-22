import SpinMacCore
import SwiftUI

private enum SettingsTab: Hashable {
    case general
    case trackpad
    case calibration
}

struct SettingsView: View {
    @Bindable var coordinator: SpinCoordinator
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        let l10n = coordinator.l10n
        TabView(selection: $selectedTab) {
            GeneralSettingsTab(coordinator: coordinator)
                .tabItem {
                    Label(l10n.t("settings.tab.general"), systemImage: "command")
                }
                .tag(SettingsTab.general)

            TrackpadSettingsTab(coordinator: coordinator)
                .tabItem {
                    Label(l10n.t("settings.tab.trackpad"), systemImage: "rectangle.and.hand.point.up.left")
                }
                .tag(SettingsTab.trackpad)

            CalibrationSettingsTab(coordinator: coordinator, feed: coordinator.calibrationFeed)
                .tabItem {
                    Label(l10n.t("settings.tab.calibration"), systemImage: "viewfinder")
                }
                .tag(SettingsTab.calibration)
        }
        // Re-evaluating TabView toolbar items on language switch while preserving selectedTab
        .id(coordinator.language)
        .environment(\.locale, l10n.resolvedLocale)
        .frame(minWidth: 540, idealWidth: 556, maxWidth: 620, minHeight: 500, idealHeight: 528)
        .onAppear {
            coordinator.refreshPermissions()
        }
    }
}
