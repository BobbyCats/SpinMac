import AppKit
import Foundation
import KeyboardShortcuts
import Observation
import ServiceManagement
import SpinMacCore

public enum UpdateUIState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(manifest: ReleaseManifest, source: UpdateSourceKind)
    case downloading(manifest: ReleaseManifest, source: UpdateSourceKind, progress: DownloadProgressSnapshot)
    case readyToInstall(manifest: ReleaseManifest, source: UpdateSourceKind, dmgURL: URL)
    case failed(message: String, manifest: ReleaseManifest?, source: UpdateSourceKind?)
}

@MainActor
@Observable
public final class SpinCoordinator {
    // MARK: - Single Source of Truth
    public private(set) var displays: [DisplayDescriptor] = []
    public var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID()
    public private(set) var currentAngle: SpinAngle = .deg0
    public private(set) var permissions: PermissionStatus = PermissionsManager.currentStatus()
    public private(set) var statusError: SpinMacError?
    public private(set) var displayShortcutLabel: String = "⌥⇧S"

    // MARK: - Software Update State (Zero-Polling, 0.0% Idle CPU)
    public private(set) var updateState: UpdateUIState = .idle
    public var isUpdateSheetPresented: Bool = false

    // MARK: - Persisted Preferences
    public var preferredVerticalAngle: SpinAngle {
        didSet { savePreferences() }
    }
    public var trackpadMode: TrackpadMode {
        didSet {
            savePreferences()
            syncTrackpadEngine()
        }
    }
    public var independentTrackpadAngle: SpinAngle {
        didSet {
            savePreferences()
            syncTrackpadEngine()
        }
    }
    public var safetyRollbackEnabled: Bool {
        didSet { savePreferences() }
    }
    public var language: AppLanguage {
        didSet { savePreferences() }
    }
    public var trackpadConfig: TrackpadConfig {
        didSet {
            savePreferences()
            syncTrackpadEngine()
        }
    }
    public var autoCheckUpdates: Bool {
        didSet {
            savePreferences()
            if autoCheckUpdates {
                scheduleBackgroundUpdateCheckIfNeeded(delaySeconds: 1.5)
            }
        }
    }
    public var skippedUpdateVersion: String? {
        didSet { savePreferences() }
    }
    public var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    // MARK: - Revert HUD State
    public private(set) var pendingRevertPreviousAngle: SpinAngle?
    public private(set) var pendingRevertCountdown: Int = 10

    // MARK: - Calibration Feed (isolated from Popover/General/Trackpad views)
    public let calibrationFeed = CalibrationFeed()

    // MARK: - Engines
    private let displayEngine = DisplayEngine()
    private let trackpadEngine = TrackpadEngine()
    private let updateChecker = UpdateChecker()
    private let updateDownloader = UpdateDownloader()
    private var lastUpdateCheckTimestamp: TimeInterval?
    private var updateCheckTask: Task<Void, Never>?
    private var updateDownloadTask: Task<Void, Never>?
    private static let autoCheckIntervalSeconds: TimeInterval = 24 * 60 * 60
    private var revertTimer: Timer?
    private var permissionPollTimer: Timer?
    private var pendingRefreshTask: Task<Void, Never>?
    private var revertHUD: RevertHUDPanelController?
    private var shortcutObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    public var multitouchMonitor: MultitouchMonitor {
        trackpadEngine.multitouchMonitor
    }

    public var l10n: L10n {
        L10n(language: language)
    }

    public var currentAppVersion: SemanticVersion {
        SemanticVersion.currentAppVersion()
    }

    public var currentAppBuild: String {
        SemanticVersion.currentAppBuild()
    }

    public var detectedUpdateManifest: ReleaseManifest? {
        switch updateState {
        case .available(let manifest, _),
             .downloading(let manifest, _, _),
             .readyToInstall(let manifest, _, _):
            return manifest
        case .failed(_, let manifest, _):
            return manifest
        case .idle, .checking, .upToDate:
            return nil
        }
    }

    public var detectedUpdateSource: UpdateSourceKind? {
        switch updateState {
        case .available(_, let source),
             .downloading(_, let source, _),
             .readyToInstall(_, let source, _):
            return source
        case .failed(_, _, let source):
            return source
        case .idle, .checking, .upToDate:
            return nil
        }
    }

    /// True when an unskipped newer version is ready to surface gently in the Popover / tray menu.
    public var hasVisibleUpdateBadge: Bool {
        guard let manifest = detectedUpdateManifest else { return false }
        return skippedUpdateVersion != manifest.version
    }

