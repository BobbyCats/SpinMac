import AppKit
import CoreGraphics
import Foundation

/// Clean-room dual-tap macOS trackpad rotation engine running on a dedicated
/// high-priority CFRunLoop thread (completely isolated from SwiftUI UI pauses).
///
/// Invariants:
/// 1. Zero idle overhead: when `config.isActive == false`, both CGEventTaps are disabled
///    and the MultitouchMonitor lease is released (0% idle CPU).
/// 2. Unconditional cursor safety: `CGAssociateMouseAndMouseCursorPosition(1)` is always
///    restored on finger-up, tap timeout, deactivation, or process exit.
/// 3. External mice always pass through untouched.
public final class TrackpadEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var config = TrackpadConfig()

    private var workerThread: Thread?
    private var workerRunLoop: CFRunLoop?
    private var hidTap: CFMachPort?
    private var hidRunLoopSource: CFRunLoopSource?
    private var sessionTap: CFMachPort?
    private var sessionRunLoopSource: CFRunLoopSource?
    private var monitorToken: UUID?

    private var cursorDetached = false
    private var virtualCursor: CGPoint = .zero
    private var displayBoundsCache: [CGRect] = []
    private var lastBoundsRefresh: CFTimeInterval = 0
    private var lastScrollEventWasTrackpad = false

    public let multitouchMonitor: MultitouchMonitor

    public private(set) var isTapInstalled = false

    public init(multitouchMonitor: MultitouchMonitor = MultitouchMonitor()) {
        self.multitouchMonitor = multitouchMonitor
        atexit {
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    deinit {
        stop()
    }

    public func updateConfig(_ newConfig: TrackpadConfig) {
        lock.lock()
        let wasActive = config.isActive
        config = newConfig
        let shouldBeActive = newConfig.isActive
        let existingToken = monitorToken
        let installed = isTapInstalled
        let hTap = hidTap
        let sTap = sessionTap
        lock.unlock()

        if shouldBeActive {
            refreshDisplayBounds()
            if existingToken == nil {
                let token = multitouchMonitor.acquireMonitoring()
                lock.lock()
                monitorToken = token
                lock.unlock()
            }
            if !installed {
                _ = startEventTapThread()
            } else {
                if let hTap { CGEvent.tapEnable(tap: hTap, enable: true) }
                if let sTap { CGEvent.tapEnable(tap: sTap, enable: true) }
            }
        } else {
            // Invariant #1: suspend taps, release touch lease, and re-associate cursor immediately
            if let hTap { CGEvent.tapEnable(tap: hTap, enable: false) }
            if let sTap { CGEvent.tapEnable(tap: sTap, enable: false) }
            if let existingToken {
                lock.lock()
                monitorToken = nil
                lock.unlock()
                multitouchMonitor.releaseMonitoring(existingToken)
            }
            if wasActive || cursorDetached {
                reassociateCursorLocked()
            }
        }
    }

    public func refreshDisplayBounds() {
        let bounds = DisplayEngine.activeDisplayBoundsList()
        lock.lock()
        displayBoundsCache = bounds
        lastBoundsRefresh = CFAbsoluteTimeGetCurrent()
        lock.unlock()
    }

    public func stop() {
        reassociateCursorLocked()

        lock.lock()
        let token = monitorToken
        monitorToken = nil
        let hTap = hidTap
        let hSrc = hidRunLoopSource
        let sTap = sessionTap
        let sSrc = sessionRunLoopSource
        let rl = workerRunLoop
        hidTap = nil
        hidRunLoopSource = nil
        sessionTap = nil
        sessionRunLoopSource = nil
        workerRunLoop = nil
        workerThread = nil
        isTapInstalled = false
        lock.unlock()

        if let hTap { CGEvent.tapEnable(tap: hTap, enable: false) }
        if let sTap { CGEvent.tapEnable(tap: sTap, enable: false) }
        if let rl {
            CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue) {
                if let hSrc { CFRunLoopRemoveSource(rl, hSrc, .commonModes) }
                if let sSrc { CFRunLoopRemoveSource(rl, sSrc, .commonModes) }
                CFRunLoopStop(rl)
            }
            CFRunLoopWakeUp(rl)
        }
        if let token {
            multitouchMonitor.releaseMonitoring(token)
        }
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    // MARK: - Dedicated Event Tap Thread

    @discardableResult
    private func startEventTapThread() -> Bool {
        lock.lock()
        if isTapInstalled {
            lock.unlock()
            return true
        }
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        final class StartResult: @unchecked Sendable { var succeeded = false }
        let result = StartResult()

        let thread = Thread { [weak self] in
            guard let self else {
                ready.signal()
                return
            }
            let currentRL = CFRunLoopGetCurrent()!
            let ok = self.installTaps(on: currentRL)
            result.succeeded = ok
            ready.signal()
            if ok {
                CFRunLoopRun()
            }
        }
        thread.name = "SpinMac.EventTapThread"
        thread.qualityOfService = .userInteractive

        lock.lock()
        workerThread = thread
        lock.unlock()

        thread.start()
        _ = ready.wait(timeout: .now() + .seconds(2))
        return result.succeeded
    }

    private func installTaps(on runLoop: CFRunLoop) -> Bool {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        // 1. HID-level tap: pointer moves, drags (incl. 3-finger drag), all clicks, and 3/4-finger Dock swipes
        let hidTypes: [CGEventType] = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .leftMouseUp,
            .rightMouseDown,
            .rightMouseUp,
            .otherMouseDown,
            .otherMouseUp,
            HIDEventRewriter.rawGestureEventType,
        ]
        let hidMask = hidTypes.reduce(CGEventMask(0)) { mask, eventType in
            mask | (CGEventMask(1) << eventType.rawValue)
        }

        guard let createdHIDTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: hidMask,
            callback: Self.hidCallback,
            userInfo: selfPtr
        ) else {
            return false
        }

        // 2. Session-level tap: continuous trackpad scroll + momentum + fluid page swipes
        let sessionMask: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue)
            | (1 << HIDEventRewriter.rawGestureEventType.rawValue)

        let createdSessionTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: sessionMask,
            callback: Self.sessionCallback,
            userInfo: selfPtr
        )

        let hidSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdHIDTap, 0)
        CFRunLoopAddSource(runLoop, hidSource, .commonModes)

        var sessionSource: CFRunLoopSource?
        if let createdSessionTap {
            sessionSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdSessionTap, 0)
            CFRunLoopAddSource(runLoop, sessionSource, .commonModes)
        }

        lock.lock()
        let activeNow = config.isActive
        workerRunLoop = runLoop
        hidTap = createdHIDTap
        hidRunLoopSource = hidSource
        sessionTap = createdSessionTap
        sessionRunLoopSource = sessionSource
        isTapInstalled = true
        lock.unlock()

        CGEvent.tapEnable(tap: createdHIDTap, enable: activeNow)
        if let createdSessionTap {
            CGEvent.tapEnable(tap: createdSessionTap, enable: activeNow)
        }
        return true
    }

    private func reassociateCursorLocked() {
        lock.lock()
        let wasDetached = cursorDetached
        cursorDetached = false
        lock.unlock()
        if wasDetached {
            CGAssociateMouseAndMouseCursorPosition(1)
        }
    }

    // MARK: - Event Tap Callbacks

    private static let hidCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let engine = Unmanaged<TrackpadEngine>.fromOpaque(userInfo).takeUnretainedValue()
        return engine.handleHIDEvent(type: type, event: event)
    }

    private static let sessionCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let engine = Unmanaged<TrackpadEngine>.fromOpaque(userInfo).takeUnretainedValue()
        return engine.handleSessionEvent(type: type, event: event)
    }

    private func handleHIDEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = hidTap
            let active = config.isActive
            lock.unlock()
            if active, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            reassociateCursorLocked()
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let cfg = config
        lock.unlock()

        guard cfg.isActive else {
            reassociateCursorLocked()
            return Unmanaged.passUnretained(event)
        }

        guard multitouchMonitor.isTargetTrackpadActive(scope: cfg.scope) else {
            reassociateCursorLocked()
            return Unmanaged.passUnretained(event)
        }

        let transform = AxisTransform(config: cfg)

        // Dock swipes (3/4-finger Spaces, Mission Control, App Exposé)
        if type == HIDEventRewriter.rawGestureEventType {
            if cfg.remapDockSwipes {
                let hidType = event.getIntegerValueField(HIDEventRewriter.cgFieldGestureHIDType)
                if hidType == HIDEventRewriter.gestureSubtypeDockSwipe {
                    HIDEventRewriter.shared.rewriteGestureEvent(
                        event,
                        transform: transform,
                        remapDockSwipes: true,
                        remapPageSwipes: false
                    )
                }
            }
            return Unmanaged.passUnretained(event)
        }

        // All mouse clicks (left / right / other) stay pinned to the virtual cursor
        switch type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            lock.lock()
            if cursorDetached {
                event.location = virtualCursor
            } else {
                virtualCursor = event.location
            }
            lock.unlock()
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        // Pointer movement & dragging (including 3-finger drag)
        guard cfg.remapPointer else {
            reassociateCursorLocked()
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let rawDX = event.getDoubleValueField(.mouseEventDeltaX)
            let rawDY = event.getDoubleValueField(.mouseEventDeltaY)
            if rawDX == 0 && rawDY == 0 {
                return Unmanaged.passUnretained(event)
            }

            let rotated = transform.transformScreenDelta(dx: rawDX, dy: rawDY)
            let dx = rotated.dx * cfg.pointerSpeed
            let dy = rotated.dy * cfg.pointerSpeed

            let now = CFAbsoluteTimeGetCurrent()
            lock.lock()
            if !cursorDetached {
                virtualCursor = event.location
                cursorDetached = true
                CGAssociateMouseAndMouseCursorPosition(0)
            }
            if now - lastBoundsRefresh > 1.5 || displayBoundsCache.isEmpty {
                displayBoundsCache = DisplayEngine.activeDisplayBoundsList()
                lastBoundsRefresh = now
            }
            let proposed = CGPoint(x: virtualCursor.x + dx, y: virtualCursor.y + dy)
            let clamped = CursorClamper.clamp(proposed, to: displayBoundsCache)
            virtualCursor = clamped
            lock.unlock()

            CGWarpMouseCursorPosition(clamped)
            event.location = clamped
            event.setDoubleValueField(.mouseEventDeltaX, value: dx)
            event.setDoubleValueField(.mouseEventDeltaY, value: dy)
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleSessionEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = sessionTap
            let active = config.isActive
            lock.unlock()
            if active, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let cfg = config
        lock.unlock()

        guard cfg.isActive else {
            return Unmanaged.passUnretained(event)
        }

        let transform = AxisTransform(config: cfg)

        if type == .scrollWheel {
            // Only continuous trackpad scrolls (never discrete mouse wheel ticks)
            let isContinuous = event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0
            guard isContinuous else { return Unmanaged.passUnretained(event) }

            let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)
            let isTrackpadNow = multitouchMonitor.isTargetTrackpadActive(scope: cfg.scope, graceWindowSeconds: 0.25)

            lock.lock()
            if momentumPhase == 0 {
                lastScrollEventWasTrackpad = isTrackpadNow
            }
            let shouldRemap = isTrackpadNow || (momentumPhase != 0 && lastScrollEventWasTrackpad)
            lock.unlock()

            guard shouldRemap && cfg.remapScroll else {
                return Unmanaged.passUnretained(event)
            }

            let speed = cfg.scrollSpeed

            let dX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
            let dY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)
            let rD = transform.transformScreenDelta(dx: dX, dy: dY)

            let ptX = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis2)
            let ptY = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
            let rPt = transform.transformScreenDelta(dx: ptX, dy: ptY)

            let fpX = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
            let fpY = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
            let rFp = transform.transformScreenDelta(dx: fpX, dy: fpY)

            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64((rD.dx * speed).rounded()))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64((rD.dy * speed).rounded()))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64((rPt.dx * speed).rounded()))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64((rPt.dy * speed).rounded()))
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: rFp.dx * speed)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: rFp.dy * speed)

            if cfg.remapPageSwipes {
                HIDEventRewriter.shared.rewriteScrollHIDEvent(on: event, transform: transform, speed: speed)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == HIDEventRewriter.rawGestureEventType {
            let isTrackpad = multitouchMonitor.isTargetTrackpadActive(scope: cfg.scope, graceWindowSeconds: 0.25)
            guard isTrackpad else { return Unmanaged.passUnretained(event) }

            let hidType = event.getIntegerValueField(HIDEventRewriter.cgFieldGestureHIDType)
            if hidType != HIDEventRewriter.gestureSubtypeDockSwipe && cfg.remapPageSwipes {
                HIDEventRewriter.shared.rewriteGestureEvent(
                    event,
                    transform: transform,
                    remapDockSwipes: false,
                    remapPageSwipes: true
                )
            }
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }
}
