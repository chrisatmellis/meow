import Foundation
import SceneKit
import UIKit

/// One leg: hip → knee → ankle → paw. Solved with two-bone IK so the paws stay planted.
struct LegRig {
    var hip = SCNNode()
    var knee = SCNNode()
    var ankle = SCNNode()
    var paw = SCNNode()
    var isFront = true
    var side: Float = 1          // -1 = the cat's left, +1 = right
    var upperLength: Float = 0.08
    var lowerLength: Float = 0.07
    var pawLength: Float = 0.03
    /// Rest position of the foot in body space.
    var restFoot = SCNVector3.zero
    /// Phase offset in the walk cycle, 0...1.
    var gaitPhase: Float = 0
    /// Which way the middle joint folds.
    var bendSign: Float = 1
}

/// Everything the animator needs to pose the cat.
final class CatRig {
    let appearance: CatAppearance

    let root = SCNNode()          // world placement (position + yaw)
    let body = SCNNode()          // vertical bob, crouch, lean
    let spine = SCNNode()         // torso, pitch/roll
    let neck = SCNNode()
    let head = SCNNode()
    let jaw = SCNNode()
    let tailRoot = SCNNode()      // fixed 180° yaw: local +Z runs down the tail
    let tailPitch = SCNNode()     // animated lift / sway of the tail base

    var tailSegments: [SCNNode] = []
    var legs: [LegRig] = []
    var earL = SCNNode()
    var earR = SCNNode()
    var eyeL = SCNNode()
    var eyeR = SCNNode()
    var lidUpperL = SCNNode()
    var lidUpperR = SCNNode()
    var lidLowerL = SCNNode()
    var lidLowerR = SCNNode()
    var whiskerRoots: [SCNNode] = []
    var chestNode = SCNNode()
    var bellyNode = SCNNode()
    /// Parts thin enough to light up from behind — ears, nose, paw pads.
    /// `Translucency` drives their emission from where the sun actually is.
    var translucentParts: [TranslucentPart] = []
    var collarNode: SCNNode?

    /// Cached measurements used by the animator.
    var bodyHeight: Float = 0.22
    var torsoLength: Float = 0.26
    var torsoRadius: Float = 0.075

    init(appearance: CatAppearance) {
        self.appearance = appearance
    }
}

enum CatBuilder {

    /// How much of the coat texture a part of a given length should cover, measured
    /// against the torso, so the stripe period is the same everywhere on the cat.
    /// Without this every part maps the whole texture over itself and short pieces —
    /// tail segments especially — come out looking bandaged.
    /// Segments around a lofted part, scaled by render tier.
    static func seg(_ base: Int, _ detail: Float) -> Int {
        max(4, Int((Float(base) * detail).rounded()))
    }

    /// Rings along a lofted part, scaled by render tier.
    static func ring(_ base: Int, _ detail: Float) -> Int {
        max(3, Int((Float(base) * detail).rounded()))
    }

    private static func vSpan(_ length: Float, _ a: CatAppearance) -> Float {
        max(0.05, length / max(0.05, a.torsoLength))
    }

