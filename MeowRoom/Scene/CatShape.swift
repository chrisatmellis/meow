import Foundation
import RealityKit

/// Turns one modelled cat into any cat the player can describe.
///
/// The mesh is a single skinned surface of a particular animal. The game offers
/// around seventy parameters — a Maine Coon and a Munchkin and a Sphynx are all
/// supposed to come out of it — so something has to stand between the file and
/// the scene. This is that something.
///
/// ## Two kinds of change, and why both are needed
///
/// **Bones move.** Leg length, tail length, body length, neck, ear angle: these
/// are joints in different places, and moving a joint drags the skin with it for
/// free, because the mesh is already bound to the skeleton. This is much the
/// better mechanism — it cannot tear the surface, it keeps the silhouette
/// coherent, and the animator goes on driving the same joints afterwards.
///
/// **Flesh swells.** Girth, chonk, chest depth, leg thickness, cheek fluff, the
/// bulk that long fur adds: no arrangement of joints expresses "the same cat, but
/// rounder". Those are radial displacements away from the bone, applied in the
/// bone's own frame so a thicker leg thickens across the leg rather than along
/// the world's X axis.
///
/// Both happen once, at build time, on the CPU, against plain arrays — so the
/// whole thing is exercised by the assertion suite on a machine with no graphics
/// framework, which is where a cat whose legs have come off its body is cheapest
/// to discover.
///
/// ## Why the bind pose has to be rebuilt too
///
/// Deforming the vertices and leaving the skeleton alone would put the skin in
/// one place and the joints that drive it in another: the first frame of
/// animation would snap the cat back. So the shaped skeleton *is* the new bind
/// pose, and the mesh is re-skinned into it by exactly the transform that took
/// each joint from where it was to where it now is.
enum CatShape {

    /// A cat, shaped. Everything downstream — the skinning, the rig, the
    /// animator — works from this and never sees the file it came from.
    struct Shaped {
        var mesh: MeshData
        /// The shaped bind pose, one world matrix per joint.
        var bind: [simd_float4x4]
        var parents: [Int]
        var jointIndices: [UInt16]
        var jointWeights: [Float]
        var influencesPerVertex: Int
        private var roleJoints: [Int]

        func joint(_ role: CatMeshAsset.Role) -> Int? {
            let j = roleJoints[role.rawValue]
            return j >= 0 ? j : nil
        }

        var jointCount: Int { parents.count }

        func position(_ j: Int) -> SIMD3<Float> {
            SIMD3<Float>(bind[j][3].x, bind[j][3].y, bind[j][3].z)
        }

        func position(_ role: CatMeshAsset.Role) -> SIMD3<Float>? {
            joint(role).map { position($0) }
        }

        /// The model-space box occupied by the flesh a set of bones carries.
        ///
        /// Bones say where joints are, not how big the animal is around them, and
        /// the difference is large: this skull's bone sits roughly 3.6 cm from the
        /// neck while the head it carries reaches 6 cm further forward. Features
        /// placed off the bone spacing end up inside the head — which is exactly
        /// where the first set of eyes and whiskers went.
        func extent(of roles: [CatMeshAsset.Role]) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
            let wanted = Set(roles.compactMap { joint($0) })
            guard !wanted.isEmpty else { return nil }
            var lo = SIMD3<Float>(repeating: .infinity)
            var hi = SIMD3<Float>(repeating: -.infinity)
            var found = false
            let n = influencesPerVertex
            for v in 0..<mesh.positions.count {
                // The bone that owns the vertex, not merely one that touches it,
                // so the neck's fringe does not stretch the head's box backwards.
                var bestW: Float = 0
                var best = -1
                for k in 0..<n where jointWeights[v * n + k] > bestW {
                    bestW = jointWeights[v * n + k]
                    best = Int(jointIndices[v * n + k])
                }
                guard wanted.contains(best) else { continue }
                let p = mesh.positions[v]
                lo = SIMD3<Float>(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = SIMD3<Float>(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
                found = true
            }
            return found ? (lo, hi) : nil
        }

        /// A joint's transform relative to its parent, which is what the rig
        /// hands the renderer as a rest pose.
        func restLocal(_ j: Int) -> simd_float4x4 {
            let p = parents[j]
            return p >= 0 ? bind[p].inverse * bind[j] : bind[j]
        }

        init(mesh: MeshData, bind: [simd_float4x4], parents: [Int],
             jointIndices: [UInt16], jointWeights: [Float],
             influencesPerVertex: Int, roleJoints: [Int]) {
            self.mesh = mesh
            self.bind = bind
            self.parents = parents
            self.jointIndices = jointIndices
            self.jointWeights = jointWeights
            self.influencesPerVertex = influencesPerVertex
            self.roleJoints = roleJoints
        }
    }

