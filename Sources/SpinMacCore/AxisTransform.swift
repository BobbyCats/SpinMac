import CoreGraphics
import Foundation

/// Pure orientation math shared across pointer deltas, scroll vectors,
/// multitouch preview dots, Dock/Spaces swipe axes, and swipe-to-calibrate inference.
public struct AxisTransform: Equatable, Sendable {
    public let angle: SpinAngle
    public let swapXY: Bool
    public let invertX: Bool
    public let invertY: Bool

    public init(angle: SpinAngle, swapXY: Bool = false, invertX: Bool = false, invertY: Bool = false) {
        self.angle = angle
        self.swapXY = swapXY
        self.invertX = invertX
        self.invertY = invertY
    }

    public init(config: TrackpadConfig) {
        self.angle = config.angle
        self.swapXY = config.swapXYOverride
        self.invertX = config.invertXOverride
        self.invertY = config.invertYOverride
    }

    /// Transforms a 2D delta in macOS screen coordinates (+X right, +Y down).
    /// Applies to pointer deltas and continuous scroll deltas (both Natural on & off).
    public func transformScreenDelta(dx: Double, dy: Double) -> (dx: Double, dy: Double) {
        var x = dx
        var y = dy

        if swapXY {
            (x, y) = (y, x)
        }
        if invertX { x = -x }
        if invertY { y = -y }

        switch angle {
        case .deg0:
            return (x, y)
        case .deg90:
            // macOS CGDisplayRotation 90° CW (kIOScaleRotate90 = SwapAxes | InvertX):
            // physical left edge is visual top; physical top is visual right.
            // physical -x (left) -> visual -y (up); physical -y (up) -> visual +x (right)
            return (-y, x)
        case .deg180:
            return (-x, -y)
        case .deg270:
            // macOS CGDisplayRotation 270° CW / 90° CCW (kIOScaleRotate270 = SwapAxes | InvertY):
            // physical right edge is visual top; physical bottom is visual right.
            // physical +x (right) -> visual -y (up); physical +y (down) -> visual +x (right)
            return (y, -x)
        }
    }

    /// Transforms a 2D vector in Y-up coordinates (+X right, +Y up),
    /// used by Dock swipes (Spaces / Mission Control / App Exposé).
    public func transformYUpVector(vx: Double, vy: Double) -> (vx: Double, vy: Double) {
        let screen = transformScreenDelta(dx: vx, dy: -vy)
        return (screen.dx, -screen.dy)
    }

    /// Transforms a Dock swipe (motion: 1 = horizontal Spaces, 2 = vertical Mission Control/Exposé).
    public func transformDockSwipe(motion: Int64, progress: Double) -> (motion: Int64, progress: Double) {
        guard motion == 1 || motion == 2 else {
            return (motion, progress)
        }
        let vx = motion == 1 ? progress : 0
        let vy = motion == 2 ? progress : 0
        let out = transformYUpVector(vx: vx, vy: vy)
        if abs(out.vx) >= abs(out.vy) {
            return (1, out.vx)
        } else {
            return (2, out.vy)
        }
    }

    /// Maps a normalized Y-down touch point in [0, 1] x [0, 1] around center (0.5, 0.5).
    public func transformNormalizedYDownPoint(_ point: CGPoint) -> CGPoint {
        let delta = transformScreenDelta(dx: point.x - 0.5, dy: point.y - 0.5)
        return CGPoint(
            x: min(max(0.5 + delta.dx, 0), 1),
            y: min(max(0.5 + delta.dy, 0), 1)
        )
    }

    /// Infers the SpinAngle that maps a physical Y-down swipe vector (dx, dy)
    /// most closely to visual UP (0, -1). Returns nil if the swipe is too short.
    public static func inferAngleForUpwardSwipe(
        rawYDownDeltaX dx: Double,
        rawYDownDeltaY dy: Double,
        minimumDistance: Double = 0.12
    ) -> SpinAngle? {
        let mag = hypot(dx, dy)
        guard mag >= minimumDistance else { return nil }

        var bestAngle: SpinAngle = .deg0
        var bestUpwardScore = -Double.infinity
        for candidate in SpinAngle.allCases {
            let transformed = AxisTransform(angle: candidate).transformScreenDelta(dx: dx, dy: dy)
            // Visual UP in Y-down coordinates is (0, -1), so upward score is -transformed.dy
            let score = -transformed.dy
            if score > bestUpwardScore {
                bestUpwardScore = score
                bestAngle = candidate
            }
        }
        return bestAngle
    }
}
