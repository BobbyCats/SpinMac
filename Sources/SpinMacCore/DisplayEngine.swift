import AppKit
import CoreGraphics
import Foundation
import ObjectiveC

/// Native macOS display orientation controller backed by MonitorPanel.framework + CoreGraphics.
public final class DisplayEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var monitorPanelLoaded = false
    private var onReconfiguration: (@Sendable () -> Void)?

    public init() {
        loadMonitorPanel()
    }

    private func loadMonitorPanel() {
        lock.lock()
        defer { lock.unlock() }
        if !monitorPanelLoaded {
            monitorPanelLoaded = dlopen("/System/Library/PrivateFrameworks/MonitorPanel.framework/MonitorPanel", RTLD_NOW) != nil
        }
    }

    public func startObservingReconfiguration(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        self.onReconfiguration = handler
        lock.unlock()

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(Self.reconfigCallback, ctx)
    }

    public func stopObservingReconfiguration() {
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(Self.reconfigCallback, ctx)
        lock.lock()
        self.onReconfiguration = nil
        lock.unlock()
    }

    private static let reconfigCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
        let engine = Unmanaged<DisplayEngine>.fromOpaque(userInfo).takeUnretainedValue()
        engine.lock.lock()
        let cb = engine.onReconfiguration
        engine.lock.unlock()
        cb?()
    }

    private func fetchMPDisplays() -> [NSObject] {
        loadMonitorPanel()
        guard let mgrCls = NSClassFromString("MPDisplayMgr") as? NSObject.Type else {
            return []
        }
        let mgr = mgrCls.init()
        return (mgr.value(forKey: "displays") as? [NSObject]) ?? []
    }

    public func listDisplays() -> [DisplayDescriptor] {
        let mpDisplays = fetchMPDisplays()
        if !mpDisplays.isEmpty {
            return mpDisplays.compactMap { mp -> DisplayDescriptor? in
                guard let rawID = mp.value(forKey: "displayID") as? Int32 else { return nil }
                let id = CGDirectDisplayID(bitPattern: rawID)
                let isBuiltIn = (mp.value(forKey: "isBuiltIn") as? Bool) ?? (CGDisplayIsBuiltin(id) != 0)
                let canRotate = (mp.value(forKey: "canChangeOrientation") as? Bool) ?? false
                let rawName = (mp.value(forKey: "displayName") as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let deg = CGDisplayRotation(id)
                let bounds = CGDisplayBounds(id)
                return DisplayDescriptor(
                    id: id,
                    rawName: (rawName?.isEmpty == false) ? rawName : nil,
                    isBuiltIn: isBuiltIn,
                    canChangeOrientation: canRotate,
                    currentAngle: SpinAngle.from(degrees: deg),
                    bounds: bounds
                )
            }
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
                return lhs.id < rhs.id
            }
        }

        // Fallback if MonitorPanel is unavailable
        let mainID = CGMainDisplayID()
        let isBuiltIn = CGDisplayIsBuiltin(mainID) != 0
        return [
            DisplayDescriptor(
                id: mainID,
                rawName: nil,
                isBuiltIn: isBuiltIn,
                canChangeOrientation: false,
                currentAngle: SpinAngle.from(degrees: CGDisplayRotation(mainID)),
                bounds: CGDisplayBounds(mainID)
            )
        ]
    }

    public func currentOrientation(displayID: CGDirectDisplayID) -> SpinAngle {
        SpinAngle.from(degrees: CGDisplayRotation(displayID))
    }

    /// Rotates the given display using MonitorPanel's MPDisplay.setOrientation:(int32_t) ABI.
    @discardableResult
    public func setOrientation(_ angle: SpinAngle, for displayID: CGDirectDisplayID) -> Bool {
        let mpDisplays = fetchMPDisplays()
        guard let target = mpDisplays.first(where: { mp in
            guard let rawID = mp.value(forKey: "displayID") as? Int32 else { return false }
            return CGDirectDisplayID(bitPattern: rawID) == displayID
        }) else {
            return false
        }

        if let canRotate = target.value(forKey: "canChangeOrientation") as? Bool, !canRotate {
            return false
        }

        let sel = NSSelectorFromString("setOrientation:")
        guard target.responds(to: sel),
              let cls = object_getClass(target),
              let method = class_getInstanceMethod(cls, sel) else {
            return false
        }

        typealias SetOrientationIMP = @convention(c) (AnyObject, Selector, Int32) -> Void
        let imp = unsafeBitCast(method_getImplementation(method), to: SetOrientationIMP.self)
        imp(target, sel, angle.rawValue)
        return true
    }

    /// Computes active display bounds list for multi-display cursor clamping.
    public static func activeDisplayBoundsList() -> [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [CGDisplayBounds(CGMainDisplayID())] }
        var ids = Array<CGDirectDisplayID>(repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
}