    // MARK: - The regions a parameter can talk about

    /// Which part of the animal a joint belongs to.
    ///
    /// Parameters are written in these terms — "thicker legs", "fluffier tail" —
    /// and a vertex belongs to a region as much as it is weighted to that
    /// region's bones. Blending by skin weight rather than by nearest bone is
    /// what stops a fat belly ending in a cliff at the ribcage.
    enum Region {
        case torso, neck, head, jaw, ear, tail, legUpper, legLower, paw
    }

    static func region(of joint: Int, in asset: CatMeshAsset) -> Region {
        func isRole(_ r: CatMeshAsset.Role) -> Bool { asset.joint(r) == joint }
        if isRole(.head) { return .head }
        if isRole(.jaw) { return .jaw }
        if isRole(.earL) || isRole(.earR) { return .ear }
        if isRole(.neck) { return .neck }
        for r in [CatMeshAsset.Role.tail0, .tail1, .tail2, .tail3] where isRole(r) { return .tail }
        for r in [CatMeshAsset.Role.foreHipL, .foreHipR, .hindHipL, .hindHipR,
                  .foreKneeL, .foreKneeR, .hindKneeL, .hindKneeR] where isRole(r) {
            return .legUpper
        }
        for r in [CatMeshAsset.Role.foreAnkleL, .foreAnkleR,
                  .hindAnkleL, .hindAnkleR] where isRole(r) { return .legLower }
        for r in [CatMeshAsset.Role.forePawL, .forePawR,
                  .hindPawL, .hindPawR] where isRole(r) { return .paw }
        return .torso
    }

    // MARK: - Shaping

