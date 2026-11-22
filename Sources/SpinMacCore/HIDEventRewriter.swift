import CoreGraphics
import Foundation

/// Dynamically binds SkyLight + IOKit private HID event accessors so scroll,
/// page-swipe, and 3/4-finger Dock swipe (Spaces / Mission Control / App Exposé)
/// gestures rotate cleanly in sync with trackpad orientation.
public final class HIDEventRewriter: @unchecked Sendable {
    public static let shared = HIDEventRewriter()

    /// Private CGEvent constants shared with TrackpadEngine (single source of truth).
    public static let rawGestureEventType = CGEventType(rawValue: 29)!
    public static let cgFieldGestureHIDType = CGEventField(rawValue: 110)!
    public static let gestureSubtypeNavSwipe: Int64 = 29
    public static let gestureSubtypeDockSwipe: Int64 = 30

    private typealias CopyHIDEventFn = @convention(c) (CGEvent) -> UnsafeMutableRawPointer?
    private typealias SetHIDEventFn = @convention(c) (CGEvent, UnsafeMutableRawPointer) -> Void
    private typealias GetTypeFn = @convention(c) (UnsafeMutableRawPointer) -> UInt32
    private typealias GetFloatFn = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Double
    private typealias SetFloatFn = @convention(c) (UnsafeMutableRawPointer, UInt32, Double) -> Void
    private typealias GetIntFn = @convention(c) (UnsafeMutableRawPointer, UInt32) -> Int64
    private typealias SetIntFn = @convention(c) (UnsafeMutableRawPointer, UInt32, Int64) -> Void
    private typealias GetChildrenFn = @convention(c) (UnsafeMutableRawPointer) -> Unmanaged<CFArray>?

    // Standard IOHIDEvent types & field constants
    private static let kIOHIDEventTypeScroll: UInt32 = 6
    private static let kIOHIDEventTypeNavigationSwipe: UInt32 = 16
    private static let kIOHIDEventTypeDockSwipe: UInt32 = 23

    private static let kIOHIDEventFieldScrollX: UInt32 = (6 << 16) | 0
    private static let kIOHIDEventFieldScrollY: UInt32 = (6 << 16) | 1

    private static let kIOHIDEventFieldNavSwipePositionX: UInt32 = (16 << 16) | 0
    private static let kIOHIDEventFieldNavSwipePositionY: UInt32 = (16 << 16) | 1
    private static let kIOHIDEventFieldNavSwipeMotion: UInt32 = (16 << 16) | 4
    private static let kIOHIDEventFieldNavSwipeProgress: UInt32 = (16 << 16) | 5

    private static let kIOHIDEventFieldDockSwipeMotion: UInt32 = (23 << 16) | 0
    private static let kIOHIDEventFieldDockSwipeProgress: UInt32 = (23 << 16) | 1
    private static let kIOHIDEventFieldDockSwipePositionX: UInt32 = (23 << 16) | 2
    private static let kIOHIDEventFieldDockSwipePositionY: UInt32 = (23 << 16) | 3

    // Private CGEvent fields for Gesture events (rawType == 29)
    private static let cgFieldGestureSwipeMotion = CGEventField(rawValue: 123)!
    private static let cgFieldGestureSwipeProgress = CGEventField(rawValue: 124)!
    private static let cgFieldGestureSwipePositionX = CGEventField(rawValue: 125)!
    private static let cgFieldGestureSwipePositionY = CGEventField(rawValue: 126)!

    private let copyHIDEvent: CopyHIDEventFn?
    private let setHIDEvent: SetHIDEventFn?
    private let getType: GetTypeFn?
    private let getFloat: GetFloatFn?
    private let setFloat: SetFloatFn?
    private let getInt: GetIntFn?
    private let setInt: SetIntFn?
    private let getChildren: GetChildrenFn?

