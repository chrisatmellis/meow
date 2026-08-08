import Foundation
import SceneKit

/// How finely a curved primitive should be divided.
///
/// SceneKit's defaults are sized for a scene where you do not know how big anything
/// is going to be on screen: 48 segments round a sphere, 48 × 24 round a torus. In a
/// room where every object's real size is known and the camera never moves, that is
/// enormously wasteful in exactly the wrong places. The paper lantern's seven ribs
/// are tori with a **2.2 mm** pipe, and each was spending 2,304 triangles on that
/// pipe's cross-section — 16,128 triangles on seven wire hoops, which is more than
/// the entire cat. The two eyeballs were another 9,000 between them, on spheres
/// eight millimetres across.
///
/// The rule here is one facet per few millimetres of arc, so tessellation follows
/// the size of the thing rather than a constant. Applied across the room this frees
/// roughly 50,000 triangles with no visible change, which is then available to spend
/// on the muzzle and the paws — the parts the player is actually looking at.
enum Tessellation {

    /// Metres of arc per facet. Everything in this room sits between one and three
    /// metres from a camera that never moves, so a fixed chord is a good enough
    /// stand-in for real screen-space error and needs no projection maths.
    static let chord: Float = 0.006

    /// Segments around a circle of this radius.
    static func around(_ radius: Float, min lower: Int = 8, max upper: Int = 36) -> Int {
        let ideal = Int((2 * Float.pi * abs(radius) / chord).rounded())
        return Swift.min(Swift.max(ideal, lower), upper)
    }

    /// A sphere's `segmentCount`. Kept a little finer than a flat circle would need,
    /// because the same number also divides the sphere top to bottom.
    static func sphere(_ radius: Float) -> Int {
        around(radius, min: 10, max: 40)
    }

    /// A torus's ring and pipe divisions. The pipe is usually the win: it is nearly
    /// always the small radius, and it defaults to 24.
    static func torus(ring: Float, pipe: Float) -> (ring: Int, pipe: Int) {
        (around(ring, min: 12, max: 36), around(pipe, min: 5, max: 16))
    }
}

extension SCNSphere {
    /// Divides the sphere for its actual size.
    @discardableResult
    func sized() -> SCNSphere {
        segmentCount = Tessellation.sphere(Float(radius))
        return self
    }
}

extension SCNCylinder {
    @discardableResult
    func sized() -> SCNCylinder {
        radialSegmentCount = Tessellation.around(Float(radius))
        return self
    }
}

extension SCNTube {
    @discardableResult
    func sized() -> SCNTube {
        radialSegmentCount = Tessellation.around(Float(outerRadius))
        return self
    }
}

extension SCNTorus {
    @discardableResult
    func sized() -> SCNTorus {
        let (r, p) = Tessellation.torus(ring: Float(ringRadius), pipe: Float(pipeRadius))
        ringSegmentCount = r
        pipeSegmentCount = p
        return self
    }
}