    static func shape(_ asset: CatMeshAsset, to a: CatAppearance) -> Shaped {
        let n = asset.jointCount

        // --- 1. Where every joint should end up.
        //
        // Built top-down: a joint's new place is its parent's new place plus its
        // bone, stretched and turned. Doing it in that order is what makes a
        // longer thigh carry the shin, the paw and the toes with it instead of
        // leaving the leg in pieces.
        var localScale = [Float](repeating: 1, count: n)
        var localTurn = [simd_quatf](repeating: simd_quatf(), count: n)

        let boneStretch = boneScales(asset, a)
        for j in 0..<n {
            localScale[j] = boneStretch[j]
        }
        applyEarShape(asset, a, turn: &localTurn, stretch: &localScale)
        applyTailShape(asset, a, turn: &localTurn, stretch: &localScale)

        var bind = asset.bind
        for j in 0..<n {
            let p = asset.parents[j]
            guard p >= 0 else { continue }
            let restLocal = asset.restLocal(j)
            var local = restLocal
            // Stretch along the bone, which is wherever the joint sits relative
            // to its parent — not a nominated axis, because this skeleton's bind
            // rotations do not line its bones up with anything in particular.
            let t = SIMD3<Float>(local[3].x, local[3].y, local[3].z) * localScale[j]
            local[3] = SIMD4<Float>(t, 1)
            // `simd_float4x4(quaternion)`, not `quaternion.matrix`. The latter is
            // a stand-in invention and does not exist in Apple's simd — the sort
            // of thing that typechecks off-device and fails the moment a real
            // compiler sees it.
            bind[j] = bind[p] * simd_float4x4(localTurn[j]) * local
        }

        // Everything is measured from the pelvis, so a change of proportion does
        // not also move the animal.
        let uniform = overallScale(asset, a)
        if let hips = asset.joint(.hips) {
            let anchor = SIMD3<Float>(asset.bind[hips][3].x, asset.bind[hips][3].y,
                                      asset.bind[hips][3].z)
            for j in 0..<n {
                var m = bind[j]
                let p = SIMD3<Float>(m[3].x, m[3].y, m[3].z)
                m[3] = SIMD4<Float>(anchor + (p - anchor) * uniform, 1)
                bind[j] = m
            }
        }

        // --- 2. Carry the skin to the new skeleton.
        let mesh = reskin(asset, to: bind)

        // --- 3. Swell the flesh the bones cannot.
        inflate(asset, a, mesh: mesh, bind: bind)
        mesh.recomputeNormals()

        var roles = [Int](repeating: -1, count: CatMeshAsset.Role.allCases.count)
        for role in CatMeshAsset.Role.allCases {
            roles[role.rawValue] = asset.joint(role) ?? -1
        }
        return Shaped(mesh: mesh, bind: bind, parents: asset.parents,
                      jointIndices: asset.jointIndices, jointWeights: asset.jointWeights,
                      influencesPerVertex: asset.influencesPerVertex, roleJoints: roles)
    }

    // MARK: - Bone lengths

    /// How much longer or shorter each bone should be than the model's.
    private static func boneScales(_ asset: CatMeshAsset, _ a: CatAppearance) -> [Float] {
        var s = [Float](repeating: 1, count: asset.jointCount)

        func set(_ role: CatMeshAsset.Role, _ v: Float) {
            if let j = asset.joint(role) { s[j] = v }
        }

        // Legs. Munchkins are the reason this exists: the breed is short legs on
        // an otherwise ordinary cat, and no amount of texture says that.
        let leg = a.legHeight / max(1e-4, restLegHeight(asset))
        for r in [CatMeshAsset.Role.foreKneeL, .foreKneeR, .hindKneeL, .hindKneeR,
                  .foreAnkleL, .foreAnkleR, .hindAnkleL, .hindAnkleR] {
            set(r, leg)
        }
        // Paws scale on their own, so big feet do not mean long shins.
        let paw = 0.75 + 0.5 * a.pawSize
        for r in [CatMeshAsset.Role.forePawL, .forePawR, .hindPawL, .hindPawR] {
            set(r, paw)
        }

        // The torso between hips and neck. `bodyLength` and the body type move
        // this together; `torsoLength` already folds both in.
        let torso = a.torsoLength / max(1e-4, asset.restTorsoLength)
        for r in [CatMeshAsset.Role.spineBase, .spineMid, .chest] { set(r, torso) }

        // The neck, which is short on a cobby cat and long on an oriental one.
        set(.neck, 0.80 + 0.45 * a.bodyLength)

        // The head. A kitten's skull is nearly adult-sized on a small body, which
        // is most of why kittens read as kittens.
        set(.head, a.headRadius / max(1e-4, restHeadRadius(asset)))
        set(.jaw, 0.75 + 0.55 * a.muzzleLength)

        return s
    }

    private static func restLegHeight(_ asset: CatMeshAsset) -> Float {
        guard let hip = asset.joint(.hindHipL), let paw = asset.joint(.hindPawL) else { return 0.19 }
        return asset.restPositions[hip].y - asset.restPositions[paw].y
    }

    private static func restHeadRadius(_ asset: CatMeshAsset) -> Float {
        guard let head = asset.joint(.head), let neck = asset.joint(.neck) else { return 0.045 }
        return (asset.restPositions[head] - asset.restPositions[neck]).length
    }

