import Foundation
import RealityKit
import UIKit

/// Builds the cat.
///
/// One modelled body, shaped by `CatShape` into whatever the player asked for,
/// plus the handful of features a single closed surface cannot carry: eyes that
/// blink, whiskers, a collar, and fur shells for the long-haired breeds.
///
/// ## What is modelled and what is generated
///
/// The body is the model — one skinned mesh, deformed at build time by the
/// appearance parameters and then driven by the skeleton it came with. There is
/// no second cat. What is still generated is what the model does not contain:
/// it has no eyeballs (its eyes are geometry-less, meant to be painted), no
/// whiskers, and obviously no collar. Those are small, they are already
/// parameterised, and they attach to the bones the exporter named.
///
/// The mouth needs nothing. The model's head is closed, so opening the jaw
/// stretches the skin over it rather than revealing a hole — which is why the
/// oral cavity the generated cat needed has no counterpart here.
enum CatBuilder {

    static func build(_ a: CatAppearance, preview: Bool = false) -> CatRig {
        guard let asset = CatAsset.shared else { return CatRig(appearance: a) }
        return build(a, preview: preview, using: asset)
    }

    static func build(_ a: CatAppearance, preview: Bool = false,
                      using asset: CatMeshAsset) -> CatRig {
        let rig = CatRig(appearance: a)
        let shaped = CatShape.shape(asset, to: a)

        rig.torsoLength = a.torsoLength
        rig.torsoRadius = a.torsoRadius

        // `CatShape` has already put the mesh and the skeleton in body space —
        // facing +Z, hips at y = 0, floor at -bodyHeight — so there is no frame
        // entity here and nothing left to turn.
        rig.bodyHeight = shaped.hipHeight
        rig.root.addChild(rig.body)

        // --- One entity per bone, for the animator to pose.
        //
        // A skinned mesh has no scene graph to move; RealityKit poses it through
        // an array of joint transforms. Giving every joint an ordinary entity,
        // parented exactly as the skeleton is, means the animator can go on
        // writing `rig.head.eulerAngles` and never learn the difference. The pose
        // is copied across once a frame, after it has run.
        //
        // Each one starts at its offset from its parent and unrotated, which is
        // what makes `eulerAngles.x` a pitch on every bone rather than a turn
        // about whichever axis the exporter left that bone on.
        let joints: [Entity] = (0..<shaped.jointCount).map { _ in Entity() }
        for j in 0..<shaped.jointCount {
            joints[j].name = "joint\(j)"
            joints[j].position = shaped.restLocal(j)
            if shaped.parents[j] >= 0 {
                joints[shaped.parents[j]].addChild(joints[j])
            } else {
                rig.body.addChild(joints[j])
            }
        }
        func bone(_ role: CatMeshAsset.Role) -> Entity? {
            shaped.joint(role).map { joints[$0] }
        }

        rig.spine = bone(.spineMid) ?? bone(.spineBase) ?? rig.spine
        rig.neck = bone(.neck) ?? rig.neck
        rig.head = bone(.head) ?? rig.head
        rig.jaw = bone(.jaw) ?? rig.jaw
        // Left and right taken from where the ears are, not from the names they
        // were exported with: the model's own sides come out mirrored once it
        // faces the right way, and nothing symmetric ever shows it.
        let ears = [bone(.earL), bone(.earR)].compactMap { $0 }
        if ears.count == 2 {
            let left = (shaped.position(shaped.joint(.earL)!).x > 0) ? ears[0] : ears[1]
            rig.earL = left
            rig.earR = left === ears[0] ? ears[1] : ears[0]
        }
        rig.chestNode = bone(.chest) ?? rig.chestNode
        rig.chestRest = rig.chestNode.position
        rig.bellyNode = bone(.spineBase) ?? rig.bellyNode
        rig.tailSegments = [bone(.tail0), bone(.tail1), bone(.tail2), bone(.tail3)]
            .compactMap { $0 }
        if let base = rig.tailSegments.first {
            rig.tailRoot = base
            rig.tailPitch = base
        }

        // --- Legs.
        let limbs: [(CatMeshAsset.Role, CatMeshAsset.Role, CatMeshAsset.Role,
                     CatMeshAsset.Role, Bool)] = [
            (.foreHipL, .foreKneeL, .foreAnkleL, .forePawL, true),
            (.foreHipR, .foreKneeR, .foreAnkleR, .forePawR, true),
            (.hindHipL, .hindKneeL, .hindAnkleL, .hindPawL, false),
            (.hindHipR, .hindKneeR, .hindAnkleR, .hindPawR, false),
        ]
        rig.legs = limbs.compactMap { hipR, kneeR, ankleR, pawR, isFront -> LegRig? in
            guard let hipJ = shaped.joint(hipR), let kneeJ = shaped.joint(kneeR),
                  let ankleJ = shaped.joint(ankleR), let pawJ = shaped.joint(pawR)
            else { return nil }
            var leg = LegRig()
            leg.hip = joints[hipJ]
            leg.knee = joints[kneeJ]
            leg.ankle = joints[ankleJ]
            leg.paw = joints[pawJ]
            leg.isFront = isFront
            // Taken from where the leg actually ends up, not from its exported
            // name. The model's own left and right come out mirrored once it is
            // turned to face the right way, and a symmetric cat hides that
            // perfectly until it starts walking.
            leg.side = shaped.position(hipJ).x < 0 ? -1 : 1
            leg.upperLength = (shaped.position(kneeJ) - shaped.position(hipJ)).length
            leg.lowerLength = (shaped.position(ankleJ) - shaped.position(kneeJ)).length
            leg.pawLength = (shaped.position(pawJ) - shaped.position(ankleJ)).length
            let foot = shaped.position(pawJ)
            leg.restFoot = SIMD3<Float>(foot.x, -rig.bodyHeight, foot.z)
            leg.restHip = shaped.position(hipJ)
            // Diagonally opposite feet move together, which is what makes a walk
            // read as a trot rather than as a shuffle.
            leg.gaitPhase = (isFront == (leg.side < 0)) ? 0 : 0.5
            leg.bendSign = isFront ? 1 : -1
            return leg
        }

        // --- The body surface, bound to those bones.
        let furMat = Materials.catFur(a, preview: preview)
        let body = Entity.make(shaped.mesh, furMat, name: "catBody")
        if let model = (body as? ModelEntity)?.model,
           let skinned = skinned(shaped, mesh: model.mesh) {
            (body as? ModelEntity)?.model = ModelComponent(mesh: skinned, materials: [furMat])
        }
        rig.body.addChild(body)
        rig.skinnedBody = body
        rig.skinJoints = joints
        syncPose(rig)

        // --- Fur shells: offset copies of the same surface, for long coats.
        if !a.hairless, a.effectiveFurLength > 0.30, RenderQuality.maxFurShells > 0 {
            let layers = min(RenderQuality.maxFurShells, a.effectiveFurLength > 0.65 ? 2 : 1)
            for i in 0..<layers {
                let depth = (0.004 + 0.009 * a.effectiveFurLength) * Float(i + 1)
                let shell = shaped.mesh.offsetAlongNormals(depth)
                // Offset along the surface normal rather than scaled about an
                // origin: the cat's origin is at its pelvis, so a uniform scale
                // gives a centimetre of "fur" at the nose and none at the hips,
                // and slides the shell's texture off the hairs painted underneath.
                let node = Entity.make(shell, Materials.furShell(a, layer: i), name: "furShell")
                // Bound to the same skeleton as the coat underneath. A shell is a
                // copy of the body's vertices, one per vertex and in the same
                // order, so it takes the same influences — and without them it
                // would hang in the bind pose while the cat walked out of it.
                if let model = (node as? ModelEntity)?.model,
                   let skinnedShell = skinned(shaped, mesh: model.mesh) {
                    (node as? ModelEntity)?.model =
                        ModelComponent(mesh: skinnedShell,
                                       materials: [Materials.furShell(a, layer: i)])
                }
                rig.body.addChild(node)
                rig.skinnedShells.append(node)
            }
        }

        addFace(rig, a, shaped: shaped, joints: joints, preview: preview)
        addCollar(rig, a, shaped: shaped, joints: joints)
        return rig
    }