    static func build(_ a: CatAppearance, preview: Bool = false) -> CatRig {
        let rig = CatRig(appearance: a)

        // Segment counts below are written for the high tier and scaled from here,
        // so a weaker device gets a coarser cat rather than a different one, and
        // the character creator — a head close-up filling the screen — gets a finer
        // one than the cat you see from across the room.
        let detail = preview ? RenderQuality.previewMeshDetail : RenderQuality.meshDetail
        func seg(_ base: Int) -> Int { CatBuilder.seg(base, detail) }
        func ring(_ base: Int) -> Int { CatBuilder.ring(base, detail) }

        let furMat = Materials.catFur(a, preview: preview)
        let skinMat = Materials.skin(a.noseColor, gloss: 0.55)

        let L = a.torsoLength            // hip → shoulder
        let R = a.torsoRadius

        rig.torsoLength = L
        rig.torsoRadius = R
        rig.bodyHeight = a.legHeight + R
        let scale = a.scale

        // ---- Root chain -------------------------------------------------
        rig.root.name = "cat"
        rig.root.addChildNode(rig.body)
        rig.body.position = SCNVector3(x: 0, y: rig.bodyHeight, z: 0)
        rig.body.addChildNode(rig.spine)

        // ---- Torso ------------------------------------------------------
        let chestDepth = 1.0 + 0.28 * a.chestDepth + 0.30 * a.chonk
        let hipWidth = 1.0 + 0.22 * a.bodyGirth + 0.25 * a.chonk
        var rings: [LoftRing] = []
        let samples = 16
        for i in 0...samples {
            let t = Float(i) / Float(samples)          // 0 = rear, 1 = front
            let z = mix(-L * 0.5, L * 0.5, t)
            // Hips full, waist tucked, ribcage deep, shoulders slightly narrower.
            let profile = 0.86
                + 0.24 * expf(-powf((t - 0.06) / 0.20, 2))     // haunches
                - 0.16 * expf(-powf((t - 0.40) / 0.16, 2))     // waist
                + 0.22 * expf(-powf((t - 0.76) / 0.22, 2))     // ribcage
            let taper = 1 - 0.34 * powf(max(0, t - 0.90) / 0.10, 2)
            let rx = R * profile * taper * (0.94 + 0.12 * hipWidth * (1 - t))
            let ry = R * profile * taper * (0.92 + 0.16 * chestDepth * t)
            // Belly sags a little with weight.
            let sag = -R * 0.16 * a.chonk * sinf(t * .pi)
            rings.append(LoftRing(center: Vec3(x: 0, y: sag, z: z), radiusX: rx, radiusY: ry))
        }
        let torsoGeo = MeshBuilder.loft(rings, segments: seg(22), capStart: true, capEnd: true)
        let torso = SCNNode.make(torsoGeo, furMat, name: "torso")
        rig.spine.addChildNode(torso)
        rig.chestNode = torso

        addFurShells(to: torso, mesh: torsoGeo, appearance: a, scaleBoost: 1)

        // Ruff / mane for long-haired cats.
        if a.effectiveFluff > 0.45 {
            let ruff = MeshBuilder.blob(radius: R * (1.15 + 0.55 * a.effectiveFluff),
                                        scaleX: 1.05, scaleY: 0.95, scaleZ: 0.55,
                                        rings: ring(12), segments: seg(18),
                                        vSpan: vSpan(R * 1.3, a))
            let rn = SCNNode.make(ruff, Materials.furShell(a, layer: 0))
            rn.position = SCNVector3(x: 0, y: -R * 0.05, z: L * 0.44)
            rig.spine.addChildNode(rn)
        }

        // ---- Neck & head -------------------------------------------------
        rig.neck.position = SCNVector3(x: 0, y: R * 0.30, z: L * 0.48)
        rig.spine.addChildNode(rig.neck)

        // Long enough that the head can genuinely lift clear of the shoulders when the
        // cat loafs or sits, rather than being welded to the chest.
        let neckLen = (0.046 + 0.030 * (1 - a.headWidth)) * scale
        let neckR = R * (0.52 + 0.22 * a.neckThickness)
        let neckGeo = MeshBuilder.tube(length: neckLen * 1.6, count: 4, segments: seg(14), radius: { t in
            neckR * (1 - 0.10 * t)
        }, vSpan: vSpan(neckLen * 1.6, a))
        let neckNode = SCNNode.make(neckGeo, furMat, name: "neck")
        neckNode.eulerAngles = SCNVector3(x: deg(-16), y: 0, z: 0)
        rig.neck.addChildNode(neckNode)

        rig.head.position = SCNVector3(x: 0, y: neckLen * 0.42, z: neckLen * 1.42)
        rig.neck.addChildNode(rig.head)
        buildHead(rig: rig, a: a, furMat: furMat, skinMat: skinMat, detail: detail)

        // ---- Legs ---------------------------------------------------------
        let hipDrop = -R * 0.30
        let groundY = -rig.bodyHeight                    // floor in body space
        let frontZ = L * 0.36
        let backZ = -L * 0.38
        let spreadFront = R * (0.52 + 0.18 * a.legThickness)
        let spreadBack = R * (0.60 + 0.18 * a.legThickness)

        for i in 0..<4 {
            let isFront = i < 2
            let side: Float = (i % 2 == 0) ? -1 : 1
            var leg = LegRig()
            leg.isFront = isFront
            leg.side = side
            leg.bendSign = isFront ? 1 : -1
            leg.gaitPhase = [0.0, 0.5, 0.5, 0.0][i]      // diagonal (trot-like) pairing

            let hipPos = SCNVector3(x: side * (isFront ? spreadFront : spreadBack),
                                    y: hipDrop,
                                    z: isFront ? frontZ : backZ)
            leg.hip.position = hipPos
            rig.spine.addChildNode(leg.hip)

            let reach = hipPos.y - groundY               // vertical distance to the floor
            // Segments are longer than the straight-line drop so the joints sit bent, the
            // way a real cat's do — and so the legs can still reach the floor when the
            // body lifts into a sit or a rear-up.
            let upper = reach * (isFront ? 0.56 : 0.60)
            let lower = reach * (isFront ? 0.50 : 0.47)
            let pawLen = reach * 0.16
            leg.upperLength = upper
            leg.lowerLength = lower
            leg.pawLength = pawLen
            leg.restFoot = SCNVector3(x: hipPos.x, y: groundY, z: hipPos.z + (isFront ? 0.012 : -0.006))

            // The upper segment is deliberately fat so it merges into the torso the way
            // a real cat's shoulder and haunch do; only the lower leg reads as a limb.
            let thickTop = R * (0.52 + 0.26 * a.legThickness) * (isFront ? 0.90 : 1.10)
            let thickBottom = R * (0.15 + 0.11 * a.legThickness)

            let upperGeo = MeshBuilder.tube(length: upper * 1.06, count: 5, segments: seg(12), radius: { t in
                mix(thickTop, thickTop * 0.52, t)
            }, vSpan: vSpan(upper, a))
            let un = SCNNode.make(upperGeo, furMat)
            un.eulerAngles = SCNVector3(x: deg(90), y: 0, z: 0)
            leg.hip.addChildNode(un)

            leg.knee.position = SCNVector3(x: 0, y: -upper, z: 0)
            leg.hip.addChildNode(leg.knee)

            let lowerGeo = MeshBuilder.tube(length: lower * 1.06, count: 5, segments: seg(14), radius: { t in
                mix(thickTop * 0.50, thickBottom, t)
            }, vSpan: vSpan(lower, a))
            let ln = SCNNode.make(lowerGeo, furMat)
            ln.eulerAngles = SCNVector3(x: deg(90), y: 0, z: 0)
            leg.knee.addChildNode(ln)

            leg.ankle.position = SCNVector3(x: 0, y: -lower, z: 0)
            leg.knee.addChildNode(leg.ankle)

            // Paw: a small rounded blob plus toe bumps.
            let pawR = R * (0.20 + 0.13 * a.pawSize)
            let pawGeo = MeshBuilder.blob(radius: pawR, scaleX: 0.95, scaleY: 0.72, scaleZ: 1.35,
                                          rings: ring(8), segments: seg(16), vSpan: vSpan(pawR * 2.7, a))
            let pn = SCNNode.make(pawGeo, furMat)
            pn.position = SCNVector3(x: 0, y: -pawLen * 0.35, z: pawR * 0.30)
            leg.ankle.addChildNode(pn)
            leg.paw = leg.ankle

            // Paw pads peeking out underneath.
            let padGeo = MeshBuilder.blob(radius: pawR * 0.55, scaleX: 1.0, scaleY: 0.30, scaleZ: 1.0,
                                          rings: ring(6), segments: seg(12))
            let padMat = Materials.skin(a.pawPadColor, gloss: 0.35)
            let pad = SCNNode.make(padGeo, padMat)
            pad.position = SCNVector3(x: 0, y: -pawLen * 0.35 - pawR * 0.46, z: pawR * 0.30)
            leg.ankle.addChildNode(pad)
            // Pads are thicker than an ear and usually face the floor, so they get
            // much less — but a cat lying on its side in a sun patch shows them.
            rig.translucentParts.append(
                TranslucentPart(node: pad, material: padMat, amount: 0.22,
                                tint: a.pawPadColor.mixed(with: RGBColor(1.0, 0.34, 0.30), 0.45)))

            if a.toeTufts > 0.15 && !a.hairless {
                for k in 0..<3 {
                    let tuft = MeshBuilder.strand(length: pawR * (0.8 + a.toeTufts), thickness: 0.0016, droop: 0.4)
                    let tn = SCNNode.make(tuft, Materials.furShell(a, layer: 1))
                    tn.position = SCNVector3(x: (Float(k) - 1) * pawR * 0.3, y: -pawLen * 0.35, z: pawR * 0.6)
                    tn.eulerAngles = SCNVector3(x: deg(70), y: 0, z: 0)
                    leg.ankle.addChildNode(tn)
                }
            }

            rig.legs.append(leg)
        }

        // ---- Tail -----------------------------------------------------------
        buildTail(rig: rig, a: a, furMat: furMat, detail: detail)

        // ---- Collar ----------------------------------------------------------
        if a.collarStyle != .none {
            buildCollar(rig: rig, a: a, detail: detail)
        }

        return rig
    }

