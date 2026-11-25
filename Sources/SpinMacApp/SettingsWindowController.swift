import AppKit
import Observation
import SpinMacCore
import SwiftUI

/// Native AppKit Settings window controller with a real macOS Preference `NSToolbar`.
/// Replaces SwiftUI's inline `TabView` fallback so all macOS 14–26 versions render crisp
/// icon+label preference toolbar tabs with zero top-section clipping and smooth per-tab sizing.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private let coordinator: SpinCoordinator
    private let navigation = SettingsNavigationState()
    private var window: NSWindow?
    private var toolbar: NSToolbar?

    init(coordinator: SpinCoordinator) {
        self.coordinator = coordinator
        super.init()
        observeLanguageForChrome()
    }

    func show(tab: SettingsTab? = nil, presentUpdateSheet: Bool = false) {
        if let tab {
            selectTab(tab, animateResize: window != nil)
        }
        if presentUpdateSheet && coordinator.detectedUpdateManifest != nil {
            coordinator.isUpdateSheetPresented = true
        }

        if let window {
            syncWindowChrome()
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let rootView = SettingsView(coordinator: coordinator, navigation: navigation)
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = []

        let initialSize = navigation.selectedTab.preferredContentSize
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = hostingController
        win.isReleasedWhenClosed = false
        win.delegate = self

        let tb = NSToolbar(identifier: NSToolbar.Identifier("app.spinmac.SettingsToolbar"))
        tb.delegate = self
        tb.displayMode = .iconAndLabel
        tb.allowsUserCustomization = false
        tb.autosavesConfiguration = false
        tb.selectedItemIdentifier = navigation.selectedTab.toolbarIdentifier
        win.toolbar = tb
        win.toolbarStyle = .preference

        self.toolbar = tb
        self.window = win
        syncWindowChrome()
        win.setContentSize(initialSize)
        win.center()

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    // MARK: - Tab Switching & Smooth Frame Resize

    private func selectTab(_ tab: SettingsTab, animateResize: Bool) {
        let changed = (navigation.selectedTab != tab)
        navigation.selectedTab = tab
        toolbar?.selectedItemIdentifier = tab.toolbarIdentifier
        syncWindowChrome()

        guard let window, changed else { return }
        let targetContent = tab.preferredContentSize
        let currentFrame = window.frame
        let newFrameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContent)).size
        let newOrigin = NSPoint(
            x: currentFrame.origin.x + (currentFrame.width - newFrameSize.width) / 2.0,
            y: currentFrame.maxY - newFrameSize.height
        )
        let targetFrame = NSRect(origin: newOrigin, size: newFrameSize)
        window.setFrame(targetFrame, display: true, animate: animateResize)
    }

    private func syncWindowChrome() {
        let l10n = coordinator.l10n
        window?.title = l10n.t(navigation.selectedTab.windowTitleKey)
        if let items = toolbar?.items {
            for item in items {
                if let tab = SettingsTab.from(toolbarIdentifier: item.itemIdentifier) {
                    let label = l10n.t(tab.toolbarLabelKey)
                    item.label = label
                    item.paletteLabel = label
                }
            }
        }
    }

    private func observeLanguageForChrome() {
        withObservationTracking {
            _ = coordinator.language
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.syncWindowChrome()
                self.observeLanguageForChrome()
            }
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsTab.allCases.map(\.toolbarIdentifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let tab = SettingsTab.from(toolbarIdentifier: itemIdentifier) else { return nil }
        let label = coordinator.l10n.t(tab.toolbarLabelKey)
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = label
        item.paletteLabel = label
        item.image = NSImage(systemSymbolName: tab.symbolName, accessibilityDescription: label)
        item.target = self
        item.action = #selector(handleToolbarItemClick(_:))
        return item
    }

    @objc private func handleToolbarItemClick(_ sender: NSToolbarItem) {
        if let tab = SettingsTab.from(toolbarIdentifier: sender.itemIdentifier) {
            selectTab(tab, animateResize: true)
        }
    }
}
