import Foundation
import RealityKit
import UIKit

/// Builds the cat from the modelled mesh instead of from lofts.
///
/// The rig it hands back is the same `CatRig` the procedural builder produces, so
/// `CatAnimator` does not know or care which one it is driving. That is the whole
/// design: the animator's gait, its inverse kinematics, its gaze and its ear
/// flicks are the part of this game that took the longest to get right, and none
/// of it is about how the geometry was made.
///
/// ## One skinned mesh, and a skeleton of entities beside it
///
/// The procedural cat is thirty-odd separate meshes parented to each other, so
/// posing it *is* moving the scene graph. A skinned mesh is one surface bound to a
/// skeleton, and RealityKit poses it through `SkeletalPosesComponent` — an array
/// of joint transforms, not a hierarchy.
///
/// Rather than teach the animator that difference, this builds an ordinary entity
/// per joint, parented exactly as the skeleton is. The animator drives those, and
/// once per frame their local transforms are copied into the pose array. The
/// animator keeps writing `eulerAngles` on something called `rig.head`, and the
/// fact that the head is now a bone rather than a mesh never reaches it.
enum ModelCatBuilder {

    /// Loaded once. The file is 141 KB and parsing it is cheap, but the character
    /// creator rebuilds the cat on every slider drag.
    private static var cached: CatMeshAsset?

    static func asset() -> CatMeshAsset? {
        if let cached { return cached }
        cached = try? CatMeshAsset.load()
        return cached
    }

