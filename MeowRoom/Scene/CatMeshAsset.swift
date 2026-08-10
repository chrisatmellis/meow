import Foundation
import RealityKit

/// The one art asset in the game.
///
/// Everything else here is generated at runtime — the room, the textures, the
/// sounds, and until now the cat. This is a modelled cat, exported by
/// `Tools/usd/export-cat.py` from a USDZ with its texture coordinates added and
/// nothing else about it changed.
///
/// It arrives as a flat binary rather than as a USDZ the renderer loads, for one
/// reason: the coat. Every pattern, marking and material map in this game is
/// painted at runtime from ~70 appearance parameters and applied through UVs, and
/// the file had none — so the unwrap happens offline, deterministically, and what
/// ships is the result. Loading the USDZ directly would hand RealityKit the mesh
/// without them and give back one grey cat.
///
/// The format is deliberately dull: counts, then plain arrays, little-endian, no
/// compression. It parses in a couple of milliseconds, which is less than the
/// room's textures take to draw.
struct CatMeshAsset {

    /// The joints the animator knows how to drive.
    ///
    /// Order is the file format. Appending is safe, reordering is not.
    enum Role: Int, CaseIterable {
        case hips, spineBase, spineMid, chest, neck, head, jaw, earL, earR
        case tail0, tail1, tail2, tail3
        case foreHipL, foreKneeL, foreAnkleL, forePawL
        case hindHipL, hindKneeL, hindAnkleL, hindPawL
        case foreHipR, foreKneeR, foreAnkleR, forePawR
        case hindHipR, hindKneeR, hindAnkleR, hindPawR
        // Added once the export carried real bone names instead of guessing roles
        // from rest-pose geometry (see `Tools/usd/export-cat.py`). One joint
        // further out than the paw on each leg, the tongue, the clavicles, and
        // the shoulder-girdle spine joint the clavicles attach to.
        case foreToeL, foreToeR, hindToeL, hindToeR
        case tongueBase, tongueTip
        case clavicleL, clavicleR
        case shoulder
    }

    /// Geometry, in the game's renderer-free form, so everything downstream — the
    /// materials, the fur shells, the triangle budget, the offline rasteriser —
    /// treats it exactly like a generated mesh.
    let mesh: MeshData
    /// Per-vertex bone indices and weights, `influencesPerVertex` of each.
    let jointIndices: [UInt16]
    let jointWeights: [Float]
    let influencesPerVertex: Int
    /// Parent index per joint, -1 for the root.
    let parents: [Int]
    /// The bind pose: each joint's full transform in model space.
    ///
    /// The whole matrix, not just where the joint is. This skeleton's bind pose
    /// carries rotation — a couple of bones are flipped outright — so a joint's
    /// rest orientation is not the identity and cannot be recovered from its
    /// position. Skinning against a translation-only inverse bind matrix gives a
    /// cat that looks right in the bind pose and folds inside out on the first
    /// frame it is animated.
    let bind: [simd_float4x4]
    /// Joint index for each role, or -1 where the skeleton has no such joint.
    private let roleJoints: [Int]

    /// Where each joint sits in model space, metres.
    var restPositions: [SIMD3<Float>] {
        bind.map { SIMD3<Float>($0[3].x, $0[3].y, $0[3].z) }
    }

    /// A joint's transform relative to its parent in the bind pose.
    func restLocal(_ j: Int) -> simd_float4x4 {
        let p = parents[j]
        return p >= 0 ? bind[p].inverse * bind[j] : bind[j]
    }

    func joint(_ role: Role) -> Int? {
        let j = roleJoints[role.rawValue]
        return j >= 0 ? j : nil
    }

    var jointCount: Int { parents.count }

    /// The rest pose's own measurements, so an appearance can be scaled onto it
    /// rather than assumed to match.
    var restTorsoLength: Float {
        guard let hips = joint(.hips), let neck = joint(.neck) else { return 0.26 }
        return (restPositions[neck] - restPositions[hips]).length
    }