    // MARK: - Face

    /// Eyes, lids and whiskers, attached to the skull bone.
    ///
    /// The model has no eyeballs at all — its eyes are painted-in geometry, which
    /// is fine for a still and useless for a cat that blinks, dilates and looks at
    /// where the wand is. So they are generated, sized from the head the shaping
    /// pass produced rather than from a constant, and hung on the bone so they
    /// follow the head however it moves.
    private static func addFace(_ rig: CatRig, _ a: CatAppearance,
                                shaped: CatShape.Shaped, joints: [Entity], preview: Bool) {
        guard let headJ = shaped.joint(.head) else { return }
        let head = joints[headJ]

        // Everything below is placed in body space: forward is +Z, up is +Y, and
        // +X is the cat's left. The joints have no rest orientation of their own,
        // so a child hung on a bone is already in those axes and there is no
        // frame conversion to get wrong — which there was, and which grew the
        // whiskers out of the top of the skull pointing backwards.

        // How big the head actually came out — measured off the flesh the skull
        // and jaw carry, not off the gap between their joints. Those are very
        // different numbers here: the bones are 3.6 cm apart and the head reaches
        // 6 cm further forward than that, so features sized from bone spacing end
        // up inside the cat.
        let box = shaped.extent(of: [.head, .jaw])
        let headMin = box?.min ?? (shaped.position(headJ) - SIMD3<Float>(repeating: a.headRadius))
        let headMax = box?.max ?? (shaped.position(headJ) + SIMD3<Float>(repeating: a.headRadius))
        let headCentre = (headMin + headMax) * 0.5
        let hr = max(0.012, (headMax.y - headMin.y) * 0.5)
        /// Somewhere on the head, in fractions of its own box: +1 is the tip of
        /// the nose, -1 the back of the skull, and the same for up and across —
        /// across being toward the cat's left.
        func onHead(_ forward: Float, _ up: Float, _ across: Float) -> SIMD3<Float> {
            SIMD3<Float>(headCentre.x + (headMax.x - headMin.x) * 0.5 * across,
                         headCentre.y + (headMax.y - headMin.y) * 0.5 * up,
                         headCentre.z + (headMax.z - headMin.z) * 0.5 * forward)
                - shaped.position(headJ)
        }
        // `hr` is half the height of the whole head, jaw included — about 4.5 cm
        // on an adult — so the fractions below are small. They used to be three
        // times larger, inherited from a generated cat whose "head radius" was a
        // parameter rather than a measurement, and produced a 3.5 cm eyeball on
        // an 8 cm head: two spheres meeting in the middle of the muzzle.
        let eyeR = hr * (0.12 + 0.07 * a.eyeSize)
        // `side` is which way along X, so +1 is the cat's left.
        for side in [Float(-1), 1] {
            let socket = Entity()
            socket.position = onHead(0.44, 0.30, side * (0.30 + 0.34 * a.eyeSpacing))
            // The eye is built around +Z, which is already where it looks, so all
            // that is left is the tilt at the outer corner — a roll about the
            // direction of sight.
            socket.orientation = EulerRotation.quaternion(
                SIMD3<Float>(0, 0, -side * deg(mix(-6, 20, a.eyeTilt))))
            head.addChild(socket)

            let ball = MeshBuilder.sphere(radius: eyeR, segments: 16)
            let ballMat = Materials.pbr(color: RGBColor(repeating: 0.10 + 0.25 * a.scleraTint),
                                        roughness: 0.05)
            socket.addChild(Entity.make(ball, ballMat, name: "eyeball"))

            // The socket already faces the way the eye looks, so the cap — which
            // is built around +Z — needs no turn of its own.
            let iris = Entity.make(cap(radius: eyeR * 1.02, angle: deg(62)),
                                   Materials.eye(a, right: side < 0), name: "iris")
            socket.addChild(iris)

            // Lids, which are what actually blink. Fur-coloured caps a little
            // larger than the eye, swinging shut from above and below.
            let furMat = Materials.catFur(a, preview: preview)
            let upper = Entity.make(cap(radius: eyeR * 1.10, angle: deg(74)), furMat, name: "lidUpper")
            upper.eulerAngles = SIMD3<Float>(deg(-90), 0, 0)
            socket.addChild(upper)
            let lower = Entity.make(cap(radius: eyeR * 1.10, angle: deg(66)), furMat, name: "lidLower")
            lower.eulerAngles = SIMD3<Float>(deg(90), 0, 0)
            socket.addChild(lower)

            switch a.eyeShape {
            case .almond: socket.scale = SIMD3<Float>(1.0, 0.88, 1.0)
            case .oriental: socket.scale = SIMD3<Float>(1.0, 0.80, 1.05)
            case .hooded: socket.scale = SIMD3<Float>(1.0, 0.84, 0.98)
            default: break
            }

            if side > 0 {
                rig.eyeL = socket; rig.lidUpperL = upper; rig.lidLowerL = lower
            } else {
                rig.eyeR = socket; rig.lidUpperR = upper; rig.lidLowerR = lower
            }
        }

        // Inner ears and a nose.
        //
        // The model's ears are solid and its nose is painted, so the two parts of
        // a cat that visibly light up from behind cannot. `Translucency` drives
        // emission per material, and one skinned surface is one material — so the
        // pieces that need to glow get generated as their own, sitting just inside
        // the ear and just on the tip of the muzzle.
        for role in [CatMeshAsset.Role.earL, .earR] {
            guard let earJ = shaped.joint(role) else { continue }
            let ear = joints[earJ]
            // Sized by how much ear stands above the joint, which is what an ear
            // is. Measuring the bone instead gives the offset from the skull to
            // the base of the ear — mostly sideways, and on this model nearly
            // twice as long — so the inner ears came out as four-centimetre
            // spikes growing out of the sides of the head.
            let earPos = shaped.position(earJ)
            let earLen = max(0.006, (headMax.y - earPos.y) * 1.25)
            let inner = MeshBuilder.ear(length: earLen, width: earLen * 0.68,
                                        thickness: earLen * 0.12,
                                        curl: a.earShape == .folded ? 1.4 * a.earFold : 0.12)
            let mat = Materials.skin(a.innerEarColor, gloss: 0.4)
            let node = Entity.make(inner, mat, name: "innerEar")
            // The cone is built along +Z, and an ear stands up and leans a little
            // outward. Aimed by direction rather than taken from the skeleton: the
            // ear joint is a leaf, so it has no bone to point along.
            let outward: Float = earPos.x < 0 ? -1 : 1
            node.orientation = aiming(SIMD3<Float>(outward * 0.30, 1, 0.12).normalized)
            // Just inside the ear it lines, rather than growing out of its back.
            node.position = SIMD3<Float>(0, 0, earLen * 0.10)
            ear.addChild(node)
            rig.translucentParts.append(
                TranslucentPart(entity: node, amount: 0.75,
                                tint: a.innerEarColor.mixed(with: RGBColor(1.0, 0.30, 0.26), 0.6)))
        }

        // Wider than it is deep and flatter than either, which is a cat's nose:
        // the blob's long axis is X, so it needs no turn of its own.
        let nose = MeshBuilder.blob(radius: hr * (0.07 + 0.05 * a.noseSize),
                                    scaleX: 1.2, scaleY: 0.85, scaleZ: 0.8,
                                    rings: 8, segments: 12)
        let noseNode = Entity.make(nose, Materials.noseLeather(a.noseColor), name: "nose")
        noseNode.position = onHead(0.94, -0.18, 0)
        head.addChild(noseNode)
        rig.translucentParts.append(
            TranslucentPart(entity: noseNode, amount: 0.35,
                            tint: a.noseColor.mixed(with: RGBColor(1.0, 0.34, 0.30), 0.5)))

        // Whiskers. Six a side, plus eyebrows, on their own root so the animator
        // can twitch them.
        guard a.whiskerLength > 0.01 else { return }
        let mat = Materials.whisker(a)
        for side in [Float(-1), 1] {
            let root = Entity()
            root.position = onHead(0.74, -0.26, side * 0.42)
            head.addChild(root)
            rig.whiskerRoots.append(root)
            for k in 0..<6 {
                let t = Float(k) / 5
                let length = hr * (1.0 + 1.6 * a.whiskerLength) * (0.72 + 0.4 * (1 - abs(t - 0.5) * 2))
                let strand = MeshBuilder.strand(length: length,
                                                thickness: 0.0004 + 0.0009 * a.whiskerThickness,
                                                droop: 0.25)
                let w = Entity.make(strand, mat, name: "whisker")
                // The strand is built along +Z, and is aimed by direction rather
                // than by Euler angles: the angles do not compose the way they
                // read, since `Rx · Ry · Rz` applies the yaw before the pitch, so
                // once the yaw has swung a whisker onto the X axis a pitch *about*
                // X cannot tilt it at all. The eyebrows were standing vertically
                // off the skull for exactly that reason.
                let out = mix(0.30, 0.95, t)
                w.orientation = aiming(SIMD3<Float>(
                    x: side * out, y: mix(0.34, -0.30, t), z: 1 - out * 0.45).normalized)
                root.addChild(w)
            }
            if a.eyebrowWhiskers > 0.05 {
                for k in 0..<3 {
                    let brow = MeshBuilder.strand(length: hr * (0.8 + 1.4 * a.eyebrowWhiskers),
                                                  thickness: 0.0005, droop: 0.1)
                    let b = Entity.make(brow, mat, name: "whisker")
                    // Over the eye, not on top of the skull. Placed at 0.70 up
                    // they read as antennae rather than as eyebrows.
                    b.position = onHead(0.52, 0.42, side * 0.34)
                    // Forward and up, fanning outward — an eyebrow whisker sweeps
                    // over the eye rather than standing on end.
                    b.orientation = aiming(SIMD3<Float>(
                        x: side * 0.26, y: 0.22 + Float(k) * 0.09, z: 0.94).normalized)
                    head.addChild(b)
                }
            }
        }
    }