    /// - Parameter using: the asset to build from. Defaults to the one in the
    ///   bundle; the assertion suite runs on a machine that has no bundle and
    ///   reads the file straight off disk instead, which is the only reason this
    ///   is a parameter at all.
    static func build(_ a: CatAppearance, preview: Bool = false,
                      using supplied: CatMeshAsset? = nil) -> CatRig? {
        guard let asset = supplied ?? asset() else { return nil }
        let rig = CatRig(appearance: a)

        // --- Proportions.
        //
        // The mesh is one cat and the game has seventy parameters describing
        // others. The ones that are texture — every pattern, every colour — apply
        // untouched. The ones that are shape apply here instead, as a scale on the
        // whole animal, because a bone that is scaled is still a bone the animator
        // can bend, where a vertex that has been moved is a different mesh.
        //
        // Deliberately uniform. Stretching a skinned cat along one axis and not
        // the others makes its legs into ovals in cross-section, which is worse
        // than the cat simply being the wrong length.
        let restTorso = asset.restTorsoLength
        let scale = restTorso > 1e-4 ? a.torsoLength / restTorso : 1
        rig.torsoLength = a.torsoLength
        rig.torsoRadius = a.torsoRadius

        // --- Which way is forward.
        //
        // The model was authored facing +X with the floor at y = 0. The game's
        // body space faces +Z, and its origin is at the hips with the floor at
        // -bodyHeight, because that is what `CatAnimator` measures its leg reach
        // against.
        //
        // Turning +X into +Z is a quarter turn about Y, and it has to be the turn
        // that lands the cat's *right* side on +X, since `LegRig.side` is +1 for
        // the right and the animator leans the body into a turn accordingly. Of
        // the two quarter turns only one faces the cat forward, so handedness is
        // not a free choice: it comes out that the model's +Z is the cat's left,
        // whatever the exporter's role names happen to say. Sides are therefore
        // taken from where a leg actually ends up rather than from its name — a
        // symmetric cat hides a left/right swap perfectly until it starts walking.
        let hipHeight = asset.joint(.hips).map { asset.restPositions[$0].y } ?? 0.2
        rig.bodyHeight = hipHeight * scale
        func toGame(_ p: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3<Float>(-p.z, p.y - hipHeight, p.x) * scale
        }

        // --- A joint hierarchy the animator can pose.
        //
        // The joints stay in the model's own axes and the wrapper turns the lot,
        // so the skinning matrices below never have to know about any of this.
        // The frame carries the scale as well as the turn, so the mesh and the
        // skeleton stay in the model's own metres and agree with each other. The
        // skin is posed from the joints' *local* transforms, which do not include
        // anything above the root joint — so a scale applied to the joints and not
        // to the mesh would tear the two apart the moment either moved.
        let frame = Entity()
        frame.eulerAngles = SIMD3<Float>(0, -.pi / 2, 0)
        frame.scale = SIMD3<Float>(repeating: scale)
        frame.position = SIMD3<Float>(0, -hipHeight * scale, 0)

        var joints: [Entity] = (0..<asset.jointCount).map { _ in Entity() }
        for j in 0..<asset.jointCount {
            let parent = asset.parents[j]
            let restLocal = parent >= 0
                ? asset.restPositions[j] - asset.restPositions[parent]
                : asset.restPositions[j]
            joints[j].position = restLocal
            joints[j].name = "joint\(j)"
            if parent >= 0 {
                joints[parent].addChild(joints[j])
            }
        }

        // --- Wire the roles the animator addresses by name.
        func entity(_ role: CatMeshAsset.Role) -> Entity? {
            asset.joint(role).map { joints[$0] }
        }

        rig.root.addChild(rig.body)
        rig.body.addChild(frame)
        if let hips = entity(.hips) {
            frame.addChild(hips)
        }
        // `spine` and `neck` are what the animator pitches and turns; on this
        // skeleton those are real vertebrae rather than the whole torso.
        rig.spine = entity(.spineMid) ?? entity(.spineBase) ?? rig.spine
        rig.neck = entity(.neck) ?? rig.neck
        rig.head = entity(.head) ?? rig.head
        rig.jaw = entity(.jaw) ?? rig.jaw
        rig.earL = entity(.earL) ?? rig.earL
        rig.earR = entity(.earR) ?? rig.earR
        rig.chestNode = entity(.chest) ?? rig.chestNode
        rig.tailSegments = [entity(.tail0), entity(.tail1), entity(.tail2), entity(.tail3)]
            .compactMap { $0 }
        if let base = rig.tailSegments.first {
            rig.tailRoot = base
            rig.tailPitch = base
        }

        // --- Legs, in the order the animator expects: front left, front right,
        // back left, back right. Side is -1 for the cat's left.
        let limbs: [(CatMeshAsset.Role, CatMeshAsset.Role, CatMeshAsset.Role,
                     CatMeshAsset.Role, Bool)] = [
            (.foreHipL, .foreKneeL, .foreAnkleL, .forePawL, true),
            (.foreHipR, .foreKneeR, .foreAnkleR, .forePawR, true),
            (.hindHipL, .hindKneeL, .hindAnkleL, .hindPawL, false),
            (.hindHipR, .hindKneeR, .hindAnkleR, .hindPawR, false),
        ]
        rig.legs = limbs.compactMap { hipR, kneeR, ankleR, pawR, isFront -> LegRig? in
            guard let hip = entity(hipR), let knee = entity(kneeR),
                  let ankle = entity(ankleR), let paw = entity(pawR),
                  let hipJ = asset.joint(hipR), let kneeJ = asset.joint(kneeR),
                  let ankleJ = asset.joint(ankleR), let pawJ = asset.joint(pawR)
            else { return nil }
            var leg = LegRig()
            leg.hip = hip
            leg.knee = knee
            leg.ankle = ankle
            leg.paw = paw
            leg.isFront = isFront
            leg.side = toGame(asset.restPositions[hipJ]).x < 0 ? -1 : 1
            leg.upperLength = (asset.restPositions[kneeJ] - asset.restPositions[hipJ]).length * scale
            leg.lowerLength = (asset.restPositions[ankleJ] - asset.restPositions[kneeJ]).length * scale
            leg.pawLength = (asset.restPositions[pawJ] - asset.restPositions[ankleJ]).length * scale
            // Where the foot sits when the cat is standing still, in body space,
            // with the sole on the floor rather than the ankle joint.
            let rest = toGame(asset.restPositions[pawJ])
            leg.restFoot = SIMD3<Float>(rest.x, -rig.bodyHeight, rest.z)
            // Diagonally opposite feet move together, which is what makes a walk
            // read as a walk rather than as a shuffle. Same pairing the generated
            // cat uses, so a gait tuned against one still reads on the other.
            leg.gaitPhase = (isFront == (leg.side < 0)) ? 0.0 : 0.5
            leg.bendSign = isFront ? 1 : -1
            return leg
        }

        // --- The surface, bound to those joints.
        let material = Materials.catFur(a, preview: preview)
        let body = Entity.make(asset.mesh, material, name: "catBody")
        if let model = (body as? ModelEntity)?.model,
           let skinned = skin(asset, mesh: model.mesh) {
            (body as? ModelEntity)?.model = ModelComponent(mesh: skinned, materials: [material])
            body.components.set(SkeletalPosesComponent(poses: [
                SkeletalPose(id: "cat", joints: (0..<asset.jointCount).map {
                    ("joint\($0)", joints[$0].transform)
                })
            ]))
        }
        // Under the frame, not under the body: the mesh has to take the same turn
        // and the same scale as the skeleton it is bound to. Attaching it a level
        // higher left the cat lying along the wrong axis, at the wrong size,
        // floating a quarter of a metre off the tatami — which is exactly what the
        // offline render showed before this line moved.
        frame.addChild(body)
        rig.skinnedBody = body
        rig.skinJoints = joints

        return rig
    }