    // MARK: - Head

    private static func buildHead(rig: CatRig, a: CatAppearance, furMat: SCNMaterial, skinMat: SCNMaterial, detail: Float) {
        func seg(_ base: Int) -> Int { CatBuilder.seg(base, detail) }
        func ring(_ base: Int) -> Int { CatBuilder.ring(base, detail) }

        let hr = a.headRadius
        let widthMul = 0.86 + 0.34 * a.headWidth
        let roundMul = 0.84 + 0.30 * a.headRoundness

        let skull = MeshBuilder.blob(radius: hr,
                                     scaleX: widthMul,
                                     scaleY: roundMul,
                                     scaleZ: 1.05 + 0.18 * (1 - a.headRoundness),
                                     rings: ring(18), segments: seg(28),
                                     vSpan: vSpan(hr * 2.2, a))
        let skullNode = SCNNode.make(skull, furMat, name: "skull")
        rig.head.addChildNode(skullNode)
        addFurShells(to: skullNode, mesh: skull, appearance: a, scaleBoost: 0.7)

        // Muzzle.
        let muzzleLen = hr * (0.34 + 0.72 * a.muzzleLength)
        let muzzleW = hr * (0.52 + 0.34 * a.muzzleWidth)
        let muzzle = MeshBuilder.blob(radius: muzzleW, scaleX: 1.25, scaleY: 0.86,
                                      scaleZ: max(0.35, muzzleLen / muzzleW),
                                      rings: ring(12), segments: seg(28),
                                      vSpan: vSpan(muzzleLen * 2, a))
        let muzzleNode = SCNNode.make(muzzle, furMat, name: "muzzle")
        muzzleNode.position = SCNVector3(x: 0, y: -hr * 0.26, z: hr * (0.52 + 0.26 * a.muzzleLength))
        rig.head.addChildNode(muzzleNode)

        // Nose leather.
        let nose = MeshBuilder.blob(radius: hr * (0.10 + 0.07 * a.noseSize), scaleX: 1.2, scaleY: 0.85, scaleZ: 0.8,
                                    rings: ring(9), segments: seg(16))
        // Its own material for the same reason as the ears: the nose is thin enough
        // to glow, and skinMat is shared with the paw pads.
        let noseMat = Materials.skin(a.noseColor, gloss: 0.55)
        let noseNode = SCNNode.make(nose, noseMat, name: "nose")
        rig.translucentParts.append(
            TranslucentPart(node: noseNode, material: noseMat, amount: 0.35,
                            tint: a.noseColor.mixed(with: RGBColor(1.0, 0.34, 0.30), 0.5)))
        noseNode.position = SCNVector3(x: 0,
                                       y: -hr * 0.14,
                                       z: hr * (0.52 + 0.26 * a.muzzleLength) + muzzleLen * 0.80)
        rig.head.addChildNode(noseNode)

        // Chin & jaw (opens when the cat meows).
        rig.jaw.position = SCNVector3(x: 0, y: -hr * 0.34, z: hr * 0.52)
        rig.head.addChildNode(rig.jaw)
        let chin = MeshBuilder.blob(radius: hr * (0.20 + 0.14 * a.chinSize), scaleX: 1.1, scaleY: 0.7, scaleZ: 1.0,
                                    rings: ring(9), segments: seg(16), vSpan: vSpan(hr * 0.6, a))
        let chinNode = SCNNode.make(chin, furMat)
        chinNode.position = SCNVector3(x: 0, y: -hr * 0.06, z: hr * (0.18 + 0.30 * a.muzzleLength))
        rig.jaw.addChildNode(chinNode)

        // Something behind the teeth.
        //
        // The jaw rotates up to 26°, and not only for the half second of a meow —
        // eating, drinking, grooming and stretching all open it too. Behind it there
        // was nothing at all, so an open mouth showed the inside of the skull blob,
        // which is to say a hole through the cat's face.
        //
        // The cavity hangs off the head rather than the jaw, so it stays put while
        // the jaw swings away from it, which is what a mouth does.
        let mouthDepth = hr * (0.34 + 0.20 * a.muzzleLength)
        let cavity = MeshBuilder.blob(radius: hr * 0.30, scaleX: 1.05, scaleY: 0.62,
                                      scaleZ: max(0.6, mouthDepth / (hr * 0.30)),
                                      rings: ring(6), segments: seg(12))
        let cavityNode = SCNNode.make(cavity, Materials.oralCavity(a.innerEarColor), name: "oralCavity")
        cavityNode.position = SCNVector3(x: 0, y: -hr * 0.30,
                                         z: hr * (0.30 + 0.24 * a.muzzleLength))
        rig.head.addChildNode(cavityNode)

        // The tongue goes with the jaw, because it does.
        let tongueGeo = MeshBuilder.blob(radius: hr * 0.17, scaleX: 0.80, scaleY: 0.26,
                                         scaleZ: 1.9, rings: ring(7), segments: seg(12))
        let tongueNode = SCNNode.make(tongueGeo, Materials.tongue(a.noseColor), name: "tongue")
        tongueNode.position = SCNVector3(x: 0, y: hr * 0.02, z: hr * (0.20 + 0.24 * a.muzzleLength))
        rig.jaw.addChildNode(tongueNode)

        // Cheek floof.
        if a.cheekFluff > 0.25 && !a.hairless {
            for side in [-1, 1] as [Float] {
                let cheek = MeshBuilder.blob(radius: hr * (0.34 + 0.36 * a.cheekFluff),
                                             scaleX: 0.75, scaleY: 1.0, scaleZ: 0.75,
                                             rings: ring(9), segments: seg(14),
                                             vSpan: vSpan(hr * 0.9, a))
                let cn = SCNNode.make(cheek, Materials.furShell(a, layer: 0))
                cn.position = SCNVector3(x: side * hr * 0.70 * widthMul, y: -hr * 0.20, z: hr * 0.14)
                rig.head.addChildNode(cn)
            }
        }

        // Ears.
        let earLen = hr * (0.75 + 1.25 * a.earLength)
        let earWidth = hr * (0.62 + 0.75 * a.earWidth)
        for side in [-1, 1] as [Float] {
            let holder = SCNNode()
            holder.position = SCNVector3(x: side * hr * 0.62 * widthMul,
                                         y: hr * 0.60 * roundMul,
                                         z: -hr * 0.05)
            let tilt = deg(mix(-8, 30, a.earTilt))
            holder.eulerAngles = SCNVector3(x: deg(-72), y: side * deg(24), z: side * tilt)
            rig.head.addChildNode(holder)

            let curl: Float = a.earShape == .curled ? -0.9 : (a.earShape == .folded ? 1.6 * a.earFold : 0.12)
            let geo = MeshBuilder.ear(length: earLen, width: earWidth, thickness: earWidth * 0.30, curl: curl,
                                      vSpan: vSpan(earLen, a))
            // Its own material instance rather than the shared body fur: an ear is
            // the one piece of a cat that visibly lights up from behind, and it
            // cannot do that while it shares emission with the torso.
            let earMat = Materials.catFur(a)
            let earNode = SCNNode.make(geo, earMat, name: "ear")
            holder.addChildNode(earNode)

            // Pink inner ear.
            let innerGeo = MeshBuilder.ear(length: earLen * 0.78, width: earWidth * 0.62,
                                           thickness: earWidth * 0.12, curl: curl)
            let innerMat = Materials.skin(a.innerEarColor, gloss: 0.4)
            let inner = SCNNode.make(innerGeo, innerMat)
            inner.position = SCNVector3(x: 0, y: earWidth * 0.09, z: earLen * 0.06)
            holder.addChildNode(inner)

            // Cartilage and a little fur over blood: the thinnest thing on the cat,
            // and the reason a backlit cat reads as alive rather than as a model.
            rig.translucentParts.append(
                TranslucentPart(node: earNode, material: earMat, amount: 0.62,
                                tint: a.innerEarColor.mixed(with: RGBColor(1.0, 0.36, 0.30), 0.55)))
            rig.translucentParts.append(
                TranslucentPart(node: inner, material: innerMat, amount: 0.75,
                                tint: a.innerEarColor.mixed(with: RGBColor(1.0, 0.30, 0.26), 0.6)))

            // Lynx tips / ear furnishings.
            if a.earTufts > 0.2 && !a.hairless {
                for k in 0..<4 {
                    let tuft = MeshBuilder.strand(length: earLen * (0.35 + 0.75 * a.earTufts),
                                                  thickness: 0.0013, droop: 0.15)
                    let tn = SCNNode.make(tuft, Materials.furShell(a, layer: 0))
                    tn.position = SCNVector3(x: (Float(k) - 1.5) * earWidth * 0.14,
                                             y: 0,
                                             z: earLen * (a.earShape == .lynxTipped ? 0.92 : 0.35))
                    tn.eulerAngles = SCNVector3(x: deg(Float(k) * 6 - 12), y: 0, z: 0)
                    holder.addChildNode(tn)
                }
            }

            if side < 0 { rig.earL = holder } else { rig.earR = holder }
        }

        // Eyes.
        let eyeR = hr * (0.20 + 0.13 * a.eyeSize)
        let spacing = hr * (0.36 + 0.22 * a.eyeSpacing) * widthMul
        for side in [-1, 1] as [Float] {
            let socket = SCNNode()
            socket.position = SCNVector3(x: side * spacing,
                                         y: hr * (0.05 + 0.10 * (1 - a.eyeSize)),
                                         z: hr * (0.60 + 0.10 * a.muzzleLength))
            let tiltZ = side * deg(mix(-4, 22, a.eyeTilt))
            socket.eulerAngles = SCNVector3(x: 0, y: side * deg(16), z: tiltZ)
            rig.head.addChildNode(socket)

            // Eyeball: mostly hidden, so it only needs to read as a dark wet sphere.
            let ball = SCNSphere(radius: CGFloat(eyeR)).sized()
            ball.segmentCount = 20
            let ballMat = Materials.pbr(diffuse: UIColor(white: CGFloat(0.10 + 0.25 * a.scleraTint), alpha: 1),
                                        roughness: 0.05, metalness: 0)
            let ballNode = SCNNode.make(ball, ballMat, name: "eyeball")
            socket.addChildNode(ballNode)

            // Iris cap sits on the front of the eyeball, facing the cat's +Z.
            let cap = eyeCap(radius: eyeR * 1.02, capAngle: deg(60))
            let capNode = SCNNode.make(cap, Materials.eye(a, right: side > 0), name: "iris")
            socket.addChildNode(capNode)

            // Eyelids: caps of fur that swing shut from above and below.
            let upper = SCNNode.make(eyeCap(radius: eyeR * 1.10, capAngle: deg(74)), furMat, name: "lidUpper")
            upper.eulerAngles = SCNVector3(x: deg(-90), y: 0, z: 0)
            socket.addChildNode(upper)
            let lower = SCNNode.make(eyeCap(radius: eyeR * 1.10, capAngle: deg(66)), furMat, name: "lidLower")
            lower.eulerAngles = SCNVector3(x: deg(90), y: 0, z: 0)
            socket.addChildNode(lower)

            // Shape the aperture: hooded / almond / oriental eyes squash differently.
            switch a.eyeShape {
            case .almond: socket.scale = SCNVector3(x: 1.0, y: 0.88, z: 1.0)
            case .round: socket.scale = SCNVector3(x: 1.0, y: 1.0, z: 1.0)
            case .oval: socket.scale = SCNVector3(x: 0.94, y: 1.02, z: 1.0)
            case .oriental: socket.scale = SCNVector3(x: 1.12, y: 0.76, z: 1.0)
            case .hooded: socket.scale = SCNVector3(x: 1.05, y: 0.72, z: 1.0)
            }

            if side < 0 {
                rig.eyeL = socket; rig.lidUpperL = upper; rig.lidLowerL = lower
            } else {
                rig.eyeR = socket; rig.lidUpperR = upper; rig.lidLowerR = lower
            }
        }

        // Whiskers.
        if a.whiskerLength > 0.03 {
            let whiskerMat = Materials.whisker(a)
            for side in [-1, 1] as [Float] {
                let pad = SCNNode()
                pad.position = SCNVector3(x: side * hr * 0.32,
                                          y: -hr * 0.20,
                                          z: hr * (0.70 + 0.34 * a.muzzleLength))
                rig.head.addChildNode(pad)
                rig.whiskerRoots.append(pad)
                for k in 0..<5 {
                    let t = Float(k) / 4
                    let len = hr * (0.9 + 1.9 * a.whiskerLength) * (0.7 + 0.5 * sinf(t * .pi))
                    let geo = MeshBuilder.strand(length: len,
                                                 thickness: 0.0006 + 0.0009 * a.whiskerThickness,
                                                 droop: 0.35)
                    let wn = SCNNode.make(geo, whiskerMat)
                    wn.eulerAngles = SCNVector3(x: deg(mix(14, -18, t)),
                                                y: side * deg(mix(58, 82, t)),
                                                z: 0)
                    pad.addChildNode(wn)
                }
            }
            // Brow whiskers.
            if a.eyebrowWhiskers > 0.1 {
                for side in [-1, 1] as [Float] {
                    for k in 0..<2 {
                        let geo = MeshBuilder.strand(length: hr * (0.7 + 1.0 * a.eyebrowWhiskers),
                                                     thickness: 0.0006, droop: 0.1)
                        let wn = SCNNode.make(geo, Materials.whisker(a))
                        wn.position = SCNVector3(x: side * hr * 0.34, y: hr * 0.42, z: hr * 0.44)
                        wn.eulerAngles = SCNVector3(x: deg(-34 - Float(k) * 10), y: side * deg(38), z: 0)
                        rig.head.addChildNode(wn)
                    }
                }
            }
        }
    }

