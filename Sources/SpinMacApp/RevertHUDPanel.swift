import AppKit
import CoreGraphics
import SpinMacCore
import SwiftUI

@MainActor
final class RevertHUDPanelController {
    private var panel: NSPanel?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private let onConfirm: () -> Void
    private let onRevert: () -> Void
    private let newAngle: SpinAngle
    private let displayID: CGDirectDisplayID
    private let coordinator: SpinCoordinator

    private static let hudSize = NSSize(width: 392, height: 122)

    init(
        newAngle: SpinAngle,
        displayID: CGDirectDisplayID,
        coordinator: SpinCoordinator,
        onConfirm: @escaping () -> Void,
        onRevert: @escaping () -> Void
    ) {
        self.newAngle = newAngle
        self.displayID = displayID
        self.coordinator = coordinator
        self.onConfirm = onConfirm
        self.onRevert = onRevert
    }

    func show() {
        close()

        let hudView = RevertHUDView(
            newAngle: newAngle,
            coordinator: coordinator,
            onConfirm: onConfirm,
            onRevert: onRevert
        )
        let hosting = NSHostingView(rootView: hudView)
        hosting.frame = NSRect(origin: .zero, size: Self.hudSize)

        let p = NSPanel(
            contentRect: NSRect(origin: centeredOrigin(for: displayID), size: Self.hudSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = hosting
        p.orderFrontRegardless()
        self.panel = p

        // Re-center once CoreGraphics finishes committing the rotated display geometry
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard let self else { return }
            self.recenterIfVisible(for: self.displayID)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyCode(event.keyCode) == true {
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                _ = self?.handleKeyCode(event.keyCode)
            }
        }
    }

    func recenterIfVisible(for targetDisplayID: CGDirectDisplayID) {
        guard let panel, panel.isVisible else { return }
        let origin = centeredOrigin(for: targetDisplayID)
        panel.setFrameOrigin(origin)
    }

    func close() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private func centeredOrigin(for id: CGDirectDisplayID) -> NSPoint {
        let matchedScreen = NSScreen.screens.first { screen in
            let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            return num.map { CGDirectDisplayID($0.uint32Value) == id } ?? false
        }
        let screenFrame = (matchedScreen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return NSPoint(
            x: screenFrame.midX - Self.hudSize.width / 2,
            y: screenFrame.midY - Self.hudSize.height / 2 + 32
        )
    }

    @discardableResult
    private func handleKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 36, 76: // Return / Enter
            onConfirm()
            return true
        case 53: // Escape
            onRevert()
            return true
        default:
            return false
        }
    }
}

private struct RevertHUDView: View {
    let newAngle: SpinAngle
    let coordinator: SpinCoordinator
    let onConfirm: () -> Void
    let onRevert: () -> Void

    var body: some View {
        let l10n = coordinator.l10n
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(coordinator.pendingRevertCountdown, 0)) / 10.0)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.9), value: coordinator.pendingRevertCountdown)
                    Text("\(coordinator.pendingRevertCountdown)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("hud.title", newAngle.label, l10n.shortName(for: newAngle)))
                        .font(.system(size: 13.5, weight: .semibold))
                    Text(l10n.t("hud.subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button(action: onRevert) {
                    Text(l10n.t("hud.revert"))
                        .font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onConfirm) {
                    Text(l10n.t("hud.keep"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .modifier(AdaptiveGlassSurface(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
        )
    }
}
