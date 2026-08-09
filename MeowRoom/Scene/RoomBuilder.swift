import Foundation
import RealityKit
import UIKit

/// The whole room, generated procedurally. Holds references to the bits that change
/// over the day (shoji glow, lantern, garden backdrop) and with play (food, water, teacup).
///
/// Materials are values in RealityKit, not shared objects, so the things that
/// change over the day are held here as the *entities* wearing them rather than
/// as materials to mutate in place. That is a real difference: under SceneKit one
/// `SCNMaterial` could be handed to twelve nodes and dimmed once. Here, dimming
/// means writing the material back onto each entity that wears it, which is why
/// these are arrays of entities and why `withMaterial` exists.
final class RoomNode {
    let root = Entity()

    var shojiPanels: [Entity] = []
    var backdropPanels: [Entity] = []
    var lanternPaperPanels: [Entity] = []
    var lanternLight: Entity?

    var foodPile: Entity?
    var waterSurface: Entity?
    var fountainStream: Entity?
    var litterSurface: Entity?
    var teacup: Entity?
    var sunPatch: Entity?
    var treatNode: Entity?
    var toyMouse: Entity?
    var toyBall: Entity?
    var dustMotes: Entity?
}

enum RoomBuilder {

    static func build(sky: SkyState) -> RoomNode {
        let room = RoomNode()
        let r = room.root
        r.name = "room"

        r.addChild(buildFloor())
        r.addChild(buildCeiling())
        r.addChild(buildWalls(room: room))
        r.addChild(buildBackdrop(room: room, sky: sky))
        r.addChild(buildFuton())
        r.addChild(buildTable(room: room))
        r.addChild(buildTansu())
        r.addChild(buildLantern(room: room))
        r.addChild(buildScroll())
        r.addChild(buildBonsai())
        r.addChild(buildCatTree())
        r.addChild(buildCatBed())
        r.addChild(buildFeeder(room: room))
        r.addChild(buildFountain(room: room))
        r.addChild(buildLitterBox(room: room))
        r.addChild(buildToys(room: room))
        r.addChild(buildZabuton())
        r.addChild(buildSunPatch(room: room))
        r.addChild(buildDustMotes(room: room))

        return room
    }

    // MARK: - Shell

    private static func buildFloor() -> Entity {
        let node = Entity()
        node.name = "floor"

        let W = RoomLayout.halfWidth * 2
        let D = RoomLayout.halfDepth * 2

        // Sub-floor slab so nothing shows through the seams.
        let slab = MeshBuilder.box(width: W, height: 0.05, length: D, chamfer: 0)
        let slabNode = Entity.make(slab, Materials.darkWood())
        slabNode.position = SIMD3<Float>(x: 0, y: -0.026, z: 0)
        node.addChild(slabNode)

        // Six tatami mats in a 3 × 2 grid, each with a dark cloth edge.
        let cols = 3, rows = 2
        let matW = W / Float(cols), matD = D / Float(rows)
        let gap: Float = 0.012
        for c in 0..<cols {
            for rw in 0..<rows {
                let cx = -RoomLayout.halfWidth + matW * (Float(c) + 0.5)
                let cz = -RoomLayout.halfDepth + matD * (Float(rw) + 0.5)

                let mat = MeshBuilder.box(width: matW - gap, height: 0.028,
                                          length: matD - gap, chamfer: 0.004,
                                          faceMaterials: true)
                let m = Materials.tatami()
                let border = Materials.tatamiBorder()
                // Sides get the cloth border; top and bottom get the woven rush,
                // and the chamfer round every edge goes to the border too, which
                // is what binds a real mat.
                let n = Entity.make(mat, [border, border, border, border, m, m])
                n.position = SIMD3<Float>(x: cx, y: 0.014, z: cz)
                // Alternate the weave direction like a real tatami room.
                if (c + rw) % 2 == 0 { n.eulerAngles = SIMD3<Float>(x: 0, y: deg(90), z: 0) }
                node.addChild(n)
            }
        }
        return node
    }

    private static func buildCeiling() -> Entity {
        let node = Entity()
        node.name = "ceiling"
        var plank = Materials.darkWood()
        plank.faceCulling = .none

        let ceiling = MeshBuilder.box(width: RoomLayout.halfWidth * 2,
                                      height: 0.04,
                                      length: RoomLayout.halfDepth * 2,
                                      chamfer: 0.006)
        let cNode = Entity.make(ceiling, plank)
        cNode.position = SIMD3<Float>(x: 0, y: RoomLayout.ceilingHeight, z: 0)
        node.addChild(cNode)

        // Two exposed beams.
        for z in [-0.90, 0.55] as [Float] {
            let beam = MeshBuilder.box(width: RoomLayout.halfWidth * 2, height: 0.11, length: 0.09, chamfer: 0.01)
            let b = Entity.make(beam, Materials.darkWood())
            b.position = SIMD3<Float>(x: 0, y: RoomLayout.ceilingHeight - 0.075, z: z)
            node.addChild(b)
        }
        return node
    }

