import SpinMacCore
import SwiftUI

struct TrackpadSettingsTab: View {
    @Bindable var coordinator: SpinCoordinator

    var body: some View {
        let l10n = coordinator.l10n

        Form {
            Section(l10n.t("settings.trackpad.modeSection")) {
                Picker(l10n.t("settings.trackpad.modeLabel"), selection: $coordinator.trackpadMode) {
                    ForEach(TrackpadMode.allCases) { mode in
                        Text(l10n.label(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if coordinator.trackpadMode == .independent {
                    Picker(l10n.t("settings.trackpad.independentAngle"), selection: $coordinator.independentTrackpadAngle) {
                        ForEach(SpinAngle.allCases) { angle in
                            Text("\(angle.label) (\(l10n.shortName(for: angle)))").tag(angle)
                        }
                    }
                }
            }

            Section(l10n.t("settings.trackpad.scopeSection")) {
                Picker(l10n.t("settings.trackpad.scopeLabel"), selection: $coordinator.trackpadConfig.scope) {
                    ForEach(TrackpadScope.allCases) { scope in
                        Text(l10n.label(for: scope)).tag(scope)
                    }
                }

                HStack {
                    Spacer()
                    Button(l10n.t("settings.trackpad.refreshDevices")) {
                        coordinator.refreshTrackpadDevices()
                    }
                    .controlSize(.small)
                }
            }

            Section(l10n.t("settings.trackpad.gesturesSection")) {
                Toggle(l10n.t("settings.trackpad.remapPointer"), isOn: $coordinator.trackpadConfig.remapPointer)
                Toggle(l10n.t("settings.trackpad.remapScroll"), isOn: $coordinator.trackpadConfig.remapScroll)
                Toggle(l10n.t("settings.trackpad.remapPageSwipes"), isOn: $coordinator.trackpadConfig.remapPageSwipes)
                Toggle(l10n.t("settings.trackpad.remapDockSwipes"), isOn: $coordinator.trackpadConfig.remapDockSwipes)
            }

            Section(l10n.t("settings.trackpad.feelSection")) {
                HStack {
                    Text(l10n.t("settings.trackpad.pointerSpeed"))
                    Slider(value: $coordinator.trackpadConfig.pointerSpeed, in: 0.5...2.0, step: 0.05)
                    Text(String(format: "%.2f×", coordinator.trackpadConfig.pointerSpeed))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                HStack {
                    Text(l10n.t("settings.trackpad.scrollSpeed"))
                    Slider(value: $coordinator.trackpadConfig.scrollSpeed, in: 0.5...2.0, step: 0.05)
                    Text(String(format: "%.2f×", coordinator.trackpadConfig.scrollSpeed))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }

                if coordinator.trackpadConfig.pointerSpeed != 1.0 || coordinator.trackpadConfig.scrollSpeed != 1.0 {
                    HStack {
                        Spacer()
                        Button(l10n.t("settings.trackpad.resetFeel")) {
                            coordinator.trackpadConfig.pointerSpeed = 1.0
                            coordinator.trackpadConfig.scrollSpeed = 1.0
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
