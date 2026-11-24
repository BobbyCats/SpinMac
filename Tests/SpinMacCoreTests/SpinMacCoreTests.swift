import CoreGraphics
import Testing
@testable import SpinMacCore

@Suite("SpinMac Core Orientation & Decoupling Invariants")
struct SpinMacCoreTests {
    @Test("0° is strict identity")
    func zeroDegreeIdentity() {
        let t = AxisTransform(angle: .deg0)
        let out = t.transformScreenDelta(dx: 12, dy: -7)
        #expect(out.dx == 12)
        #expect(out.dy == -7)
    }

    @Test("90° (CGDisplayRotation 90° CW: physical left edge is visual top) maps deltas cleanly")
    func deg90ScreenDelta() {
        let t = AxisTransform(angle: .deg90)
        // Physical left (-x) -> visual up (-y)
        let up = t.transformScreenDelta(dx: -10, dy: 0)
        #expect(up.dx == 0)
        #expect(up.dy == -10)

        // Physical up (-y, toward hinge) -> visual right (+x)
        let right = t.transformScreenDelta(dx: 0, dy: -10)
        #expect(right.dx == 10)
        #expect(right.dy == 0)
    }

    @Test("270° (CGDisplayRotation 270° CW: physical right edge is visual top) is exact opposite of 90°")
    func deg270ScreenDelta() {
        let t = AxisTransform(angle: .deg270)
        // Physical right (+x) -> visual up (-y)
        let up = t.transformScreenDelta(dx: 10, dy: 0)
        #expect(up.dx == 0)
        #expect(up.dy == -10)

        // Physical down (+y, toward user) -> visual right (+x)
        let right = t.transformScreenDelta(dx: 0, dy: 10)
        #expect(right.dx == 10)
        #expect(right.dy == 0)
    }

    @Test("180° inverts both axes")
    func deg180ScreenDelta() {
        let t = AxisTransform(angle: .deg180)
        let out = t.transformScreenDelta(dx: 8, dy: -5)
        #expect(out.dx == -8)
        #expect(out.dy == 5)
    }

    @Test("Dock swipe axes rotate consistently at 90° (Spaces <-> Mission Control)")
    func dockSwipe90() {
        let t = AxisTransform(angle: .deg90)
        // Physical left swipe (motion 1, progress -0.6) -> visual UP Mission Control (motion 2, progress +0.6)
        let mc = t.transformDockSwipe(motion: 1, progress: -0.6)
        #expect(mc.motion == 2)
        #expect(abs(mc.progress - 0.6) < 0.0001)

        // Physical up swipe (motion 2, progress +0.5) -> visual RIGHT Spaces (motion 1, progress +0.5)
        let sp = t.transformDockSwipe(motion: 2, progress: 0.5)
        #expect(sp.motion == 1)
        #expect(abs(sp.progress - 0.5) < 0.0001)
    }

    @Test("Normalized touch point rotation preserves center and maps edges accurately")
    func normalizedPoint90() {
        let t = AxisTransform(angle: .deg90)
        let center = t.transformNormalizedYDownPoint(CGPoint(x: 0.5, y: 0.5))
        #expect(abs(center.x - 0.5) < 0.0001)
        #expect(abs(center.y - 0.5) < 0.0001)

        // At 90° CW, physical left edge (x=0, y=0.5) maps to visual top (x=0.5, y=0.0)
        let leftMid = t.transformNormalizedYDownPoint(CGPoint(x: 0.0, y: 0.5))
        #expect(abs(leftMid.x - 0.5) < 0.0001)
        #expect(abs(leftMid.y - 0.0) < 0.0001)
    }

    @Test("Auto-calibrate infers exact angle for upward swipe in all 4 orientations")
    func autoCalibrateInference() {
        // 0°: physical swipe UP -> dy < 0
        #expect(AxisTransform.inferAngleForUpwardSwipe(rawYDownDeltaX: 0.02, rawYDownDeltaY: -0.35) == .deg0)
        // 90° CW: physical left edge is top -> swipe left (dx < 0)
        #expect(AxisTransform.inferAngleForUpwardSwipe(rawYDownDeltaX: -0.38, rawYDownDeltaY: -0.04) == .deg90)
        // 180°: inverted -> swipe down (dy > 0)
        #expect(AxisTransform.inferAngleForUpwardSwipe(rawYDownDeltaX: -0.02, rawYDownDeltaY: 0.35) == .deg180)
        // 270° CW: physical right edge is top -> swipe right (dx > 0)
        #expect(AxisTransform.inferAngleForUpwardSwipe(rawYDownDeltaX: 0.40, rawYDownDeltaY: 0.03) == .deg270)
        // Tiny accidental tap rejected
        #expect(AxisTransform.inferAngleForUpwardSwipe(rawYDownDeltaX: 0.03, rawYDownDeltaY: -0.04) == nil)
    }

