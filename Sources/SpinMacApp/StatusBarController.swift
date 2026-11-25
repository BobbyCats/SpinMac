import AppKit
import Observation
import SpinMacCore
import SwiftUI

/// First-class AppKit status bar host replacing SwiftUI's limited `MenuBarExtra(.window)`:
/// - Left-click: toggles the native Control Center `NSPopover` (with auto-dismiss & Esc close).
/// - Right-click (or Control-click): pops up a crisp native `NSMenu` with instant rotation,
///   trackpad mode, language switcher, Settings, and Quit actions.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let coordinator: SpinCoordinator
    private let onOpenSettings: () -> Void
    private let onCheckUpdates: () -> Void
    private let onQuit: () -> Void

    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var outsideClickMonitor: Any?

    init(
        coordinator: SpinCoordinator,
        onOpenSettings: @escaping () -> Void,
        onCheckUpdates: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.onOpenSettings = onOpenSettings
        self.onCheckUpdates = onCheckUpdates
        self.onQuit = onQuit
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configureStatusButton()
        configurePopover()
        observeRotationState()
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusButtonClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateStatusIcon()
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        let rootView = MenuBarPopoverView(
            coordinator: coordinator,
            onOpenSettings: { [weak self] in
                self?.closePopover()
                self?.onOpenSettings()
            },
            onOpenUpdates: { [weak self] in
                self?.closePopover()
                self?.onCheckUpdates()
            },
            onQuit: { [weak self] in
                self?.closePopover()
                self?.onQuit()
            }
        )
        let hosting = NSHostingController(rootView: rootView)
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        let symbolName = coordinator.isAnyRotationActive
            ? "rectangle.portrait.rotate"
            : "rectangle.landscape.rotate"
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "SpinMac")?
            .withSymbolConfiguration(config)
        img?.isTemplate = true
        button.image = img
    }

    private func observeRotationState() {
        withObservationTracking {
            _ = coordinator.isAnyRotationActive
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateStatusIcon()
                self.observeRotationState()
            }
        }
    }

    // MARK: - Left-Click Popover vs Right-Click Context Menu

    @objc private func handleStatusButtonClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)

        if isRightClick {
            closePopover()
            showContextMenu(from: sender)
        } else {
            togglePopover(from: sender)
        }
    }

    private func togglePopover(from button: NSStatusBarButton) {
        if popover.isShown {
            closePopover()
        } else {
            coordinator.refreshPermissions()
            coordinator.refreshDisplays()
            coordinator.refreshShortcutDisplay()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installOutsideClickMonitor()
        }
    }

    func closePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
        removeOutsideClickMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    // MARK: - Native Right-Click NSMenu

    private func showContextMenu(from button: NSStatusBarButton) {
        coordinator.refreshDisplays()
        let menu = buildContextMenu()
        statusItem.menu = menu
        button.performClick(nil)
        // Clear menu immediately after pop-up so next left-click triggers action normally
        statusItem.menu = nil
    }

    private func buildContextMenu() -> NSMenu {
        let l10n = coordinator.l10n
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 1. Quick Toggle
        let toggleTitle = l10n.t("menu.quickToggle", SpinAngle.deg0.label, coordinator.preferredVerticalAngle.label)
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(menuQuickToggle), keyEquivalent: "")
        toggleItem.target = self
        if coordinator.displayShortcutLabel != "—" {
            toggleItem.title = "\(toggleTitle)   \(coordinator.displayShortcutLabel)"
        }
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        // 2. Display Orientation Submenu
        let displayMenuItem = NSMenuItem(title: "\(l10n.t("menu.displayAngle")) (\(coordinator.currentAngle.label))", action: nil, keyEquivalent: "")
        let displaySubmenu = NSMenu()
        for angle in SpinAngle.allCases {
            let item = NSMenuItem(
                title: "\(angle.label) — \(l10n.shortName(for: angle))",
                action: #selector(menuSelectDisplayAngle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(angle.rawValue)
            item.state = (coordinator.currentAngle == angle) ? .on : .off
            displaySubmenu.addItem(item)
        }
        displayMenuItem.submenu = displaySubmenu
        menu.addItem(displayMenuItem)

        // 3. Trackpad Mode Submenu (Linked / Independent / Off + quick independent angles)
        let padTitle = "\(l10n.t("menu.trackpadMode")) (\(l10n.label(for: coordinator.trackpadMode)))"
        let trackpadMenuItem = NSMenuItem(title: padTitle, action: nil, keyEquivalent: "")
        let trackpadSubmenu = NSMenu()
        for mode in TrackpadMode.allCases {
            let item = NSMenuItem(
                title: l10n.label(for: mode),
                action: #selector(menuSelectTrackpadMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (coordinator.trackpadMode == mode) ? .on : .off
            trackpadSubmenu.addItem(item)
        }
        trackpadSubmenu.addItem(.separator())
        let indepHeader = NSMenuItem(title: l10n.t("menu.trackpadAngle"), action: nil, keyEquivalent: "")
        indepHeader.isEnabled = false
        trackpadSubmenu.addItem(indepHeader)
        for angle in SpinAngle.allCases {
            let item = NSMenuItem(
                title: "\(angle.label) — \(l10n.shortName(for: angle))",
                action: #selector(menuSelectTrackpadAngle(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(angle.rawValue)
            item.state = (coordinator.trackpadMode == .independent && coordinator.independentTrackpadAngle == angle) ? .on : .off
            trackpadSubmenu.addItem(item)
        }
        trackpadMenuItem.submenu = trackpadSubmenu
        menu.addItem(trackpadMenuItem)

        // 4. Language Submenu
        let langMenuItem = NSMenuItem(title: l10n.t("menu.language"), action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu()
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(
                title: l10n.label(for: lang),
                action: #selector(menuSelectLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lang.rawValue
            item.state = (coordinator.language == lang) ? .on : .off
            langSubmenu.addItem(item)
        }
        langMenuItem.submenu = langSubmenu
        menu.addItem(langMenuItem)

        menu.addItem(.separator())

        // 5. Updates, Settings & Quit
        let updateTitle: String
        if coordinator.hasVisibleUpdateBadge, let manifest = coordinator.detectedUpdateManifest {
            updateTitle = l10n.t("menu.updateAvailable", manifest.version)
        } else {
            updateTitle = l10n.t("menu.checkUpdates")
        }
        let updateItem = NSMenuItem(title: updateTitle, action: #selector(menuCheckUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let settingsItem = NSMenuItem(title: l10n.t("menu.settings"), action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: l10n.t("menu.quit"), action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @objc private func menuCheckUpdates() {
        onCheckUpdates()
    }

    @objc private func menuQuickToggle() {
        coordinator.toggleQuickPortrait()
    }

    @objc private func menuSelectDisplayAngle(_ sender: NSMenuItem) {
        if let angle = SpinAngle(rawValue: Int32(sender.tag)) {
            coordinator.applyDisplayRotation(to: angle)
        }
    }

    @objc private func menuSelectTrackpadMode(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let mode = TrackpadMode(rawValue: raw) {
            coordinator.trackpadMode = mode
        }
    }

    @objc private func menuSelectTrackpadAngle(_ sender: NSMenuItem) {
        if let angle = SpinAngle(rawValue: Int32(sender.tag)) {
            coordinator.applyIndependentTrackpadAngle(angle)
        }
    }

    @objc private func menuSelectLanguage(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let lang = AppLanguage(rawValue: raw) {
            coordinator.language = lang
        }
    }

    @objc private func menuOpenSettings() {
        onOpenSettings()
    }

    @objc private func menuQuit() {
        onQuit()
    }
}