    private init() {
        let sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

        copyHIDEvent = sl.flatMap { dlsym($0, "SLEventCopyIOHIDEvent") ?? dlsym($0, "CGEventCopyIOHIDEvent") }
            .map { unsafeBitCast($0, to: CopyHIDEventFn.self) }
        setHIDEvent = sl.flatMap { dlsym($0, "SLEventSetIOHIDEvent") }
            .map { unsafeBitCast($0, to: SetHIDEventFn.self) }
        getType = io.flatMap { dlsym($0, "IOHIDEventGetType") }
            .map { unsafeBitCast($0, to: GetTypeFn.self) }
        getFloat = io.flatMap { dlsym($0, "IOHIDEventGetFloatValue") }
            .map { unsafeBitCast($0, to: GetFloatFn.self) }
        setFloat = io.flatMap { dlsym($0, "IOHIDEventSetFloatValue") }
            .map { unsafeBitCast($0, to: SetFloatFn.self) }
        getInt = io.flatMap { dlsym($0, "IOHIDEventGetIntegerValue") }
            .map { unsafeBitCast($0, to: GetIntFn.self) }
        setInt = io.flatMap { dlsym($0, "IOHIDEventSetIntegerValue") }
            .map { unsafeBitCast($0, to: SetIntFn.self) }
        getChildren = io.flatMap { dlsym($0, "IOHIDEventGetChildren") }
            .map { unsafeBitCast($0, to: GetChildrenFn.self) }
    }

    public var isAvailable: Bool {
        copyHIDEvent != nil && getType != nil && getFloat != nil && setFloat != nil
    }

    /// Rewrites attached IOHIDEvent scroll vector (for page swipes / fluid AppKit scrolling).
    public func rewriteScrollHIDEvent(on event: CGEvent, transform: AxisTransform, speed: Double) {
        guard let copyHIDEvent, let root = copyHIDEvent(event) else { return }
        defer { Unmanaged<AnyObject>.fromOpaque(root).release() }

        var mutated = false
        visitHIDTree(root) { node, type in
            if type == Self.kIOHIDEventTypeScroll,
               let getFloat = self.getFloat, let setFloat = self.setFloat {
                let x = getFloat(node, Self.kIOHIDEventFieldScrollX)
                let y = getFloat(node, Self.kIOHIDEventFieldScrollY)
                let out = transform.transformScreenDelta(dx: x, dy: y)
                setFloat(node, Self.kIOHIDEventFieldScrollX, out.dx * speed)
                setFloat(node, Self.kIOHIDEventFieldScrollY, out.dy * speed)
                mutated = true
            }
        }
        if mutated, let setHIDEvent {
            setHIDEvent(event, root)
        }
    }