    public init() {
        let loaded = PreferencesStore.load()
        self.preferredVerticalAngle = loaded.preferredVerticalAngle
        self.trackpadMode = loaded.trackpadMode
        self.independentTrackpadAngle = loaded.independentTrackpadAngle
        self.safetyRollbackEnabled = loaded.safetyRollbackEnabled
        self.language = loaded.language
        self.trackpadConfig = loaded.trackpadConfig
        self.autoCheckUpdates = loaded.autoCheckUpdates
        self.skippedUpdateVersion = loaded.skippedUpdateVersion
        self.lastUpdateCheckTimestamp = loaded.lastUpdateCheckTimestamp
        self.launchAtLogin = SMAppService.mainApp.status == .enabled

        calibrationFeed.attach(to: self)
        refreshDisplays()
        configureSystemObservers()
        configureGlobalShortcuts()
        syncTrackpadEngine()
        updatePermissionPollingState()
        scheduleBackgroundUpdateCheckIfNeeded(delaySeconds: 5.0)
    }

    // MARK: - Derived State

    public var selectedDisplay: DisplayDescriptor? {
        displays.first(where: { $0.id == selectedDisplayID }) ?? displays.first
    }

    public var isSelectedDisplayBuiltIn: Bool {
        selectedDisplay?.isBuiltIn ?? true
    }

    public var effectiveTrackpadAngle: SpinAngle {
        TrackpadConfig.resolveEffectiveAngle(
            displayAngle: currentAngle,
            isSelectedDisplayBuiltIn: isSelectedDisplayBuiltIn,
            mode: trackpadMode,
            independentAngle: independentTrackpadAngle,
            scope: trackpadConfig.scope
        )
    }

    /// True if either the display or the trackpad is actively rotated/transformed.
    public var isAnyRotationActive: Bool {
        currentAngle != .deg0 || (trackpadMode != .off && (effectiveTrackpadAngle != .deg0 || trackpadConfig.hasAxisOverrides))
    }

    public var needsTrackpadPermissions: Bool {
        trackpadMode != .off && !permissions.allGranted
    }

    // MARK: - Actions

    public func refreshDisplays() {
        let list = displayEngine.listDisplays()
        displays = list
        if !list.contains(where: { $0.id == selectedDisplayID }), let first = list.first {
            selectedDisplayID = first.id
        }
        if let active = selectedDisplay {
            currentAngle = active.currentAngle
        }
        syncTrackpadEngine()
        revertHUD?.recenterIfVisible(for: selectedDisplayID)
    }

    public func selectDisplay(_ id: CGDirectDisplayID) {
        selectedDisplayID = id
        if let active = selectedDisplay {
            currentAngle = active.currentAngle
        }
        syncTrackpadEngine()
    }

    public func toggleQuickPortrait() {
        let target: SpinAngle = (currentAngle == .deg0) ? preferredVerticalAngle : .deg0
        applyDisplayRotation(to: target, allowSafetyHUD: target != .deg0)
    }

    public func cycleTrackpadMode() {
        switch trackpadMode {
        case .linked: trackpadMode = .independent
        case .independent: trackpadMode = .off
        case .off: trackpadMode = .linked
        }
    }

    public func applyDisplayRotation(to target: SpinAngle, allowSafetyHUD: Bool = true) {
        cancelRevertHUD()

        let previous = currentAngle
        guard target != previous else { return }

        let targetDisplayID = selectedDisplay?.id ?? CGMainDisplayID()
        let ok = displayEngine.setOrientation(target, for: targetDisplayID)
        if !ok {
            statusError = .displayRotationUnsupported
            return
        }

        statusError = nil
        currentAngle = target
        scheduleDisplayRefresh()
        syncTrackpadEngine()

        if allowSafetyHUD && safetyRollbackEnabled && target != .deg0 {
            startRevertHUD(previousAngle: previous, newAngle: target, displayID: targetDisplayID)
        }
    }

    public func applyIndependentTrackpadAngle(_ angle: SpinAngle) {
        if trackpadMode != .independent {
            trackpadMode = .independent
        }
        independentTrackpadAngle = angle
    }

    public func confirmPendingRotation() {
        cancelRevertHUD()
    }

    public func revertPendingRotation() {
        guard let previous = pendingRevertPreviousAngle else { return }
        cancelRevertHUD()
        applyDisplayRotation(to: previous, allowSafetyHUD: false)
    }