    var restShoulderHeight: Float {
        guard let chest = joint(.chest) else { return 0.22 }
        return restPositions[chest].y
    }

    // MARK: - Loading

    enum LoadError: Error { case missing, malformed }

    static func load(_ name: String = "cat", in bundle: Bundle = .main) throws -> CatMeshAsset {
        guard let url = bundle.url(forResource: name, withExtension: "catmesh") else {
            throw LoadError.missing
        }
        return try CatMeshAsset(data: try Data(contentsOf: url))
    }

    init(data: Data) throws {
        var at = 0

        func need(_ n: Int) throws {
            guard at + n <= data.count else { throw LoadError.malformed }
        }
        func u32() throws -> Int {
            try need(4)
            defer { at += 4 }
            return Int(UInt32(data[at]) | UInt32(data[at + 1]) << 8
                       | UInt32(data[at + 2]) << 16 | UInt32(data[at + 3]) << 24)
        }
        func u16() throws -> UInt16 {
            try need(2)
            defer { at += 2 }
            return UInt16(data[at]) | UInt16(data[at + 1]) << 8
        }
        func i16() throws -> Int {
            let raw = try u16()
            return Int(Int16(bitPattern: raw))
        }
        func f32() throws -> Float {
            try need(4)
            defer { at += 4 }
            let bits = UInt32(data[at]) | UInt32(data[at + 1]) << 8
                | UInt32(data[at + 2]) << 16 | UInt32(data[at + 3]) << 24
            return Float(bitPattern: bits)
        }

        try need(8)
        guard data[0..<8].elementsEqual("MEOWCAT2".utf8) else { throw LoadError.malformed }
        at = 8

        let vertexCount = try u32()
        let indexCount = try u32()
        let jointCount = try u32()
        influencesPerVertex = try u32()
        guard vertexCount > 0, indexCount % 3 == 0, jointCount > 0,
              influencesPerVertex > 0 else { throw LoadError.malformed }

        var positions: [Vec3] = []
        positions.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            positions.append(Vec3(x: try f32(), y: try f32(), z: try f32()))
        }
        var normals: [Vec3] = []
        normals.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            normals.append(Vec3(x: try f32(), y: try f32(), z: try f32()))
        }
        var uvs: [Vec2] = []
        uvs.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            uvs.append(Vec2(x: try f32(), y: try f32()))
        }
        var indices: [Int32] = []
        indices.reserveCapacity(indexCount)
        for _ in 0..<indexCount {
            let v = try u32()
            guard v < vertexCount else { throw LoadError.malformed }
            indices.append(Int32(v))
        }

        var ji: [UInt16] = []
        ji.reserveCapacity(vertexCount * influencesPerVertex)
        for _ in 0..<(vertexCount * influencesPerVertex) {
            let j = try u16()
            guard Int(j) < jointCount else { throw LoadError.malformed }
            ji.append(j)
        }
        var jw: [Float] = []
        jw.reserveCapacity(vertexCount * influencesPerVertex)
        for _ in 0..<(vertexCount * influencesPerVertex) { jw.append(try f32()) }

        var par: [Int] = []
        var binds: [simd_float4x4] = []
        for _ in 0..<jointCount {
            par.append(try i16())
            var m = matrix_identity_float4x4
            for c in 0..<4 {
                m[c] = SIMD4<Float>(try f32(), try f32(), try f32(), try f32())
            }
            binds.append(m)
        }

        let roleCount = try u32()
        var roles = [Int](repeating: -1, count: Role.allCases.count)
        for i in 0..<roleCount {
            let j = try i16()
            if i < roles.count { roles[i] = j }
        }

        mesh = MeshData(positions: positions, normals: normals, uvs: uvs, indices: indices)
        jointIndices = ji
        jointWeights = jw
        parents = par
        bind = binds
        roleJoints = roles
    }
}
