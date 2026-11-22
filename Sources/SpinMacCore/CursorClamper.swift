import CoreGraphics
import Foundation

/// Pure multi-display cursor coordinate clamping logic.
public enum CursorClamper {
    /// Clamps `point` into the union of active display rectangles, snapping to the nearest edge if outside.
    public static func clamp(_ point: CGPoint, to boundsList: [CGRect]) -> CGPoint {
        guard !boundsList.isEmpty else { return point }
        if boundsList.contains(where: { $0.contains(point) }) {
            return point
        }
        guard let nearest = boundsList.min(by: {
            distanceSquared(point, to: $0) < distanceSquared(point, to: $1)
        }) else {
            return point
        }
        let maxX = max(nearest.minX, nearest.maxX - 1)
        let maxY = max(nearest.minY, nearest.maxY - 1)
        return CGPoint(
            x: min(max(point.x, nearest.minX), maxX),
            y: min(max(point.y, nearest.minY), maxY)
        )
    }

    private static func distanceSquared(_ p: CGPoint, to rect: CGRect) -> Double {
        let cx = min(max(p.x, rect.minX), rect.maxX)
        let cy = min(max(p.y, rect.minY), rect.maxY)
        let dx = p.x - cx
        let dy = p.y - cy
        return dx * dx + dy * dy
    }
}
