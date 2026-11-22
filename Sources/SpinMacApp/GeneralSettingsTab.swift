import KeyboardShortcuts
import SpinMacCore
import SwiftUI

struct GeneralSettingsTab: View {
    @Bindable var coordinator: SpinCoordinator

    var body: some View {
        let l10n = coordinator.l10n

        Form {
            Section(l10n.t("settings.general.quickToggle")) {
                Picker(l10n.t("settings.general.preferredAngle"), selection: $coordinator.preferredVerticalAngle) {
                    ForEach([SpinAngle.deg270, .deg90, .deg180], id: \.self) { angle in
                        Text("\(angle.label) (\(l10n.shortName(for: angle)))").tag(angle)
                    }
                }

                LabeledContent(l10n.t("settings.general.shortcutDisplay")) {
                    KeyboardShortcuts.Recorder(for: .toggleDisplayRotation)
                }

                LabeledContent {
                    KeyboardShortcuts.Recorder(for: .cycleTrackpadMode)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.t("settings.general.shortcutTrackpad"))
                        Text(l10n.t("settings.general.shortcutTrackpadHint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section(l10n.t("settings.general.system")) {
                Toggle(l10n.t("settings.general.safetyRollback"), isOn: $coordinator.safetyRollbackEnabled)
                Toggle(l10n.t("settings.general.launchAtLogin"), isOn: $coordinator.launchAtLogin)

                Picker(l10n.t("settings.general.language"), selection: $coordinator.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(l10n.label(for: lang)).tag(lang)
                    }
                }
            }

            Section(l10n.t("settings.general.permissions")) {
                permissionRow(
                    title: l10n.t("settings.perm.accessibility"),
                    granted: coordinator.permissions.accessibility,
                    l10n: l10n,
                    action: { PermissionsManager.requestAccessibility() }
                )
                permissionRow(
                    title: l10n.t("settings.perm.inputMonitoring"),
                    granted: coordinator.permissions.inputMonitoring,
                    l10n: l10n,
                    action: { PermissionsManager.requestInputMonitoring() }
                )
            }
        }
        .formStyle(.grouped)
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        l10n: L10n,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(granted ? Color.green : Color.orange)
            Text(title)
                .lineLimit(1)
            Spacer()
            if granted {
                Text(l10n.t("settings.perm.granted"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                Button(l10n.t("settings.perm.grant"), action: action)
                    .controlSize(.small)
            }
        }
    }
}
