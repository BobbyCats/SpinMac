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

            Section(l10n.t("settings.general.updates")) {
                updateStatusRow(l10n: l10n)
                Toggle(l10n.t("settings.updates.autoCheck"), isOn: $coordinator.autoCheckUpdates)
            }
        }
        .formStyle(.grouped)
    }

    private func updateStatusRow(l10n: L10n) -> some View {
        let accentOrange = Color(red: 0.89, green: 0.36, blue: 0.16)

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SpinMac v\(coordinator.currentAppVersion.description) (\(coordinator.currentAppBuild))")
                    .font(.system(size: 12.5, weight: .medium))
                    .monospacedDigit()

                updateSubtitle(l10n: l10n, accentOrange: accentOrange)
            }

            Spacer(minLength: 8)

            switch coordinator.updateState {
            case .checking:
                ProgressView()
                    .controlSize(.small)

            case .available(let manifest, _), .downloading(let manifest, _, _), .readyToInstall(let manifest, _, _):
                Button(l10n.t("settings.updates.viewUpdate", manifest.version)) {
                    coordinator.isUpdateSheetPresented = true
                }
                .buttonStyle(.borderedProminent)
                .tint(accentOrange)
                .controlSize(.small)

            default:
                Button(l10n.t("settings.updates.checkNow")) {
                    coordinator.checkForUpdates(manual: true)
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func updateSubtitle(l10n: L10n, accentOrange: Color) -> some View {
        switch coordinator.updateState {
        case .idle:
            EmptyView()
        case .checking:
            Text(l10n.t("settings.updates.statusChecking"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .upToDate:
            Text(l10n.t("settings.updates.statusUpToDate"))
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .available(let manifest, _):
            Text(l10n.t("settings.updates.statusAvailable", manifest.version))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accentOrange)
        case .downloading(_, _, let progress):
            Text("\(Int((progress.fractionCompleted * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(accentOrange)
        case .readyToInstall(let manifest, _, _):
            Text(l10n.t("settings.updates.statusReady", manifest.version))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.green)
        case .failed(let message, _, _):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .lineLimit(2)
        }
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
