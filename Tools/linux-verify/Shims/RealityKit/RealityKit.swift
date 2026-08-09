// Linux typecheck shim mirroring the RealityKit API surface the game uses.
//
// Written against Apple's published declarations rather than memory. The
// skinning surface in particular was checked symbol by symbol, because it is
// new enough that guessing at it would be guessing:
//
//   MeshResource.Skeleton(id:jointNames:inverseBindPoseMatrices:restPoseTransforms:parentIndices:)
//   MeshResource.Skeleton(id:joints:)                                    iOS 18.0
//   MeshResource.Part.jointInfluences / .skeletonID / .triangleIndices   iOS 15.0 / 18.0
//   MeshResource.JointInfluences(influences:influencesPerVertex:)        iOS 18.0
//   MeshJointInfluence(jointIndex:weight:)                               iOS 18.0
//   SkeletalPosesComponent(poses:) / SkeletalPose(id:from:)              iOS 18.0
//
// Matrices are column-major with a `columns` tuple, exactly as `simd` has them.
// A row-major stand-in would typecheck, run, and then transpose every joint on
// device — which is the failure mode this whole file exists to avoid.
//
// The material, lighting and view surface was checked the same way on 2026-08-09,
// and three of the port plan's stated losses turned out not to be losses:
//
//   RealityViewRenderingEffects has depthOfField, dynamicRange, antialiasing,
//     cameraGrain, motionBlur and customPostProcessing — so depth of field and
//     HDR survive the port, and bloom and vignette are reachable in Metal rather
//     than gone.
//   PhysicallyBasedMaterial has subsurfaceColor / subsurfaceWeight /
//     subsurfaceRadius — real subsurface scattering, which is what `Translucency`
//     fakes with driven emission. **iOS 26, so out of reach at this target** —
//     noted here because reading the property list without checking each entry's
//     own availability is what put it in the "available" column to begin with,
//     and the compiler is what corrected that.
//   PhysicallyBasedMaterial.textureCoordinateTransform (iOS 15) gives per-material
//     tiling, so the room's tile factors do not have to be baked into UVs.
//
// Confirmed as stated: no torus and no tube in MeshResource (generate is limited
// to box, plane, sphere, cone, cylinder and text), no ambient light, and
// ImageBasedLightComponent is iOS 18.
@_exported import Foundation
@_exported import CoreGraphics
@_exported import UIKit
// For `RealityView`, which is a SwiftUI view that RealityKit vends — so on Linux
// the RealityKit stand-in has to be built after the SwiftUI one.
import SwiftUI
// For `MTLSamplerDescriptor`, which is how RealityKit configures a texture's
// addressing mode.
@_exported import Metal

// MARK: - simd stand-ins
//
// On Apple platforms these come from the `simd` module, which RealityKit
// re-exports. Off Apple they have to exist somewhere.

public typealias simd_float2 = SIMD2<Float>
public typealias simd_float3 = SIMD3<Float>
public typealias simd_float4 = SIMD4<Float>

public struct simd_float4x4 {
    public var columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)

    public init(columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)) {
        self.columns = columns
    }

    public init(_ c0: SIMD4<Float>, _ c1: SIMD4<Float>, _ c2: SIMD4<Float>, _ c3: SIMD4<Float>) {
        columns = (c0, c1, c2, c3)
    }

    public init() {
        self.init(diagonal: SIMD4<Float>(1, 1, 1, 1))
    }

    public init(diagonal d: SIMD4<Float>) {
        columns = (SIMD4<Float>(d.x, 0, 0, 0),
                   SIMD4<Float>(0, d.y, 0, 0),
                   SIMD4<Float>(0, 0, d.z, 0),
                   SIMD4<Float>(0, 0, 0, d.w))
    }

    /// `simd_float4x4(1)` is identity — a diagonal fill, matching simd.
    public init(_ scalar: Float) {
        self.init(diagonal: SIMD4<Float>(repeating: scalar))
    }

    /// The rotation matrix for a quaternion. This is how Apple's simd spells it —
    /// a matrix initialiser, not a property on the quaternion — and the app has to
    /// use the spelling that exists on device.
    public init(_ q: simd_quatf) {
        self = q.matrix
    }

    public subscript(column: Int) -> SIMD4<Float> {
        get {
            switch column {
            case 0: return columns.0
            case 1: return columns.1
            case 2: return columns.2
            default: return columns.3
            }
        }
        set {
            switch column {
            case 0: columns.0 = newValue
            case 1: columns.1 = newValue
            case 2: columns.2 = newValue
            default: columns.3 = newValue
            }
        }
    }

    public subscript(column: Int, row: Int) -> Float {
        get { self[column][row] }
        set { var c = self[column]; c[row] = newValue; self[column] = c }
    }

    public static func * (a: simd_float4x4, b: simd_float4x4) -> simd_float4x4 {
        var out = simd_float4x4(0)
        for c in 0..<4 {
            let bc = b[c]
            var acc = SIMD4<Float>(repeating: 0)
            for k in 0..<4 { acc += a[k] * bc[k] }
            out[c] = acc
        }
        return out
    }

    public static func * (m: simd_float4x4, v: SIMD4<Float>) -> SIMD4<Float> {
        var acc = SIMD4<Float>(repeating: 0)
        for k in 0..<4 { acc += m[k] * v[k] }
        return acc
    }

    public var inverse: simd_float4x4 {
        // Gauss-Jordan on a row-major scratch copy; the transforms here are
        // always invertible.
        var a = [Float](repeating: 0, count: 16)
        var inv = [Float](repeating: 0, count: 16)
        for r in 0..<4 {
            for c in 0..<4 { a[r * 4 + c] = self[c, r] }
            inv[r * 4 + r] = 1
        }
        for col in 0..<4 {
            var pivot = col
            for r in (col + 1)..<4 where abs(a[r * 4 + col]) > abs(a[pivot * 4 + col]) { pivot = r }
            if abs(a[pivot * 4 + col]) < 1e-12 { return simd_float4x4(1) }
            if pivot != col {
                for k in 0..<4 {
                    a.swapAt(col * 4 + k, pivot * 4 + k)
                    inv.swapAt(col * 4 + k, pivot * 4 + k)
                }
            }
            let d = a[col * 4 + col]
            for k in 0..<4 { a[col * 4 + k] /= d; inv[col * 4 + k] /= d }
            for r in 0..<4 where r != col {
                let f = a[r * 4 + col]
                if f == 0 { continue }
                for k in 0..<4 {
                    a[r * 4 + k] -= f * a[col * 4 + k]
                    inv[r * 4 + k] -= f * inv[col * 4 + k]
                }
            }
        }
        var out = simd_float4x4(0)
        for r in 0..<4 {
            for c in 0..<4 { out[c, r] = inv[r * 4 + c] }
        }
        return out
    }
}