    // MARK: - Collar

    private static func addCollar(_ rig: CatRig, _ a: CatAppearance,
                                  shaped: CatShape.Shaped, joints: [Entity]) {
        guard a.collarStyle != .none, let neckJ = shaped.joint(.neck) else { return }
        let neck = joints[neckJ]
        let r = a.torsoRadius * 0.62

        let holder = Entity()
        // A little back along the neck, which runs forward.
        holder.position = SIMD3<Float>(0, 0, -r * 0.2)
        neck.addChild(holder)
        rig.collarNode = holder

        switch a.collarStyle {
        case .bandana:
            let cloth = MeshBuilder.blob(radius: r * 1.25, scaleX: 0.9, scaleY: 0.55, scaleZ: 1.0,
                                         rings: 8, segments: 14)
            let n = Entity.make(cloth, Materials.linen(a.collarColor,
                                                       key: "bandana-\(a.collarColor.hashValue)"))
            n.position = SIMD3<Float>(0, -r * 0.6, r * 0.25)
            holder.addChild(n)
        default:
            // The torus is built in the XZ plane, so its hole faces up; the neck
            // runs forward, so it is tipped a quarter turn to thread onto it.
            let band = MeshBuilder.torus(ringRadius: r, pipeRadius: r * 0.16)
            let mat = a.collarStyle == .ribbon
                ? Materials.linen(a.collarColor, key: "ribbon-\(a.collarColor.hashValue)")
                : Materials.pbr(color: a.collarColor, roughness: 0.5)
            let n = Entity.make(band, mat)
            n.eulerAngles = SIMD3<Float>(deg(90), 0, 0)
            holder.addChild(n)
        }

        if a.collarHasBell || a.collarStyle == .bell {
            let bell = Entity.make(MeshBuilder.sphere(radius: r * 0.30),
                                   Materials.metal(a.bellColor, roughness: 0.18), name: "bell")
            bell.position = SIMD3<Float>(0, -r * 0.95, r * 0.2)
            holder.addChild(bell)
        }
        if a.collarStyle == .charm {
            let tag = MeshBuilder.box(width: r * 0.42, height: r * 0.42,
                                      length: r * 0.05, chamfer: r * 0.08)
            let n = Entity.make(tag, Materials.metal(RGBColor(hex: 0xD9C07A), roughness: 0.2))
            n.position = SIMD3<Float>(0, -r * 0.95, r * 0.28)
            holder.addChild(n)
        }
    }

