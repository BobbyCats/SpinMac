import SpinMacCore
import SwiftUI

/// Progressive macOS 26 Liquid Glass surface with automatic `.ultraThinMaterial` fallback on macOS 14–15.
struct AdaptiveGlassSurface: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
        #else
        content.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

/// Crisp Apple Control Center card surface with subtle hairline rim.
struct ControlCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 11

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(Color.primary.opacity(0.042), in: shape)
            .overlay(
                shape.strokeBorder(Color.primary.opacity(0.075), lineWidth: 0.6)
            )
    }
}

/// Reusable 4-way angle selector with sliding spring pill and hover micro-interaction.
struct AngleSegmentedControl: View {
    let selectedAngle: SpinAngle
    let l10n: L10n
    var tint: Color = .accentColor
    var compact: Bool = false
    let onSelect: (SpinAngle) -> Void

    @Namespace private var selectionNS
    @State private var hoveredAngle: SpinAngle?

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SpinAngle.allCases) { angle in
                let isSelected = selectedAngle == angle
                let isHovered = hoveredAngle == angle && !isSelected

                Button {
                    onSelect(angle)
                } label: {
                    VStack(spacing: compact ? 0.5 : 1.5) {
                        Text(angle.label)
                            .font(.system(size: compact ? 11.5 : 12.5, weight: isSelected ? .semibold : .medium, design: .rounded))
                            .monospacedDigit()
                        Text(l10n.shortName(for: angle))
                            .font(.system(size: compact ? 9 : 9.5, weight: .regular))
                            .opacity(isSelected ? 0.92 : 0.62)
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 5.5 : 7)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(tint)
                                .matchedGeometryEffect(id: "angle-pill", in: selectionNS)
                                .shadow(color: tint.opacity(0.28), radius: 3, y: 1)
                        } else if isHovered {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.055))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredAngle = hovering ? angle : (hoveredAngle == angle ? nil : hoveredAngle)
                }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10.5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10.5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selectedAngle)
    }
}

/// Subtle macOS hover footer/toolbar button style.
struct SubtleHoverButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.11 : (isHovering ? 0.065 : 0)))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            .onHover { isHovering = $0 }
    }
}