public let matrix_identity_float4x4 = simd_float4x4(1)

public struct simd_quatf {
    /// (x, y, z, w) — the imaginary part first, as simd stores it.
    public var vector: SIMD4<Float>

    /// All four lanes zero, which is what Apple's does — *not* the identity.
    /// A zero quaternion is not a rotation, and code that assumes otherwise wants
    /// to fail here rather than on a device.
    public init() { vector = SIMD4<Float>(0, 0, 0, 0) }
    public init(vector: SIMD4<Float>) { self.vector = vector }
    public init(ix: Float, iy: Float, iz: Float, r: Float) { vector = SIMD4<Float>(ix, iy, iz, r) }

    public init(angle: Float, axis: SIMD3<Float>) {
        let len = sqrtf(axis.x * axis.x + axis.y * axis.y + axis.z * axis.z)
        guard len > 1e-9 else { vector = SIMD4<Float>(0, 0, 0, 1); return }
        let n = axis / len
        let h = angle * 0.5
        let s = sinf(h)
        vector = SIMD4<Float>(n.x * s, n.y * s, n.z * s, cosf(h))
    }

    public var real: Float { vector.w }
    public var imag: SIMD3<Float> { SIMD3<Float>(vector.x, vector.y, vector.z) }

    public var angle: Float { 2 * acosf(max(-1, min(1, vector.w))) }

    public var axis: SIMD3<Float> {
        let s = sqrtf(max(0, 1 - vector.w * vector.w))
        return s < 1e-6 ? SIMD3<Float>(0, 0, 1) : imag / s
    }

    public var normalized: simd_quatf {
        let l = sqrtf(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z + vector.w * vector.w)
        return l > 1e-9 ? simd_quatf(vector: vector / l) : simd_quatf()
    }

    public var inverse: simd_quatf {
        simd_quatf(vector: SIMD4<Float>(-vector.x, -vector.y, -vector.z, vector.w)).normalized
    }

    public static func * (a: simd_quatf, b: simd_quatf) -> simd_quatf {
        let ax = a.vector.x, ay = a.vector.y, az = a.vector.z, aw = a.vector.w
        let bx = b.vector.x, by = b.vector.y, bz = b.vector.z, bw = b.vector.w
        return simd_quatf(ix: aw * bx + ax * bw + ay * bz - az * by,
                          iy: aw * by - ax * bz + ay * bw + az * bx,
                          iz: aw * bz + ax * by - ay * bx + az * bw,
                          r:  aw * bw - ax * bx - ay * by - az * bz)
    }

    /// Rotates a vector.
    public func act(_ v: SIMD3<Float>) -> SIMD3<Float> {
        let q = imag
        let w = real
        let t = 2 * cross3(q, v)
        return v + w * t + cross3(q, t)
    }

    /// Column-major rotation matrix for this quaternion.
    public var matrix: simd_float4x4 {
        let n = normalized.vector
        let x = n.x, y = n.y, z = n.z, w = n.w
        let c0 = SIMD4<Float>(1 - 2 * (y * y + z * z), 2 * (x * y + z * w), 2 * (x * z - y * w), 0)
        let c1 = SIMD4<Float>(2 * (x * y - z * w), 1 - 2 * (x * x + z * z), 2 * (y * z + x * w), 0)
        let c2 = SIMD4<Float>(2 * (x * z + y * w), 2 * (y * z - x * w), 1 - 2 * (x * x + y * y), 0)
        return simd_float4x4(c0, c1, c2, SIMD4<Float>(0, 0, 0, 1))
    }

    /// Builds a rotation from an orthonormal column-major basis.
    public init(_ m: simd_float4x4) {
        let trace = m[0, 0] + m[1, 1] + m[2, 2]
        if trace > 0 {
            let s = sqrtf(trace + 1) * 2
            vector = SIMD4<Float>((m[1, 2] - m[2, 1]) / s,
                                  (m[2, 0] - m[0, 2]) / s,
                                  (m[0, 1] - m[1, 0]) / s,
                                  0.25 * s)
        } else if m[0, 0] > m[1, 1] && m[0, 0] > m[2, 2] {
            let s = sqrtf(1 + m[0, 0] - m[1, 1] - m[2, 2]) * 2
            vector = SIMD4<Float>(0.25 * s,
                                  (m[1, 0] + m[0, 1]) / s,
                                  (m[2, 0] + m[0, 2]) / s,
                                  (m[1, 2] - m[2, 1]) / s)
        } else if m[1, 1] > m[2, 2] {
            let s = sqrtf(1 + m[1, 1] - m[0, 0] - m[2, 2]) * 2
            vector = SIMD4<Float>((m[1, 0] + m[0, 1]) / s,
                                  0.25 * s,
                                  (m[2, 1] + m[1, 2]) / s,
                                  (m[2, 0] - m[0, 2]) / s)
        } else {
            let s = sqrtf(1 + m[2, 2] - m[0, 0] - m[1, 1]) * 2
            vector = SIMD4<Float>((m[2, 0] + m[0, 2]) / s,
                                  (m[2, 1] + m[1, 2]) / s,
                                  0.25 * s,
                                  (m[0, 1] - m[1, 0]) / s)
        }
        self = normalized
    }
}

public func cross3(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(a.y * b.z - a.z * b.y,
                 a.z * b.x - a.x * b.z,
                 a.x * b.y - a.y * b.x)
}

public func simd_length(_ v: SIMD3<Float>) -> Float { sqrtf(v.x * v.x + v.y * v.y + v.z * v.z) }

public func simd_normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let l = simd_length(v)
    return l > 1e-9 ? v / l : SIMD3<Float>(0, 0, 1)
}

public func simd_dot(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }
public func simd_cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> { cross3(a, b) }
public func simd_act(_ q: simd_quatf, _ v: SIMD3<Float>) -> SIMD3<Float> { q.act(v) }
public func simd_mul(_ a: simd_float4x4, _ b: simd_float4x4) -> simd_float4x4 { a * b }

