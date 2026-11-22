import SpinMacCore
import SwiftUI

/// High-FPS live calibration studio backed by SwiftUI Canvas.
/// Acquires MultitouchMonitor ONLY while visible, guaranteeing 0% idle CPU when closed.
struct CalibrationSettingsTab: View {
    @Bindable var coordinator: SpinCoordinator
    @Bindable var feed: CalibrationFeed

    var body: some View {
        let l10n = coordinator.l10n

        ScrollView {
            VStack(spacing: 12) {
                Text(l10n.t("settings.cal.subtitle"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                // Live status + Swipe Up to Auto-Calibrate bar
                statusAndAutoCalibrateBar(l10n: l10n)

                // Dual high-fps Canvas surfaces
                HStack(spacing: 14) {
                    TouchSurfaceCanvas(
                        title: l10n.t("settings.cal.rawBox"),
                        points: feed.activePoints.map { ($0.id, $0.rawPoint) },
                        trails: feed.trails.mapValues { $0.map(\.raw) },
                        accent: .secondary,
                        isRecording: feed.isAutoCalibrating
                    )

                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)

                    TouchSurfaceCanvas(
                        title: l10n.t("settings.cal.mappedBox", coordinator.effectiveTrackpadAngle.label),
                        points: feed.activePoints.map { ($0.id, $0.mappedPoint) },
                        trails: feed.trails.mapValues { $0.map(\.mapped) },
                        accent: coordinator.trackpadMode == .independent ? .teal : .accentColor,
                        isRecording: false
                    )
                }

                // Cleanly stacked Trackpad Mode + Independent Angle + Axis Overrides card
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(l10n.t("popover.trackpad.syncRow"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: true, vertical: false)

                        Picker("", selection: $coordinator.trackpadMode) {
                            ForEach(TrackpadMode.allCases) { mode in
                                Text(l10n.label(for: mode)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.regular)
                    }

                    if coordinator.trackpadMode == .independent {
                        AngleSegmentedControl(
                            selectedAngle: coordinator.independentTrackpadAngle,
                            l10n: l10n,
                            tint: .teal,
                            compact: true
                        ) { angle in
                            coordinator.applyIndependentTrackpadAngle(angle)
                        }
                    }

                    Divider().opacity(0.45)

                    HStack(spacing: 16) {
                        Toggle(l10n.t("settings.cal.swapXY"), isOn: $coordinator.trackpadConfig.swapXYOverride)
                            .fixedSize()
                        Toggle(l10n.t("settings.cal.invertX"), isOn: $coordinator.trackpadConfig.invertXOverride)
                            .fixedSize()
                        Toggle(l10n.t("settings.cal.invertY"), isOn: $coordinator.trackpadConfig.invertYOverride)
                            .fixedSize()
                        Spacer(minLength: 8)
                        Button(l10n.t("settings.cal.resetAxes")) {
                            coordinator.trackpadConfig.swapXYOverride = false
                            coordinator.trackpadConfig.invertXOverride = false
                            coordinator.trackpadConfig.invertYOverride = false
                        }
                        .controlSize(.small)
                        .fixedSize()
                        .disabled(!coordinator.trackpadConfig.hasAxisOverrides)
                    }
                    .font(.system(size: 12))
                }
                .padding(12)
                .modifier(ControlCardModifier(cornerRadius: 10))

                HStack(spacing: 5) {
                    Image(systemName: "computermouse")
                        .font(.system(size: 10.5))
                    Text(l10n.t("settings.cal.mouseNote"))
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .foregroundStyle(.tertiary)
            }
            .padding(18)
        }
        .onAppear {
            coordinator.refreshPermissions()
            feed.beginPreview()
        }
        .onDisappear {
            feed.endPreview()
        }
    }

    private func statusAndAutoCalibrateBar(l10n: L10n) -> some View {
        HStack(spacing: 8) {
            if !coordinator.permissions.inputMonitoring {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11.5))
                Text(l10n.t("settings.cal.statusNoPermission"))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(l10n.t("settings.perm.grant")) {
                    PermissionsManager.requestInputMonitoring()
                }
                .controlSize(.small)
                .fixedSize()
            } else if feed.isAutoCalibrating {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.system(size: 12))
                Text(l10n.t("settings.cal.statusRecording"))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(l10n.t("settings.cal.cancelCalibrate")) {
                    feed.cancelAutoCalibration()
                }
                .controlSize(.small)
                .fixedSize()
            } else {
                Circle()
                    .fill(feed.activePoints.isEmpty ? Color.secondary.opacity(0.4) : Color.green)
                    .frame(width: 7, height: 7)

                if !feed.activePoints.isEmpty {
                    Text(l10n.t("settings.cal.statusActive", feed.activePoints.count))
                        .font(.system(size: 11.5, weight: .medium))
                        .monospacedDigit()
                        .lineLimit(1)
                } else if let detected = feed.lastAutoCalibratedAngle {
                    Text(l10n.t("settings.cal.autoResult", detected.label))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                } else {
                    Text(l10n.t("settings.cal.statusWaiting"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    feed.startAutoCalibration()
                } label: {
                    Label(l10n.t("settings.cal.autoCalibrate"), systemImage: "wand.and.stars")
                        .font(.system(size: 11, weight: .medium))
                }
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            (feed.isAutoCalibrating ? Color.accentColor.opacity(0.11) : Color.primary.opacity(0.045)),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    feed.isAutoCalibrating ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.07),
                    lineWidth: 0.6
                )
        )
    }
}

/// Pure SwiftUI Canvas renderer for 120fps touch dots, motion trails, and directional vector arrows.
private struct TouchSurfaceCanvas: View {
    let title: String
    let points: [(id: Int32, point: CGPoint)]
    let trails: [Int32: [CGPoint]]
    let accent: Color
    let isRecording: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Canvas { context, size in
                let pad: CGFloat = 12
                let innerW = max(size.width - pad * 2, 1)
                let innerH = max(size.height - pad * 2, 1)

                func map(_ pt: CGPoint) -> CGPoint {
                    CGPoint(x: pad + pt.x * innerW, y: pad + pt.y * innerH)
                }

                // Subtle precision crosshair & micro-grid
                var grid = Path()
                for frac in [0.25, 0.5, 0.75] {
                    let gx = pad + CGFloat(frac) * innerW
                    let gy = pad + CGFloat(frac) * innerH
                    grid.move(to: CGPoint(x: gx, y: pad))
                    grid.addLine(to: CGPoint(x: gx, y: size.height - pad))
                    grid.move(to: CGPoint(x: pad, y: gy))
                    grid.addLine(to: CGPoint(x: size.width - pad, y: gy))
                }
                context.stroke(grid, with: .color(.primary.opacity(0.055)), lineWidth: 0.75)

                // Top orientation indicator bar
                let barRect = CGRect(x: size.width / 2 - 16, y: 7, width: 32, height: 3)
                context.fill(
                    Path(roundedRect: barRect, cornerRadius: 1.5),
                    with: .color(accent.opacity(0.45))
                )

                // Fading trails + directional vector per finger
                for (_, trail) in trails where trail.count >= 2 {
                    for i in 1..<trail.count {
                        let progress = Double(i) / Double(trail.count)
                        var seg = Path()
                        seg.move(to: map(trail[i - 1]))
                        seg.addLine(to: map(trail[i]))
                        context.stroke(
                            seg,
                            with: .color(accent.opacity(0.12 + 0.55 * progress)),
                            style: StrokeStyle(lineWidth: 2.0 + CGFloat(progress) * 2.0, lineCap: .round)
                        )
                    }

                    if let first = trail.first, let last = trail.last {
                        let p0 = map(first)
                        let p1 = map(last)
                        let dx = p1.x - p0.x
                        let dy = p1.y - p0.y
                        let len = hypot(dx, dy)
                        if len > 16 {
                            let angle = atan2(dy, dx)
                            let headLen: CGFloat = 8
                            var arrow = Path()
                            arrow.move(to: p1)
                            arrow.addLine(to: CGPoint(
                                x: p1.x - headLen * cos(angle - .pi / 6),
                                y: p1.y - headLen * sin(angle - .pi / 6)
                            ))
                            arrow.move(to: p1)
                            arrow.addLine(to: CGPoint(
                                x: p1.x - headLen * cos(angle + .pi / 6),
                                y: p1.y - headLen * sin(angle + .pi / 6)
                            ))
                            context.stroke(
                                arrow,
                                with: .color(accent.opacity(0.85)),
                                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                            )
                        }
                    }
                }

                // Active touch contact rings
                for (_, pt) in points {
                    let c = map(pt)
                    let halo = CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)
                    context.fill(Path(ellipseIn: halo), with: .color(accent.opacity(0.22)))
                    let dot = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: dot), with: .color(accent))
                }
            }
            .frame(height: 154)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isRecording ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.11),
                        lineWidth: isRecording ? 1.5 : 0.9
                    )
            )
        }
    }
}
