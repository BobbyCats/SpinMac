import SpinMacCore
import SwiftUI

/// Dual-body geometric vector MacBook silhouette displaying live Display AND Trackpad orientation.
/// - Display lid rotates smoothly with `displayAngle`.
/// - Trackpad directional arrow independently reflects `effectiveTrackpadAngle` and `trackpadMode`.
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
        return -effectiveTrackpadAngle.visualRotationDegrees
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

                    // Cardinal degree ticks
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
                            .rotationEffect(.degrees(tickAngle.visualRotationDegrees))
                    }

                    // Rotating MacBook hardware silhouette
                    VStack(spacing: 3) {
                        // Display lid
                        ZStack(alignment: .top) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.accentColor.opacity(displayAngle == .deg0 ? 0.12 : 0.26),
                                            Color.accentColor.opacity(displayAngle == .deg0 ? 0.05 : 0.11),
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.30), lineWidth: 1.4)
                                )

                            // Camera notch
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(Color.primary.opacity(0.35))
                                .frame(width: 12, height: 3)
                                .padding(.top, 2)

                            // Visual "TOP" direction indicator inside display
                            VStack(spacing: 1) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundStyle(displayAngle == .deg0 ? Color.secondary : Color.accentColor)
                                Text(displayAngle.label)
                                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary.opacity(0.84))
                            }
                            .frame(maxHeight: .infinity)
                            .rotationEffect(.degrees(-displayAngle.visualRotationDegrees))
                        }
                        .frame(width: 64, height: 40)

                        // Lower deck + glass trackpad
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
                        .frame(width: 64, height: 20)
                    }
                    .rotationEffect(.degrees(displayAngle.visualRotationDegrees))
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: displayAngle)
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
}