// MARK: - Transform

public struct Transform {
    public var scale: SIMD3<Float>
    public var rotation: simd_quatf
    public var translation: SIMD3<Float>

    /// Apple's documented defaults: identity rotation, unit scale, no translation.
    /// The identity is spelled out because `simd_quatf()` is not it.
    public init() {
        scale = SIMD3<Float>(1, 1, 1)
        rotation = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        translation = SIMD3<Float>(0, 0, 0)
    }

    public init(scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1),
                rotation: simd_quatf = simd_quatf(),
                translation: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) {
        self.scale = scale
        self.rotation = rotation
        self.translation = translation
    }

    public init(matrix: simd_float4x4) {
        let c0 = SIMD3<Float>(matrix[0].x, matrix[0].y, matrix[0].z)
        let c1 = SIMD3<Float>(matrix[1].x, matrix[1].y, matrix[1].z)
        let c2 = SIMD3<Float>(matrix[2].x, matrix[2].y, matrix[2].z)
        scale = SIMD3<Float>(simd_length(c0), simd_length(c1), simd_length(c2))
        var basis = simd_float4x4(1)
        basis[0] = SIMD4<Float>(simd_normalize(c0), 0)
        basis[1] = SIMD4<Float>(simd_normalize(c1), 0)
        basis[2] = SIMD4<Float>(simd_normalize(c2), 0)
        rotation = simd_quatf(basis)
        translation = SIMD3<Float>(matrix[3].x, matrix[3].y, matrix[3].z)
    }

    public static let identity = Transform()

    /// Translation · rotation · scale, the order RealityKit composes in.
    public var matrix: simd_float4x4 {
        var m = rotation.matrix
        m[0] = m[0] * scale.x
        m[1] = m[1] * scale.y
        m[2] = m[2] * scale.z
        m[3] = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
        return m
    }
}

// MARK: - Components

public struct ComponentSet {
    private var storage: [ObjectIdentifier: Any] = [:]

    public init() {}

    public subscript<T>(componentType: T.Type) -> T? where T: Component {
        get { storage[ObjectIdentifier(componentType)] as? T }
        set { storage[ObjectIdentifier(componentType)] = newValue }
    }

    public mutating func set<T>(_ component: T) where T: Component {
        storage[ObjectIdentifier(T.self)] = component
    }

    public func has<T>(_ componentType: T.Type) -> Bool where T: Component {
        storage[ObjectIdentifier(componentType)] != nil
    }

    public mutating func remove<T>(_ componentType: T.Type) where T: Component {
        storage.removeValue(forKey: ObjectIdentifier(componentType))
    }
}

// MARK: - Entity

open class Entity {
    public var name: String = ""
    public var transform = Transform()
    public var components = ComponentSet()
    public var isEnabled = true

    public private(set) weak var parent: Entity?
    public private(set) var children: [Entity] = []

    public required init() {}

    // Convenience accessors mirroring RealityKit's.
    public var position: SIMD3<Float> {
        get { transform.translation }
        set { transform.translation = newValue }
    }

    public var orientation: simd_quatf {
        get { transform.rotation }
        set { transform.rotation = newValue }
    }

    public var scale: SIMD3<Float> {
        get { transform.scale }
        set { transform.scale = newValue }
    }

    public func addChild(_ child: Entity, preservingWorldTransform: Bool = false) {
        child.removeFromParent()
        child.parent = self
        children.append(child)
    }

    public func removeChild(_ child: Entity) {
        children.removeAll { $0 === child }
        if child.parent === self { child.parent = nil }
    }

    public func removeFromParent() {
        parent?.removeChild(self)
    }

    public func findEntity(named name: String) -> Entity? {
        if self.name == name { return self }
        for child in children {
            if let hit = child.findEntity(named: name) { return hit }
        }
        return nil
    }

    /// World transform, composed through the parent chain.
    public var worldMatrix: simd_float4x4 {
        if let parent = parent { return parent.worldMatrix * transform.matrix }
        return transform.matrix
    }

    public func transformMatrix(relativeTo reference: Entity?) -> simd_float4x4 {
        guard let reference = reference else { return worldMatrix }
        return reference.worldMatrix.inverse * worldMatrix
    }

    // No `worldPosition` here on purpose. RealityKit does not have one — it wants
    // `position(relativeTo: nil)` — and the game's spelling of it belongs in the
    // app's own compatibility layer, where it can be wrong in only one place.

    public func position(relativeTo reference: Entity?) -> SIMD3<Float> {
        let m = transformMatrix(relativeTo: reference)
        return SIMD3<Float>(m[3].x, m[3].y, m[3].z)
    }

    public func setPosition(_ p: SIMD3<Float>, relativeTo reference: Entity?) {
        transform.translation = convert(position: p, from: reference)
        if let parent = parent {
            let world = SIMD4<Float>(transform.translation, 1)
            let local = parent.worldMatrix.inverse * world
            transform.translation = SIMD3<Float>(local.x, local.y, local.z)
        }
    }

    /// Converts a point from `reference` space into this entity's local space.
    public func convert(position: SIMD3<Float>, from reference: Entity?) -> SIMD3<Float> {
        let world: SIMD4<Float>
        if let reference = reference {
            world = reference.worldMatrix * SIMD4<Float>(position, 1)
        } else {
            world = SIMD4<Float>(position, 1)
        }
        let local = worldMatrix.inverse * world
        return SIMD3<Float>(local.x, local.y, local.z)
    }

    /// Converts a point from this entity's local space into `reference` space.
    public func convert(position: SIMD3<Float>, to reference: Entity?) -> SIMD3<Float> {
        let world = worldMatrix * SIMD4<Float>(position, 1)
        guard let reference = reference else { return SIMD3<Float>(world.x, world.y, world.z) }
        let local = reference.worldMatrix.inverse * world
        return SIMD3<Float>(local.x, local.y, local.z)
    }

    public func convert(direction: SIMD3<Float>, from reference: Entity?) -> SIMD3<Float> {
        let world: SIMD4<Float>
        if let reference = reference {
            world = reference.worldMatrix * SIMD4<Float>(direction, 0)
        } else {
            world = SIMD4<Float>(direction, 0)
        }
        let local = worldMatrix.inverse * world
        return SIMD3<Float>(local.x, local.y, local.z)
    }

