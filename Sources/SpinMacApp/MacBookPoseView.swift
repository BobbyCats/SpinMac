import SpinMacCore
import SwiftUI

/// Flat-chassis dual-body geometric MacBook silhouette displaying live Display AND Trackpad orientation.
/// - MacBook hardware stays flat and horizontal, matching real flat-on-bed / flat-on-desk placement.
/// - Inside the display lid, an active edge bar + directional arrow point toward the rotated visual TOP.
/// - Inside the glass trackpad, an independent directional arrow reflects `effectiveTrackpadAngle` and `trackpadMode`.
struct MacBookPoseView: View {
    let displayAngle: SpinAngle
    let effectiveTrackpadAngle: SpinAngle
    let trackpadMode: TrackpadMode
    let l10n: L10n
    let onTapToggle: () -> Void

    @State private var isPressed = false
    @State private var isHovering = false

    private var isIndependentSplit: Bool {
        trackpadMode == .independent && effectiveTrackpadAngle != displayAngle
    }

    private var trackpadAccent: Color {
        switch trackpadMode {
        case .linked: return .accentColor
        case .independent: return .teal
        case .off: return .secondary
        }
    }

    private var trackpadArrowRotation: Double {
        if trackpadMode == .off { return 0 }
        return effectiveTrackpadAngle.contentTopDegrees
    }

    private var stageBadgeText: String {
        switch trackpadMode {
        case .linked:
            return l10n.t("popover.pose.synced", displayAngle.label)
        case .independent:
            return l10n.t("popover.pose.independent", displayAngle.label, effectiveTrackpadAngle.label)
        case .off:
            return l10n.t("popover.pose.padOff", displayAngle.label)
        }
    }

    var body: some View {
        Button(action: onTapToggle) {
            VStack(spacing: 8) {
                ZStack {
                    // Soft concentric orientation guide ring
                    Circle()
                        .strokeBorder(Color.primary.opacity(isHovering ? 0.12 : 0.07), lineWidth: 1)
                        .frame(width: 102, height: 102)

                    // Cardinal degree ticks aligned directly with content-top arrow directions (0° up, 90° right, 180° down, 270° left)
                    ForEach(SpinAngle.allCases) { tickAngle in
                        let isDisplayTick = tickAngle == displayAngle
                        let isPadOnlyTick = isIndependentSplit && tickAngle == effectiveTrackpadAngle
                        Circle()
                            .fill(
                                isDisplayTick ? Color.accentColor
                                    : (isPadOnlyTick ? Color.teal : Color.primary.opacity(0.16))
                            )
                            .frame(
                                width: (isDisplayTick || isPadOnlyTick) ? 5 : 3,
                                height: (isDisplayTick || isPadOnlyTick) ? 5 : 3
                            )
                            .offset(y: -51)
                            .rotationEffect(.degrees(tickAngle.contentTopDegrees))
                    }

                    // Flat MacBook hardware silhouette — stays horizontal while screen & trackpad axes rotate
                    VStack(spacing: 3) {
                        // Display lid
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(displayAngle == .deg0 ? 0.12 : 0.24),
                                            Color.accentColor.opacity(displayAngle == .deg0 ? 0.05 : 0.10),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.30), lineWidth: 1.4)
                                )

                            // Physical camera notch stays centered on the top bezel
                            VStack {
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(Color.primary.opacity(0.35))
                                    .frame(width: 12, height: 3)
                                    .padding(.top, 2)
                                Spacer(minLength: 0)
                            }

                            // Active visual-top ("menu bar") edge indicator inside the flat screen
                            rotatedTopEdgeBar

                            // Visual "TOP" direction arrow + always-upright angle label
                            VStack(spacing: 1) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(displayAngle == .deg0 ? Color.secondary : Color.accentColor)
                                    .rotationEffect(.degrees(displayAngle.contentTopDegrees))
                                Text(displayAngle.label)
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary.opacity(0.84))
                            }
                            .padding(.top, 3)
                        }
                        .frame(width: 66, height: 42)

                        // Lower deck + glass trackpad (always flat)
                        ZStack {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1.2)
                                )

                            // Trackpad recess + live directional arrow
                            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                .fill(trackpadMode == .off ? Color.primary.opacity(0.04) : trackpadAccent.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .strokeBorder(
                                            trackpadMode == .off ? Color.primary.opacity(0.18) : trackpadAccent.opacity(0.62),
                                            lineWidth: 1
                                        )
                                )
                                .overlay {
                                    Image(systemName: trackpadMode == .off ? "hand.raised.slash" : "arrow.up")
                                        .font(.system(size: 7.5, weight: .bold))
                                        .foregroundStyle(trackpadAccent)
                                        .rotationEffect(.degrees(trackpadArrowRotation))
                                }
                                .frame(width: 24, height: 13)
                        }
                        .frame(width: 66, height: 20)
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: displayAngle)
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: effectiveTrackpadAngle)
                    .animation(.spring(response: 0.3, dampingFraction: 0.85), value: trackpadMode)
                }
                .frame(height: 108)

                // Dedicated centered status pill below the ring — never overlaps hardware geometry
                HStack(spacing: 4) {
                    Image(systemName: trackpadMode == .linked ? "link" : (trackpadMode == .independent ? "arrow.triangle.branch" : "hand.raised.slash"))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(trackpadAccent)
                    Text(stageBadgeText)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.055), in: Capsule())
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.05 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(isHovering ? 0.1 : 0.06), lineWidth: 0.6)
            )
            .scaleEffect(isPressed ? 0.975 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
        .help(l10n.t("popover.pose.help"))
    }

    @ViewBuilder
    private var rotatedTopEdgeBar: some View {
        switch displayAngle {
        case .deg0:
            EmptyView()
        case .deg90:
            // macOS 90° CW: physical left edge becomes visual top (menu bar)
            HStack {
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 2.5, height: 26)
                    .padding(.leading, 3)
                Spacer(minLength: 0)
            }
        case .deg180:
            VStack {
                Spacer(minLength: 0)
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 34, height: 2.5)
                    .padding(.bottom, 3)
            }
        case .deg270:
            // macOS 270° CW (90° CCW): physical right edge becomes visual top (menu bar)
            HStack {
                Spacer(minLength: 0)
                Capsule()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 2.5, height: 26)
                    .padding(.trailing, 3)
            }
        }
    }
}