    /// A spherical cap with planar UVs, used for irises and eyelids.
    private static func eyeCap(radius: Float, capAngle: Float) -> MeshData {
        let mesh = MeshData()
        let ringCount = 6, segs = 18
        var ringIdx: [[Int32]] = []
        for i in 0...ringCount {
            let t = Float(i) / Float(ringCount)
            let phi = t * capAngle
            var row: [Int32] = []
            for s in 0...segs {
                let th = Float(s) / Float(segs) * 2 * .pi
                let p = Vec3(x: sinf(phi) * cosf(th) * radius,
                             y: sinf(phi) * sinf(th) * radius,
                             z: cosf(phi) * radius)
                let uv = Vec2(x: 0.5 + 0.5 * t * cosf(th),
                              y: 0.5 + 0.5 * t * sinf(th))
                row.append(mesh.addVertex(p, uv: uv))
            }
            ringIdx.append(row)
        }
        for i in 0..<ringCount {
            for s in 0..<segs {
                // Outward-facing winding, matching MeshBuilder.loft.
                mesh.addQuad(ringIdx[i][s], ringIdx[i + 1][s], ringIdx[i + 1][s + 1], ringIdx[i][s + 1])
            }
        }
        mesh.recomputeNormals()
        return mesh
    }

    // MARK: - Tail

