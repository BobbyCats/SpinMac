import AppKit
import Observation
import SpinMacCore
import SwiftUI

/// Native AppKit Settings window controller.
/// Replaces SwiftUI's `Settings` scene so BOTH left-click Popover and right-click tray NSMenu
/// can open and activate Settings reliably in `.accessory` mode, and so the window title
/// updates immediately on live language switches.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let coordinator: SpinCoordinator
    private var window: NSWindow?

    init(coordinator: SpinCoordinator) {
        self.coordinator = coordinator
        super.init()
        observeLanguageForTitle()
    }

    func show(presentUpdateSheet: Bool = false) {
        if presentUpdateSheet && coordinator.detectedUpdateManifest != nil {
            coordinator.isUpdateSheetPresented = true
        }
        if let window {
            window.title = coordinator.l10n.t("settings.window.title")
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsView(coordinator: coordinator)
        let hostingController = NSHostingController(rootView: rootView)

        let win = NSWindow(contentViewController: hostingController)
        win.title = coordinator.l10n.t("settings.window.title")
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.toolbarStyle = .preference
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.setContentSize(NSSize(width: 556, height: 590))
        win.center()
        self.window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func observeLanguageForTitle() {
        withObservationTracking {
            _ = coordinator.language
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.window?.title = self.coordinator.l10n.t("settings.window.title")
                self.observeLanguageForTitle()
            }
        }
    }
}
