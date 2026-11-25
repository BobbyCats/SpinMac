import AppKit
import CoreGraphics
import SpinMacCore

@main
@MainActor
final class SpinMacApplicationDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SpinCoordinator?
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = SpinMacApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coord = SpinCoordinator()
        let settings = SettingsWindowController(coordinator: coord)
        let statusBar = StatusBarController(
            coordinator: coord,
            onOpenSettings: { [weak settings] in
                settings?.show()
            },
            onCheckUpdates: { [weak coord, weak settings] in
                guard let coord else { return }
                if coord.detectedUpdateManifest != nil {
                    settings?.show(presentUpdateSheet: true)
                } else {
                    settings?.show(presentUpdateSheet: false)
                    coord.checkForUpdates(manual: true)
                }
            },
            onQuit: { [weak coord] in
                coord?.shutdownCleanly()
                NSApp.terminate(nil)
            }
        )

        self.coordinator = coord
        self.settingsWindowController = settings
        self.statusBarController = statusBar
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.closePopover()
        coordinator?.shutdownCleanly()
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