    @Test("TrackpadConfig isActive stays false at 0° without overrides and when disabled")
    func trackpadConfigActivityInvariant() {
        var cfg = TrackpadConfig()
        #expect(cfg.isActive == false)

        cfg.angle = .deg270
        #expect(cfg.isActive == true)

        cfg.enabled = false
        #expect(cfg.isActive == false)

        cfg.enabled = true
        cfg.angle = .deg0
        cfg.invertXOverride = true
        #expect(cfg.isActive == true)
    }

    @Test("Decoupled TrackpadMode resolves linked, independent, external-isolation, and off correctly")
    func decoupledTrackpadResolution() {
        // Linked on built-in display follows display angle
        #expect(
            TrackpadConfig.resolveEffectiveAngle(
                displayAngle: .deg270,
                isSelectedDisplayBuiltIn: true,
                mode: .linked,
                independentAngle: .deg90,
                scope: .builtInOnly
            ) == .deg270
        )

        // Linked on external display does NOT accidentally rotate built-in trackpad
        #expect(
            TrackpadConfig.resolveEffectiveAngle(
                displayAngle: .deg270,
                isSelectedDisplayBuiltIn: false,
                mode: .linked,
                independentAngle: .deg90,
                scope: .builtInOnly
            ) == .deg0
        )

        // Linked on external display DOES rotate if scope targets external Magic Trackpad
        #expect(
            TrackpadConfig.resolveEffectiveAngle(
                displayAngle: .deg270,
                isSelectedDisplayBuiltIn: false,
                mode: .linked,
                independentAngle: .deg90,
                scope: .externalOnly
            ) == .deg270
        )

        // Independent mode completely decouples trackpad from display (0° screen + 270° trackpad)
        #expect(
            TrackpadConfig.resolveEffectiveAngle(
                displayAngle: .deg0,
                isSelectedDisplayBuiltIn: true,
                mode: .independent,
                independentAngle: .deg270,
                scope: .builtInOnly
            ) == .deg270
        )

        // Independent mode allows mismatched angles (90° display + 180° trackpad)
        #expect(
            TrackpadConfig.resolveEffectiveAngle(
                displayAngle: .deg90,
                isSelectedDisplayBuiltIn: true,
                mode: .independent,
                independentAngle: .deg180,
                scope: .allTrackpads
            ) == .deg180
        )

        // Off mode always resolves to 0°
        #expect(
            TrackpadConfig.resolveEffectiveAngle(
                displayAngle: .deg270,
                isSelectedDisplayBuiltIn: true,
                mode: .off,
                independentAngle: .deg180,
                scope: .allTrackpads
            ) == .deg0
        )
    }

    @Test("CursorClamper keeps points inside multi-display union and snaps cleanly to nearest display edge")
    func multiDisplayCursorClamping() {
        let left = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let displays = [left, right]

        // Inside left display -> untouched
        let inside = CursorClamper.clamp(CGPoint(x: 400, y: 300), to: displays)
        #expect(inside == CGPoint(x: 400, y: 300))

        // Far negative X -> clamped to left minX
        let clampedLeft = CursorClamper.clamp(CGPoint(x: -50, y: 200), to: displays)
        #expect(clampedLeft == CGPoint(x: 0, y: 200))

        // Far right X -> clamped to right maxX - 1
        let clampedRight = CursorClamper.clamp(CGPoint(x: 4000, y: 500), to: displays)
        #expect(clampedRight == CGPoint(x: 3359, y: 500))
    }

    @Test("TrackpadScope matches built-in vs external devices accurately")
    func trackpadScopeMatching() {
        #expect(TrackpadScope.builtInOnly.matches(isBuiltIn: true) == true)
        #expect(TrackpadScope.builtInOnly.matches(isBuiltIn: false) == false)
        #expect(TrackpadScope.externalOnly.matches(isBuiltIn: true) == false)
        #expect(TrackpadScope.externalOnly.matches(isBuiltIn: false) == true)
        #expect(TrackpadScope.allTrackpads.matches(isBuiltIn: true) == true)
        #expect(TrackpadScope.allTrackpads.matches(isBuiltIn: false) == true)
    }

    @Test("Flat-chassis contentTopDegrees matches AxisTransform visual-UP direction across all 4 angles")
    func contentTopDegreesInvariant() {
        // 0° -> up (0°), 90° -> left (-90°), 180° -> down (180°), 270° -> right (+90°)
        #expect(SpinAngle.deg0.contentTopDegrees == 0)
        #expect(SpinAngle.deg90.contentTopDegrees == -90)
        #expect(SpinAngle.deg180.contentTopDegrees == 180)
        #expect(SpinAngle.deg270.contentTopDegrees == 90)

        for angle in SpinAngle.allCases {
            // Arrow pointing in contentTopDegrees (clockwise from up 0,-1) equals physical vector that maps to visual UP (0,-1).
            let rad = angle.contentTopDegrees * .pi / 180.0
            let physDx = sin(rad)
            let physDy = -cos(rad)
            let mapped = AxisTransform(angle: angle).transformScreenDelta(dx: physDx, dy: physDy)
            #expect(abs(mapped.dx) < 0.0001)
            #expect(abs(mapped.dy - (-1.0)) < 0.0001)
        }
    }
}