    private static func overallScale(_ asset: CatMeshAsset, _ a: CatAppearance) -> Float {
        // The torso is already sized by its own bones, so this is only what is
        // left: the difference between a kitten and a cat, and the player's own
        // size slider.
        a.scale
    }

    // MARK: - Ears and tail

    private static func applyEarShape(_ asset: CatMeshAsset, _ a: CatAppearance,
                                      turn: inout [simd_quatf], stretch: inout [Float]) {
        let length = 0.6 + 0.9 * a.earLength
        // A folded ear tips forward from its base rather than shrinking, which is
        // what a Scottish Fold actually is.
        let fold = a.earFold * 1.15
        let tilt = (a.earTilt - 0.5) * 0.9
        for (role, side) in [(CatMeshAsset.Role.earL, Float(-1)), (.earR, 1)] {
            guard let j = asset.joint(role) else { continue }
            stretch[j] = length
            turn[j] = EulerRotation.quaternion(SIMD3<Float>(-fold, 0, side * tilt))
        }
    }

    private static func applyTailShape(_ asset: CatMeshAsset, _ a: CatAppearance,
                                       turn: inout [simd_quatf], stretch: inout [Float]) {
        let target = a.tailLengthMeters / max(1e-4, restTailLength(asset))
        let kink = a.tailKink
        let segments: [CatMeshAsset.Role] = [.tail0, .tail1, .tail2, .tail3]
        for (i, role) in segments.enumerated() {
            guard let j = asset.joint(role) else { continue }
            stretch[j] = target
            // A kinked tail bends more the further along it you go, which is where
            // the kink is on a Japanese Bobtail.
            if kink > 0.01 {
                let t = Float(i) / Float(max(1, segments.count - 1))
                turn[j] = EulerRotation.quaternion(SIMD3<Float>(kink * 0.9 * t * t, 0, 0))
            }
        }
    }

    private static func restTailLength(_ asset: CatMeshAsset) -> Float {
        guard let a0 = asset.joint(.tail0), let a3 = asset.joint(.tail3) else { return 0.24 }
        return (asset.restPositions[a3] - asset.restPositions[a0]).length
    }

    // MARK: - Re-skinning

    /// Moves every vertex by the same blend of bone motions that moved the
    /// skeleton — ordinary linear blend skinning, run once against the change of
    /// bind pose rather than every frame against an animation.
    private static func reskin(_ asset: CatMeshAsset, to bind: [simd_float4x4]) -> MeshData {
        var delta = [simd_float4x4](repeating: matrix_identity_float4x4, count: asset.jointCount)
        for j in 0..<asset.jointCount {
            delta[j] = bind[j] * asset.bind[j].inverse
        }

        let n = asset.influencesPerVertex
        var positions = asset.mesh.positions
        for v in 0..<positions.count {
            let p = SIMD4<Float>(positions[v].x, positions[v].y, positions[v].z, 1)
            var acc = SIMD4<Float>(repeating: 0)
            var total: Float = 0
            for k in 0..<n {
                let w = asset.jointWeights[v * n + k]
                guard w > 0 else { continue }
                acc += (delta[Int(asset.jointIndices[v * n + k])] * p) * w
                total += w
            }
            if total > 1e-5 {
                acc /= total
                positions[v] = Vec3(x: acc.x, y: acc.y, z: acc.z)
            }
        }
        return MeshData(positions: positions, normals: asset.mesh.normals,
                        uvs: asset.mesh.uvs, indices: asset.mesh.indices)
    }

    // MARK: - Girth