    private static func buildTail(rig: CatRig, a: CatAppearance, furMat: SCNMaterial, detail: Float) {
        func seg(_ base: Int) -> Int { CatBuilder.seg(base, detail) }
        func ring(_ base: Int) -> Int { CatBuilder.ring(base, detail) }

        // The root only carries the 180° yaw, so the animator's pitch is unambiguous:
        // inside `tailPitch`, +Z runs down the tail and +X rotation lifts it.
        rig.tailRoot.position = SCNVector3(x: 0, y: a.torsoRadius * 0.55, z: -a.torsoLength * 0.5)
        rig.tailRoot.eulerAngles = SCNVector3(x: 0, y: .pi, z: 0)
        rig.spine.addChildNode(rig.tailRoot)
        rig.tailPitch.eulerAngles = SCNVector3(x: deg(-30), y: 0, z: 0)
        rig.tailRoot.addChildNode(rig.tailPitch)

        let segCount = a.tailShape == .bobbed ? 3 : 9
        let total = a.tailLengthMeters
        let segLen = total / Float(segCount)
        var parent = rig.tailPitch
        rig.tailSegments.removeAll()

        for i in 0..<segCount {
            let node = SCNNode()
            node.position = SCNVector3(x: 0, y: 0, z: i == 0 ? 0 : segLen)
            parent.addChildNode(node)

            let t0 = Float(i) / Float(segCount)
            let t1 = Float(i + 1) / Float(segCount)
            let tailSpan = vSpan(segLen, a)
            let geo = MeshBuilder.tube(length: segLen * 1.08, count: 3, segments: seg(10), radius: { u in
                let t = mix(t0, t1, u)
                var r = a.tailRadius
                switch a.tailShape {
                case .plumed: r *= 0.85 + 1.10 * sinf(t * .pi * 0.9)
                case .whip: r *= 1.05 - 0.65 * t
                case .bobbed: r *= 1.0 - 0.2 * t
                case .curled, .kinked, .long: r *= 1.02 - 0.30 * t
                }
                return r
            }, vSpan: tailSpan)
            let geoNode = SCNNode.make(geo, furMat, name: "tail\(i)")
            node.addChildNode(geoNode)

            if a.effectiveFluff > 0.35 || a.tailFluff > 0.4 {
                let shellGeo = MeshBuilder.tube(length: segLen * 1.10, count: 3, segments: seg(10), radius: { u in
                    let t = mix(t0, t1, u)
                    return a.tailRadius * (1.35 + 0.9 * a.tailFluff) * (a.tailShape == .plumed
                                                                        ? (0.8 + 1.1 * sinf(t * .pi * 0.9)) : 1.0)
                }, vSpan: tailSpan)
                let sn = SCNNode.make(shellGeo, Materials.furShell(a, layer: 0))
                node.addChildNode(sn)
            }

            // Tail rings for tabby cats.
            if a.tailRingCount > 0.15 && (i % 2 == 0) && a.pattern != .solid {
                let ring = SCNTorus(ringRadius: CGFloat(a.tailRadius * 0.86), pipeRadius: CGFloat(a.tailRadius * 0.20)).sized()
                let rn = SCNNode.make(ring, Materials.skin(a.markingColor, gloss: 0.2))
                rn.position = SCNVector3(x: 0, y: 0, z: segLen * 0.5)
                rn.eulerAngles = SCNVector3(x: deg(90), y: 0, z: 0)
                rn.opacity = CGFloat(0.35 * a.tailRingCount * a.patternContrast)
                node.addChildNode(rn)
            }

            rig.tailSegments.append(node)
            parent = node
        }
    }

