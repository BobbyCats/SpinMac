import SpinMacCore
import SwiftUI

struct UpdateSheetView: View {
    @Bindable var coordinator: SpinCoordinator
    @Environment(\.dismiss) private var dismiss

    private let accentOrange = Color(red: 0.89, green: 0.36, blue: 0.16)

    var body: some View {
        let l10n = coordinator.l10n
        let manifest = coordinator.detectedUpdateManifest

        VStack(alignment: .leading, spacing: 14) {
            headerSection(manifest: manifest, l10n: l10n)

            if let manifest {
                notesCard(manifest: manifest, l10n: l10n)
            }

            statusProgressSection(l10n: l10n)

            Divider()
                .opacity(0.45)

            actionBar(manifest: manifest, l10n: l10n)
        }
        .padding(18)
        .frame(width: 440)
        .environment(\.locale, l10n.resolvedLocale)
    }

    private func headerSection(manifest: ReleaseManifest?, l10n: L10n) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accentOrange.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accentOrange)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(
                    manifest.map { l10n.t("update.sheet.title", $0.version) }
                        ?? l10n.t("settings.general.updates")
                )
                .font(.system(size: 15, weight: .semibold))

                HStack(spacing: 6) {
                    Text(
                        manifest.map {
                            l10n.t("update.sheet.versionTransition", coordinator.currentAppVersion.description, $0.version)
                        } ?? "v\(coordinator.currentAppVersion.description)"
                    )
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                    if let size = manifest?.sizeBytes, size > 0 {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(Self.formatBytes(size))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func notesCard(manifest: ReleaseManifest, l10n: L10n) -> some View {
        let notes = manifest.localizedNotes(isChinese: l10n.isChinese)

        return VStack(alignment: .leading, spacing: 7) {
            Text(l10n.t("update.sheet.whatsNew"))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if notes.isEmpty {
                Text(l10n.t("update.sheet.noNotes"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, line in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(accentOrange.opacity(0.85))
                                    .frame(width: 4.5, height: 4.5)
                                    .padding(.top, 5.5)
                                Text(line)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 136)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(ControlCardModifier(cornerRadius: 10))
    }

    @ViewBuilder
    private func statusProgressSection(l10n: L10n) -> some View {
        switch coordinator.updateState {
        case .downloading(_, _, let progress):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(
                        l10n.t(
                            "update.status.downloadingFrom",
                            progress.channel == .mirror
                                ? l10n.t("update.channel.mirror")
                                : l10n.t("update.channel.github")
                        )
                    )
                    .font(.system(size: 11.5, weight: .medium))

                    Spacer()

                    if progress.totalBytes > 0 {
                        Text("\(Self.formatBytes(progress.bytesReceived)) / \(Self.formatBytes(progress.totalBytes))")
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Int((progress.fractionCompleted * 100).rounded()))%")
                            .font(.system(size: 11, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: progress.fractionCompleted, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(accentOrange)

                Text(l10n.t("update.status.shaHint"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

        case .readyToInstall(_, _, _):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.green)
                Text(l10n.t("update.status.verifiedReady"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .failed(let message, _, _):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.orange)
                    .padding(.top, 1)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        default:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(l10n.t("update.sheet.installHint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionBar(manifest: ReleaseManifest?, l10n: L10n) -> some View {
        HStack(spacing: 8) {
            if manifest != nil, !isDownloading {
                Button(l10n.t("update.action.skip")) {
                    coordinator.skipAvailableUpdate()
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(l10n.t("update.action.releasePage")) {
                coordinator.openReleasePage()
            }
            .controlSize(.regular)

            if isDownloading {
                Button(l10n.t("update.action.cancel")) {
                    coordinator.cancelUpdateDownload()
                }
                .controlSize(.regular)
            } else {
                Button(l10n.t("update.action.later")) {
                    coordinator.isUpdateSheetPresented = false
                    dismiss()
                }
                .controlSize(.regular)

                if case .readyToInstall(_, _, let dmgURL) = coordinator.updateState {
                    Button(l10n.t("update.action.openDmg")) {
                        coordinator.openDownloadedDMG(dmgURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentOrange)
                    .controlSize(.regular)
                } else if manifest != nil {
                    Button(l10n.t("update.action.downloadInstall")) {
                        coordinator.downloadAvailableUpdate()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentOrange)
                    .controlSize(.regular)
                }
            }
        }
    }

    private var isDownloading: Bool {
        if case .downloading = coordinator.updateState { return true }
        return false
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
