import CMultitouch
import CoreGraphics
import Foundation

/// Reference-counted MultitouchSupport monitor.
/// - Starts hardware touch callbacks ONLY while at least one consumer holds a token
///   (e.g. active TrackpadEngine rotation or visible Calibration UI), guaranteeing 0% idle CPU.
/// - Tracks built-in vs external touch grace timestamps separately so external trackpads
///   never leak into `.builtInOnly` scope (and vice versa).
/// - Gates live preview callbacks behind `livePreviewEnabled` so normal background use
///   allocates zero UI updates.
public final class MultitouchMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var activeFingersByDevice: [UInt64: (isBuiltIn: Bool, fingers: [SMMultitouchFinger], lastTime: CFTimeInterval)] = [:]
    private var lastBuiltInTouchTime: CFTimeInterval = 0
    private var lastExternalTouchTime: CFTimeInterval = 0
    private var activeTokens: Set<UUID> = []
    private var isRunning = false
    private var livePreviewEnabled = false

    public var onLiveFrame: (@Sendable (_ isBuiltIn: Bool, _ fingers: [(id: Int32, rawYDown: CGPoint)]) -> Void)?

    public init() {}

    /// Acquires a monitoring lease. Hardware callbacks start when the first lease is acquired.
    @discardableResult
    public func acquireMonitoring() -> UUID {
        let token = UUID()
        lock.lock()
        activeTokens.insert(token)
        let shouldStart = !isRunning
        if shouldStart {
            isRunning = true
        }
        lock.unlock()

        if shouldStart {
            let ctx = Unmanaged.passUnretained(self).toOpaque()
            let ok = sm_mt_start(Self.cCallback, ctx)
            if !ok {
                lock.lock()
                isRunning = false
                lock.unlock()
            }
        }
        return token
    }

    /// Releases a previously acquired lease. Hardware callbacks stop when the last lease is released.
    public func releaseMonitoring(_ token: UUID) {
        lock.lock()
        activeTokens.remove(token)
        let shouldStop = activeTokens.isEmpty && isRunning
        if shouldStop {
            isRunning = false
            activeFingersByDevice.removeAll()
        }
        lock.unlock()

        if shouldStop {
            sm_mt_stop()
        }
    }

    /// Re-enumerates trackpad devices (e.g. after connecting a Bluetooth Magic Trackpad).
    public func refreshDevicesIfRunning() {
        lock.lock()
        let running = isRunning
        lock.unlock()
        guard running else { return }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        _ = sm_mt_start(Self.cCallback, ctx)
    }

    /// Enables or disables live touch streaming for the calibration canvas.
    public func setLivePreviewEnabled(_ enabled: Bool) {
        lock.lock()
        livePreviewEnabled = enabled
        lock.unlock()
    }

    /// Force-stops monitoring and clears all leases (used during clean app shutdown).
    public func stopAll() {
        lock.lock()
        activeTokens.removeAll()
        isRunning = false
        livePreviewEnabled = false
        activeFingersByDevice.removeAll()
        lock.unlock()
        sm_mt_stop()
    }

    public var isMonitoringActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning
    }

    public func listDevices() -> [(deviceID: UInt64, isBuiltIn: Bool)] {
        var buffer = Array(repeating: SMMultitouchDeviceInfo(deviceID: 0, isBuiltIn: false), count: 8)
        let count = sm_mt_list_devices(&buffer, 8)
        return buffer.prefix(Int(count)).map { ($0.deviceID, $0.isBuiltIn) }
    }

    /// Returns true if a trackpad matching `scope` currently has fingers on it (or had within grace window).
    public func isTargetTrackpadActive(scope: TrackpadScope, graceWindowSeconds: CFTimeInterval = 0.12) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        defer { lock.unlock() }

        for entry in activeFingersByDevice.values {
            if scope.matches(isBuiltIn: entry.isBuiltIn) && !entry.fingers.isEmpty {
                return true
            }
        }

        switch scope {
        case .builtInOnly:
            return (now - lastBuiltInTouchTime) <= graceWindowSeconds
        case .externalOnly:
            return (now - lastExternalTouchTime) <= graceWindowSeconds
        case .allTrackpads:
            return (now - max(lastBuiltInTouchTime, lastExternalTouchTime)) <= graceWindowSeconds
        }
    }

    private func handleFrame(_ frame: SMMultitouchFrame) {
        let now = CFAbsoluteTimeGetCurrent()
        var fingers: [SMMultitouchFinger] = []
        fingers.reserveCapacity(Int(frame.fingerCount))

        withUnsafeBytes(of: frame.fingers) { raw in
            let typed = raw.bindMemory(to: SMMultitouchFinger.self)
            for i in 0..<Int(frame.fingerCount) {
                fingers.append(typed[i])
            }
        }

        let liveCallback: (@Sendable (_ isBuiltIn: Bool, _ fingers: [(id: Int32, rawYDown: CGPoint)]) -> Void)?
        lock.lock()
        activeFingersByDevice[frame.deviceID] = (frame.isBuiltIn, fingers, now)
        if !fingers.isEmpty {
            if frame.isBuiltIn {
                lastBuiltInTouchTime = now
            } else {
                lastExternalTouchTime = now
            }
        }
        liveCallback = livePreviewEnabled ? onLiveFrame : nil
        lock.unlock()

        if let liveCallback {
            let pts = fingers.map { f in
                // MultitouchSupport normY is bottom-to-top; convert to Y-down for SwiftUI Canvas
                (id: f.identifier, rawYDown: CGPoint(x: Double(f.normX), y: 1.0 - Double(f.normY)))
            }
            liveCallback(frame.isBuiltIn, pts)
        }
    }

    private static let cCallback: SMMultitouchFrameCallback = { framePtr, context in
        guard let framePtr, let context else { return }
        let monitor = Unmanaged<MultitouchMonitor>.fromOpaque(context).takeUnretainedValue()
        monitor.handleFrame(framePtr.pointee)
    }
}