    /// Pushes vertices away from the bone that owns them.
    ///
    /// In the bone's own frame, so a thicker leg thickens across the leg. The
    /// amount is blended by skin weight, which is what makes a heavy cat's belly
    /// blend into its ribs rather than stop at them.
    private static func inflate(_ asset: CatMeshAsset, _ a: CatAppearance,
                                mesh: MeshData, bind: [simd_float4x4]) {
        // Fur adds real silhouette, and a hairless cat has none of it. This is the
        // one place `furLength` touches the shape rather than the texture.
        let coat = a.effectiveFurLength * 0.10 + a.effectiveFluff * 0.06

        func amount(for region: Region) -> Float {
            switch region {
            case .torso:
                return (a.bodyGirth - 0.5) * 0.30 + a.chonk * 0.34 + coat
            case .neck:
                return (a.neckThickness - 0.5) * 0.34 + coat
            case .head:
                return (a.headWidth - 0.5) * 0.26 + (a.cheekFluff - 0.2) * 0.28 + coat * 0.7
            case .jaw:
                return (a.muzzleWidth - 0.5) * 0.30 + (a.chinSize - 0.5) * 0.18
            case .ear:
                return (a.earWidth - 0.5) * 0.35
            case .tail:
                return (a.tailThickness - 0.5) * 0.40 + a.tailFluff * 0.55 + coat
            case .legUpper:
                return (a.legThickness - 0.5) * 0.34 + coat * 0.8
            case .legLower:
                return (a.legThickness - 0.5) * 0.26 + coat * 0.6
            case .paw:
                return (a.pawSize - 0.5) * 0.20 + a.toeTufts * 0.12
            }
        }

        // Chest depth and belly are the same swelling weighted by which way the
        // surface faces, so a deep-chested cat is deep rather than merely wide.
        let deepen = (a.chestDepth - 0.5) * 0.34

        var perJoint = [Float](repeating: 0, count: asset.jointCount)
        for j in 0..<asset.jointCount {
            perJoint[j] = amount(for: region(of: j, in: asset))
        }

        let n = asset.influencesPerVertex
        var positions = mesh.positions
        for v in 0..<positions.count {
            var swell: Float = 0
            var axisPoint = SIMD3<Float>(repeating: 0)
            var axisDir = SIMD3<Float>(repeating: 0)
            var total: Float = 0
            var torsoWeight: Float = 0
            for k in 0..<n {
                let w = asset.jointWeights[v * n + k]
                guard w > 0 else { continue }
                let j = Int(asset.jointIndices[v * n + k])
                swell += perJoint[j] * w
                axisPoint += SIMD3<Float>(bind[j][3].x, bind[j][3].y, bind[j][3].z) * w
                // The bone's own direction: toward its parent, which is the one
                // direction every joint has whatever its rotation happens to be.
                let p = asset.parents[j]
                if p >= 0 {
                    let d = SIMD3<Float>(bind[j][3].x - bind[p][3].x,
                                         bind[j][3].y - bind[p][3].y,
                                         bind[j][3].z - bind[p][3].z)
                    if d.length > 1e-6 { axisDir += d.normalized * w }
                }
                if region(of: j, in: asset) == .torso { torsoWeight += w }
                total += w
            }
            guard total > 1e-5 else { continue }
            swell /= total
            axisPoint /= total
            guard abs(swell) > 1e-5 || abs(deepen) > 1e-5 else { continue }

            let p = SIMD3<Float>(positions[v].x, positions[v].y, positions[v].z)
            var radial = p - axisPoint
            if axisDir.length > 1e-6 {
                let axis = axisDir.normalized
                radial -= axis * dot(radial, axis)
            }
            guard radial.length > 1e-6 else { continue }

            // A deep chest is taller, not wider, so it only follows the vertical
            // part of the radius — and only on the torso.
            let vertical = radial.normalized.y
            let extra = deepen * (torsoWeight / total) * vertical * vertical
                * (vertical > 0 ? 0.55 : 1.0)
            positions[v] = Vec3(x: p.x, y: p.y, z: p.z) + Vec3(
                x: radial.x, y: radial.y, z: radial.z) * (swell + extra)
        }
        mesh.replacePositions(positions)
    }
}
