import Foundation
import SceneKit
import UIKit

/// The whole room, generated procedurally. Holds references to the bits that change
/// over the day (shoji glow, lantern, garden backdrop) and with play (food, water, teacup).
final class RoomNode {
    let root = SCNNode()

    var shojiMaterials: [SCNMaterial] = []
    var backdropMaterials: [SCNMaterial] = []
    var lanternPaper: SCNMaterial?
    var lanternLight: SCNLight?
    var lanternLightNode: SCNNode?

    var foodPile: SCNNode?
    var waterSurface: SCNNode?
    var fountainStream: SCNNode?
    var litterSurface: SCNNode?
    var teacup: SCNNode?
    var sunPatch: SCNNode?
    var treatNode: SCNNode?
    var toyMouse: SCNNode?
    var toyBall: SCNNode?
    var dustMotes: SCNNode?
}

enum RoomBuilder {

    static func build(sky: SkyState) -> RoomNode {
        let room = RoomNode()
        let r = room.root
        r.name = "room"

        r.addChildNode(buildFloor())
        r.addChildNode(buildCeiling())
        r.addChildNode(buildWalls(room: room))
        r.addChildNode(buildBackdrop(room: room, sky: sky))
        r.addChildNode(buildFuton())
        r.addChildNode(buildTable(room: room))
        r.addChildNode(buildTansu())
        r.addChildNode(buildLantern(room: room))
        r.addChildNode(buildScroll())
        r.addChildNode(buildBonsai())
        r.addChildNode(buildCatTree())
        r.addChildNode(buildCatBed())
        r.addChildNode(buildFeeder(room: room))
        r.addChildNode(buildFountain(room: room))
        r.addChildNode(buildLitterBox(room: room))
        r.addChildNode(buildToys(room: room))
        r.addChildNode(buildZabuton())
        r.addChildNode(buildSunPatch(room: room))
        r.addChildNode(buildDustMotes(room: room))

        return room
    }

    // MARK: - Shell

    private static func buildFloor() -> SCNNode {
        let node = SCNNode()
        node.name = "floor"

        let W = RoomLayout.halfWidth * 2
        let D = RoomLayout.halfDepth * 2

        // Sub-floor slab so nothing shows through the seams.
        let slab = SCNBox(width: CGFloat(W), height: 0.05, length: CGFloat(D), chamferRadius: 0)
        let slabNode = SCNNode.make(slab, Materials.darkWood())
        slabNode.simdPosition = SIMD3<Float>(x: 0, y: -0.026, z: 0)
        node.addChildNode(slabNode)

        // Six tatami mats in a 3 × 2 grid, each with a dark cloth edge.
        let cols = 3, rows = 2
        let matW = W / Float(cols), matD = D / Float(rows)
        let gap: Float = 0.012
        for c in 0..<cols {
            for rw in 0..<rows {
                let cx = -RoomLayout.halfWidth + matW * (Float(c) + 0.5)
                let cz = -RoomLayout.halfDepth + matD * (Float(rw) + 0.5)

                let mat = SCNBox(width: CGFloat(matW - gap), height: 0.028,
                                 length: CGFloat(matD - gap), chamferRadius: 0.004)
                let m = Materials.tatami()
                let border = Materials.tatamiBorder()
                // Sides get the cloth border; top and bottom get the woven rush.
                mat.materials = [border, border, border, border, m, m]
                let n = SCNNode(geometry: mat)
                n.simdPosition = SIMD3<Float>(x: cx, y: 0.014, z: cz)
                // Alternate the weave direction like a real tatami room.
                if (c + rw) % 2 == 0 { n.simdEulerAngles = SIMD3<Float>(x: 0, y: deg(90), z: 0) }
                n.castsShadow = false
                node.addChildNode(n)
            }
        }
        return node
    }

    private static func buildCeiling() -> SCNNode {
        let node = SCNNode()
        node.name = "ceiling"
        let plank = Materials.darkWood()
        plank.isDoubleSided = true

        let ceiling = SCNBox(width: CGFloat(RoomLayout.halfWidth * 2),
                             height: 0.04,
                             length: CGFloat(RoomLayout.halfDepth * 2),
                             chamferRadius: 0)
        let cNode = SCNNode.make(ceiling, plank)
        cNode.simdPosition = SIMD3<Float>(x: 0, y: RoomLayout.ceilingHeight, z: 0)
        node.addChildNode(cNode)

        // Two exposed beams.
        for z in [-0.90, 0.55] as [Float] {
            let beam = SCNBox(width: CGFloat(RoomLayout.halfWidth * 2), height: 0.11, length: 0.09, chamferRadius: 0.01)
            let b = SCNNode.make(beam, Materials.darkWood())
            b.simdPosition = SIMD3<Float>(x: 0, y: RoomLayout.ceilingHeight - 0.075, z: z)
            node.addChildNode(b)
        }
        return node
    }

    private static func buildWalls(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "walls"

        let hw = RoomLayout.halfWidth
        let hd = RoomLayout.halfDepth
        let h = RoomLayout.ceilingHeight
        let t = RoomLayout.wallThickness
        let plasterMat = Materials.plaster()
        plasterMat.isDoubleSided = true

        func wallPanel(width: Float, height: Float, position: SIMD3<Float>, yaw: Float, material: SCNMaterial) -> SCNNode {
            let box = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(t), chamferRadius: 0)
            let n = SCNNode.make(box, material)
            n.simdPosition = position
            n.simdEulerAngles = SIMD3<Float>(x: 0, y: yaw, z: 0)
            return n
        }