    private static func buildWalls(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "walls"

        let hw = RoomLayout.halfWidth
        let hd = RoomLayout.halfDepth
        let h = RoomLayout.ceilingHeight
        let t = RoomLayout.wallThickness
        var plasterMat = Materials.plaster()
        plasterMat.faceCulling = .none

        func wallPanel(width: Float, height: Float, position: SIMD3<Float>, yaw: Float, material: PhysicallyBasedMaterial) -> Entity {
            let box = MeshBuilder.box(width: width, height: height, length: t, chamfer: 0)
            let n = Entity.make(box, material)
            n.position = position
            n.eulerAngles = SIMD3<Float>(x: 0, y: yaw, z: 0)
            return n
        }

        // +Z wall (behind the player) and -X wall: plain plaster with a wooden dado rail.
        node.addChild(wallPanel(width: hw * 2, height: h,
                                    position: SIMD3<Float>(x: 0, y: h / 2, z: hd), yaw: 0, material: plasterMat))
        node.addChild(wallPanel(width: hd * 2, height: h,
                                    position: SIMD3<Float>(x: -hw, y: h / 2, z: 0), yaw: deg(90), material: plasterMat))

        // +X wall with a small side window near the far corner.
        node.addChild(buildSideWall(room: room, plaster: plasterMat))

        // -Z wall: the shoji window wall.
        node.addChild(buildWindowWall(room: room, plaster: plasterMat))

        // Skirting and a picture rail tie the room together.
        let trim = Materials.darkWood()
        for (pos, yaw, len) in [(SIMD3<Float>(x: 0, y: 0.055, z: hd - 0.01), Float(0), hw * 2),
                                (SIMD3<Float>(x: -hw + 0.01, y: 0.055, z: 0), deg(90), hd * 2),
                                (SIMD3<Float>(x: hw - 0.01, y: 0.055, z: 0), deg(90), hd * 2)] {
            let box = MeshBuilder.box(width: len, height: 0.10, length: 0.02, chamfer: 0.003)
            let n = Entity.make(box, trim)
            n.position = pos
            n.eulerAngles = SIMD3<Float>(x: 0, y: yaw, z: 0)
            node.addChild(n)
        }
        return node
    }

    private static func buildWindowWall(room: RoomNode, plaster: PhysicallyBasedMaterial) -> Entity {
        let node = Entity()
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
            let box = MeshBuilder.box(width: w, height: ht, length: t, chamfer: 0)
            let n = Entity.make(box, plaster)
            n.position = SIMD3<Float>(x: x, y: y, z: -hd)
            node.addChild(n)
        }
        // Header, sill and jambs around the opening.
        panel(hw * 2, h - openTop, 0, openTop + (h - openTop) / 2)
        panel(hw * 2, openBottom, 0, openBottom / 2)
        panel(hw + openLeft, openTop - openBottom, (-hw + openLeft) / 2, (openTop + openBottom) / 2)
        panel(hw - openRight, openTop - openBottom, (hw + openRight) / 2, (openTop + openBottom) / 2)

        // Wooden window frame.
        let frameMat = Materials.darkWood()
        func frameBar(_ w: Float, _ ht: Float, _ d: Float, _ x: Float, _ y: Float, _ z: Float) {
            let box = MeshBuilder.box(width: w, height: ht, length: d, chamfer: 0.004)
            let n = Entity.make(box, frameMat)
            n.position = SIMD3<Float>(x: x, y: y, z: z)
            node.addChild(n)
        }
        let zFrame = -hd + 0.035
        frameBar(openRight - openLeft + 0.10, 0.07, 0.07, 0, openTop + 0.02, zFrame)
        frameBar(openRight - openLeft + 0.10, 0.09, 0.14, 0, openBottom - 0.02, zFrame + 0.04)  // sill the cat sits on
        frameBar(0.07, openTop - openBottom, 0.07, openLeft - 0.02, (openTop + openBottom) / 2, zFrame)
        frameBar(0.07, openTop - openBottom, 0.07, openRight + 0.02, (openTop + openBottom) / 2, zFrame)
        frameBar(0.06, openTop - openBottom, 0.06, 0, (openTop + openBottom) / 2, zFrame)       // centre mullion

        // Left half: closed shoji screen with a lattice.
        let shojiW = -openLeft
        let shojiH = openTop - openBottom
        let paper = MeshBuilder.plane(width: shojiW - 0.04, height: shojiH - 0.04)
        let paperNode = Entity.make(paper, Materials.shoji())
        room.shojiPanels.append(paperNode)
        paperNode.position = SIMD3<Float>(x: openLeft / 2, y: (openTop + openBottom) / 2, z: -hd + 0.055)
        node.addChild(paperNode)

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

        // Right half: slid open, and nothing in it.
        //
        // There used to be a pane of glass here — white, five percent opaque, not
        // writing depth. It is gone, and the window is an actual hole now.
        //
        // It earned that twice over. Real glazing seen head-on reflects a few
        // percent and is invisible; this one was neither. Its specular outlived
        // its transparency, so a mirrored paper lantern a metre away once made the
        // open half of the window brighter at ten at night than at noon — patched
        // at the time by roughening the glass rather than by asking what the glass
        // was for. And a transparent sheet directly in front of the one thing in
        // the room the player looks *through* is the worst place in the scene to
        // have to reason about blend ordering.
        //
        // What is behind it is the garden, and the garden is what should be there.