    /// Rebuilds the mesh resource with a skeleton and per-vertex influences.
    private static func skin(_ asset: CatMeshAsset, mesh: MeshResource) -> MeshResource? {
        var contents = mesh.contents
        guard var model = contents.models.first, var part = model.parts.first else { return nil }

        let joints = (0..<asset.jointCount).map { j -> MeshResource.Joint in
            let rest = asset.restPositions[j]
            let parent = asset.parents[j]
            let local = parent >= 0 ? rest - asset.restPositions[parent] : rest
            // The inverse bind matrix undoes the joint's rest pose, which for a
            // skeleton with no rotation in its bind pose is a plain translation.
            var inverseBind = matrix_identity_float4x4
            inverseBind[3] = SIMD4<Float>(-rest.x, -rest.y, -rest.z, 1)
            return MeshResource.Joint(
                name: "joint\(j)",
                parentIndex: parent >= 0 ? parent : nil,
                inverseBindPoseMatrix: inverseBind,
                restPoseTransform: Transform(translation: local))
        }

        let n = asset.influencesPerVertex
        var influences: [MeshJointInfluence] = []
        influences.reserveCapacity(asset.mesh.positions.count * n)
        for v in 0..<asset.mesh.positions.count {
            for k in 0..<n {
                influences.append(MeshJointInfluence(
                    jointIndex: Int(asset.jointIndices[v * n + k]),
                    weight: asset.jointWeights[v * n + k]))
            }
        }

        part.skeletonID = "cat"
        part.jointInfluences = MeshResource.JointInfluences(influences: influences,
                                                            influencesPerVertex: n)
        model.parts = [part]
        contents.models = [model]
        contents.skeletons = [MeshResource.Skeleton(id: "cat", joints: joints)]
        guard let skinned = try? MeshResource.generate(from: contents) else { return nil }
        #if DEBUG
        // Rebinding the mesh replaces the resource, and with it the registry entry
        // the offline renderer looks the buffers up by — so the cat silently
        // rendered as nothing at all. It draws the bind pose rather than the
        // skinned one, which is the honest limit of a rasteriser that does not
        // skin, and is still the difference between seeing the cat and not.
        MeshSourceRegistry.record(skinned, asset.mesh)
        #endif
        return skinned
    }

    /// Copies the posed joint hierarchy into the skinned mesh.
    ///
    /// Called once per frame after the animator has run. Reading the entities
    /// back rather than having the animator write the pose directly is what keeps
    /// the animator ignorant of skinning — and it costs one array of thirty-six
    /// transforms, which is nothing next to what it just spent computing them.
    static func syncPose(_ rig: CatRig) {
        guard let body = rig.skinnedBody, !rig.skinJoints.isEmpty else { return }
        body.components.set(SkeletalPosesComponent(poses: [
            SkeletalPose(id: "cat", joints: rig.skinJoints.enumerated().map {
                ("joint\($0.offset)", $0.element.transform)
            })
        ]))
    }
}
