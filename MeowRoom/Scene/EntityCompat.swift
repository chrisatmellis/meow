import Foundation
import RealityKit
#if canImport(simd)
import simd
#endif

/// Euler angles for RealityKit, in SceneKit's convention.
///
/// This exists because of one asymmetry between the two renderers. `SCNNode` has
/// `eulerAngles`; `Entity` has only `orientation`, a quaternion. The cat is posed
/// almost entirely in Euler angles — the animator writes them in thirty-nine
/// places, because "pitch the head down, yaw the tail out" is how a pose is
/// actually thought about — so the port either converts every one of those sites
/// to quaternion algebra, or it converts once, here, and gets it right.
///
/// Getting it right means matching SceneKit exactly. SceneKit builds a node's
/// rotation as `Rx · Ry · Rz` against a column vector, so the *last* factor acts
/// first: roll, then yaw, then pitch. Compose in any other order and every joint
/// with two non-zero angles is subtly wrong — which is most of the head and all of
/// the tail, and is exactly the kind of wrong that looks like a bad animation
/// rather than a bad matrix.
enum EulerRotation {

    /// Euler angles → quaternion, in SceneKit's `Rx · Ry · Rz` order.
    ///
    /// Quaternion products compose the same way matrix products do — `(a * b)`
    /// applies `b` first — so the factors here are written in the same order as
    /// the matrices they stand for.
    static func quaternion(_ e: SIMD3<Float>) -> simd_quatf {
        let qx = simd_quatf(angle: e.x, axis: SIMD3<Float>(1, 0, 0))
        let qy = simd_quatf(angle: e.y, axis: SIMD3<Float>(0, 1, 0))
        let qz = simd_quatf(angle: e.z, axis: SIMD3<Float>(0, 0, 1))
        return qx * qy * qz
    }

    /// Quaternion → Euler angles, inverting the above.
    ///
    /// Only the five matrix entries the decomposition needs are formed, which
    /// avoids depending on anyone's opinion about whether a `simd_float4x4`
    /// subscript is row-major or column-major. The identities are the standard
    /// ones for a rotation acting on a column vector.
    ///
    /// Pitch is recovered from `asin`, so it is the axis that degenerates: at
    /// ±90° of yaw the X and Z rotations become the same rotation and only their
    /// sum is recoverable. The gimbal-lock branch resolves that by attributing
    /// all of it to X, which is what SceneKit does and, more importantly, is a
    /// choice rather than a NaN.
    static func angles(_ q: simd_quatf) -> SIMD3<Float> {
        let n = q.normalized
        let x = n.imag.x, y = n.imag.y, z = n.imag.z, w = n.real

        let r02 = 2 * (x * z + w * y)
        let sinYaw = max(-1, min(1, r02))
        let yaw = asinf(sinYaw)

        // cos(yaw) ~ 0 is the locked case. The threshold is generous: near the
        // pole the two recovered angles are numerically worthless long before
        // the division actually blows up.
        if abs(sinYaw) > 0.99999 {
            let r10 = 2 * (x * y + w * z)
            let r11 = 1 - 2 * (x * x + z * z)
            let pitch = atan2f(sinYaw > 0 ? r10 : -r10, r11)
            return SIMD3<Float>(pitch, yaw, 0)
        }

        let r00 = 1 - 2 * (y * y + z * z)
        let r01 = 2 * (x * y - w * z)
        let r12 = 2 * (y * z - w * x)
        let r22 = 1 - 2 * (x * x + y * y)
        return SIMD3<Float>(atan2f(-r12, r22), yaw, atan2f(-r01, r00))
    }
}

/// Remembers the Euler angles an entity was last posed with.
///
/// The quaternion is the truth — it is what gets rendered — but it is a lossy
/// record of *how* the pose was expressed, and a few sites read an angle back to
/// nudge it (the wand drags by accumulating yaw and pitch, the tail reads its
/// socket's roll). Decomposition would answer those correctly everywhere except
/// at gimbal lock, and would quietly renormalise angles that the caller is
/// clamping to a range. Keeping the authored numbers side by side costs twelve
/// bytes and removes the whole class of problem.
struct EulerAnglesComponent: Component {
    /// The angles as written by the caller.
    var angles: SIMD3<Float>
    /// The orientation those angles produced. If the entity's current orientation
    /// is not this, someone set `orientation` directly and the cache is stale.
    var orientation: simd_quatf
}

extension Entity {

    /// Rotation as pitch/yaw/roll, in SceneKit's `Rx · Ry · Rz` order.
    ///
    /// Writing this sets `orientation`; reading it returns exactly what was
    /// written, unless `orientation` has since been set some other way, in which
    /// case it is decomposed.
    var eulerAngles: SIMD3<Float> {
        get {
            let current = orientation
            if let cached = components[EulerAnglesComponent.self],
               quaternionsMatch(cached.orientation, current) {
                return cached.angles
            }
            return EulerRotation.angles(current)
        }
        set {
            let q = EulerRotation.quaternion(newValue)
            orientation = q
            components[EulerAnglesComponent.self] = EulerAnglesComponent(angles: newValue,
                                                                        orientation: q)
        }
    }

    /// Position in world space.
    ///
    /// `SCNNode` spells this `worldPosition`; RealityKit expects you to ask for a
    /// position relative to a reference entity, and `nil` means the scene root.
    var worldPosition: SIMD3<Float> {
        position(relativeTo: nil)
    }
}

/// Two quaternions describe the same rotation if their components agree, or if
/// they agree after negating one — `q` and `-q` are the same rotation. Comparing
/// the absolute dot product covers both without a branch.
private func quaternionsMatch(_ a: simd_quatf, _ b: simd_quatf) -> Bool {
    let d = a.vector.x * b.vector.x + a.vector.y * b.vector.y
        + a.vector.z * b.vector.z + a.vector.w * b.vector.w
    return abs(d) > 0.999999
}