    /// Aims the entity's -Z at `target`.
    ///
    /// The SceneKit shim left this empty, which quietly meant the sun and moon
    /// aiming was never exercised by any test. It is implemented here.
    public func look(at target: SIMD3<Float>,
                     from position: SIMD3<Float>,
                     upVector: SIMD3<Float> = SIMD3<Float>(0, 1, 0),
                     relativeTo reference: Entity? = nil) {
        let worldTarget = reference.map { $0.worldMatrix * SIMD4<Float>(target, 1) }
            ?? SIMD4<Float>(target, 1)
        let worldFrom = reference.map { $0.worldMatrix * SIMD4<Float>(position, 1) }
            ?? SIMD4<Float>(position, 1)
        let eye = SIMD3<Float>(worldFrom.x, worldFrom.y, worldFrom.z)
        let at = SIMD3<Float>(worldTarget.x, worldTarget.y, worldTarget.z)

        let forward = simd_normalize(eye - at)          // +Z points back toward the eye
        var right = cross3(simd_normalize(upVector), forward)
        if simd_length(right) < 1e-5 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        let up = cross3(forward, right)

        var basis = simd_float4x4(1)
        basis[0] = SIMD4<Float>(right, 0)
        basis[1] = SIMD4<Float>(up, 0)
        basis[2] = SIMD4<Float>(forward, 0)

        var worldTransform = Transform(matrix: basis)
        worldTransform.translation = eye
        worldTransform.scale = transform.scale

        if let parent = parent {
            transform = Transform(matrix: parent.worldMatrix.inverse * worldTransform.matrix)
        } else {
            transform = worldTransform
        }
    }
}

public final class ModelEntity: Entity {
    public var model: ModelComponent?

    public required init() { super.init() }

    public convenience init(mesh: MeshResource, materials: [Material] = []) {
        self.init()
        model = ModelComponent(mesh: mesh, materials: materials)
    }
}

public struct ModelComponent: Component {
    public var mesh: MeshResource
    public var materials: [Material]

    public init(mesh: MeshResource, materials: [Material]) {
        self.mesh = mesh
        self.materials = materials
    }
}

// MARK: - Meshes

public enum MeshBuffers {
    public typealias Positions = [SIMD3<Float>]
    public typealias Normals = [SIMD3<Float>]
    public typealias TextureCoordinates = [SIMD2<Float>]
    public typealias TriangleIndices = [UInt32]
    public typealias JointInfluences = [MeshJointInfluence]
}

public struct MeshJointInfluence {
    public var jointIndex: Int
    public var weight: Float
    public init() { jointIndex = 0; weight = 0 }
    public init(jointIndex: Int, weight: Float) {
        self.jointIndex = jointIndex
        self.weight = weight
    }
}

public final class MeshResource {
    /// Nested under `Skeleton` in the real framework, and only reachable as
    /// `MeshResource.Skeleton.Joint`. The alias keeps existing shim code working
    /// while the app uses the spelling that exists on device.
    public typealias Joint = Skeleton.Joint

    public struct _Joint {
        public var name: String
        public var parentIndex: Int?
        public var inverseBindPoseMatrix: simd_float4x4
        public var restPoseTransform: Transform

        public init(name: String,
                    parentIndex: Int? = nil,
                    inverseBindPoseMatrix: simd_float4x4 = matrix_identity_float4x4,
                    restPoseTransform: Transform = .identity) {
            self.name = name
            self.parentIndex = parentIndex
            self.inverseBindPoseMatrix = inverseBindPoseMatrix
            self.restPoseTransform = restPoseTransform
        }
    }

    public struct Skeleton {
        public typealias Joint = _Joint
        public var id: String
        public var joints: [Joint]

        public init(id: String, joints: [Joint]) {
            self.id = id
            self.joints = joints
        }

        public init?(id: String,
                     jointNames: [String],
                     inverseBindPoseMatrices: [simd_float4x4],
                     restPoseTransforms: [Transform]? = nil,
                     parentIndices: [Int?]? = nil) {
            guard jointNames.count == inverseBindPoseMatrices.count else { return nil }
            if let r = restPoseTransforms, r.count != jointNames.count { return nil }
            if let p = parentIndices, p.count != jointNames.count { return nil }
            self.id = id
            self.joints = jointNames.enumerated().map { i, name in
                Joint(name: name,
                      parentIndex: parentIndices?[i] ?? nil,
                      inverseBindPoseMatrix: inverseBindPoseMatrices[i],
                      restPoseTransform: restPoseTransforms?[i] ?? .identity)
            }
        }
    }

    public struct JointInfluences {
        public var influences: MeshBuffers.JointInfluences
        public var influencesPerVertex: Int

        public init(influences: MeshBuffers.JointInfluences, influencesPerVertex: Int) {
            self.influences = influences
            self.influencesPerVertex = influencesPerVertex
        }
    }

    public struct Part {
        public var id: String
        public var materialIndex: Int
        public var positions: MeshBuffers.Positions = []
        public var normals: MeshBuffers.Normals?
        public var textureCoordinates: MeshBuffers.TextureCoordinates?
        public var triangleIndices: MeshBuffers.TriangleIndices?
        public var jointInfluences: JointInfluences?
        public var skeletonID: String?

        public init(id: String, materialIndex: Int) {
            self.id = id
            self.materialIndex = materialIndex
        }
    }

    public struct Model {
        public var id: String
        public var parts: [Part]
        public init(id: String, parts: [Part]) {
            self.id = id
            self.parts = parts
        }
    }

    public struct Instance {
        public var id: String
        public var model: String
        public var transform: simd_float4x4
        public init(id: String, model: String, at transform: simd_float4x4 = matrix_identity_float4x4) {
            self.id = id
            self.model = model
            self.transform = transform
        }
    }

    public struct Contents {
        public var models: [Model] = []
        public var instances: [Instance] = []
        public var skeletons: [Skeleton] = []
        public init() {}
    }

    public private(set) var contents: Contents

    private init(contents: Contents) {
        self.contents = contents
    }

    public static func generate(from contents: Contents) throws -> MeshResource {
        MeshResource(contents: contents)
    }