    // MARK: - Bits

    /// Turns a mesh built along +Z to point along a direction.
    ///
    /// The shortest rotation taking one unit vector to another, built from the
    /// half-way vector so it needs no trigonometry and has no quadrant to get
    /// wrong. The antiparallel case has no shortest rotation — every axis
    /// perpendicular to the pair works — so it picks one.
    private static func aiming(_ direction: SIMD3<Float>) -> simd_quatf {
        let d = direction.normalized
        let z = SIMD3<Float>(0, 0, 1)
        if dot(z, d) < -0.9999 {
            return simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }
        let half = (z + d).normalized
        let axis = cross(z, half)
        return simd_quatf(ix: axis.x, iy: axis.y, iz: axis.z, r: dot(z, half)).normalized
    }

    /// A spherical cap around +Z: an eye's iris, or a lid that closes over it.
    private static func cap(radius: Float, angle: Float) -> MeshData {
        var rings: [LoftRing] = []
        let steps = 8
        for i in 0...steps {
            let phi = angle * Float(i) / Float(steps)
            rings.append(LoftRing(z: cosf(phi) * radius,
                                  radius: max(0.0004, sinf(phi) * radius)))
        }
        return MeshBuilder.loft(rings.reversed(), segments: 16, capStart: false, capEnd: true)
    }

