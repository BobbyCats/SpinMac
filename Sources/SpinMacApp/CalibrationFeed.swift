import CoreGraphics
import Foundation
import Observation
import SpinMacCore

/// Isolated high-frequency observable state for the Calibration canvas ONLY.
/// Kept completely separate from SpinCoordinator so 120Hz touch streams never
/// invalidate the menu bar popover or other Settings tabs.
@MainActor
@Observable
public final class CalibrationFeed {
    public struct TrailSample: Sendable {
        public let raw: CGPoint
        public let mapped: CGPoint
        public let timestamp: CFTimeInterval
    }

    public private(set) var activePoints: [TouchPointSnapshot] = []
    public private(set) var trails: [Int32: [TrailSample]] = [:]
    public private(set) var isMonitoringActive = false
    public private(set) var isAutoCalibrating = false
    public private(set) var lastAutoCalibratedAngle: SpinAngle?

    private var monitorToken: UUID?
    private var swipeStartPoint: CGPoint?
    private var swipeLatestPoint: CGPoint?
    private var swipeFingerID: Int32?

    private weak var coordinator: SpinCoordinator?

    public init() {}

    public func attach(to coordinator: SpinCoordinator) {
        self.coordinator = coordinator
        let monitor = coordinator.multitouchMonitor

        monitor.onLiveFrame = { [weak self] isBuiltIn, points in
            Task { @MainActor [weak self] in
                self?.ingestFrame(isBuiltIn: isBuiltIn, rawPoints: points)
            }
        }
    }

    public func beginPreview() {
        guard let coordinator else { return }
        let monitor = coordinator.multitouchMonitor
        monitor.setLivePreviewEnabled(true)
        if monitorToken == nil {
            monitorToken = monitor.acquireMonitoring()
        }
        isMonitoringActive = monitor.isMonitoringActive
    }

    public func endPreview() {
        isAutoCalibrating = false
        swipeStartPoint = nil
        swipeLatestPoint = nil
        swipeFingerID = nil
        activePoints = []
        trails.removeAll()

        guard let coordinator else { return }
        let monitor = coordinator.multitouchMonitor
        monitor.setLivePreviewEnabled(false)
        if let token = monitorToken {
            monitorToken = nil
            monitor.releaseMonitoring(token)
        }
        isMonitoringActive = false
    }

    public func startAutoCalibration() {
        lastAutoCalibratedAngle = nil
        swipeStartPoint = nil
        swipeLatestPoint = nil
        swipeFingerID = nil
        isAutoCalibrating = true
    }

    public func cancelAutoCalibration() {
        isAutoCalibrating = false
        swipeStartPoint = nil
        swipeLatestPoint = nil
        swipeFingerID = nil
    }

    private func ingestFrame(isBuiltIn: Bool, rawPoints: [(id: Int32, rawYDown: CGPoint)]) {
        guard let coordinator else { return }
        guard coordinator.trackpadConfig.scope.matches(isBuiltIn: isBuiltIn) else { return }

        let now = CFAbsoluteTimeGetCurrent()
        var cfg = coordinator.trackpadConfig
        cfg.angle = coordinator.effectiveTrackpadAngle
        let transform = AxisTransform(config: cfg)

        let snapshots = rawPoints.map { pt in
            TouchPointSnapshot(
                id: pt.id,
                rawPoint: pt.rawYDown,
                mappedPoint: transform.transformNormalizedYDownPoint(pt.rawYDown)
            )
        }

        // Avoid redundant @Observable invalidations when idle (empty -> empty)
        if snapshots.isEmpty && activePoints.isEmpty && trails.isEmpty {
            return
        }

        activePoints = snapshots
        isMonitoringActive = true

        // Update fading trails (keep last 0.45s and max 28 points per finger)
        for snap in snapshots {
            var list = trails[snap.id] ?? []
            list.append(TrailSample(raw: snap.rawPoint, mapped: snap.mappedPoint, timestamp: now))
            if list.count > 28 {
                list.removeFirst(list.count - 28)
            }
            trails[snap.id] = list
        }
        let cutoff = now - 0.45
        for key in Array(trails.keys) {
            let filtered = trails[key]?.filter { $0.timestamp >= cutoff } ?? []
            if filtered.isEmpty {
                trails.removeValue(forKey: key)
            } else {
                trails[key] = filtered
            }
        }

        if isAutoCalibrating {
            handleAutoCalibrationSample(rawPoints: rawPoints, coordinator: coordinator)
        }
    }

    private func handleAutoCalibrationSample(
        rawPoints: [(id: Int32, rawYDown: CGPoint)],
        coordinator: SpinCoordinator
    ) {
        if let first = rawPoints.first {
            if swipeFingerID == nil {
                swipeFingerID = first.id
                swipeStartPoint = first.rawYDown
                swipeLatestPoint = first.rawYDown
            } else if let tracked = rawPoints.first(where: { $0.id == swipeFingerID }) {
                swipeLatestPoint = tracked.rawYDown
                if let start = swipeStartPoint {
                    let dx = tracked.rawYDown.x - start.x
                    let dy = tracked.rawYDown.y - start.y
                    if hypot(dx, dy) >= 0.24,
                       let detected = AxisTransform.inferAngleForUpwardSwipe(rawYDownDeltaX: dx, rawYDownDeltaY: dy) {
                        applyDetectedCalibration(detected, coordinator: coordinator)
                    }
                }
            }
        } else if let start = swipeStartPoint, let end = swipeLatestPoint {
            let dx = end.x - start.x
            let dy = end.y - start.y
            if let detected = AxisTransform.inferAngleForUpwardSwipe(rawYDownDeltaX: dx, rawYDownDeltaY: dy) {
                applyDetectedCalibration(detected, coordinator: coordinator)
            } else {
                swipeFingerID = nil
                swipeStartPoint = nil
                swipeLatestPoint = nil
            }
        }
    }

    private func applyDetectedCalibration(_ angle: SpinAngle, coordinator: SpinCoordinator) {
        isAutoCalibrating = false
        swipeFingerID = nil
        swipeStartPoint = nil
        swipeLatestPoint = nil
        lastAutoCalibratedAngle = angle

        coordinator.trackpadConfig.swapXYOverride = false
        coordinator.trackpadConfig.invertXOverride = false
        coordinator.trackpadConfig.invertYOverride = false

        if angle == coordinator.currentAngle && coordinator.isSelectedDisplayBuiltIn {
            coordinator.trackpadMode = .linked
        } else {
            coordinator.trackpadMode = .independent
            coordinator.independentTrackpadAngle = angle
        }
    }
}