    /// The box the vertices occupy, in the mesh's own space. Real, rather than a
    /// stub, because it is used to compare what the GPU holds against what we
    /// think we handed it — a stub would answer that question with our own belief.
    public var bounds: BoundingBox {
        var lo = SIMD3<Float>(repeating: Float.infinity)
        var hi = SIMD3<Float>(repeating: -Float.infinity)
        for model in contents.models {
            for part in model.parts {
                for p in part.positions {
                    lo = SIMD3<Float>(Swift.min(lo.x, p.x), Swift.min(lo.y, p.y), Swift.min(lo.z, p.z))
                    hi = SIMD3<Float>(Swift.max(hi.x, p.x), Swift.max(hi.y, p.y), Swift.max(hi.z, p.z))
                }
            }
        }
        return lo.x <= hi.x ? BoundingBox(min: lo, max: hi) : BoundingBox()
    }

    public func replace(with contents: Contents) throws {
        self.contents = contents
    }

    public var expectedMaterialCount: Int {
        let indices = contents.models.flatMap { $0.parts.map(\.materialIndex) }
        return (indices.max() ?? -1) + 1
    }

    // Primitive generators the room props may still want.
    public static func generateBox(width: Float, height: Float, depth: Float,
                                   cornerRadius: Float = 0, splitFaces: Bool = false) -> MeshResource {
        MeshResource(contents: Contents())
    }

    public static func generateSphere(radius: Float) -> MeshResource {
        MeshResource(contents: Contents())
    }

    public static func generatePlane(width: Float, height: Float, cornerRadius: Float = 0) -> MeshResource {
        MeshResource(contents: Contents())
    }

    public static func generateCylinder(height: Float, radius: Float) -> MeshResource {
        MeshResource(contents: Contents())
    }
}

// MARK: - Skeletal posing

public struct JointTransforms {
    public typealias Element = Transform
    public var elements: [Transform]
    public init(_ elements: [Transform] = []) { self.elements = elements }

    public subscript(index: Int) -> Transform {
        get { elements[index] }
        set { elements[index] = newValue }
    }

    public var count: Int { elements.count }
}

public struct SkeletalPose {
    public typealias ID = String

    public var id: ID
    public var jointNames: [String]
    public var jointTransforms: JointTransforms

    public init(id: ID, from skeleton: MeshResource.Skeleton) {
        self.id = id
        self.jointNames = skeleton.joints.map(\.name)
        self.jointTransforms = JointTransforms(skeleton.joints.map(\.restPoseTransform))
    }

    public init(id: ID, joints: [(String, JointTransforms.Element)]) {
        self.id = id
        self.jointNames = joints.map(\.0)
        self.jointTransforms = JointTransforms(joints.map(\.1))
    }

    public subscript(jointName: String) -> Transform? {
        get {
            guard let i = jointNames.firstIndex(of: jointName) else { return nil }
            return jointTransforms[i]
        }
        set {
            guard let newValue = newValue, let i = jointNames.firstIndex(of: jointName) else { return }
            jointTransforms[i] = newValue
        }
    }
}

public struct SkeletalPoseSet {
    public var poses: [SkeletalPose]
    public init(_ poses: [SkeletalPose] = []) { self.poses = poses }

    public subscript(id: SkeletalPose.ID) -> SkeletalPose? {
        get { poses.first { $0.id == id } }
        set {
            guard let newValue = newValue else { return }
            if let i = poses.firstIndex(where: { $0.id == id }) { poses[i] = newValue }
            else { poses.append(newValue) }
        }
    }

    public var isEmpty: Bool { poses.isEmpty }
    public var count: Int { poses.count }
    public var first: SkeletalPose? { poses.first }
}

public struct SkeletalPosesComponent: Component {
    public var poses: SkeletalPoseSet
    public init(poses: [SkeletalPose]) { self.poses = SkeletalPoseSet(poses) }
}

// MARK: - Materials
//
// Checked against Apple's published declarations rather than memory, symbol by
// symbol, on 2026-08-09. The pieces that differ most from what one would guess:
//
//   PhysicallyBasedMaterial.Texture      = MaterialParameters.Texture       iOS 15
//   .TextureCoordinateTransform          = MaterialParameterTypes...        iOS 15
//     — so per-material tiling is real and does not need baking into UVs
//   Blending is an *enum*: .opaque / .transparent(opacity:)                 iOS 15
//   TextureResource(image:withName:options:)                               (generate(from:) is deprecated)
//   .subsurfaceColor / .subsurfaceWeight / .subsurfaceRadius exist          — real SSS, not an emission hack
//   .clearcoat / .clearcoatRoughness / .sheen / .ambientOcclusion exist
//
// The scalar wrappers are `ExpressibleByFloatLiteral` in the real framework, so
// `material.roughness = 0.8` compiles there. They are here too, or the port
// would be written against a stricter API than the one it ships on and would
// then not compile on device — the exact failure this file exists to prevent.

public protocol Material {}

public protocol Component {
    static func registerComponent()
}

public extension Component {
    /// RealityKit requires this once per custom component type before use, and
    /// provides a default. Registration has nothing to observe off-device.
    static func registerComponent() {}
}

public enum MaterialParameterTypes {
    public struct TextureCoordinateTransform {
        public var offset: SIMD2<Float>
        public var scale: SIMD2<Float>
        public var rotation: Float
        public init(offset: SIMD2<Float> = SIMD2<Float>(0, 0),
                    scale: SIMD2<Float> = SIMD2<Float>(1, 1),
                    rotation: Float = 0) {
            self.offset = offset
            self.scale = scale
            self.rotation = rotation
        }
    }
}

public enum MaterialParameters {
    public struct Texture {
        /// Wraps an `MTLSamplerDescriptor`, which is a class, so `modify` hands it
        /// over by reference rather than as `inout`. Only the addressing mode
        /// matters here: a tiled surface sampled with Metal's default clamp shows
        /// one repeat and then a smear, which reads as a broken UV rather than as
        /// a broken sampler.
        public struct Sampler {
            public var descriptor = MTLSamplerDescriptor()
            public init() {}
            public init(_ descriptor: MTLSamplerDescriptor) { self.descriptor = descriptor }
            @discardableResult
            public mutating func modify<R>(_ body: (MTLSamplerDescriptor) throws -> R) rethrows -> R {
                try body(descriptor)
            }
            @discardableResult
            public func access<R>(_ body: (MTLSamplerDescriptor) throws -> R) rethrows -> R {
                try body(descriptor)
            }
        }

        public var resource: TextureResource
        public var sampler = Sampler()
        public var uvIndex: Int = 0