    /// Rebuilds a mesh resource with the skeleton and per-vertex influences.
    private static func skinned(_ shaped: CatShape.Shaped, mesh: MeshResource) -> MeshResource? {
        var contents = mesh.contents
        guard var model = contents.models.first, var part = model.parts.first else { return nil }

        let joints = (0..<shaped.jointCount).map { j in
            MeshResource.Skeleton.Joint(name: "joint\(j)",
                               parentIndex: shaped.parents[j] >= 0 ? shaped.parents[j] : nil,
                               // Skinning only ever evaluates `jointWorld ·
                               // inverseBind`, so these two have to be inverses of
                               // each other and are otherwise free. Both are the
                               // joint's rest position and nothing else, which is
                               // what leaves a joint's axes equal to the body's.
                               inverseBindPoseMatrix: shaped.inverseBind(j),
                               restPoseTransform: Transform(translation: shaped.restLocal(j)))
        }

        let n = shaped.influencesPerVertex
        var influences: [MeshJointInfluence] = []
        influences.reserveCapacity(shaped.mesh.positions.count * n)
        for v in 0..<shaped.mesh.positions.count {
            for k in 0..<n {
                influences.append(MeshJointInfluence(
                    jointIndex: Int(shaped.jointIndices[v * n + k]),
                    weight: shaped.jointWeights[v * n + k]))
            }
        }

        part.skeletonID = "cat"
        // A mesh buffer, not a bare array — `MeshResource.JointInfluences` takes
        // `MeshBuffers.JointInfluences`, and `Joint` lives under `Skeleton`. Both
        // were spelled from the stand-in and both only exist the other way round.
        part.jointInfluences = MeshResource.JointInfluences(
            influences: MeshBuffers.JointInfluences(influences), influencesPerVertex: n)
        model.parts = [part]
        contents.models = [model]
        contents.skeletons = [MeshResource.Skeleton(id: "cat", joints: joints)]
        guard let out = try? MeshResource.generate(from: contents) else { return nil }
        #if DEBUG
        // Rebinding replaces the resource, and with it the registry entry the
        // offline renderer looks its buffers up by — without this the cat renders
        // as exactly zero triangles while reporting success.
        MeshSourceRegistry.record(out, shaped.mesh)
        #endif
        return out
    }