    public func refreshPermissions() {
        let updated = PermissionsManager.currentStatus()
        guard updated != permissions else { return }
        permissions = updated
        if updated.allGranted {
            stopPermissionPolling()
            syncTrackpadEngine()
        } else {
            updatePermissionPollingState()
        }
    }

    public func refreshTrackpadDevices() {
        multitouchMonitor.refreshDevicesIfRunning()
    }

    public func refreshShortcutDisplay() {
        displayShortcutLabel = KeyboardShortcuts.getShortcut(for: .toggleDisplayRotation)?.description ?? "—"
    }

    public func shutdownCleanly() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
        updateDownloadTask?.cancel()
        updateDownloadTask = nil
        let downloader = updateDownloader
        Task { await downloader.cancel() }
        cancelRevertHUD()
        stopPermissionPolling()
        calibrationFeed.endPreview()
        if let shortcutObserver {
            NotificationCenter.default.removeObserver(shortcutObserver)
            self.shortcutObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
        displayEngine.stopObservingReconfiguration()
        trackpadEngine.stop()
        multitouchMonitor.stopAll()
    }

    // MARK: - Software Updates

    public func checkForUpdates(manual: Bool) {
        switch updateState {
        case .downloading:
            if manual { isUpdateSheetPresented = true }
            return
        case .readyToInstall:
            if manual { isUpdateSheetPresented = true }
            return
        default:
            break
        }

        updateCheckTask?.cancel()
        if manual {
            updateState = .checking
        }

        let current = currentAppVersion
        let checker = updateChecker
        updateCheckTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let outcome = try await checker.check(currentVersion: current)
                guard !Task.isCancelled else { return }
                self.lastUpdateCheckTimestamp = Date().timeIntervalSince1970
                self.savePreferences()

                switch outcome {
                case .updateAvailable(let manifest, let source):
                    if manual, self.skippedUpdateVersion == manifest.version {
                        self.skippedUpdateVersion = nil
                    }
                    self.updateState = .available(manifest: manifest, source: source)
                    if manual {
                        self.isUpdateSheetPresented = true
                    }
                case .upToDate:
                    self.updateState = .upToDate(checkedAt: Date())
                }
            } catch {
                guard !Task.isCancelled else { return }
                if manual {
                    self.updateState = .failed(
                        message: self.localizedUpdateError(error),
                        manifest: nil,
                        source: nil
                    )
                }
            }
        }
    }

    public func downloadAvailableUpdate() {
        guard let manifest = detectedUpdateManifest else { return }
        let source = detectedUpdateSource ?? .githubRaw
        let initialChannel: DownloadChannel = (source == .chinaMirror || source == .jsDelivr) ? .mirror : .github

        updateDownloadTask?.cancel()
        updateState = .downloading(
            manifest: manifest,
            source: source,
            progress: DownloadProgressSnapshot(
                channel: initialChannel,
                fractionCompleted: 0,
                bytesReceived: 0,
                totalBytes: manifest.sizeBytes ?? 0
            )
        )

        let downloader = updateDownloader
        updateDownloadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let dmgURL = try await downloader.downloadVerifiedDMG(
                    for: manifest,
                    winningSource: source,
                    onProgress: { [weak self] snapshot in
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if case .downloading = self.updateState {
                                self.updateState = .downloading(
                                    manifest: manifest,
                                    source: source,
                                    progress: snapshot
                                )
                            }
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                self.updateState = .readyToInstall(manifest: manifest, source: source, dmgURL: dmgURL)
                NSWorkspace.shared.open(dmgURL)
            } catch UpdateEngineError.cancelled {
                self.updateState = .available(manifest: manifest, source: source)
            } catch {
                guard !Task.isCancelled else { return }
                self.updateState = .failed(
                    message: self.localizedUpdateError(error),
                    manifest: manifest,
                    source: source
                )
            }
        }
    }

    public func cancelUpdateDownload() {
        let manifest = detectedUpdateManifest
        let source = detectedUpdateSource ?? .githubRaw
        updateDownloadTask?.cancel()
        updateDownloadTask = nil
        let downloader = updateDownloader
        Task { await downloader.cancel() }
        if let manifest {
            updateState = .available(manifest: manifest, source: source)
        } else {
            updateState = .idle
        }
    }

    public func openDownloadedDMG(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func openReleasePage() {
        let url = detectedUpdateManifest?.releaseUrl
            ?? URL(string: "https://github.com/BobbyCats/SpinMac/releases/latest")!
        NSWorkspace.shared.open(url)
    }

    public func skipAvailableUpdate() {
        if let manifest = detectedUpdateManifest {
            skippedUpdateVersion = manifest.version
        }
        isUpdateSheetPresented = false
    }

    private func scheduleBackgroundUpdateCheckIfNeeded(delaySeconds: Double) {
        guard autoCheckUpdates else { return }
        if detectedUpdateManifest != nil { return }
        let now = Date().timeIntervalSince1970
        if let last = lastUpdateCheckTimestamp, now - last < Self.autoCheckIntervalSeconds {
            return
        }
        updateCheckTask?.cancel()
        updateCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled, let self, self.autoCheckUpdates else { return }
            self.checkForUpdates(manual: false)
        }
    }

    private func localizedUpdateError(_ error: Error) -> String {
        if let engineError = error as? UpdateEngineError {
            switch engineError {
            case .checksumMismatch:
                return l10n.t("update.error.checksum")
            case .allSourcesFailed, .invalidManifest, .untrustedURL, .httpStatus:
                return l10n.t("update.error.allSources")
            case .cancelled:
                return ""
            }
        }
        return l10n.t("update.error.generic", error.localizedDescription)
    }

    // MARK: - Private

    private func configureSystemObservers() {
        displayEngine.startObservingReconfiguration { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshDisplays()
            }
        }

        shortcutObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_shortcutByNameDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshShortcutDisplay()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDisplays()
                self?.refreshTrackpadDevices()
                self?.scheduleBackgroundUpdateCheckIfNeeded(delaySeconds: 8.0)
            }
        }
    }

    private func configureGlobalShortcuts() {
        refreshShortcutDisplay()
        KeyboardShortcuts.onKeyUp(for: .toggleDisplayRotation) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleQuickPortrait()
            }
        }
        KeyboardShortcuts.onKeyUp(for: .cycleTrackpadMode) { [weak self] in
            Task { @MainActor [weak self] in
                self?.cycleTrackpadMode()
            }
        }
    }

    private func syncTrackpadEngine() {
        var effective = trackpadConfig
        effective.enabled = (trackpadMode != .off)
        effective.angle = effectiveTrackpadAngle
        trackpadEngine.updateConfig(effective)
        updatePermissionPollingState()
    }

    private func scheduleDisplayRefresh() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard !Task.isCancelled else { return }
            self?.refreshDisplays()
        }
    }

    private func updatePermissionPollingState() {
        if permissions.allGranted || trackpadMode == .off {
            stopPermissionPolling()
            return
        }
        guard permissionPollTimer == nil else { return }
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermissions()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private func startRevertHUD(previousAngle: SpinAngle, newAngle: SpinAngle, displayID: CGDirectDisplayID) {
        pendingRevertPreviousAngle = previousAngle
        pendingRevertCountdown = 10

        let hud = RevertHUDPanelController(
            newAngle: newAngle,
            displayID: displayID,
            coordinator: self,
            onConfirm: { [weak self] in self?.confirmPendingRotation() },
            onRevert: { [weak self] in self?.revertPendingRotation() }
        )
        revertHUD = hud
        hud.show()

        revertTimer?.invalidate()
        revertTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.pendingRevertCountdown <= 1 {
                    self.revertPendingRotation()
                } else {
                    self.pendingRevertCountdown -= 1
                }
            }
        }
    }

    private func cancelRevertHUD() {
        revertTimer?.invalidate()
        revertTimer = nil
        pendingRevertPreviousAngle = nil
        revertHUD?.close()
        revertHUD = nil
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            if case .launchAtLoginFailed = statusError {
                statusError = nil
            }
        } catch {
            statusError = .launchAtLoginFailed(error.localizedDescription)
        }
    }

    private func savePreferences() {
        var prefs = SpinMacPreferences()
        prefs.preferredVerticalAngle = preferredVerticalAngle
        prefs.trackpadMode = trackpadMode
        prefs.independentTrackpadAngle = independentTrackpadAngle
        prefs.safetyRollbackEnabled = safetyRollbackEnabled
        prefs.language = language
        prefs.trackpadConfig = trackpadConfig
        prefs.autoCheckUpdates = autoCheckUpdates
        prefs.skippedUpdateVersion = skippedUpdateVersion
        prefs.lastUpdateCheckTimestamp = lastUpdateCheckTimestamp
        PreferencesStore.save(prefs)
    }
}