    // MARK: - Collar

    private static func buildCollar(rig: CatRig, a: CatAppearance, detail: Float) {
        func seg(_ base: Int) -> Int { CatBuilder.seg(base, detail) }
        func ring(_ base: Int) -> Int { CatBuilder.ring(base, detail) }

        let holder = SCNNode()
        holder.position = SCNVector3(x: 0, y: 0, z: 0.012 * a.scale)
        rig.neck.addChildNode(holder)
        rig.collarNode = holder

        let r = a.torsoRadius * 0.60
        switch a.collarStyle {
        case .none:
            return
        case .bandana:
            let cloth = MeshBuilder.blob(radius: r * 1.25, scaleX: 1.0, scaleY: 0.55, scaleZ: 0.9, rings: ring(8), segments: seg(14))
            let cn = SCNNode.make(cloth, Materials.linen(a.collarColor, key: "bandana-\(a.collarColor.hashValue)"))
            cn.position = SCNVector3(x: 0, y: -r * 0.6, z: r * 0.25)
            cn.eulerAngles = SCNVector3(x: deg(90), y: 0, z: 0)
            holder.addChildNode(cn)
        default:
            let band = SCNTorus(ringRadius: CGFloat(r), pipeRadius: CGFloat(r * 0.16)).sized()
            let mat = a.collarStyle == .ribbon
                ? Materials.linen(a.collarColor, key: "ribbon-\(a.collarColor.hashValue)")
                : Materials.pbr(diffuse: UIColor(a.collarColor), roughness: 0.5)
            let bn = SCNNode.make(band, mat)
            bn.eulerAngles = SCNVector3(x: deg(74), y: 0, z: 0)
            holder.addChildNode(bn)
        }

        if a.collarHasBell || a.collarStyle == .bell {
            let bell = SCNSphere(radius: CGFloat(r * 0.30)).sized()
            let bn = SCNNode.make(bell, Materials.metal(a.bellColor, roughness: 0.18))
            bn.position = SCNVector3(x: 0, y: -r * 0.95, z: r * 0.20)
            bn.name = "bell"
            holder.addChildNode(bn)
        }
        if a.collarStyle == .charm {
            let tag = SCNBox(width: CGFloat(r * 0.42), height: CGFloat(r * 0.42),
                             length: CGFloat(r * 0.05), chamferRadius: CGFloat(r * 0.08))
            let tn = SCNNode.make(tag, Materials.metal(RGBColor(hex: 0xD9C07A), roughness: 0.2))
            tn.position = SCNVector3(x: 0, y: -r * 0.95, z: r * 0.28)
            holder.addChildNode(tn)
        }
    }

    // MARK: - Fur shells

    private static func addFurShells(to node: SCNNode, mesh: MeshData,
                                     appearance a: CatAppearance, scaleBoost: Float) {
        guard !a.hairless, a.effectiveFurLength > 0.30 else { return }
        let layers = min(RenderQuality.maxFurShells, a.effectiveFurLength > 0.65 ? 2 : 1)
        guard layers > 0 else { return }
        for i in 0..<layers {
            // Realising the mesh once per shell gives each its own geometry, which is
            // what the old `copy()` dance was for.
            let shell = SCNNode.make(mesh, Materials.furShell(a, layer: i))
            let s = 1 + (0.035 + 0.075 * a.effectiveFurLength) * Float(i + 1) * scaleBoost
            shell.scale = SCNVector3(x: s, y: s, z: s)
            shell.castsShadow = false
            shell.renderingOrder = 10 + i
            node.addChildNode(shell)
        }
    }
}