        public init(_ resource: TextureResource) { self.resource = resource }
        public init(_ resource: TextureResource, sampler: Sampler) {
            self.resource = resource
            self.sampler = sampler
        }
    }
}

public final class TextureResource {
    public var identifier: String
    public var width: Int
    public var height: Int
    public var semantic: Semantic?

    public init(identifier: String = "", width: Int = 1, height: Int = 1, semantic: Semantic? = nil) {
        self.identifier = identifier
        self.width = width
        self.height = height
        self.semantic = semantic
    }

    /// The current spelling. `generate(from:withName:options:)` still exists and
    /// is deprecated, which is worth remembering when reading older samples.
    public convenience init(image: CGImage, withName name: String? = nil,
                            options: CreateOptions) throws {
        self.init(identifier: name ?? "cgimage",
                  width: image.width, height: image.height,
                  semantic: options.semantic)
    }

    public static func generate(from image: CGImage, withName name: String? = nil,
                                options: CreateOptions) throws -> TextureResource {
        try TextureResource(image: image, withName: name, options: options)
    }

    public struct CreateOptions {
        public var semantic: Semantic?
        public var mipmapsMode: MipmapsMode = .allocateAndGenerateAll
        public init(semantic: Semantic?) { self.semantic = semantic }
        public init(semantic: Semantic?, mipmapsMode: MipmapsMode) {
            self.semantic = semantic
            self.mipmapsMode = mipmapsMode
        }
    }

    public enum MipmapsMode { case none, allocateAll, allocateAndGenerateAll }

    public struct Compression {
        public static let `default` = Compression()
        public static let none = Compression()
        public init() {}
    }

    /// What the pixels *mean*, which decides the colour space they are read in.
    /// A normal map read as sRGB is the classic silent disaster: it still looks
    /// like a normal map, just with every slope wrong by the gamma curve.
    public enum Semantic {
        case color, normal, raw, scalar, hdrColor
    }
}

public struct PhysicallyBasedMaterial: Material {
    public typealias Texture = MaterialParameters.Texture
    public typealias TextureCoordinateTransform = MaterialParameterTypes.TextureCoordinateTransform

    public struct BaseColor {
        public var tint: UIColor
        public var texture: Texture?
        public init(tint: UIColor = .white, texture: Texture? = nil) {
            self.tint = tint
            self.texture = texture
        }
    }

    /// A scalar that a texture may override. All of RealityKit's single-channel
    /// material parameters share this shape, so they share an implementation.
    public struct Scalar: ExpressibleByFloatLiteral {
        public var scale: Float
        public var texture: Texture?
        public init(floatLiteral value: Float) { scale = value; texture = nil }
        public init(scale: Float = 1, texture: Texture? = nil) {
            self.scale = scale
            self.texture = texture
        }
        public init(_ value: Float) { scale = value; texture = nil }
    }

    public typealias Roughness = Scalar
    public typealias Metallic = Scalar
    public typealias Specular = Scalar
    public typealias Clearcoat = Scalar
    public typealias ClearcoatRoughness = Scalar
    public typealias SubsurfaceWeight = Scalar
    public typealias SubsurfaceRadius = Scalar
    public typealias AnisotropyLevel = Scalar
    public typealias AnisotropyAngle = Scalar

    public struct AmbientOcclusion {
        public var texture: Texture?
        public init(texture: Texture? = nil) { self.texture = texture }
        public init(_ texture: Texture?) { self.texture = texture }
    }

    public struct Normal {
        public var texture: Texture?
        public init(texture: Texture? = nil) { self.texture = texture }
        public init(_ texture: Texture?) { self.texture = texture }
    }

    public struct EmissiveColor {
        public var color: UIColor
        public var texture: Texture?
        public init(color: UIColor = .black, texture: Texture? = nil) {
            self.color = color
            self.texture = texture
        }
    }

    /// The colour light takes on once it has been through the surface. On a cat
    /// this is the ears, the nose leather and the toe webbing — thin tissue over
    /// blood — and RealityKit models it properly, which the SceneKit build had to
    /// fake with emission.
    public struct SubsurfaceColor {
        public var tint: UIColor
        public var texture: Texture?
        public init(tint: UIColor = .white, texture: Texture? = nil) {
            self.tint = tint
            self.texture = texture
        }
    }

    public struct SheenColor {
        public var tint: UIColor
        public var texture: Texture?
        public init(tint: UIColor = .white, texture: Texture? = nil) {
            self.tint = tint
            self.texture = texture
        }
    }

    public struct Opacity: ExpressibleByFloatLiteral {
        public var scale: Float
        public var texture: Texture?
        public init(floatLiteral value: Float) { scale = value; texture = nil }
        public init(scale: Float, texture: Texture? = nil) {
            self.scale = scale
            self.texture = texture
        }
    }

    public enum Blending {
        case opaque
        case transparent(opacity: Opacity)
    }

    public enum FaceCulling { case none, front, back }
    public enum TriangleFillMode { case fill, lines }

    public var baseColor = BaseColor()
    public var roughness = Roughness(scale: 0.5)
    public var metallic = Metallic(scale: 0)
    public var normal = Normal()
    public var ambientOcclusion = AmbientOcclusion()
    public var specular = Specular(scale: 0.5)
    public var clearcoat = Clearcoat(scale: 0)
    public var clearcoatRoughness = ClearcoatRoughness(scale: 0)
    public var sheen: SheenColor?
    public var emissiveColor = EmissiveColor()
    public var emissiveIntensity: Float = 0
    public var subsurfaceColor = SubsurfaceColor()
    public var subsurfaceWeight = SubsurfaceWeight(scale: 0)
    public var subsurfaceRadius = SubsurfaceRadius(scale: 0)
    public var blending = Blending.opaque
    public var opacityThreshold: Float?
    public var faceCulling: FaceCulling = .back
    public var triangleFillMode: TriangleFillMode = .fill
    public var readsDepth = true
    public var writesDepth = true
    public var textureCoordinateTransform = TextureCoordinateTransform()
    public var secondaryTextureCoordinateTransform = TextureCoordinateTransform()

    public init() {}
}

public struct SimpleMaterial: Material {
    public var color: UIColor
    public var roughness: Float
    public var isMetallic: Bool
    public init(color: UIColor = .white, roughness: Float = 0.5, isMetallic: Bool = false) {
        self.color = color
        self.roughness = roughness
        self.isMetallic = isMetallic
    }
}

