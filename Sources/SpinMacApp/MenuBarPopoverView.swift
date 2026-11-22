import SpinMacCore
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var coordinator: SpinCoordinator
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        let l10n = coordinator.l10n

        VStack(spacing: 11) {
            headerBar(l10n: l10n)

            MacBookPoseView(
                displayAngle: coordinator.currentAngle,
                effectiveTrackpadAngle: coordinator.effectiveTrackpadAngle,
                trackpadMode: coordinator.trackpadMode,
                l10n: l10n,
                onTapToggle: { coordinator.toggleQuickPortrait() }
            )

            // Display rotation 4-way selector
            VStack(alignment: .leading, spacing: 5) {
                sectionCaption(
                    title: l10n.t("popover.section.display"),
                    trailing: coordinator.currentAngle.label,
                    tint: .accentColor
                )
                AngleSegmentedControl(
                    selectedAngle: coordinator.currentAngle,
                    l10n: l10n,
                    tint: .accentColor
                ) { angle in
                    coordinator.applyDisplayRotation(to: angle)
                }
            }

            if let error = coordinator.statusError {
                errorBanner(l10n.message(for: error))
            }

            controlCard(l10n: l10n)

            footerBar(l10n: l10n)
        }
        .padding(14)
        .frame(width: 336)
        .environment(\.locale, l10n.resolvedLocale)
    }

    // MARK: - Header

    private func headerBar(l10n: L10n) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(coordinator.isAnyRotationActive ? Color.accentColor : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
                .shadow(color: coordinator.isAnyRotationActive ? Color.accentColor.opacity(0.5) : .clear, radius: 3)

            Text(l10n.t("app.name"))
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)

            if coordinator.displays.count > 1 {
                Menu {
                    ForEach(coordinator.displays) { display in
                        Button {
                            coordinator.selectDisplay(display.id)
                        } label: {
                            HStack {
                                Text(l10n.displayName(for: display))
                                if display.id == coordinator.selectedDisplayID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    displayPill(l10n: l10n, showChevron: true)
                }
                .menuStyle(.borderlessButton)
            } else {
                displayPill(l10n: l10n, showChevron: false)
            }

            Spacer(minLength: 4)

            Button {
                coordinator.toggleQuickPortrait()
            } label: {
                Text(coordinator.displayShortcutLabel)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.065), in: Capsule())
            }
            .buttonStyle(.plain)
            .help(l10n.t("popover.shortcut.help", coordinator.preferredVerticalAngle.label))
        }
    }

    private func displayPill(l10n: L10n, showChevron: Bool) -> some View {
        HStack(spacing: 3) {
            Text(coordinator.selectedDisplay.map { l10n.displayName(for: $0) } ?? l10n.t("display.builtin"))
                .lineLimit(1)
                .truncationMode(.tail)
            if showChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Color.primary.opacity(0.055), in: Capsule())
    }

    private func sectionCaption(title: String, trailing: String, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(trailing)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 2)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.11), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Control Card (Decoupled Trackpad Mode + Safety Rollback)

    private func controlCard(l10n: L10n) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.and.hand.point.up.left")
                        .font(.system(size: 12.5))
                        .foregroundStyle(
                            coordinator.trackpadMode == .independent ? Color.teal
                                : (coordinator.trackpadMode == .linked ? Color.accentColor : Color.secondary)
                        )
                        .frame(width: 16)

                    Text(l10n.t("popover.trackpad.syncRow"))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if coordinator.needsTrackpadPermissions {
                        Button {
                            if !coordinator.permissions.accessibility {
                                PermissionsManager.requestAccessibility()
                            } else {
                                PermissionsManager.requestInputMonitoring()
                            }
                        } label: {
                            Text(l10n.t("popover.permission.grant"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2.5)
                                .background(Color.orange.opacity(0.14), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help(l10n.t("popover.permission.help"))
                    } else {
                        Text(coordinator.effectiveTrackpadAngle.label)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(
                                coordinator.trackpadMode == .independent ? Color.teal
                                    : (coordinator.trackpadMode == .linked ? Color.accentColor : Color.secondary)
                            )
                    }
                }

                Picker("", selection: $coordinator.trackpadMode) {
                    ForEach(TrackpadMode.allCases) { mode in
                        Text(l10n.label(for: mode)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.regular)

                if coordinator.trackpadMode == .independent {
                    VStack(alignment: .leading, spacing: 4) {
                        sectionCaption(
                            title: l10n.t("popover.trackpad.independentAngle"),
                            trailing: coordinator.independentTrackpadAngle.label,
                            tint: .teal
                        )
                        AngleSegmentedControl(
                            selectedAngle: coordinator.independentTrackpadAngle,
                            l10n: l10n,
                            tint: .teal,
                            compact: true
                        ) { angle in
                            coordinator.applyIndependentTrackpadAngle(angle)
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if coordinator.trackpadMode == .linked
                            && !coordinator.isSelectedDisplayBuiltIn
                            && coordinator.trackpadConfig.scope == .builtInOnly {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .padding(.top, 1)
                        Text(l10n.t("popover.trackpad.externalNotice"))
                            .font(.system(size: 10.5))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .animation(.spring(response: 0.32, dampingFraction: 0.86), value: coordinator.trackpadMode)

            Divider()
                .opacity(0.45)
                .padding(.horizontal, 12)

            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12.5))
                    .foregroundStyle(coordinator.safetyRollbackEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 16)

                Text(l10n.t("popover.safety.rollback"))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Toggle("", isOn: $coordinator.safetyRollbackEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .modifier(ControlCardModifier())
    }

    // MARK: - Footer (Settings + Quick Language Switcher + Quit)

    private func footerBar(l10n: L10n) -> some View {
        HStack(spacing: 4) {
            Button(action: onOpenSettings) {
                Label(l10n.t("popover.footer.settings"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(SubtleHoverButtonStyle())

            Spacer(minLength: 4)

            // Instant in-popover bilingual switcher
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button {
                        coordinator.language = lang
                    } label: {
                        HStack {
                            Text(l10n.label(for: lang))
                            if coordinator.language == lang {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "globe")
                        .font(.system(size: 10.5))
                    Text(l10n.compactLanguageBadge)
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(Color.primary.opacity(0.055), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(l10n.t("popover.footer.languageHelp"))

            Button(action: onQuit) {
                Text(l10n.t("popover.footer.quit"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(SubtleHoverButtonStyle())
        }
        .padding(.horizontal, 1)
    }
}