    /// Rewrites 3/4-finger Dock swipe & navigation swipe CGEvent + attached IOHIDEvent.
    public func rewriteGestureEvent(
        _ event: CGEvent,
        transform: AxisTransform,
        remapDockSwipes: Bool,
        remapPageSwipes: Bool
    ) {
        let hidSubtype = event.getIntegerValueField(Self.cgFieldGestureHIDType)

        // Rewrite CGEvent-level gesture fields for Dock swipe (30) and Nav swipe (29)
        if (hidSubtype == Self.gestureSubtypeDockSwipe && remapDockSwipes)
            || (hidSubtype == Self.gestureSubtypeNavSwipe && remapPageSwipes) {
            let motion = event.getIntegerValueField(Self.cgFieldGestureSwipeMotion)
            let progress = event.getDoubleValueField(Self.cgFieldGestureSwipeProgress)
            if motion == 1 || motion == 2 {
                let mapped = transform.transformDockSwipe(motion: motion, progress: progress)
                event.setIntegerValueField(Self.cgFieldGestureSwipeMotion, value: mapped.motion)
                event.setDoubleValueField(Self.cgFieldGestureSwipeProgress, value: mapped.progress)
            }
            let px = event.getDoubleValueField(Self.cgFieldGestureSwipePositionX)
            let py = event.getDoubleValueField(Self.cgFieldGestureSwipePositionY)
            if px != 0 || py != 0 {
                let out = transform.transformYUpVector(vx: px, vy: py)
                event.setDoubleValueField(Self.cgFieldGestureSwipePositionX, value: out.vx)
                event.setDoubleValueField(Self.cgFieldGestureSwipePositionY, value: out.vy)
            }
        }

        // Also rewrite the attached IOHIDEvent (which Dock and AppKit actually consume)
        guard let copyHIDEvent, let root = copyHIDEvent(event) else { return }
        defer { Unmanaged<AnyObject>.fromOpaque(root).release() }

        var mutated = false
        visitHIDTree(root) { node, type in
            if type == Self.kIOHIDEventTypeDockSwipe && remapDockSwipes,
               let getInt = self.getInt, let setInt = self.setInt,
               let getFloat = self.getFloat, let setFloat = self.setFloat {
                let motion = getInt(node, Self.kIOHIDEventFieldDockSwipeMotion)
                let progress = getFloat(node, Self.kIOHIDEventFieldDockSwipeProgress)
                if motion == 1 || motion == 2 {
                    let mapped = transform.transformDockSwipe(motion: motion, progress: progress)
                    setInt(node, Self.kIOHIDEventFieldDockSwipeMotion, mapped.motion)
                    setFloat(node, Self.kIOHIDEventFieldDockSwipeProgress, mapped.progress)
                    mutated = true
                }
                let px = getFloat(node, Self.kIOHIDEventFieldDockSwipePositionX)
                let py = getFloat(node, Self.kIOHIDEventFieldDockSwipePositionY)
                if px != 0 || py != 0 {
                    let out = transform.transformYUpVector(vx: px, vy: py)
                    setFloat(node, Self.kIOHIDEventFieldDockSwipePositionX, out.vx)
                    setFloat(node, Self.kIOHIDEventFieldDockSwipePositionY, out.vy)
                    mutated = true
                }
            } else if type == Self.kIOHIDEventTypeNavigationSwipe && remapPageSwipes,
                      let getInt = self.getInt, let setInt = self.setInt,
                      let getFloat = self.getFloat, let setFloat = self.setFloat {
                let motion = getInt(node, Self.kIOHIDEventFieldNavSwipeMotion)
                let progress = getFloat(node, Self.kIOHIDEventFieldNavSwipeProgress)
                if motion == 1 || motion == 2 {
                    let mapped = transform.transformDockSwipe(motion: motion, progress: progress)
                    setInt(node, Self.kIOHIDEventFieldNavSwipeMotion, mapped.motion)
                    setFloat(node, Self.kIOHIDEventFieldNavSwipeProgress, mapped.progress)
                    mutated = true
                }
                let px = getFloat(node, Self.kIOHIDEventFieldNavSwipePositionX)
                let py = getFloat(node, Self.kIOHIDEventFieldNavSwipePositionY)
                if px != 0 || py != 0 {
                    let out = transform.transformYUpVector(vx: px, vy: py)
                    setFloat(node, Self.kIOHIDEventFieldNavSwipePositionX, out.vx)
                    setFloat(node, Self.kIOHIDEventFieldNavSwipePositionY, out.vy)
                    mutated = true
                }
            } else if type == Self.kIOHIDEventTypeScroll && remapPageSwipes,
                      let getFloat = self.getFloat, let setFloat = self.setFloat {
                let x = getFloat(node, Self.kIOHIDEventFieldScrollX)
                let y = getFloat(node, Self.kIOHIDEventFieldScrollY)
                if x != 0 || y != 0 {
                    let out = transform.transformScreenDelta(dx: x, dy: y)
                    setFloat(node, Self.kIOHIDEventFieldScrollX, out.dx)
                    setFloat(node, Self.kIOHIDEventFieldScrollY, out.dy)
                    mutated = true
                }
            }
        }

        if mutated, let setHIDEvent {
            setHIDEvent(event, root)
        }
    }

    private func visitHIDTree(_ node: UnsafeMutableRawPointer, visitor: (UnsafeMutableRawPointer, UInt32) -> Void) {
        guard let getType else { return }
        visitor(node, getType(node))
        guard let getChildren, let children = getChildren(node)?.takeUnretainedValue() else { return }
        let count = CFArrayGetCount(children)
        for i in 0..<count {
            if let child = CFArrayGetValueAtIndex(children, i) {
                visitHIDTree(UnsafeMutableRawPointer(mutating: child), visitor: visitor)
            }
        }
    }
}