public struct UnlitMaterial: Material {
    public var color: UIColor
    public init(color: UIColor = .white) { self.color = color }
}

// MARK: - Image-based lighting
//
// RealityKit has no ambient light. What SceneKit spelled as one number is an
// environment map here, which is strictly better — a room lit by a window is not
// lit equally from every direction — but it does mean the sky has to become an
// image before it can light anything.

public final class EnvironmentResource {
    public typealias Compression = TextureResource.Compression

    public struct CreateOptions {
        public enum SamplingQuality { case fast, normal, high, veryHigh }

        public var samplingQuality: SamplingQuality
        public var specularCubeDimension: Int?
        public var compression: Compression

        public init(samplingQuality: SamplingQuality,
                    specularCubeDimension: Int? = nil,
                    compression: Compression = .default) {
            self.samplingQuality = samplingQuality
            self.specularCubeDimension = specularCubeDimension
            self.compression = compression
        }
    }

    public var name: String
    public init(name: String = "environment") { self.name = name }

    /// The path this game uses: the sky is drawn procedurally every few minutes,
    /// so it arrives as a `CGImage` and never touches the bundle.
    ///
    /// Deliberately the `options:` spelling. The `withName:` one is `async`, and
    /// the sky is rebuilt from inside a synchronous frame loop — so taking the
    /// convenient-looking initialiser would have compiled here, against a
    /// stand-in that forgot to be async, and failed on device.
    /// Async, and there is no synchronous form that takes an equirectangular
    /// image — the `options:` initialiser that is not async takes an already-built
    /// cube texture instead. So the sky arrives a frame or two late, which for a
    /// sky is fine.
    public convenience init(equirectangular image: CGImage, withName name: String? = nil) async throws {
        self.init(name: name ?? "equirectangular")
    }

    public convenience init(named name: String, in bundle: Bundle? = nil) throws {
        self.init(name: name)
    }
}

public struct ImageBasedLightComponent: Component {
    public enum Source {
        case single(EnvironmentResource)
        case blend(EnvironmentResource, EnvironmentResource, Float)
    }

    public var source: Source
    /// A power-of-two exponent, not a multiplier: RealityKit scales the
    /// environment by `pow(2, intensityExponent)`.
    public var intensityExponent: Float
    public var inheritsRotation = false

    public init(source: Source, intensityExponent: Float = 0) {
        self.source = source
        self.intensityExponent = intensityExponent
    }
}

/// Points an entity at the entity carrying the image-based light. Without one,
/// nothing receives it — which is easy to miss, because the scene still renders.
public struct ImageBasedLightReceiverComponent: Component {
    public var imageBasedLight: Entity
    public init(imageBasedLight: Entity) { self.imageBasedLight = imageBasedLight }
}

// MARK: - Lights and cameras

public struct DirectionalLightComponent: Component {
    public struct Shadow: Component {
        public var maximumDistance: Float
        public var depthBias: Float
        public init(maximumDistance: Float = 10, depthBias: Float = 1) {
            self.maximumDistance = maximumDistance
            self.depthBias = depthBias
        }
    }

    public var color: UIColor
    public var intensity: Float
    public var isRealWorldProxy: Bool

    public init(color: UIColor = .white, intensity: Float = 1000, isRealWorldProxy: Bool = false) {
        self.color = color
        self.intensity = intensity
        self.isRealWorldProxy = isRealWorldProxy
    }
}

public struct PointLightComponent: Component {
    public var color: UIColor
    public var intensity: Float
    public var attenuationRadius: Float

    public init(color: UIColor = .white, intensity: Float = 1000, attenuationRadius: Float = 10) {
        self.color = color
        self.intensity = intensity
        self.attenuationRadius = attenuationRadius
    }
}

public struct SpotLightComponent: Component {
    public var color: UIColor
    public var intensity: Float
    public var innerAngleInDegrees: Float
    public var outerAngleInDegrees: Float
    public var attenuationRadius: Float

    public init(color: UIColor = .white, intensity: Float = 1000,
                innerAngleInDegrees: Float = 30, outerAngleInDegrees: Float = 60,
                attenuationRadius: Float = 10) {
        self.color = color
        self.intensity = intensity
        self.innerAngleInDegrees = innerAngleInDegrees
        self.outerAngleInDegrees = outerAngleInDegrees
        self.attenuationRadius = attenuationRadius
    }
}

public struct PerspectiveCameraComponent: Component {
    /// Which axis `fieldOfViewInDegrees` describes. RealityKit defaults to
    /// vertical and derives the other from the aspect ratio; SceneKit's camera in
    /// this game was pinned horizontal, because a room framed by its width is the
    /// thing that has to stay put when the phone changes shape.
    public enum FieldOfViewOrientation { case horizontal, vertical }

    public var near: Float
    public var far: Float
    public var fieldOfViewInDegrees: Float
    public var fieldOfViewOrientation: FieldOfViewOrientation = .vertical

    public init(near: Float = 0.01, far: Float = 100, fieldOfViewInDegrees: Float = 60) {
        self.near = near
        self.far = far
        self.fieldOfViewInDegrees = fieldOfViewInDegrees
    }
}

public final class PerspectiveCamera: Entity {
    public var camera = PerspectiveCameraComponent()
    public required init() { super.init() }
}

public final class DirectionalLight: Entity {
    public var light = DirectionalLightComponent()
    public var shadow: DirectionalLightComponent.Shadow?
    public required init() { super.init() }
}

public final class PointLight: Entity {
    public var light = PointLightComponent()
    public required init() { super.init() }
}

// MARK: - Particles

public struct ParticleEmitterComponent: Component {
    public struct ParticleEmitter {
        public var birthRate: Float = 10
        public var size: Float = 0.01
        public var lifeSpan: Double = 1
        public var color: ParticleColor = .constant(.single(.white))
        public init() {}
    }

    public enum ParticleColor {
        case constant(ColorMode)
        case evolving(start: ColorMode, end: ColorMode)

        public enum ColorMode {
            case single(UIColor)
            case random(a: UIColor, b: UIColor)
        }
    }

    public enum EmitterShape {
        case point, plane, sphere, box, cone, torus, cylinder
    }

    public var emitterShape: EmitterShape = .point
    public var emitterShapeSize: SIMD3<Float> = SIMD3<Float>(0.1, 0.1, 0.1)
    public var birthDirection: BirthDirection = .normal
    public var mainEmitter = ParticleEmitter()
    public var isEmitting = true
    public var speed: Float = 0.1