        // +Z wall (behind the player) and -X wall: plain plaster with a wooden dado rail.
        node.addChildNode(wallPanel(width: hw * 2, height: h,
                                    position: SIMD3<Float>(x: 0, y: h / 2, z: hd), yaw: 0, material: plasterMat))
        node.addChildNode(wallPanel(width: hd * 2, height: h,
                                    position: SIMD3<Float>(x: -hw, y: h / 2, z: 0), yaw: deg(90), material: plasterMat))

        // +X wall with a small side window near the far corner.
        node.addChildNode(buildSideWall(room: room, plaster: plasterMat))

        // -Z wall: the shoji window wall.
        node.addChildNode(buildWindowWall(room: room, plaster: plasterMat))

        // Skirting and a picture rail tie the room together.
        let trim = Materials.darkWood()
        for (pos, yaw, len) in [(SIMD3<Float>(x: 0, y: 0.055, z: hd - 0.01), Float(0), hw * 2),
                                (SIMD3<Float>(x: -hw + 0.01, y: 0.055, z: 0), deg(90), hd * 2),
                                (SIMD3<Float>(x: hw - 0.01, y: 0.055, z: 0), deg(90), hd * 2)] {
            let box = SCNBox(width: CGFloat(len), height: 0.10, length: 0.02, chamferRadius: 0.003)
            let n = SCNNode.make(box, trim)
            n.simdPosition = pos
            n.simdEulerAngles = SIMD3<Float>(x: 0, y: yaw, z: 0)
            node.addChildNode(n)
        }
        return node
    }

    private static func buildWindowWall(room: RoomNode, plaster: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        node.name = "windowWall"
        let hw = RoomLayout.halfWidth
        let hd = RoomLayout.halfDepth
        let h = RoomLayout.ceilingHeight
        let t = RoomLayout.wallThickness

        let openLeft: Float = -1.30
        let openRight: Float = 1.30
        let openBottom: Float = RoomLayout.windowSillHeight
        let openTop: Float = 1.98

        func panel(_ w: Float, _ ht: Float, _ x: Float, _ y: Float) {
            let box = SCNBox(width: CGFloat(w), height: CGFloat(ht), length: CGFloat(t), chamferRadius: 0)
            let n = SCNNode.make(box, plaster)
            n.simdPosition = SIMD3<Float>(x: x, y: y, z: -hd)
            node.addChildNode(n)
        }
        // Header, sill and jambs around the opening.
        panel(hw * 2, h - openTop, 0, openTop + (h - openTop) / 2)
        panel(hw * 2, openBottom, 0, openBottom / 2)
        panel(hw + openLeft, openTop - openBottom, (-hw + openLeft) / 2, (openTop + openBottom) / 2)
        panel(hw - openRight, openTop - openBottom, (hw + openRight) / 2, (openTop + openBottom) / 2)

        // Wooden window frame.
        let frameMat = Materials.darkWood()
        func frameBar(_ w: Float, _ ht: Float, _ d: Float, _ x: Float, _ y: Float, _ z: Float) {
            let box = SCNBox(width: CGFloat(w), height: CGFloat(ht), length: CGFloat(d), chamferRadius: 0.004)
            let n = SCNNode.make(box, frameMat)
            n.simdPosition = SIMD3<Float>(x: x, y: y, z: z)
            node.addChildNode(n)
        }
        let zFrame = -hd + 0.035
        frameBar(openRight - openLeft + 0.10, 0.07, 0.07, 0, openTop + 0.02, zFrame)
        frameBar(openRight - openLeft + 0.10, 0.09, 0.14, 0, openBottom - 0.02, zFrame + 0.04)  // sill the cat sits on
        frameBar(0.07, openTop - openBottom, 0.07, openLeft - 0.02, (openTop + openBottom) / 2, zFrame)
        frameBar(0.07, openTop - openBottom, 0.07, openRight + 0.02, (openTop + openBottom) / 2, zFrame)
        frameBar(0.06, openTop - openBottom, 0.06, 0, (openTop + openBottom) / 2, zFrame)       // centre mullion

        // Left half: closed shoji screen with a lattice.
        let shojiMat = Materials.shoji()
        room.shojiMaterials.append(shojiMat)
        let shojiW = -openLeft
        let shojiH = openTop - openBottom
        let paper = SCNPlane(width: CGFloat(shojiW - 0.04), height: CGFloat(shojiH - 0.04))
        let paperNode = SCNNode.make(paper, shojiMat)
        paperNode.simdPosition = SIMD3<Float>(x: openLeft / 2, y: (openTop + openBottom) / 2, z: -hd + 0.055)
        paperNode.castsShadow = false
        node.addChildNode(paperNode)

        // Lattice (kumiko).
        let lattice = Materials.hinoki()
        let cols = 4, rows = 6
        for c in 1..<cols {
            let x = openLeft + shojiW * Float(c) / Float(cols)
            frameBarInto(node, lattice, 0.014, shojiH - 0.04, 0.016, x, (openTop + openBottom) / 2, -hd + 0.068)
        }
        for rw in 1..<rows {
            let y = openBottom + shojiH * Float(rw) / Float(rows)
            frameBarInto(node, lattice, shojiW - 0.04, 0.014, 0.016, openLeft / 2, y, -hd + 0.068)
        }

        // Right half: slid open. A thin pane of glass and the garden beyond.
        //
        // The roughness here has to stay well away from zero. At 0.02 the pane is
        // effectively a mirror, and the paper lantern a metre away in the corner
        // reflected across the whole opening — at night the open half of the
        // window came out brighter than it does at noon, which read as sunlight
        // outside at 10pm. Transparency does not damp that: a mirrored point
        // light is bright enough that even a few percent of it blows out.
        // Real glazing seen head-on reflects only a few percent, so scatter it.
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(white: 1, alpha: 1)
        glass.roughness.contents = NSNumber(value: 0.35)
        glass.metalness.contents = NSNumber(value: 0.0)
        glass.transparency = 0.05
        glass.blendMode = .alpha
        glass.writesToDepthBuffer = false
        let pane = SCNPlane(width: CGFloat(openRight - 0.04), height: CGFloat(shojiH - 0.04))
        let paneNode = SCNNode.make(pane, glass)
        paneNode.simdPosition = SIMD3<Float>(x: openRight / 2, y: (openTop + openBottom) / 2, z: -hd + 0.05)
        paneNode.castsShadow = false
        node.addChildNode(paneNode)

        return node
    }

    private static func frameBarInto(_ parent: SCNNode, _ mat: SCNMaterial,
                                     _ w: Float, _ h: Float, _ d: Float,
                                     _ x: Float, _ y: Float, _ z: Float) {
        let box = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(d), chamferRadius: 0.002)
        let n = SCNNode.make(box, mat)
        n.simdPosition = SIMD3<Float>(x: x, y: y, z: z)
        n.castsShadow = false
        parent.addChildNode(n)
    }

    private static func buildSideWall(room: RoomNode, plaster: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        let hw = RoomLayout.halfWidth
        let hd = RoomLayout.halfDepth
        let h = RoomLayout.ceilingHeight
        let t = RoomLayout.wallThickness

        // Opening for a small high window towards the far end.
        let openZ0: Float = -1.95, openZ1: Float = -0.55
        let openY0: Float = 0.82, openY1: Float = 1.66

        func panel(_ len: Float, _ ht: Float, _ z: Float, _ y: Float) {
            let box = SCNBox(width: CGFloat(len), height: CGFloat(ht), length: CGFloat(t), chamferRadius: 0)
            let n = SCNNode.make(box, plaster)
            n.simdPosition = SIMD3<Float>(x: hw, y: y, z: z)
            n.simdEulerAngles = SIMD3<Float>(x: 0, y: deg(90), z: 0)
            node.addChildNode(n)
        }
        panel(hd * 2, h - openY1, 0, openY1 + (h - openY1) / 2)
        panel(hd * 2, openY0, 0, openY0 / 2)
        panel(openZ0 + hd, openY1 - openY0, (-hd + openZ0) / 2, (openY0 + openY1) / 2)
        panel(hd - openZ1, openY1 - openY0, (hd + openZ1) / 2, (openY0 + openY1) / 2)

        // Shoji infill: this one stays closed, so it glows.
        let shojiMat = Materials.shoji()
        room.shojiMaterials.append(shojiMat)
        let paper = SCNPlane(width: CGFloat(openZ1 - openZ0), height: CGFloat(openY1 - openY0))
        let pNode = SCNNode.make(paper, shojiMat)
        pNode.simdPosition = SIMD3<Float>(x: hw - 0.05, y: (openY0 + openY1) / 2, z: (openZ0 + openZ1) / 2)
        pNode.simdEulerAngles = SIMD3<Float>(x: 0, y: deg(-90), z: 0)
        pNode.castsShadow = false
        node.addChildNode(pNode)

        let lattice = Materials.hinoki()
        for i in 1..<4 {
            let z = openZ0 + (openZ1 - openZ0) * Float(i) / 4
            let box = SCNBox(width: 0.016, height: CGFloat(openY1 - openY0), length: 0.014, chamferRadius: 0.002)
            let n = SCNNode.make(box, lattice)
            n.simdPosition = SIMD3<Float>(x: hw - 0.065, y: (openY0 + openY1) / 2, z: z)
            node.addChildNode(n)
        }
        for i in 1..<3 {
            let y = openY0 + (openY1 - openY0) * Float(i) / 3
            let box = SCNBox(width: 0.016, height: 0.014, length: CGFloat(openZ1 - openZ0), chamferRadius: 0.002)
            let n = SCNNode.make(box, lattice)
            n.simdPosition = SIMD3<Float>(x: hw - 0.065, y: y, z: (openZ0 + openZ1) / 2)
            node.addChildNode(n)
        }
        return node
    }

    private static func buildBackdrop(room: RoomNode, sky: SkyState) -> SCNNode {
        let node = SCNNode()
        node.name = "backdrop"

        let mat = Materials.backdrop(sky: sky)
        room.backdropMaterials.append(mat)
        let plane = SCNPlane(width: 12, height: 7)
        let n = SCNNode.make(plane, mat)
        n.simdPosition = SIMD3<Float>(x: 0.1, y: 1.6, z: -5.4)
        n.castsShadow = false
        node.addChildNode(n)

        let sideMat = Materials.backdrop(sky: sky)
        room.backdropMaterials.append(sideMat)
        let sidePlane = SCNPlane(width: 9, height: 5)
        let sn = SCNNode.make(sidePlane, sideMat)
        sn.simdPosition = SIMD3<Float>(x: 4.6, y: 1.5, z: -1.2)
        sn.simdEulerAngles = SIMD3<Float>(x: 0, y: deg(-90), z: 0)
        sn.castsShadow = false
        node.addChildNode(sn)
        return node
    }

    // MARK: - Furniture

    private static func buildFuton() -> SCNNode {
        let node = SCNNode()
        node.name = "futon"
        let c = RoomLayout.futonCenter
        let s = RoomLayout.futonSize

        let mattress = SCNBox(width: CGFloat(s.x), height: CGFloat(s.y), length: CGFloat(s.z), chamferRadius: 0.035)
        let mNode = SCNNode.make(mattress, Materials.linen(RGBColor(hex: 0xE7DFCD), key: "futonBase"))
        mNode.simdPosition = SIMD3<Float>(x: c.x, y: s.y / 2, z: c.z)
        node.addChildNode(mNode)

        // Folded duvet across the lower half.
        let duvet = SCNBox(width: CGFloat(s.x + 0.03), height: 0.10, length: 0.78, chamferRadius: 0.05)
        let dNode = SCNNode.make(duvet, Materials.futon())
        dNode.simdPosition = SIMD3<Float>(x: c.x, y: s.y + 0.05, z: c.z + 0.42)
        node.addChildNode(dNode)

        // Buckwheat pillow.
        let pillow = SCNBox(width: 0.46, height: 0.09, length: 0.24, chamferRadius: 0.045)
        let pNode = SCNNode.make(pillow, Materials.linen(RGBColor(hex: 0xF2ECDE), key: "pillow"))
        pNode.simdPosition = RoomLayout.pillowCenter
        node.addChildNode(pNode)

        return node
    }

    private static func buildTable(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "chabudai"
        let c = RoomLayout.tableCenter
        let s = RoomLayout.tableSize

        let top = SCNBox(width: CGFloat(s.x), height: 0.03, length: CGFloat(s.z), chamferRadius: 0.012)
        let tNode = SCNNode.make(top, Materials.lightWood())
        tNode.simdPosition = SIMD3<Float>(x: c.x, y: RoomLayout.tableTop, z: c.z)
        node.addChildNode(tNode)

        for dx in [-1, 1] as [Float] {
            for dz in [-1, 1] as [Float] {
                let leg = SCNCylinder(radius: 0.018, height: CGFloat(RoomLayout.tableTop - 0.015)).sized()
                let l = SCNNode.make(leg, Materials.darkWood())
                l.simdPosition = SIMD3<Float>(x: c.x + dx * (s.x / 2 - 0.06),
                                        y: (RoomLayout.tableTop - 0.015) / 2,
                                        z: c.z + dz * (s.z / 2 - 0.06))
                node.addChildNode(l)
            }
        }

        // A teacup, precariously placed.
        let cup = SCNTube(innerRadius: 0.030, outerRadius: 0.035, height: 0.055).sized()
        let cupNode = SCNNode.make(cup, Materials.ceramic(RGBColor(hex: 0xE8E4DA), key: "cup"))
        let cupBase = SCNCylinder(radius: 0.035, height: 0.006).sized()
        let baseNode = SCNNode.make(cupBase, Materials.ceramic(RGBColor(hex: 0xE8E4DA), key: "cup"))
        baseNode.simdPosition = SIMD3<Float>(x: 0, y: -0.0245, z: 0)
        cupNode.addChildNode(baseNode)
        let tea = SCNCylinder(radius: 0.029, height: 0.004).sized()
        let teaNode = SCNNode.make(tea, Materials.pbr(diffuse: UIColor(RGBColor(hex: 0x6E7B3E)), roughness: 0.15))
        teaNode.simdPosition = SIMD3<Float>(x: 0, y: 0.012, z: 0)
        cupNode.addChildNode(teaNode)
        cupNode.simdPosition = SIMD3<Float>(x: c.x + 0.20, y: RoomLayout.tableTop + 0.043, z: c.z - 0.10)
        node.addChildNode(cupNode)
        room.teacup = cupNode

        return node
    }

    private static func buildTansu() -> SCNNode {
        let node = SCNNode()
        node.name = "tansu"
        let c = RoomLayout.tansuCenter
        let s = RoomLayout.tansuSize

        let body = SCNBox(width: CGFloat(s.x), height: CGFloat(s.y), length: CGFloat(s.z), chamferRadius: 0.006)
        let b = SCNNode.make(body, Materials.darkWood())
        b.simdPosition = SIMD3<Float>(x: c.x, y: s.y / 2, z: c.z)
        node.addChildNode(b)

        // Drawer fronts with iron pulls.
        for i in 0..<3 {
            let y = 0.10 + Float(i) * 0.22
            let front = SCNBox(width: 0.012, height: 0.19, length: CGFloat(s.z - 0.05), chamferRadius: 0.004)
            let f = SCNNode.make(front, Materials.lightWood())
            f.simdPosition = SIMD3<Float>(x: c.x - s.x / 2 - 0.004, y: y, z: c.z)
            node.addChildNode(f)

            let pull = SCNTorus(ringRadius: 0.022, pipeRadius: 0.004).sized()
            let p = SCNNode.make(pull, Materials.metal(RGBColor(hex: 0x3A3A3E), roughness: 0.45))
            p.simdPosition = SIMD3<Float>(x: c.x - s.x / 2 - 0.014, y: y, z: c.z)
            p.simdEulerAngles = SIMD3<Float>(x: 0, y: 0, z: deg(90))
            node.addChildNode(p)
        }
        return node
    }

    private static func buildLantern(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "lantern"
        let c = RoomLayout.lanternCenter

        // Bamboo tripod.
        for i in 0..<3 {
            let a = Float(i) / 3 * .pi * 2
            let leg = SCNCylinder(radius: 0.010, height: 0.36).sized()
            let l = SCNNode.make(leg, Materials.darkWood())
            l.simdPosition = SIMD3<Float>(x: c.x + cosf(a) * 0.09, y: 0.18, z: c.z + sinf(a) * 0.09)
            l.simdEulerAngles = SIMD3<Float>(x: sinf(a) * 0.22, y: 0, z: -cosf(a) * 0.22)
            node.addChildNode(l)
        }

        // Paper globe.
        let paperMat = Materials.lanternPaper()
        room.lanternPaper = paperMat
        let globe = MeshBuilder.blob(radius: 0.17, scaleX: 1, scaleY: 1, scaleZ: 1.25, rings: 16, segments: 22)
        let g = SCNNode.make(globe, paperMat)
        g.simdPosition = SIMD3<Float>(x: c.x, y: RoomLayout.lanternLightHeight - 0.10, z: c.z)
        g.simdEulerAngles = SIMD3<Float>(x: deg(90), y: 0, z: 0)
        g.castsShadow = false
        node.addChildNode(g)

        // Ribs.
        for i in 0..<7 {
            let y = -0.14 + Float(i) * 0.047
            let ring = SCNTorus(ringRadius: CGFloat(0.172 * sqrtf(max(0.05, 1 - powf(y / 0.21, 2)))), pipeRadius: 0.0022).sized()
            let rNode = SCNNode.make(ring, Materials.hinoki())
            rNode.simdPosition = SIMD3<Float>(x: c.x, y: RoomLayout.lanternLightHeight - 0.10 + y, z: c.z)
            rNode.castsShadow = false
            node.addChildNode(rNode)
        }

        let light = SCNLight()
        light.type = .omni
        light.color = UIColor(red: 1.0, green: 0.82, blue: 0.56, alpha: 1)
        light.intensity = 0
        light.attenuationStartDistance = 0.3
        // The room's diagonal is about 5.6 m, so a 5 m reach was effectively no
        // falloff at all and the lantern lit the whole room like a ceiling light.
        // A paper andon throws a pool of warm light near its corner, not a flood.
        light.attenuationEndDistance = 2.8
        light.castsShadow = true
        light.shadowMode = .deferred
        light.shadowRadius = 8
        light.shadowSampleCount = 8
        light.shadowColor = UIColor(white: 0, alpha: 0.42)
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.simdPosition = SIMD3<Float>(x: c.x, y: RoomLayout.lanternLightHeight - 0.10, z: c.z)
        node.addChildNode(lightNode)
        room.lanternLight = light
        room.lanternLightNode = lightNode

        return node
    }

    private static func buildScroll() -> SCNNode {
        let node = SCNNode()
        node.name = "scroll"
        let plane = SCNPlane(width: 0.42, height: 1.05)
        let n = SCNNode.make(plane, Materials.scroll())
        n.simdPosition = SIMD3<Float>(x: -RoomLayout.halfWidth + 0.045, y: 1.42, z: -1.20)
        n.simdEulerAngles = SIMD3<Float>(x: 0, y: deg(90), z: 0)
        n.castsShadow = false
        node.addChildNode(n)

        for y in [1.95, 0.89] as [Float] {
            let rod = SCNCylinder(radius: 0.011, height: 0.50).sized()
            let r = SCNNode.make(rod, Materials.darkWood())
            r.simdPosition = SIMD3<Float>(x: -RoomLayout.halfWidth + 0.05, y: y, z: -1.20)
            r.simdEulerAngles = SIMD3<Float>(x: deg(90), y: 0, z: 0)
            node.addChildNode(r)
        }
        return node
    }

    private static func buildBonsai() -> SCNNode {
        let node = SCNNode()
        node.name = "bonsai"
        let base = SIMD3<Float>(x: RoomLayout.tansuCenter.x - 0.02,
                              y: RoomLayout.tansuSize.y,
                              z: RoomLayout.tansuCenter.z - 0.16)

        let pot = SCNTube(innerRadius: 0.075, outerRadius: 0.088, height: 0.07).sized()
        let p = SCNNode.make(pot, Materials.ceramic(RGBColor(hex: 0x5A4038), key: "pot"))
        p.simdPosition = SIMD3<Float>(x: base.x, y: base.y + 0.035, z: base.z)
        node.addChildNode(p)

        let soil = SCNCylinder(radius: 0.078, height: 0.05).sized()
        let s = SCNNode.make(soil, Materials.pbr(diffuse: UIColor(RGBColor(hex: 0x3A2E24)), roughness: 1))
        s.simdPosition = SIMD3<Float>(x: base.x, y: base.y + 0.045, z: base.z)
        node.addChildNode(s)

        let trunk = MeshBuilder.tube(length: 0.20, count: 6, segments: 8, radius: { t in
            0.016 * (1 - t * 0.55)
        }, offset: { t in
            Vec3(x: sinf(t * 3.2) * 0.035, y: 0, z: cosf(t * 2.1) * 0.02)
        })
        let tr = SCNNode.make(trunk, Materials.pbr(diffuse: UIColor(RGBColor(hex: 0x4A3A2C)), roughness: 0.9))
        tr.simdPosition = SIMD3<Float>(x: base.x, y: base.y + 0.06, z: base.z)
        tr.simdEulerAngles = SIMD3<Float>(x: deg(-90), y: 0, z: 0)
        node.addChildNode(tr)

        for (dx, dy, dz, r) in [(0.05, 0.24, 0.0, 0.075), (-0.045, 0.20, 0.03, 0.055), (0.01, 0.28, -0.03, 0.05)] as [(Float, Float, Float, Float)] {
            let canopy = MeshBuilder.blob(radius: r, scaleX: 1.25, scaleY: 0.62, scaleZ: 1.1, rings: 10, segments: 14)
            let c = SCNNode.make(canopy, Materials.foliage())
            c.simdPosition = SIMD3<Float>(x: base.x + dx, y: base.y + dy, z: base.z + dz)
            node.addChildNode(c)
        }
        return node
    }

    private static func buildCatTree() -> SCNNode {
        let node = SCNNode()
        node.name = "catTree"
        let b = RoomLayout.catTreeBase

        let base = SCNBox(width: 0.46, height: 0.05, length: 0.46, chamferRadius: 0.012)
        let bn = SCNNode.make(base, Materials.linen(RGBColor(hex: 0xBFAE92), key: "treeBase"))
        bn.simdPosition = SIMD3<Float>(x: b.x, y: 0.025, z: b.z)
        node.addChildNode(bn)

        // Two sisal posts.
        func post(x: Float, z: Float, height: Float) {
            let p = SCNCylinder(radius: 0.048, height: CGFloat(height)).sized()
            let pn = SCNNode.make(p, Materials.sisal())
            pn.simdPosition = SIMD3<Float>(x: x, y: height / 2 + 0.05, z: z)
            node.addChildNode(pn)
        }
        post(x: b.x - 0.13, z: b.z + 0.02, height: RoomLayout.catTreeMidPlatform.y - 0.05)
        post(x: b.x + 0.11, z: b.z - 0.06, height: RoomLayout.catTreeTopPlatform.y - 0.05)

        // Platforms.
        for p in [RoomLayout.catTreeMidPlatform, RoomLayout.catTreeTopPlatform] {
            let plat = SCNBox(width: 0.44, height: 0.035, length: 0.40, chamferRadius: 0.014)
            let pn = SCNNode.make(plat, Materials.linen(RGBColor(hex: 0xCBBB9E), key: "platform"))
            pn.simdPosition = SIMD3<Float>(x: p.x, y: p.y, z: p.z)
            node.addChildNode(pn)
        }

        // Dangling pompom on a string.
        let string = SCNCylinder(radius: 0.0018, height: 0.22).sized()
        let sn = SCNNode.make(string, Materials.pbr(diffuse: UIColor(white: 0.85, alpha: 1), roughness: 0.9))
        sn.simdPosition = SIMD3<Float>(x: b.x + 0.20, y: RoomLayout.catTreeTopPlatform.y - 0.11, z: b.z + 0.14)
        node.addChildNode(sn)
        let pom = SCNSphere(radius: 0.030).sized()
        let pn = SCNNode.make(pom, Materials.linen(RGBColor(hex: 0xC4576A), key: "pompom"))
        pn.simdPosition = SIMD3<Float>(x: b.x + 0.20, y: RoomLayout.catTreeTopPlatform.y - 0.24, z: b.z + 0.14)
        pn.name = "pompom"
        node.addChildNode(pn)

        return node
    }

    private static func buildCatBed() -> SCNNode {
        let node = SCNNode()
        node.name = "catBed"
        let c = RoomLayout.catBedCenter

        let rim = SCNTorus(ringRadius: 0.21, pipeRadius: 0.058).sized()
        let r = SCNNode.make(rim, Materials.linen(RGBColor(hex: 0x8E9E8C), key: "bedRim"))
        r.simdPosition = SIMD3<Float>(x: c.x, y: 0.058, z: c.z)
        node.addChildNode(r)

        let cushion = MeshBuilder.blob(radius: 0.20, scaleX: 1.05, scaleY: 1.05, scaleZ: 0.22, rings: 10, segments: 20)
        let cu = SCNNode.make(cushion, Materials.linen(RGBColor(hex: 0xD9D2C0), key: "bedCushion"))
        cu.simdPosition = SIMD3<Float>(x: c.x, y: 0.048, z: c.z)
        cu.simdEulerAngles = SIMD3<Float>(x: deg(90), y: 0, z: 0)
        node.addChildNode(cu)
        return node
    }

    private static func buildFeeder(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "feeder"
        let b = RoomLayout.feederBase
        let plasticMat = Materials.plastic(RGBColor(hex: 0xF0EDE7))

        let hopper = SCNBox(width: 0.20, height: 0.34, length: 0.22, chamferRadius: 0.045)
        let h = SCNNode.make(hopper, plasticMat)
        h.simdPosition = SIMD3<Float>(x: b.x, y: 0.17, z: b.z)
        node.addChildNode(h)

        let chute = SCNBox(width: 0.20, height: 0.10, length: 0.14, chamferRadius: 0.03)
        let ch = SCNNode.make(chute, plasticMat)
        ch.simdPosition = SIMD3<Float>(x: b.x, y: 0.09, z: b.z + 0.13)
        node.addChildNode(ch)

        let bowl = SCNTube(innerRadius: 0.070, outerRadius: 0.082, height: 0.036).sized()
        let bo = SCNNode.make(bowl, Materials.ceramic(RGBColor(hex: 0xDDD8CE), key: "bowl"))
        bo.simdPosition = SIMD3<Float>(x: RoomLayout.feederBowl.x, y: 0.018, z: RoomLayout.feederBowl.z)
        node.addChildNode(bo)
        let bowlFloor = SCNCylinder(radius: 0.082, height: 0.006).sized()
        let bf = SCNNode.make(bowlFloor, Materials.ceramic(RGBColor(hex: 0xDDD8CE), key: "bowl"))
        bf.simdPosition = SIMD3<Float>(x: RoomLayout.feederBowl.x, y: 0.003, z: RoomLayout.feederBowl.z)
        node.addChildNode(bf)

        // Kibble level, scaled at runtime by RoomState.feederFood.
        let food = SCNCylinder(radius: 0.066, height: 0.030).sized()
        let fn = SCNNode.make(food, Materials.pbr(diffuse: UIColor(RGBColor(hex: 0x8A5A32)), roughness: 0.95))
        fn.simdPosition = SIMD3<Float>(x: RoomLayout.feederBowl.x, y: 0.019, z: RoomLayout.feederBowl.z)
        node.addChildNode(fn)
        room.foodPile = fn

        // A little status LED.
        let led = SCNSphere(radius: 0.006).sized()
        let ledMat = Materials.pbr(diffuse: UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1), roughness: 0.2)
        ledMat.emission.contents = UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1)
        ledMat.emission.intensity = 0.9
        let ln = SCNNode.make(led, ledMat)
        ln.simdPosition = SIMD3<Float>(x: b.x - 0.06, y: 0.30, z: b.z + 0.10)
        node.addChildNode(ln)

        return node
    }

    private static func buildFountain(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "fountain"
        let b = RoomLayout.fountainBase
        let shell = Materials.plastic(RGBColor(hex: 0xE9E6DF))

        let cx = b.x
        let cz = b.z + 0.24

        let basin = SCNTube(innerRadius: 0.105, outerRadius: 0.125, height: 0.085).sized()
        let ba = SCNNode.make(basin, shell)
        ba.simdPosition = SIMD3<Float>(x: cx, y: 0.043, z: cz)
        node.addChildNode(ba)
        let basinFloor = SCNCylinder(radius: 0.125, height: 0.008).sized()
        let bf = SCNNode.make(basinFloor, shell)
        bf.simdPosition = SIMD3<Float>(x: cx, y: 0.004, z: cz)
        node.addChildNode(bf)

        // Pump tower at the back with a curved spout arcing forward.
        let tower = SCNCylinder(radius: 0.045, height: 0.17).sized()
        let tw = SCNNode.make(tower, shell)
        tw.simdPosition = SIMD3<Float>(x: cx, y: 0.09, z: cz - 0.058)
        node.addChildNode(tw)

        let spout = SCNTorus(ringRadius: 0.045, pipeRadius: 0.008).sized()
        let sp = SCNNode.make(spout, shell)
        sp.simdPosition = SIMD3<Float>(x: cx, y: 0.175, z: cz - 0.028)
        sp.simdEulerAngles = SIMD3<Float>(x: 0, y: 0, z: deg(90))
        node.addChildNode(sp)

        // Water surface (scaled with the level) and the falling stream.
        let surface = SCNCylinder(radius: 0.100, height: 0.004).sized()
        let su = SCNNode.make(surface, Materials.water())
        su.simdPosition = SIMD3<Float>(x: cx, y: 0.055, z: cz)
        su.castsShadow = false
        node.addChildNode(su)
        room.waterSurface = su

        let stream = SCNCylinder(radius: 0.006, height: 0.11).sized()
        let st = SCNNode.make(stream, Materials.water())
        st.simdPosition = SIMD3<Float>(x: cx, y: 0.115, z: cz + 0.010)
        st.castsShadow = false
        node.addChildNode(st)
        room.fountainStream = st

        return node
    }

    private static func buildLitterBox(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "litterBox"
        let c = RoomLayout.litterBoxCenter
        let shell = Materials.plastic(RGBColor(hex: 0x5B6470))

        let tray = SCNBox(width: 0.44, height: 0.16, length: 0.52, chamferRadius: 0.03)
        let t = SCNNode.make(tray, shell)
        t.simdPosition = SIMD3<Float>(x: c.x, y: 0.08, z: c.z)
        node.addChildNode(t)

        // Hood with an opening facing into the room.
        let hood = MeshBuilder.blob(radius: 0.26, scaleX: 0.85, scaleY: 0.62, scaleZ: 1.0, rings: 10, segments: 16)
        let hoodMat = Materials.plastic(RGBColor(hex: 0x6B7480))
        hoodMat.isDoubleSided = true
        let h = SCNNode.make(hood, hoodMat)
        h.simdPosition = SIMD3<Float>(x: c.x, y: 0.16, z: c.z)
        node.addChildNode(h)

        // Dark entrance so it reads as an opening.
        let entry = SCNPlane(width: 0.24, height: 0.22)
        let entryMat = Materials.pbr(diffuse: UIColor(white: 0.06, alpha: 1), roughness: 1)
        let e = SCNNode.make(entry, entryMat)
        e.simdPosition = SIMD3<Float>(x: c.x, y: 0.23, z: c.z + 0.255)
        node.addChildNode(e)

        let substrate = SCNBox(width: 0.40, height: 0.05, length: 0.48, chamferRadius: 0.01)
        let s = SCNNode.make(substrate, Materials.litter())
        s.simdPosition = SIMD3<Float>(x: c.x, y: 0.12, z: c.z)
        node.addChildNode(s)
        room.litterSurface = s

        return node
    }

    private static func buildToys(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "toys"

        // Basket.
        let basket = SCNTube(innerRadius: 0.11, outerRadius: 0.125, height: 0.12).sized()
        let b = SCNNode.make(basket, Materials.sisal())
        b.simdPosition = SIMD3<Float>(x: RoomLayout.toyBasketCenter.x, y: 0.06, z: RoomLayout.toyBasketCenter.z)
        node.addChildNode(b)
        let basketFloor = SCNCylinder(radius: 0.125, height: 0.008).sized()
        let bf = SCNNode.make(basketFloor, Materials.sisal())
        bf.simdPosition = SIMD3<Float>(x: RoomLayout.toyBasketCenter.x, y: 0.004, z: RoomLayout.toyBasketCenter.z)
        node.addChildNode(bf)

        // Toy mouse on the floor.
        let mouseBody = MeshBuilder.blob(radius: 0.035, scaleX: 0.7, scaleY: 0.7, scaleZ: 1.5, rings: 8, segments: 12)
        let mouse = SCNNode.make(mouseBody, Materials.linen(RGBColor(hex: 0x9A8FA8), key: "mouse"))
        mouse.simdPosition = SIMD3<Float>(x: RoomLayout.toyMouseSpot.x, y: 0.026, z: RoomLayout.toyMouseSpot.z)
        mouse.simdEulerAngles = SIMD3<Float>(x: 0, y: deg(35), z: 0)
        mouse.name = "toyMouse"
        node.addChildNode(mouse)
        let tail = MeshBuilder.strand(length: 0.07, thickness: 0.0022, droop: 0.2)
        let tn = SCNNode.make(tail, Materials.pbr(diffuse: UIColor(white: 0.75, alpha: 1), roughness: 0.8))
        tn.simdPosition = SIMD3<Float>(x: 0, y: 0.004, z: -0.05)
        tn.simdEulerAngles = SIMD3<Float>(x: 0, y: .pi, z: 0)
        mouse.addChildNode(tn)
        room.toyMouse = mouse

        // Jingle ball.
        let ball = SCNSphere(radius: 0.024).sized()
        let ballMat = Materials.plastic(RGBColor(hex: 0xE0A83A))
        let bn = SCNNode.make(ball, ballMat)
        bn.simdPosition = SIMD3<Float>(x: RoomLayout.toyBallSpot.x, y: 0.024, z: RoomLayout.toyBallSpot.z)
        bn.name = "toyBall"
        node.addChildNode(bn)
        room.toyBall = bn

        return node
    }

    private static func buildZabuton() -> SCNNode {
        let node = SCNNode()
        node.name = "zabuton"
        let cushion = SCNBox(width: 0.60, height: 0.09, length: 0.60, chamferRadius: 0.05)
        let c = SCNNode.make(cushion, Materials.linen(RGBColor(hex: 0x7A4B4B), key: "zabuton"))
        c.simdPosition = SIMD3<Float>(x: RoomLayout.cameraPosition.x, y: 0.045, z: RoomLayout.cameraPosition.z + 0.10)
        node.addChildNode(c)
        return node
    }

    /// A soft warm rectangle on the tatami where sunlight lands.
    private static func buildSunPatch(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "sunPatchHolder"
        let plane = SCNPlane(width: 0.95, height: 0.72)
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.diffuse.contents = sunPatchImage()
        mat.blendMode = .add
        mat.writesToDepthBuffer = false
        mat.readsFromDepthBuffer = true
        let n = SCNNode.make(plane, mat)
        n.simdEulerAngles = SIMD3<Float>(x: deg(-90), y: 0, z: 0)
        n.simdPosition = SIMD3<Float>(x: 0.3, y: 0.032, z: -1.1)
        n.castsShadow = false
        n.opacity = 0
        node.addChildNode(n)
        room.sunPatch = n
        return node
    }

    private static func sunPatchImage() -> UIImage {
        let size = CGSize(width: 128, height: 128)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { c in
            let ctx = c.cgContext
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            let colors = [UIColor(red: 1.0, green: 0.88, blue: 0.66, alpha: 1).cgColor,
                          UIColor.black.cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 64, y: 64), startRadius: 12,
                                       endCenter: CGPoint(x: 64, y: 64), endRadius: 62, options: [])
            }
        }
    }

    /// Dust motes drifting in the light beam. Subtle, but it sells the room.
    private static func buildDustMotes(room: RoomNode) -> SCNNode {
        let node = SCNNode()
        node.name = "dust"
        guard RenderQuality.dustMotes else { return node }

        let particles = SCNParticleSystem()
        particles.birthRate = 26
        particles.particleLifeSpan = 14
        particles.particleLifeSpanVariation = 6
        particles.particleSize = 0.0035
        particles.particleSizeVariation = 0.002
        particles.particleColor = UIColor(white: 1.0, alpha: 0.55)
        particles.particleColorVariation = SCNVector4(x: 0.05, y: 0.05, z: 0.05, w: 0.25)
        particles.emitterShape = SCNBox(width: 2.8, height: 1.6, length: 2.4, chamferRadius: 0)
        particles.birthLocation = .volume
        particles.particleVelocity = 0.012
        particles.particleVelocityVariation = 0.02
        particles.acceleration = SCNVector3(x: 0.002, y: -0.0035, z: 0)
        particles.spreadingAngle = 180
        particles.blendMode = .additive
        particles.isLightingEnabled = false
        particles.isAffectedByGravity = false
        particles.particleImage = softDotImage()

        let emitter = SCNNode()
        emitter.simdPosition = SIMD3<Float>(x: 0.1, y: 1.05, z: -1.1)
        emitter.addParticleSystem(particles)
        node.addChildNode(emitter)
        room.dustMotes = emitter
        return node
    }

    private static func softDotImage() -> UIImage {
        let size = CGSize(width: 32, height: 32)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { c in
            let ctx = c.cgContext
            let colors = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                       endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
            }
        }
    }
}
