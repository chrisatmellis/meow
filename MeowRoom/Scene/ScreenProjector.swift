import Foundation
import CoreGraphics
#if canImport(simd)
import simd
#endif

/// Where a point in the room lands on the screen.
///
/// The room's camera never moves — the player sits on a zabuton with their back
/// to the wall — so this is a fixed transform built once per query rather than
/// anything the renderer has to be asked for. Which matters, because RealityKit
/// will not answer the question: SwiftUI's spatial gestures resolve an entity for
/// you and hand that over, and there is no screen-point-to-scene hit test on iOS.
/// A gesture's entity is also decided when the gesture *begins*, so it cannot say
/// whether a finger is still over the cat halfway through a stroke.
///
/// Doing the projection ourselves answers both, and does it in plain arithmetic
/// that runs on a machine with no graphics framework — so the assertion suite can
/// check that the cat is where the player is being told it is.
struct ScreenProjector {
    let eye: SIMD3<Float>
    let forward: SIMD3<Float>
    let right: SIMD3<Float>
    let up: SIMD3<Float>
    /// Tangent of the half-angle across the frame, horizontally.
    let tanHalfHorizontal: Float
    let size: CGSize

    /// - Parameters:
    ///   - pitch: the camera's rotation about X. The room's camera has no yaw and
    ///     no roll, which is what keeps the basis this simple.
    ///   - horizontalFieldOfView: in radians, and horizontal because that is how
    ///     the scene's lens is specified — a tall phone crops the top and bottom
    ///     of a room rather than narrowing it.
    init(eye: SIMD3<Float>, pitch: Float, horizontalFieldOfView: Float, size: CGSize) {
        self.eye = eye
        self.size = size
        // A RealityKit camera looks along its own -Z.
        forward = SIMD3<Float>(0, sinf(pitch), -cosf(pitch))
        right = SIMD3<Float>(1, 0, 0)
        up = SIMD3<Float>(0, cosf(pitch), sinf(pitch))
        tanHalfHorizontal = tanf(horizontalFieldOfView * 0.5)
    }

    /// Nil for anything level with or behind the lens, which has no screen
    /// position at all rather than one far off to the side.
    func project(_ world: SIMD3<Float>) -> CGPoint? {
        let d = world - eye
        let depth = dot(d, forward)
        guard depth > 0.01, size.width > 0, size.height > 0 else { return nil }
        let aspect = Float(size.width / size.height)
        let tanHalfVertical = tanHalfHorizontal / max(0.0001, aspect)
        let x = dot(d, right) / (depth * tanHalfHorizontal)
        let y = dot(d, up) / (depth * tanHalfVertical)
        return CGPoint(x: CGFloat(x * 0.5 + 0.5) * size.width,
                       y: CGFloat(1 - (y * 0.5 + 0.5)) * size.height)
    }

    /// How many points a metre covers at a given depth, for turning a size in the
    /// room into a size on the screen.
    func pointsPerMetre(atDepth depth: Float) -> CGFloat {
        guard depth > 0.01, size.width > 0 else { return 0 }
        return size.width / CGFloat(2 * depth * tanHalfHorizontal)
    }

    /// The depth of a point along the view direction.
    func depth(of world: SIMD3<Float>) -> Float {
        dot(world - eye, forward)
    }

    /// The box a set of points occupies on screen, grown by a margin given in
    /// metres rather than in points.
    ///
    /// Metres because the thing being framed is an animal and the points are its
    /// skeleton: a cat is its girth wider than its bones everywhere. And because a
    /// constant in points would be honest at one distance only — a cat by the
    /// window is half the size on screen of one in your lap, and a fixed margin
    /// would quietly make the far one the easier target.
    func box(of points: [SIMD3<Float>], paddedBy metres: Float) -> CGRect? {
        var lo = CGPoint(x: CGFloat.greatestFiniteMagnitude,
                         y: CGFloat.greatestFiniteMagnitude)
        var hi = CGPoint(x: -CGFloat.greatestFiniteMagnitude,
                         y: -CGFloat.greatestFiniteMagnitude)
        var depthSum: Float = 0
        var count = 0
        for world in points {
            guard let p = project(world) else { continue }
            lo = CGPoint(x: Swift.min(lo.x, p.x), y: Swift.min(lo.y, p.y))
            hi = CGPoint(x: Swift.max(hi.x, p.x), y: Swift.max(hi.y, p.y))
            depthSum += depth(of: world)
            count += 1
        }
        guard count > 4 else { return nil }
        let pad = pointsPerMetre(atDepth: depthSum / Float(count)) * CGFloat(metres)
        return CGRect(x: lo.x - pad, y: lo.y - pad,
                      width: (hi.x - lo.x) + pad * 2, height: (hi.y - lo.y) + pad * 2)
    }
}