    /// Hands the posed joint hierarchy to the skin. Called once a frame, after
    /// the animator; reading the entities back rather than having the animator
    /// write the pose directly is what keeps the animator ignorant of skinning.
    static func syncPose(_ rig: CatRig) {
        guard let body = rig.skinnedBody, !rig.skinJoints.isEmpty else { return }
        let pose = SkeletalPose(id: "cat", joints: rig.skinJoints.enumerated().map {
            ("joint\($0.offset)", $0.element.transform)
        })
        body.components.set(SkeletalPosesComponent(poses: [pose]))
        // The fur shells are the same vertices bound to the same skeleton, so
        // they take the same pose. Without this they hang in the bind pose and
        // the cat walks out of its own coat.
        for shell in rig.skinnedShells {
            shell.components.set(SkeletalPosesComponent(poses: [pose]))
        }
    }
}

/// The shipped mesh, loaded once.
enum CatAsset {
    static let shared: CatMeshAsset? = {
        if let fromBundle = try? CatMeshAsset.load() { return fromBundle }
        // The assertion suite and the offline renderer run on a machine with no
        // app bundle. They read the same bytes out of the source tree.
        guard let d = FileManager.default.contents(atPath: "MeowRoom/Resources/cat.catmesh")
        else { return nil }
        return try? CatMeshAsset(data: d)
    }()
}