    public enum BirthDirection {
        case normal, world, local
    }

    public init() {}
}

// MARK: - Bounds

public struct BoundingBox {
    public var min: SIMD3<Float>
    public var max: SIMD3<Float>
    public init(min: SIMD3<Float> = SIMD3<Float>(repeating: 0),
                max: SIMD3<Float> = SIMD3<Float>(repeating: 0)) {
        self.min = min
        self.max = max
    }

    public var center: SIMD3<Float> { (min + max) * 0.5 }
    public var extents: SIMD3<Float> { max - min }
}

// MARK: - RealityView

/// The SwiftUI host. On iOS this is the non-AR path: `content.camera = .virtual`
/// and an explicit `PerspectiveCamera` in the scene, rather than the device's
/// camera looking at the room through AR.
public struct RealityViewCamera {
    public static let virtual = RealityViewCamera()
    public static let spatialTracking = RealityViewCamera()
}

public struct RealityViewEnvironment {
    public static let `default` = RealityViewEnvironment()
    public static func skybox(_ resource: EnvironmentResource) -> RealityViewEnvironment {
        RealityViewEnvironment()
    }
}

/// One mode type for every effect, with three states — not an enum per effect.
public struct RealityViewRenderingEffectMode: Equatable {
    public static let `default` = RealityViewRenderingEffectMode()
    public static let enabled = RealityViewRenderingEffectMode()
    public static let disabled = RealityViewRenderingEffectMode()
    private init() {}
}

/// Antialiasing and dynamic range each have their own type rather than sharing
/// the mode above, and neither offers a "high" — the choice is 4x multisampling
/// or nothing, and the display's own range or a forced standard one.
public enum AntialiasingMode {
    case none, multisample4X
}

public struct RealityViewDynamicRange: Equatable {
    public static let `default` = RealityViewDynamicRange()
    public static let standard = RealityViewDynamicRange()
    private init() {}
}

public struct RealityViewRenderingEffects {
    public var antialiasing = AntialiasingMode.multisample4X
    public var depthOfField = RealityViewRenderingEffectMode.default
    public var dynamicRange = RealityViewDynamicRange.default
    public var cameraGrain = RealityViewRenderingEffectMode.default
    public var motionBlur = RealityViewRenderingEffectMode.default
    public init() {}
}

public struct RealityViewCameraContent {
    public var camera = RealityViewCamera.virtual
    public var environment = RealityViewEnvironment.default
    public var renderingEffects = RealityViewRenderingEffects()
    public private(set) var entities: [Entity] = []

    public init() {}
    public mutating func add(_ entity: Entity) { entities.append(entity) }
    public mutating func remove(_ entity: Entity) { entities.removeAll { $0 === entity } }

    @discardableResult
    public func subscribe<E>(to event: E.Type, _ handler: @escaping (E) -> Void) -> EventSubscription {
        EventSubscription()
    }
}

public struct EventSubscription {
    public init() {}
    public func cancel() {}
}

/// The frame loop. RealityKit hands out a delta rather than an absolute time,
/// which removes the "is this the first frame" dance the SceneKit delegate needed.
public enum SceneEvents {
    public struct Update {
        public var deltaTime: TimeInterval
        public init(deltaTime: TimeInterval = 1.0 / 60.0) { self.deltaTime = deltaTime }
    }
}

// MARK: - Input

/// Marks an entity as something a gesture can land on. Without it an entity is
/// invisible to touch however solid it looks, which is the trap: the scene still
/// renders perfectly and nothing responds.
public struct InputTargetComponent: Component {
    public var allowedInputTypes: InputTypes = .all
    public init(allowedInputTypes: InputTypes = .all) { self.allowedInputTypes = allowedInputTypes }

    public struct InputTypes: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let indirect = InputTypes(rawValue: 1)
        public static let direct = InputTypes(rawValue: 2)
        public static let all: InputTypes = [.indirect, .direct]
    }
}

public struct CollisionComponent: Component {
    public var shapes: [ShapeResource]
    public var isStatic: Bool
    public init(shapes: [ShapeResource], isStatic: Bool = false) {
        self.shapes = shapes
        self.isStatic = isStatic
    }
}

public struct ShapeResource {
    public static func generateBox(size: SIMD3<Float>) -> ShapeResource { ShapeResource() }
    public static func generateSphere(radius: Float) -> ShapeResource { ShapeResource() }
    public static func generateConvex(from mesh: MeshResource) -> ShapeResource { ShapeResource() }
}

public struct RealityView<Content: View>: View {
    public var body: Never { fatalError() }

    // The real initialiser's `make`/`update` closures are what the app writes, and
    // `Content` is inferred from the (unused here) placeholder. Defaulting it to
    // `EmptyView` keeps the app's call sites written exactly as they are on
    // device, where trailing-closure syntax names no generic argument at all.
    public init(make: @escaping (inout RealityViewCameraContent) async -> Void,
                update: @escaping (inout RealityViewCameraContent) -> Void = { _ in })
        where Content == EmptyView {
        var content = RealityViewCameraContent()
        update(&content)
    }
}

// MARK: - Entity-targeted gestures

/// What a targeted gesture hands back: the gesture's own value, plus the entity
/// it landed on and the means to put its location into scene space.
public struct EntityTargetValue<Value> {
    public var gestureValue: Value
    public var entity: Entity

    public init(gestureValue: Value, entity: Entity) {
        self.gestureValue = gestureValue
        self.entity = entity
    }

}

public struct TargetedGesture<G: SwiftUI.Gesture> {
    public typealias Value = EntityTargetValue<G.Value>
    public init() {}
    public func onChanged(_ action: @escaping (Value) -> Void) -> TargetedGesture<G> { self }
    public func onEnded(_ action: @escaping (Value) -> Void) -> TargetedGesture<G> { self }
}

public extension SwiftUI.Gesture {
    /// Restricts a gesture to entities carrying an `InputTargetComponent`, and
    /// tells the handler which one it hit.
    func targetedToAnyEntity() -> TargetedGesture<Self> { TargetedGesture<Self>() }
}

public extension EntityTargetValue where Value == SwiftUI.DragGesture.Value {
    var location: CGPoint { gestureValue.location }
}

public extension EntityTargetValue where Value == SwiftUI.SpatialTapGesture.Value {
    var location: CGPoint { gestureValue.location }
}
