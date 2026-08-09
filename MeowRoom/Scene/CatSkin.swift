import Foundation
import RealityKit

/// Deforms the cat's surface to match its skeleton, on the CPU, once a frame.
///
/// ## Why not the GPU
///
/// RealityKit will do this: a `MeshResource.Skeleton` on the mesh, per-vertex
/// `jointInfluences`, and a `SkeletalPosesComponent` on the entity. That was the
/// first implementation and it did not work — on device the cat drew as a small
/// crumpled clump at the skeleton's origin, every vertex pulled toward one point,
/// which is what you get when the inverse bind matrices are applied and the joint
/// transforms are not. The same pose, run through the same arithmetic here,
/// produces a cat; so the fault is in how the pose reaches RealityKit's skinning,
/// somewhere in an API surface that is a year old, sparsely documented, and
/// impossible to step through from this side of the fence.
///
/// It is not worth finding out. The cat is about two thousand vertices — blending
/// them costs well under a tenth of a millisecond, against a frame budget of
/// eight — and doing it here buys something the GPU path cannot: the offline
/// rasteriser draws the very same buffers, so a picture of the cat is now a
/// picture of what the phone will draw, and the assertion suite exercises the
/// code that actually ships rather than a stand-in for it. The bug that started
/// this was invisible for exactly that reason.
///
/// If the skinning ever costs enough to matter, `LowLevelMesh` is the next step
/// and this class is the thing that fills it.
final class CatSkin {
    /// The surface as modelled, which every frame is computed from afresh. Skinning
    /// is not incremental — blending yesterday's pose into today's compounds.
    private let restPositions: [SIMD3<Float>]
    private let restNormals: [SIMD3<Float>]
    /// Where each joint sits at rest. The inverse bind matrix, in the only form it
    /// takes here: the skeleton has no rest rotations, so binding is a subtraction.
    private let restJoints: [SIMD3<Float>]
    private let parents: [Int]
    private let jointIndices: [UInt16]
    private let jointWeights: [Float]
    private let influencesPerVertex: Int

    /// The live buffers, handed to RealityKit and read by the offline renderer.
    private let mesh: MeshData
    private weak var entity: ModelEntity?

    #if DEBUG
    /// What the last pose put into the blend, for the on-screen diagnostic.
    private(set) var report = ""
    #endif

    /// Scratch, kept between frames so a pose costs no allocation.
    private var posed: [Vec3]
    private var normals: [Vec3]
    private var skin: [simd_float4x4]

    init?(_ shaped: CatShape.Shaped, mesh: MeshData, entity: Entity) {
        guard let model = entity as? ModelEntity,
              mesh.positions.count == shaped.mesh.positions.count else { return nil }
        self.mesh = mesh
        self.entity = model
        restPositions = mesh.positions.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        restNormals = mesh.normals.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        restJoints = shaped.rest
        parents = shaped.parents
        jointIndices = shaped.jointIndices
        jointWeights = shaped.jointWeights
        influencesPerVertex = shaped.influencesPerVertex
        posed = mesh.positions
        normals = mesh.normals
        skin = [simd_float4x4](repeating: matrix_identity_float4x4, count: shaped.jointCount)
    }

    /// Poses the surface to match the joint entities.
    ///
    /// - Parameter joints: one entity per joint, parented as the skeleton is.
    func apply(_ joints: [Entity]) {
        guard joints.count == parents.count else { return }

        // Each joint's transform relative to the cat's body, accumulated in one
        // pass — joints are stored parents-first, so a parent is always ready by
        // the time its children are reached.
        for j in 0..<joints.count {
            var m = joints[j].transform.matrix
            if parents[j] >= 0 { m = skin[parents[j]] * m }
            skin[j] = m
        }
        #if DEBUG
        // What the accumulation actually saw. The offline harness runs this same
        // code and produces a cat; the device produces a five-centimetre knot, so
        // the numbers that go into it are the thing to look at rather than the
        // picture that comes out.
        var maxLocal: Float = 0, maxWorld: Float = 0, maxRest: Float = 0
        for j in 0..<joints.count {
            maxLocal = max(maxLocal, simd_length(joints[j].transform.translation))
            maxWorld = max(maxWorld, simd_length(SIMD3<Float>(skin[j][3].x, skin[j][3].y, skin[j][3].z)))
            maxRest = max(maxRest, simd_length(restJoints[j]))
        }
        report = String(format: "local %.3f · world %.3f · rest %.3f · n %d",
                        maxLocal, maxWorld, maxRest, joints.count)
        #endif

        // Then composed with the bind, which for a skeleton of points is the
        // subtraction of where the joint started: `world · translate(-rest)`,
        // whose translation is `t - R·rest` and not `t + R·rest`. The rotation is
        // applied to the offset with w = 0 so it carries no translation of its own.
        for j in 0..<skin.count {
            let t = skin[j][3]
            let shift = skin[j] * SIMD4<Float>(-restJoints[j], 0)
            skin[j][3] = SIMD4<Float>(t.x + shift.x, t.y + shift.y, t.z + shift.z, 1)
        }

        let n = influencesPerVertex
        for v in 0..<restPositions.count {
            let p = SIMD4<Float>(restPositions[v], 1)
            let nrm = restNormals[v]
            var accP = SIMD3<Float>.zero
            var accN = SIMD3<Float>.zero
            var total: Float = 0
            for k in 0..<n {
                let w = jointWeights[v * n + k]
                guard w > 0 else { continue }
                let m = skin[Int(jointIndices[v * n + k])]
                let q = m * p
                accP += SIMD3<Float>(q.x, q.y, q.z) * w
                // The rotation alone for the normal. Every one of these is rigid —
                // nothing scales a joint — so there is no inverse transpose to take.
                accN += (SIMD3<Float>(m[0].x, m[0].y, m[0].z) * nrm.x
                         + SIMD3<Float>(m[1].x, m[1].y, m[1].z) * nrm.y
                         + SIMD3<Float>(m[2].x, m[2].y, m[2].z) * nrm.z) * w
                total += w
            }
            if total > 1e-5 {
                accP /= total
                posed[v] = Vec3(x: accP.x, y: accP.y, z: accP.z)
                let len = simd_length(accN)
                let out = len > 1e-6 ? accN / len : nrm
                normals[v] = Vec3(x: out.x, y: out.y, z: out.z)
            } else {
                posed[v] = Vec3(x: restPositions[v].x, y: restPositions[v].y, z: restPositions[v].z)
                normals[v] = Vec3(x: nrm.x, y: nrm.y, z: nrm.z)
            }
        }

        mesh.replacePositions(posed)
        mesh.replaceNormals(normals)
        push()
    }

    /// Hands the new vertices to the resource already on screen.
    ///
    /// `replace` rather than a fresh `MeshResource`: the triangles, the texture
    /// coordinates and the material bindings are all unchanged, and rebuilding
    /// them sixty times a second would allocate GPU buffers for no reason.
    private func push() {
        guard let resource = entity?.model?.mesh else { return }
        var contents = resource.contents
        guard var model = contents.models.first, var part = model.parts.first else { return }
        part.positions = MeshBuffers.Positions(posed.map { SIMD3<Float>($0.x, $0.y, $0.z) })
        part.normals = MeshBuffers.Normals(normals.map { SIMD3<Float>($0.x, $0.y, $0.z) })
        // One part, because the cat is one material. Written as a literal for the
        // same reason the rest of this file is: it is a spelling the compiler on
        // the other side has already accepted.
        model.parts = [part]
        contents.models = [model]
        try? resource.replace(with: contents)
    }
}