        return node
    }

    private static func frameBarInto(_ parent: Entity, _ mat: PhysicallyBasedMaterial,
                                     _ w: Float, _ h: Float, _ d: Float,
                                     _ x: Float, _ y: Float, _ z: Float) {
        let box = MeshBuilder.box(width: w, height: h, length: d, chamfer: 0.002)
        let n = Entity.make(box, mat)
        n.position = SIMD3<Float>(x: x, y: y, z: z)
        parent.addChild(n)
    }

    private static func buildSideWall(room: RoomNode, plaster: PhysicallyBasedMaterial) -> Entity {
        let node = Entity()
        let hw = RoomLayout.halfWidth
        let hd = RoomLayout.halfDepth
        let h = RoomLayout.ceilingHeight
        let t = RoomLayout.wallThickness

        // Opening for a small high window towards the far end.
        let openZ0: Float = -1.95, openZ1: Float = -0.55
        let openY0: Float = 0.82, openY1: Float = 1.66

        func panel(_ len: Float, _ ht: Float, _ z: Float, _ y: Float) {
            let box = MeshBuilder.box(width: len, height: ht, length: t, chamfer: 0)
            let n = Entity.make(box, plaster)
            n.position = SIMD3<Float>(x: hw, y: y, z: z)
            n.eulerAngles = SIMD3<Float>(x: 0, y: deg(90), z: 0)
            node.addChild(n)
        }
        panel(hd * 2, h - openY1, 0, openY1 + (h - openY1) / 2)
        panel(hd * 2, openY0, 0, openY0 / 2)
        panel(openZ0 + hd, openY1 - openY0, (-hd + openZ0) / 2, (openY0 + openY1) / 2)
        panel(hd - openZ1, openY1 - openY0, (hd + openZ1) / 2, (openY0 + openY1) / 2)

        // Shoji infill: this one stays closed, so it glows.
        let paper = MeshBuilder.plane(width: openZ1 - openZ0, height: openY1 - openY0)
        let pNode = Entity.make(paper, Materials.shoji())
        room.shojiPanels.append(pNode)
        pNode.position = SIMD3<Float>(x: hw - 0.05, y: (openY0 + openY1) / 2, z: (openZ0 + openZ1) / 2)
        pNode.eulerAngles = SIMD3<Float>(x: 0, y: deg(-90), z: 0)
        node.addChild(pNode)

        let lattice = Materials.hinoki()
        for i in 1..<4 {
            let z = openZ0 + (openZ1 - openZ0) * Float(i) / 4
            let box = MeshBuilder.box(width: 0.016, height: openY1 - openY0, length: 0.014, chamfer: 0.002)
            let n = Entity.make(box, lattice)
            n.position = SIMD3<Float>(x: hw - 0.065, y: (openY0 + openY1) / 2, z: z)
            node.addChild(n)
        }
        for i in 1..<3 {
            let y = openY0 + (openY1 - openY0) * Float(i) / 3
            let box = MeshBuilder.box(width: 0.016, height: 0.014, length: openZ1 - openZ0, chamfer: 0.002)
            let n = Entity.make(box, lattice)
            n.position = SIMD3<Float>(x: hw - 0.065, y: y, z: (openZ0 + openZ1) / 2)
            node.addChild(n)
        }
        return node
    }

    private static func buildBackdrop(room: RoomNode, sky: SkyState) -> Entity {
        let node = Entity()
        node.name = "backdrop"

        let plane = MeshBuilder.plane(width: 12, height: 7)
        let n = Entity.make(plane, Materials.backdrop(sky: sky))
        room.backdropPanels.append(n)
        n.position = SIMD3<Float>(x: 0.1, y: 1.6, z: -5.4)
        node.addChild(n)

        let sidePlane = MeshBuilder.plane(width: 9, height: 5)
        let sn = Entity.make(sidePlane, Materials.backdrop(sky: sky))
        room.backdropPanels.append(sn)
        sn.position = SIMD3<Float>(x: 4.6, y: 1.5, z: -1.2)
        sn.eulerAngles = SIMD3<Float>(x: 0, y: deg(-90), z: 0)
        node.addChild(sn)
        return node
    }

    // MARK: - Furniture

    private static func buildFuton() -> Entity {
        let node = Entity()
        node.name = "futon"
        let c = RoomLayout.futonCenter
        let s = RoomLayout.futonSize

        let mattress = MeshBuilder.box(width: s.x, height: s.y, length: s.z, chamfer: 0.035)
        let mNode = Entity.make(mattress, Materials.linen(RGBColor(hex: 0xE7DFCD), key: "futonBase"))
        mNode.position = SIMD3<Float>(x: c.x, y: s.y / 2, z: c.z)
        node.addChild(mNode)

        // Folded duvet across the lower half.
        let duvet = MeshBuilder.box(width: s.x + 0.03, height: 0.10, length: 0.78, chamfer: 0.05)
        let dNode = Entity.make(duvet, Materials.futon())
        dNode.position = SIMD3<Float>(x: c.x, y: s.y + 0.05, z: c.z + 0.42)
        node.addChild(dNode)

        // Buckwheat pillow.
        let pillow = MeshBuilder.box(width: 0.46, height: 0.09, length: 0.24, chamfer: 0.045)
        let pNode = Entity.make(pillow, Materials.linen(RGBColor(hex: 0xF2ECDE), key: "pillow"))
        pNode.position = RoomLayout.pillowCenter
        node.addChild(pNode)

        return node
    }

    private static func buildTable(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "chabudai"
        let c = RoomLayout.tableCenter
        let s = RoomLayout.tableSize

        let top = MeshBuilder.box(width: s.x, height: 0.03, length: s.z, chamfer: 0.012)
        let tNode = Entity.make(top, Materials.lightWood())
        tNode.position = SIMD3<Float>(x: c.x, y: RoomLayout.tableTop, z: c.z)
        node.addChild(tNode)

        for dx in [-1, 1] as [Float] {
            for dz in [-1, 1] as [Float] {
                let leg = MeshBuilder.cylinder(radius: 0.018, height: RoomLayout.tableTop - 0.015)
                let l = Entity.make(leg, Materials.darkWood())
                l.position = SIMD3<Float>(x: c.x + dx * (s.x / 2 - 0.06),
                                        y: (RoomLayout.tableTop - 0.015) / 2,
                                        z: c.z + dz * (s.z / 2 - 0.06))
                node.addChild(l)
            }
        }

        // A teacup, precariously placed.
        let cup = MeshBuilder.pipe(innerRadius: 0.030, outerRadius: 0.035, height: 0.055)
        let cupNode = Entity.make(cup, Materials.ceramic(RGBColor(hex: 0xE8E4DA), key: "cup"))
        let cupBase = MeshBuilder.cylinder(radius: 0.035, height: 0.006)
        let baseNode = Entity.make(cupBase, Materials.ceramic(RGBColor(hex: 0xE8E4DA), key: "cup"))
        baseNode.position = SIMD3<Float>(x: 0, y: -0.0245, z: 0)
        cupNode.addChild(baseNode)
        let tea = MeshBuilder.cylinder(radius: 0.029, height: 0.004)
        let teaNode = Entity.make(tea, Materials.pbr(color: RGBColor(hex: 0x6E7B3E), roughness: 0.15))
        teaNode.position = SIMD3<Float>(x: 0, y: 0.012, z: 0)
        cupNode.addChild(teaNode)
        cupNode.position = SIMD3<Float>(x: c.x + 0.20, y: RoomLayout.tableTop + 0.043, z: c.z - 0.10)
        node.addChild(cupNode)
        room.teacup = cupNode

        return node
    }

    private static func buildTansu() -> Entity {
        let node = Entity()
        node.name = "tansu"
        let c = RoomLayout.tansuCenter
        let s = RoomLayout.tansuSize

        let body = MeshBuilder.box(width: s.x, height: s.y, length: s.z, chamfer: 0.006)
        let b = Entity.make(body, Materials.darkWood())
        b.position = SIMD3<Float>(x: c.x, y: s.y / 2, z: c.z)
        node.addChild(b)

        // Drawer fronts with iron pulls.
        for i in 0..<3 {
            let y = 0.10 + Float(i) * 0.22
            let front = MeshBuilder.box(width: 0.012, height: 0.19, length: s.z - 0.05, chamfer: 0.004)
            let f = Entity.make(front, Materials.lightWood())
            f.position = SIMD3<Float>(x: c.x - s.x / 2 - 0.004, y: y, z: c.z)
            node.addChild(f)

            let pull = MeshBuilder.torus(ringRadius: 0.022, pipeRadius: 0.004)
            let p = Entity.make(pull, Materials.metal(RGBColor(hex: 0x3A3A3E), roughness: 0.45))
            p.position = SIMD3<Float>(x: c.x - s.x / 2 - 0.014, y: y, z: c.z)
            p.eulerAngles = SIMD3<Float>(x: 0, y: 0, z: deg(90))
            node.addChild(p)
        }
        return node
    }

    private static func buildLantern(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "lantern"
        let c = RoomLayout.lanternCenter

        // Bamboo tripod.
        for i in 0..<3 {
            let a = Float(i) / 3 * .pi * 2
            let leg = MeshBuilder.cylinder(radius: 0.010, height: 0.36)
            let l = Entity.make(leg, Materials.darkWood())
            l.position = SIMD3<Float>(x: c.x + cosf(a) * 0.09, y: 0.18, z: c.z + sinf(a) * 0.09)
            l.eulerAngles = SIMD3<Float>(x: sinf(a) * 0.22, y: 0, z: -cosf(a) * 0.22)
            node.addChild(l)
        }

        // Paper globe.
        let globe = MeshBuilder.blob(radius: 0.17, scaleX: 1, scaleY: 1, scaleZ: 1.25, rings: 16, segments: 22)
        let g = Entity.make(globe, Materials.lanternPaper())
        room.lanternPaperPanels.append(g)
        g.position = SIMD3<Float>(x: c.x, y: RoomLayout.lanternLightHeight - 0.10, z: c.z)
        g.eulerAngles = SIMD3<Float>(x: deg(90), y: 0, z: 0)
        node.addChild(g)

        // Ribs.
        for i in 0..<7 {
            let y = -0.14 + Float(i) * 0.047
            let ring = MeshBuilder.torus(ringRadius: 0.172 * sqrtf(max(0.05, 1 - powf(y / 0.21, 2))),
                                        pipeRadius: 0.0022)
            let rNode = Entity.make(ring, Materials.hinoki())
            rNode.position = SIMD3<Float>(x: c.x, y: RoomLayout.lanternLightHeight - 0.10 + y, z: c.z)
            node.addChild(rNode)
        }

        // The room's diagonal is about 5.6 m, so a 5 m reach was effectively no
        // falloff at all and the lantern lit the whole room like a ceiling light.
        // A paper andon throws a pool of warm light near its corner, not a flood.
        let lightEntity = Entity()
        lightEntity.components.set(PointLightComponent(
            color: UIColor(red: 1.0, green: 0.82, blue: 0.56, alpha: 1),
            intensity: 0,
            attenuationRadius: 2.8))
        lightEntity.position = SIMD3<Float>(x: c.x, y: RoomLayout.lanternLightHeight - 0.10, z: c.z)
        node.addChild(lightEntity)
        room.lanternLight = lightEntity

        return node
    }

    private static func buildScroll() -> Entity {
        let node = Entity()
        node.name = "scroll"
        let plane = MeshBuilder.plane(width: 0.42, height: 1.05)
        let n = Entity.make(plane, Materials.scroll())
        n.position = SIMD3<Float>(x: -RoomLayout.halfWidth + 0.045, y: 1.42, z: -1.20)
        n.eulerAngles = SIMD3<Float>(x: 0, y: deg(90), z: 0)
        node.addChild(n)

        for y in [1.95, 0.89] as [Float] {
            let rod = MeshBuilder.cylinder(radius: 0.011, height: 0.50)
            let r = Entity.make(rod, Materials.darkWood())
            r.position = SIMD3<Float>(x: -RoomLayout.halfWidth + 0.05, y: y, z: -1.20)
            r.eulerAngles = SIMD3<Float>(x: deg(90), y: 0, z: 0)
            node.addChild(r)
        }
        return node
    }

    private static func buildBonsai() -> Entity {
        let node = Entity()
        node.name = "bonsai"
        let base = SIMD3<Float>(x: RoomLayout.tansuCenter.x - 0.02,
                              y: RoomLayout.tansuSize.y,
                              z: RoomLayout.tansuCenter.z - 0.16)

        let pot = MeshBuilder.pipe(innerRadius: 0.075, outerRadius: 0.088, height: 0.07)
        let p = Entity.make(pot, Materials.ceramic(RGBColor(hex: 0x5A4038), key: "pot"))
        p.position = SIMD3<Float>(x: base.x, y: base.y + 0.035, z: base.z)
        node.addChild(p)

        let soil = MeshBuilder.cylinder(radius: 0.078, height: 0.05)
        let s = Entity.make(soil, Materials.pbr(color: RGBColor(hex: 0x3A2E24), roughness: 1))
        s.position = SIMD3<Float>(x: base.x, y: base.y + 0.045, z: base.z)
        node.addChild(s)

        let trunk = MeshBuilder.tube(length: 0.20, count: 6, segments: 8, radius: { t in
            0.016 * (1 - t * 0.55)
        }, offset: { t in
            Vec3(x: sinf(t * 3.2) * 0.035, y: 0, z: cosf(t * 2.1) * 0.02)
        })
        let tr = Entity.make(trunk, Materials.pbr(color: RGBColor(hex: 0x4A3A2C), roughness: 0.9))
        tr.position = SIMD3<Float>(x: base.x, y: base.y + 0.06, z: base.z)
        tr.eulerAngles = SIMD3<Float>(x: deg(-90), y: 0, z: 0)
        node.addChild(tr)

        for (dx, dy, dz, r) in [(0.05, 0.24, 0.0, 0.075), (-0.045, 0.20, 0.03, 0.055), (0.01, 0.28, -0.03, 0.05)] as [(Float, Float, Float, Float)] {
            let canopy = MeshBuilder.blob(radius: r, scaleX: 1.25, scaleY: 0.62, scaleZ: 1.1, rings: 10, segments: 14)
            let c = Entity.make(canopy, Materials.foliage())
            c.position = SIMD3<Float>(x: base.x + dx, y: base.y + dy, z: base.z + dz)
            node.addChild(c)
        }
        return node
    }

    private static func buildCatTree() -> Entity {
        let node = Entity()
        node.name = "catTree"
        let b = RoomLayout.catTreeBase

        let base = MeshBuilder.box(width: 0.46, height: 0.05, length: 0.46, chamfer: 0.012)
        let bn = Entity.make(base, Materials.linen(RGBColor(hex: 0xBFAE92), key: "treeBase"))
        bn.position = SIMD3<Float>(x: b.x, y: 0.025, z: b.z)
        node.addChild(bn)

        // Two sisal posts.
        func post(x: Float, z: Float, height: Float) {
            let p = MeshBuilder.cylinder(radius: 0.048, height: height)
            let pn = Entity.make(p, Materials.sisal())
            pn.position = SIMD3<Float>(x: x, y: height / 2 + 0.05, z: z)
            node.addChild(pn)
        }
        post(x: b.x - 0.13, z: b.z + 0.02, height: RoomLayout.catTreeMidPlatform.y - 0.05)
        post(x: b.x + 0.11, z: b.z - 0.06, height: RoomLayout.catTreeTopPlatform.y - 0.05)

        // Platforms.
        for p in [RoomLayout.catTreeMidPlatform, RoomLayout.catTreeTopPlatform] {
            let plat = MeshBuilder.box(width: 0.44, height: 0.035, length: 0.40, chamfer: 0.014)
            let pn = Entity.make(plat, Materials.linen(RGBColor(hex: 0xCBBB9E), key: "platform"))
            pn.position = SIMD3<Float>(x: p.x, y: p.y, z: p.z)
            node.addChild(pn)
        }

        // Dangling pompom on a string.
        let string = MeshBuilder.cylinder(radius: 0.0018, height: 0.22)
        let sn = Entity.make(string, Materials.pbr(color: RGBColor(repeating: 0.85), roughness: 0.9))
        sn.position = SIMD3<Float>(x: b.x + 0.20, y: RoomLayout.catTreeTopPlatform.y - 0.11, z: b.z + 0.14)
        node.addChild(sn)
        let pom = MeshBuilder.sphere(radius: 0.030)
        let pn = Entity.make(pom, Materials.linen(RGBColor(hex: 0xC4576A), key: "pompom"))
        pn.position = SIMD3<Float>(x: b.x + 0.20, y: RoomLayout.catTreeTopPlatform.y - 0.24, z: b.z + 0.14)
        pn.name = "pompom"
        node.addChild(pn)

        return node
    }

    private static func buildCatBed() -> Entity {
        let node = Entity()
        node.name = "catBed"
        let c = RoomLayout.catBedCenter

        let rim = MeshBuilder.torus(ringRadius: 0.21, pipeRadius: 0.058)
        let r = Entity.make(rim, Materials.linen(RGBColor(hex: 0x8E9E8C), key: "bedRim"))
        r.position = SIMD3<Float>(x: c.x, y: 0.058, z: c.z)
        node.addChild(r)

        let cushion = MeshBuilder.blob(radius: 0.20, scaleX: 1.05, scaleY: 1.05, scaleZ: 0.22, rings: 10, segments: 20)
        let cu = Entity.make(cushion, Materials.linen(RGBColor(hex: 0xD9D2C0), key: "bedCushion"))
        cu.position = SIMD3<Float>(x: c.x, y: 0.048, z: c.z)
        cu.eulerAngles = SIMD3<Float>(x: deg(90), y: 0, z: 0)
        node.addChild(cu)
        return node
    }

    private static func buildFeeder(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "feeder"
        let b = RoomLayout.feederBase
        let plasticMat = Materials.plastic(RGBColor(hex: 0xF0EDE7))

        let hopper = MeshBuilder.box(width: 0.20, height: 0.34, length: 0.22, chamfer: 0.045)
        let h = Entity.make(hopper, plasticMat)
        h.position = SIMD3<Float>(x: b.x, y: 0.17, z: b.z)
        node.addChild(h)

        let chute = MeshBuilder.box(width: 0.20, height: 0.10, length: 0.14, chamfer: 0.03)
        let ch = Entity.make(chute, plasticMat)
        ch.position = SIMD3<Float>(x: b.x, y: 0.09, z: b.z + 0.13)
        node.addChild(ch)

        let bowl = MeshBuilder.pipe(innerRadius: 0.070, outerRadius: 0.082, height: 0.036)
        let bo = Entity.make(bowl, Materials.ceramic(RGBColor(hex: 0xDDD8CE), key: "bowl"))
        bo.position = SIMD3<Float>(x: RoomLayout.feederBowl.x, y: 0.018, z: RoomLayout.feederBowl.z)
        node.addChild(bo)
        let bowlFloor = MeshBuilder.cylinder(radius: 0.082, height: 0.006)
        let bf = Entity.make(bowlFloor, Materials.ceramic(RGBColor(hex: 0xDDD8CE), key: "bowl"))
        bf.position = SIMD3<Float>(x: RoomLayout.feederBowl.x, y: 0.003, z: RoomLayout.feederBowl.z)
        node.addChild(bf)

        // Kibble level, scaled at runtime by RoomState.feederFood.
        let food = MeshBuilder.cylinder(radius: 0.066, height: 0.030)
        let fn = Entity.make(food, Materials.pbr(color: RGBColor(hex: 0x8A5A32), roughness: 0.95))
        fn.position = SIMD3<Float>(x: RoomLayout.feederBowl.x, y: 0.019, z: RoomLayout.feederBowl.z)
        node.addChild(fn)
        room.foodPile = fn

        // A little status LED.
        let led = MeshBuilder.sphere(radius: 0.006)
        var ledMat = Materials.pbr(color: RGBColor(0.3, 1.0, 0.5), roughness: 0.2)
        ledMat.emissiveColor = .init(color: UIColor(red: 0.3, green: 1.0, blue: 0.5, alpha: 1))
        ledMat.emissiveIntensity = 0.9
        let ln = Entity.make(led, ledMat)
        ln.position = SIMD3<Float>(x: b.x - 0.06, y: 0.30, z: b.z + 0.10)
        node.addChild(ln)

        return node
    }

    private static func buildFountain(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "fountain"
        let b = RoomLayout.fountainBase
        let shell = Materials.plastic(RGBColor(hex: 0xE9E6DF))

        let cx = b.x
        let cz = b.z + 0.24

        let basin = MeshBuilder.pipe(innerRadius: 0.105, outerRadius: 0.125, height: 0.085)
        let ba = Entity.make(basin, shell)
        ba.position = SIMD3<Float>(x: cx, y: 0.043, z: cz)
        node.addChild(ba)
        let basinFloor = MeshBuilder.cylinder(radius: 0.125, height: 0.008)
        let bf = Entity.make(basinFloor, shell)
        bf.position = SIMD3<Float>(x: cx, y: 0.004, z: cz)
        node.addChild(bf)

        // Pump tower at the back with a curved spout arcing forward.
        let tower = MeshBuilder.cylinder(radius: 0.045, height: 0.17)
        let tw = Entity.make(tower, shell)
        tw.position = SIMD3<Float>(x: cx, y: 0.09, z: cz - 0.058)
        node.addChild(tw)

        let spout = MeshBuilder.torus(ringRadius: 0.045, pipeRadius: 0.008)
        let sp = Entity.make(spout, shell)
        sp.position = SIMD3<Float>(x: cx, y: 0.175, z: cz - 0.028)
        sp.eulerAngles = SIMD3<Float>(x: 0, y: 0, z: deg(90))
        node.addChild(sp)

        // Water surface (scaled with the level) and the falling stream.
        let surface = MeshBuilder.cylinder(radius: 0.100, height: 0.004)
        let su = Entity.make(surface, Materials.water())
        su.position = SIMD3<Float>(x: cx, y: 0.055, z: cz)
        node.addChild(su)
        room.waterSurface = su

        let stream = MeshBuilder.cylinder(radius: 0.006, height: 0.11)
        let st = Entity.make(stream, Materials.water())
        st.position = SIMD3<Float>(x: cx, y: 0.115, z: cz + 0.010)
        node.addChild(st)
        room.fountainStream = st

        return node
    }

    private static func buildLitterBox(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "litterBox"
        let c = RoomLayout.litterBoxCenter
        let shell = Materials.plastic(RGBColor(hex: 0x5B6470))

        let tray = MeshBuilder.box(width: 0.44, height: 0.16, length: 0.52, chamfer: 0.03)
        let t = Entity.make(tray, shell)
        t.position = SIMD3<Float>(x: c.x, y: 0.08, z: c.z)
        node.addChild(t)

        // Hood with an opening facing into the room.
        let hood = MeshBuilder.blob(radius: 0.26, scaleX: 0.85, scaleY: 0.62, scaleZ: 1.0, rings: 10, segments: 16)
        var hoodMat = Materials.plastic(RGBColor(hex: 0x6B7480))
        hoodMat.faceCulling = .none
        let h = Entity.make(hood, hoodMat)
        h.position = SIMD3<Float>(x: c.x, y: 0.16, z: c.z)
        node.addChild(h)

        // Dark entrance so it reads as an opening.
        let entry = MeshBuilder.plane(width: 0.24, height: 0.22)
        let entryMat = Materials.pbr(color: RGBColor(repeating: 0.06), roughness: 1)
        let e = Entity.make(entry, entryMat)
        e.position = SIMD3<Float>(x: c.x, y: 0.23, z: c.z + 0.255)
        node.addChild(e)

        let substrate = MeshBuilder.box(width: 0.40, height: 0.05, length: 0.48, chamfer: 0.01)
        let s = Entity.make(substrate, Materials.litter())
        s.position = SIMD3<Float>(x: c.x, y: 0.12, z: c.z)
        node.addChild(s)
        room.litterSurface = s

        return node
    }

    private static func buildToys(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "toys"

        // Basket.
        let basket = MeshBuilder.pipe(innerRadius: 0.11, outerRadius: 0.125, height: 0.12)
        let b = Entity.make(basket, Materials.sisal())
        b.position = SIMD3<Float>(x: RoomLayout.toyBasketCenter.x, y: 0.06, z: RoomLayout.toyBasketCenter.z)
        node.addChild(b)
        let basketFloor = MeshBuilder.cylinder(radius: 0.125, height: 0.008)
        let bf = Entity.make(basketFloor, Materials.sisal())
        bf.position = SIMD3<Float>(x: RoomLayout.toyBasketCenter.x, y: 0.004, z: RoomLayout.toyBasketCenter.z)
        node.addChild(bf)

        // Toy mouse on the floor.
        let mouseBody = MeshBuilder.blob(radius: 0.035, scaleX: 0.7, scaleY: 0.7, scaleZ: 1.5, rings: 8, segments: 12)
        let mouse = Entity.make(mouseBody, Materials.linen(RGBColor(hex: 0x9A8FA8), key: "mouse"))
        mouse.position = SIMD3<Float>(x: RoomLayout.toyMouseSpot.x, y: 0.026, z: RoomLayout.toyMouseSpot.z)
        mouse.eulerAngles = SIMD3<Float>(x: 0, y: deg(35), z: 0)
        mouse.name = "toyMouse"
        node.addChild(mouse)
        let tail = MeshBuilder.strand(length: 0.07, thickness: 0.0022, droop: 0.2)
        let tn = Entity.make(tail, Materials.pbr(color: RGBColor(repeating: 0.75), roughness: 0.8))
        tn.position = SIMD3<Float>(x: 0, y: 0.004, z: -0.05)
        tn.eulerAngles = SIMD3<Float>(x: 0, y: .pi, z: 0)
        mouse.addChild(tn)
        room.toyMouse = mouse

        // Jingle ball.
        let ball = MeshBuilder.sphere(radius: 0.024)
        let ballMat = Materials.plastic(RGBColor(hex: 0xE0A83A))
        let bn = Entity.make(ball, ballMat)
        bn.position = SIMD3<Float>(x: RoomLayout.toyBallSpot.x, y: 0.024, z: RoomLayout.toyBallSpot.z)
        bn.name = "toyBall"
        node.addChild(bn)
        room.toyBall = bn

        return node
    }

    private static func buildZabuton() -> Entity {
        let node = Entity()
        node.name = "zabuton"
        let cushion = MeshBuilder.box(width: 0.60, height: 0.09, length: 0.60, chamfer: 0.05)
        let c = Entity.make(cushion, Materials.linen(RGBColor(hex: 0x7A4B4B), key: "zabuton"))
        c.position = SIMD3<Float>(x: RoomLayout.cameraPosition.x, y: 0.045, z: RoomLayout.cameraPosition.z + 0.10)
        node.addChild(c)
        return node
    }

    /// A soft warm rectangle on the tatami where sunlight lands.
    private static func buildSunPatch(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "sunPatchHolder"
        let plane = MeshBuilder.plane(width: 0.95, height: 0.72)
        // Unlit and additive under SceneKit; here it is an emissive surface that
        // starts at nothing, and `LightingRig` opens it as the sun comes up. The
        // opacity that used to live on the node lives on the material now, which
        // is the only place RealityKit has for it.
        var mat = PhysicallyBasedMaterial()
        mat.baseColor = .init(tint: .black)
        mat.emissiveColor = .init(color: .white,
                                  texture: TextureBridge.tiling(sunPatchImage(), semantic: .color))
        mat.emissiveIntensity = 1
        mat.blending = .transparent(opacity: .init(scale: 0))
        mat.writesDepth = false
        let n = Entity.make(plane, mat)
        n.eulerAngles = SIMD3<Float>(x: deg(-90), y: 0, z: 0)
        n.position = SIMD3<Float>(x: 0.3, y: 0.032, z: -1.1)
        node.addChild(n)
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
    private static func buildDustMotes(room: RoomNode) -> Entity {
        let node = Entity()
        node.name = "dust"
        guard RenderQuality.dustMotes else { return node }

        // A box of slowly falling motes. RealityKit's emitter is configured in
        // world units rather than SceneKit's mix of rates and variations, so this
        // is a translation rather than a transcription: 26 births a second over a
        // fourteen-second life is about 360 motes alive at once, in a volume 2.8 m
        // across, drifting at just over a centimetre a second.
        var particles = ParticleEmitterComponent()
        particles.emitterShape = .box
        particles.emitterShapeSize = SIMD3<Float>(2.8, 1.6, 2.4)
        particles.birthDirection = .local
        particles.speed = 0.012
        particles.mainEmitter.birthRate = 26
        particles.mainEmitter.lifeSpan = 14
        particles.mainEmitter.size = 0.0035
        particles.mainEmitter.color = .constant(.random(a: UIColor(white: 1.0, alpha: 0.35),
                                                        b: UIColor(white: 1.0, alpha: 0.7)))

        let emitter = Entity()
        emitter.position = SIMD3<Float>(x: 0.1, y: 1.05, z: -1.1)
        emitter.components.set(particles)
        node.addChild(emitter)
        room.dustMotes = emitter
        return node
    }

}
