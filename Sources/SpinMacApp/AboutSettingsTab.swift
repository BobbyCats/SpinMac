import AppKit
import SpinMacCore
import SwiftUI

struct AboutSettingsTab: View {
    @Bindable var coordinator: SpinCoordinator
    @State private var copiedDiagnostics = false
    @State private var showCoffeeSheet = false

    private let accentOrange = Color(red: 0.89, green: 0.36, blue: 0.16)

    private static let twitterURL = URL(string: "https://x.com/BobbyCat2025")!
    private static let githubURL = URL(string: "https://github.com/BobbyCats/SpinMac")!
    private static let issuesURL = URL(string: "https://github.com/BobbyCats/SpinMac/issues")!

    var body: some View {
        let l10n = coordinator.l10n

        ScrollView {
            VStack(spacing: 14) {
                brandHeaderCard(l10n: l10n)
                authorAndLinksCard(l10n: l10n)
                transparencyFooterCard(l10n: l10n)

                Text(l10n.t("about.eyeHealth"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
            }
            .padding(18)
        }
        .sheet(isPresented: $showCoffeeSheet) {
            CoffeeTipSheetView(l10n: l10n)
        }
    }

    // MARK: - Brand Header

    @ViewBuilder
    private var appIconView: some View {
        if Bundle.main.bundleURL.pathExtension == "app",
           let icnsURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: icnsURL) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
        } else {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
        }
    }

    private func brandHeaderCard(l10n: L10n) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                appIconView
                    .frame(width: 60, height: 60)
                    .shadow(color: .black.opacity(0.16), radius: 5, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(l10n.t("app.name"))
                            .font(.system(size: 19, weight: .bold))

                        Text("v\(coordinator.currentAppVersion.description) (\(coordinator.currentAppBuild))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.primary.opacity(0.065), in: Capsule())
                    }

                    Text(l10n.t("about.archUniversal"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Text(l10n.t("about.tagline"))
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            Divider().opacity(0.45)

            HStack(spacing: 8) {
                if case .available(let manifest, _) = coordinator.updateState {
                    Button(l10n.t("settings.updates.viewUpdate", manifest.version)) {
                        coordinator.isUpdateSheetPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accentOrange)
                    .controlSize(.small)
                } else if case .checking = coordinator.updateState {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(l10n.t("settings.updates.statusChecking"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button(l10n.t("settings.updates.checkNow")) {
                        coordinator.checkForUpdates(manual: true)
                    }
                    .controlSize(.small)
                }

                if case .upToDate = coordinator.updateState {
                    Text(l10n.t("settings.updates.statusUpToDate"))
                        .font(.system(size: 11))
                        .foregroundStyle(.green)
                }

                Spacer()

                Button {
                    copyDiagnosticsToPasteboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copiedDiagnostics ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text(copiedDiagnostics ? l10n.t("about.copied") : l10n.t("about.copyDiagnostics"))
                    }
                    .foregroundStyle(copiedDiagnostics ? Color.green : Color.primary)
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .modifier(ControlCardModifier(cornerRadius: 12))
    }

    // MARK: - Author & Links

    private func authorAndLinksCard(l10n: L10n) -> some View {
        VStack(spacing: 0) {
            infoRow(
                icon: "person.crop.circle",
                iconColor: .secondary,
                title: l10n.t("about.row.author"),
                trailing: "BobbyCat",
                action: nil
            )

            rowDivider()

            infoRow(
                icon: "at",
                iconColor: .primary,
                title: l10n.t("about.row.twitter"),
                trailing: "@BobbyCat2025",
                action: { NSWorkspace.shared.open(Self.twitterURL) }
            )

            rowDivider()

            infoRow(
                icon: "chevron.left.forwardslash.chevron.right",
                iconColor: .accentColor,
                title: l10n.t("about.row.github"),
                trailing: "BobbyCats/SpinMac",
                action: { NSWorkspace.shared.open(Self.githubURL) }
            )

            rowDivider()

            infoRow(
                icon: "bubble.left.and.exclamationmark.bubble.right",
                iconColor: .teal,
                title: l10n.t("about.row.issues"),
                trailing: "GitHub Issues",
                action: { NSWorkspace.shared.open(Self.issuesURL) }
            )

            rowDivider()

            infoRow(
                icon: "cup.and.saucer.fill",
                iconColor: accentOrange,
                title: l10n.t("about.row.coffee"),
                trailing: l10n.t("about.row.coffeeAction"),
                trailingColor: accentOrange,
                action: { showCoffeeSheet = true }
            )
        }
        .modifier(ControlCardModifier(cornerRadius: 12))
    }

    // MARK: - Transparency & License

    private func transparencyFooterCard(l10n: L10n) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Text(l10n.t("about.privacy"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(l10n.t("about.license"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .modifier(ControlCardModifier(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func rowDivider() -> some View {
        Divider()
            .opacity(0.45)
            .padding(.horizontal, 14)
    }

    @ViewBuilder
    private func infoRow(
        icon: String,
        iconColor: Color,
        title: String,
        trailing: String,
        trailingColor: Color = .secondary,
        action: (() -> Void)?
    ) -> some View {
        let content = HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Text(trailing)
                    .font(.system(size: 12))
                    .foregroundStyle(trailingColor)
                if action != nil {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(trailingColor.opacity(0.75))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func copyDiagnosticsToPasteboard() {
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif

        // Strictly sanitized hardware/version summary — zero username, path, or serial info.
        let summary = """
        SpinMac: v\(coordinator.currentAppVersion.description) (\(coordinator.currentAppBuild)) [\(arch)]
        macOS: \(osVersion)
        Displays: \(coordinator.displays.count) (active angle: \(coordinator.currentAngle.label), built-in: \(coordinator.isSelectedDisplayBuiltIn))
        Trackpad: mode=\(coordinator.trackpadMode.rawValue), angle=\(coordinator.effectiveTrackpadAngle.label), scope=\(coordinator.trackpadConfig.scope.rawValue)
        Permissions: accessibility=\(coordinator.permissions.accessibility), inputMonitoring=\(coordinator.permissions.inputMonitoring)
        """

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary, forType: .string)

        copiedDiagnostics = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copiedDiagnostics = false
        }
    }
}

private struct CoffeeTipSheetView: View {
    let l10n: L10n
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text(l10n.t("about.coffee.title"))
                .font(.system(size: 15, weight: .semibold))

            Text(l10n.t("about.coffee.subtitle"))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let qrImage = Self.loadCoffeeImage() {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 290)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
                    )
            }

            Button(l10n.t("about.coffee.close")) {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 2)
        }
        .padding(20)
        .frame(width: 316)
        .environment(\.locale, l10n.resolvedLocale)
    }

    private static func loadCoffeeImage() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "wechat-coffee", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}
