// A tiny software rasteriser. SceneKit isn't available off-Apple, but the meshes,
// the rig and the animator are all ours — so we can walk the node tree, project the
// triangles ourselves and actually look at the cat. Run with `--render`.
import Foundation
import SceneKit

// MARK: - Triangle soup

private struct Tri {
    var a: SCNVector3
    var b: SCNVector3
    var c: SCNVector3
    var shade: Float          // material lightness 0…1
}

private func tessellate(_ geometry: SCNGeometry) -> ([SCNVector3], [Int32]) {
    // Custom meshes carry their own vertices.
    if let source = geometry.sources.first(where: { !$0.vertices.isEmpty }),
       let element = geometry.elements.first, !element.indices.isEmpty {
        return (source.vertices, element.indices)
    }

    var verts: [SCNVector3] = []
    var idx: [Int32] = []

    func quad(_ a: SCNVector3, _ b: SCNVector3, _ c: SCNVector3, _ d: SCNVector3) {
        let base = Int32(verts.count)
        verts.append(contentsOf: [a, b, c, d])
        idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }

    switch geometry {
    case let box as SCNBox:
        let w = Float(box.width) / 2, h = Float(box.height) / 2, l = Float(box.length) / 2
        let p = [SCNVector3(x: -w, y: -h, z: -l), SCNVector3(x: w, y: -h, z: -l),
                 SCNVector3(x: w, y: h, z: -l), SCNVector3(x: -w, y: h, z: -l),
                 SCNVector3(x: -w, y: -h, z: l), SCNVector3(x: w, y: -h, z: l),
                 SCNVector3(x: w, y: h, z: l), SCNVector3(x: -w, y: h, z: l)]
        quad(p[0], p[3], p[2], p[1]); quad(p[4], p[5], p[6], p[7])
        quad(p[0], p[1], p[5], p[4]); quad(p[2], p[3], p[7], p[6])
        quad(p[1], p[2], p[6], p[5]); quad(p[0], p[4], p[7], p[3])

    case let sphere as SCNSphere:
        let r = Float(sphere.radius), rings = 12, segs = 18
        for i in 0..<rings {
            for s in 0..<segs {
                func pt(_ i: Int, _ s: Int) -> SCNVector3 {
                    let phi = Float(i) / Float(rings) * .pi
                    let th = Float(s) / Float(segs) * 2 * .pi
                    return SCNVector3(x: sinf(phi) * cosf(th) * r, y: cosf(phi) * r, z: sinf(phi) * sinf(th) * r)
                }
                quad(pt(i, s), pt(i + 1, s), pt(i + 1, s + 1), pt(i, s + 1))
            }
        }

    case let cyl as SCNCylinder:
        let r = Float(cyl.radius), h = Float(cyl.height) / 2, segs = 16
        for s in 0..<segs {
            let a0 = Float(s) / Float(segs) * 2 * .pi
            let a1 = Float(s + 1) / Float(segs) * 2 * .pi
            quad(SCNVector3(x: cosf(a0) * r, y: -h, z: sinf(a0) * r),
                 SCNVector3(x: cosf(a1) * r, y: -h, z: sinf(a1) * r),
                 SCNVector3(x: cosf(a1) * r, y: h, z: sinf(a1) * r),
                 SCNVector3(x: cosf(a0) * r, y: h, z: sinf(a0) * r))
            let base = Int32(verts.count)
            verts.append(contentsOf: [SCNVector3(x: 0, y: h, z: 0),
                                      SCNVector3(x: cosf(a0) * r, y: h, z: sinf(a0) * r),
                                      SCNVector3(x: cosf(a1) * r, y: h, z: sinf(a1) * r)])
            idx.append(contentsOf: [base, base + 1, base + 2])
        }

    case let tube as SCNTube:
        let ro = Float(tube.outerRadius), ri = Float(tube.innerRadius)
        let h = Float(tube.height) / 2, segs = 16
        for s in 0..<segs {
            let a0 = Float(s) / Float(segs) * 2 * .pi
            let a1 = Float(s + 1) / Float(segs) * 2 * .pi
            for r in [ro, ri] {
                quad(SCNVector3(x: cosf(a0) * r, y: -h, z: sinf(a0) * r),
                     SCNVector3(x: cosf(a1) * r, y: -h, z: sinf(a1) * r),
                     SCNVector3(x: cosf(a1) * r, y: h, z: sinf(a1) * r),
                     SCNVector3(x: cosf(a0) * r, y: h, z: sinf(a0) * r))
            }
            quad(SCNVector3(x: cosf(a0) * ri, y: h, z: sinf(a0) * ri),
                 SCNVector3(x: cosf(a1) * ri, y: h, z: sinf(a1) * ri),
                 SCNVector3(x: cosf(a1) * ro, y: h, z: sinf(a1) * ro),
                 SCNVector3(x: cosf(a0) * ro, y: h, z: sinf(a0) * ro))
        }

    case let torus as SCNTorus:
        let R = Float(torus.ringRadius), r = Float(torus.pipeRadius)
        let major = 16, minor = 8
        for i in 0..<major {
            for j in 0..<minor {
                func pt(_ i: Int, _ j: Int) -> SCNVector3 {
                    let u = Float(i) / Float(major) * 2 * .pi
                    let v = Float(j) / Float(minor) * 2 * .pi
                    return SCNVector3(x: (R + r * cosf(v)) * cosf(u),
                                      y: r * sinf(v),
                                      z: (R + r * cosf(v)) * sinf(u))
                }
                quad(pt(i, j), pt(i + 1, j), pt(i + 1, j + 1), pt(i, j + 1))
            }
        }

    case let plane as SCNPlane:
        let w = Float(plane.width) / 2, h = Float(plane.height) / 2
        quad(SCNVector3(x: -w, y: -h, z: 0), SCNVector3(x: w, y: -h, z: 0),
             SCNVector3(x: w, y: h, z: 0), SCNVector3(x: -w, y: h, z: 0))

    default:
        break
    }
    return (verts, idx)
}

private func gather(_ node: SCNNode, into tris: inout [Tri], skipHidden: Bool = true) {
    if skipHidden && node.isHidden { return }
    if let geometry = node.geometry {
        let (verts, idx) = tessellate(geometry)
        if !verts.isEmpty && !idx.isEmpty {
            let world = node.worldTransform
            // Approximate the material by its diffuse colour's lightness.
            var shade: Float = 0.65
            if let mat = geometry.materials.first, let ui = mat.diffuse.contents as? UIColor {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                ui.getRed(&r, green: &g, blue: &b, alpha: &a)
                shade = Float(0.2126 * r + 0.7152 * g + 0.0722 * b)
                if shade < 0.02 { shade = 0.55 }   // shim colours read back as black
            }
            var i = 0
            while i + 2 < idx.count {
                let a = world.apply(verts[Int(idx[i])])
                let b = world.apply(verts[Int(idx[i + 1])])
                let c = world.apply(verts[Int(idx[i + 2])])
                tris.append(Tri(a: a, b: b, c: c, shade: shade))
                i += 3
            }
        }
    }
    for child in node.childNodes { gather(child, into: &tris, skipHidden: skipHidden) }
}

// MARK: - Rasteriser

private func render(_ tris: [Tri],
                    eye: SCNVector3, target: SCNVector3,
                    fovDegrees: Float, width: Int, height: Int,
                    background: (Float, Float, Float)) -> [UInt8] {
    // Camera basis.
    let forward = (target - eye).normalized
    let worldUp = SCNVector3(x: 0, y: 1, z: 0)
    var right = cross(worldUp, forward).normalized
    if right.length < 1e-4 { right = SCNVector3(x: 1, y: 0, z: 0) }
    let up = cross(forward, right).normalized

    let aspect = Float(width) / Float(height)
    let tanHalf = tanf(fovDegrees * .pi / 180 / 2)

    var depth = [Float](repeating: .greatestFiniteMagnitude, count: width * height)
    var pixels = [UInt8](repeating: 0, count: width * height * 3)
    for i in 0..<(width * height) {
        pixels[i * 3] = UInt8(clamp(background.0) * 255)
        pixels[i * 3 + 1] = UInt8(clamp(background.1) * 255)
        pixels[i * 3 + 2] = UInt8(clamp(background.2) * 255)
    }

    let lightDir = SCNVector3(x: -0.45, y: 0.8, z: -0.4).normalized

    for tri in tris {
        // To camera space.
        func toCamera(_ p: SCNVector3) -> SCNVector3 {
            let d = p - eye
            return SCNVector3(x: dot(d, right), y: dot(d, up), z: dot(d, forward))
        }
        let ca = toCamera(tri.a), cb = toCamera(tri.b), cc = toCamera(tri.c)
        guard ca.z > 0.02, cb.z > 0.02, cc.z > 0.02 else { continue }

        func project(_ p: SCNVector3) -> (Float, Float) {
            let x = (p.x / (p.z * tanHalf * aspect) * 0.5 + 0.5) * Float(width)
            let y = (1 - (p.y / (p.z * tanHalf) * 0.5 + 0.5)) * Float(height)
            return (x, y)
        }
        let (x0, y0) = project(ca), (x1, y1) = project(cb), (x2, y2) = project(cc)

        let normal = cross(tri.b - tri.a, tri.c - tri.a).normalized
        let lambert = max(0.12, dot(normal, lightDir))
        let value = clamp(tri.shade * (0.28 + 0.85 * lambert))

        let minX = max(0, Int(floor(min(x0, x1, x2))))
        let maxX = min(width - 1, Int(ceil(max(x0, x1, x2))))
        let minY = max(0, Int(floor(min(y0, y1, y2))))
        let maxY = min(height - 1, Int(ceil(max(y0, y1, y2))))
        if minX > maxX || minY > maxY { continue }

        let area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if abs(area) < 1e-8 { continue }

        for py in minY...maxY {
            for px in minX...maxX {
                let fx = Float(px) + 0.5, fy = Float(py) + 0.5
                var w0 = ((x1 - fx) * (y2 - fy) - (x2 - fx) * (y1 - fy)) / area
                var w1 = ((x2 - fx) * (y0 - fy) - (x0 - fx) * (y2 - fy)) / area
                var w2 = 1 - w0 - w1
                if area < 0 { w0 = -w0; w1 = -w1; w2 = -w2 }
                guard w0 >= -1e-5, w1 >= -1e-5, w2 >= -1e-5 else { continue }
                let z = abs(w0) * ca.z + abs(w1) * cb.z + abs(w2) * cc.z
                let o = py * width + px
                guard z < depth[o] else { continue }
                depth[o] = z
                let v = UInt8(clamp(value) * 255)
                pixels[o * 3] = v
                pixels[o * 3 + 1] = UInt8(clamp(value * 0.98) * 255)
                pixels[o * 3 + 2] = UInt8(clamp(value * 0.94) * 255)
            }
        }
    }
    return pixels
}

// MARK: - PNG

private func writePNG(_ pixels: [UInt8], width: Int, height: Int, to path: String) {
    var raw = [UInt8]()
    raw.reserveCapacity(height * (1 + width * 3))
    for y in 0..<height {
        raw.append(0)
        raw.append(contentsOf: pixels[(y * width * 3)..<((y + 1) * width * 3)])
    }

    func crc32(_ data: [UInt8]) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1 }
            table[i] = c
        }
        var c: UInt32 = 0xFFFFFFFF
        for byte in data { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFFFFFF
    }

    func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        return (b << 16) | a
    }

    func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }

    func chunk(_ tag: String, _ payload: [UInt8]) -> [UInt8] {
        let tagBytes = Array(tag.utf8)
        return be32(UInt32(payload.count)) + tagBytes + payload + be32(crc32(tagBytes + payload))
    }

    // zlib stream with stored (uncompressed) deflate blocks.
    var z: [UInt8] = [0x78, 0x01]
    var offset = 0
    while offset < raw.count {
        let size = min(65535, raw.count - offset)
        let final: UInt8 = (offset + size >= raw.count) ? 1 : 0
        z.append(final)
        z.append(UInt8(size & 0xFF)); z.append(UInt8((size >> 8) & 0xFF))
        let inv = ~UInt16(size)
        z.append(UInt8(inv & 0xFF)); z.append(UInt8((inv >> 8) & 0xFF))
        z.append(contentsOf: raw[offset..<(offset + size)])
        offset += size
    }
    z += be32(adler32(raw))

    var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    png += chunk("IHDR", be32(UInt32(width)) + be32(UInt32(height)) + [8, 2, 0, 0, 0])
    png += chunk("IDAT", z)
    png += chunk("IEND", [])
    _ = FileManager.default.createFile(atPath: path, contents: Data(png))
}

// MARK: - Screen-space measurement

/// Where a node lands in the final frame, in points, using the same projection as
/// the rasteriser. The HUD occupies a fixed band along the bottom of the screen,
/// so knowing the cat's screen box is the only way to tell — without a Mac —
/// whether a cat that comes when called ends up hidden behind the status pill.
private func screenBounds(_ node: SCNNode,
                          eye: SCNVector3, target: SCNVector3,
                          fovDegrees: Float, width: Int, height: Int)
    -> (minX: Float, maxX: Float, minY: Float, maxY: Float)? {

    var tris: [Tri] = []
    gather(node, into: &tris)

    let forward = (target - eye).normalized
    var right = cross(SCNVector3(x: 0, y: 1, z: 0), forward).normalized
    if right.length < 1e-4 { right = SCNVector3(x: 1, y: 0, z: 0) }
    let up = cross(forward, right).normalized

    let aspect = Float(width) / Float(height)
    let tanHalf = tanf(fovDegrees * .pi / 180 / 2)

    var minX = Float.infinity, maxX = -Float.infinity
    var minY = Float.infinity, maxY = -Float.infinity
    var any = false

    for tri in tris {
        for p in [tri.a, tri.b, tri.c] {
            let d = p - eye
            let z = dot(d, forward)
            guard z > 0.02 else { continue }
            let x = (dot(d, right) / (z * tanHalf * aspect) * 0.5 + 0.5) * Float(width)
            let y = (1 - (dot(d, up) / (z * tanHalf) * 0.5 + 0.5)) * Float(height)
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            any = true
        }
    }
    return any ? (minX, maxX, minY, maxY) : nil
}

// MARK: - Entry point

func runRender(outputDirectory: String) {
    let fm = FileManager.default
    try? fm.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

    func shot(_ name: String, _ node: SCNNode, eye: SCNVector3, target: SCNVector3,
              fov: Float, size: (Int, Int), bg: (Float, Float, Float) = (0.10, 0.10, 0.12)) {
        var tris: [Tri] = []
        gather(node, into: &tris)
        let pixels = render(tris, eye: eye, target: target, fovDegrees: fov,
                            width: size.0, height: size.1, background: bg)
        writePNG(pixels, width: size.0, height: size.1, to: "\(outputDirectory)/\(name).png")
        var lo = SCNVector3(x: .infinity, y: .infinity, z: .infinity)
        var hi = SCNVector3(x: -.infinity, y: -.infinity, z: -.infinity)
        for t in tris {
            for p in [t.a, t.b, t.c] {
                lo = SCNVector3(x: min(lo.x, p.x), y: min(lo.y, p.y), z: min(lo.z, p.z))
                hi = SCNVector3(x: max(hi.x, p.x), y: max(hi.y, p.y), z: max(hi.z, p.z))
            }
        }
        print(String(format: "  %@.png  %d tris  bbox x[%.2f %.2f] y[%.2f %.2f] z[%.2f %.2f]",
                     name as NSString, tris.count, lo.x, hi.x, lo.y, hi.y, lo.z, hi.z))
    }

    print("rendering to \(outputDirectory)")

    // --- The cat, in a few poses, from the side and three-quarter.
    let poses: [(String, CatPose)] = [("stand", .standing), ("sit", .sittingTall),
                                      ("loaf", .loaf), ("curl", .curled),
                                      ("walk", .walking), ("stretch", .stretching)]
    for (label, pose) in poses {
        let appearance = BreedPresets.appearance(for: .domesticShorthair)
        let rig = CatBuilder.build(appearance)
        let animator = CatAnimator(rig: rig)
        var motion = CatMotion()
        motion.position = .zero
        motion.pose = pose
        motion.speed = pose.isLocomotion ? 0.6 : 0
        motion.eyeOpen = pose.isSleep ? 0.05 : 1
        for _ in 0..<300 { animator.update(dt: 1.0 / 60, motion: motion) }

        shot("cat-\(label)-side", rig.root,
             eye: SCNVector3(x: 0.95, y: 0.20, z: 0.05), target: SCNVector3(x: 0, y: 0.16, z: 0),
             fov: 34, size: (420, 320))
        shot("cat-\(label)-front", rig.root,
             eye: SCNVector3(x: 0.30, y: 0.30, z: 0.85), target: SCNVector3(x: 0, y: 0.16, z: 0),
             fov: 34, size: (420, 320))
    }

    // --- The head, close up. The game is mostly a face at close range, and the
    // ear/skull junction in particular is easy to get wrong: the ear roots sit
    // inside the skull, so if they drift out the ears read as floating.
    for breed in [CatBreed.domesticShorthair, .maineCoon, .persian, .siamese] {
        let a = BreedPresets.appearance(for: breed)
        let rig = CatBuilder.build(a)
        let animator = CatAnimator(rig: rig)
        var motion = CatMotion()
        motion.position = .zero
        motion.pose = .sittingTall
        for _ in 0..<200 { animator.update(dt: 1.0 / 60, motion: motion) }

        let head = rig.head.convertPosition(.zero, to: nil)
        let d = a.headRadius * 11
        shot("head-\(breed.rawValue)-front", rig.root,
             eye: SCNVector3(x: head.x, y: head.y + d * 0.16, z: head.z + d),
             target: head, fov: 30, size: (460, 460))
        shot("head-\(breed.rawValue)-threequarter", rig.root,
             eye: SCNVector3(x: head.x + d * 0.62, y: head.y + d * 0.30, z: head.z + d * 0.72),
             target: head, fov: 30, size: (460, 460))
    }

    // --- A few breeds, so the silhouettes can be compared.
    for breed in [CatBreed.maineCoon, .siamese, .persian, .munchkin, .sphynx, .britishShorthair] {
        let rig = CatBuilder.build(BreedPresets.appearance(for: breed))
        let animator = CatAnimator(rig: rig)
        var motion = CatMotion()
        motion.position = .zero
        motion.pose = .standing
        for _ in 0..<200 { animator.update(dt: 1.0 / 60, motion: motion) }
        shot("breed-\(breed.rawValue)", rig.root,
             eye: SCNVector3(x: 1.0, y: 0.22, z: 0.10), target: SCNVector3(x: 0, y: 0.16, z: 0),
             fov: 34, size: (420, 320))
    }

    // --- The room, from exactly where the player sits.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var comps = DateComponents(); comps.year = 2026; comps.month = 5; comps.day = 12; comps.hour = 11
    let sky = WorldClock.sky(at: cal.date(from: comps)!, timeZone: TimeZone(identifier: "UTC")!)
    let room = RoomBuilder.build(sky: sky)

    let catRig = CatBuilder.build(BreedPresets.appearance(for: .domesticShorthair))
    let catAnim = CatAnimator(rig: catRig)
    var catMotion = CatMotion()
    catMotion.pose = .sittingTall
    catMotion.position = SCNVector3(x: 0.1, y: 0, z: -0.3)
    catMotion.yaw = deg(170)
    for _ in 0..<200 { catAnim.update(dt: 1.0 / 60, motion: catMotion) }

    let world = SCNNode()
    world.addChildNode(room.root)
    world.addChildNode(catRig.root)

    let eye = RoomLayout.cameraPosition
    let aim = SCNVector3(x: eye.x, y: eye.y + tanf(RoomLayout.cameraPitch), z: eye.z - 1)
    // The app pins the field of view to the horizontal axis at 54°; this rasteriser
    // takes a vertical FOV, so convert for a 390x844 portrait frame.
    let horizontal: Float = 54
    let aspect: Float = 390.0 / 844.0
    let vertical = 2 * atanf(tanf(horizontal * .pi / 180 / 2) / aspect) * 180 / .pi
    shot("room-player-view", world, eye: eye, target: aim, fov: vertical, size: (390, 844),
         bg: (0.05, 0.06, 0.09))
    shot("room-overhead", world,
         eye: SCNVector3(x: 0.2, y: 3.4, z: 2.6), target: SCNVector3(x: 0, y: 0.3, z: -0.6),
         fov: 60, size: (600, 480), bg: (0.05, 0.06, 0.09))

    // --- The cat where it sits when called over, checked against the HUD.
    // The bottom bar, status line and home indicator together occupy roughly the
    // lowest 150 pt of an 844 pt frame; the cat has to stay clear of that.
    let closeRig = CatBuilder.build(BreedPresets.appearance(for: .domesticShorthair))
    let closeAnim = CatAnimator(rig: closeRig)
    var closeMotion = CatMotion()
    closeMotion.pose = .sittingTall
    closeMotion.position = RoomLayout.playerLapSpot
    // Same facing the brain gives a cat that has come over to be petted.
    closeMotion.yaw = yawTowards(from: RoomLayout.playerLapSpot, to: RoomLayout.cameraPosition)
    for _ in 0..<200 { closeAnim.update(dt: 1.0 / 60, motion: closeMotion) }

    let closeWorld = SCNNode()
    closeWorld.addChildNode(RoomBuilder.build(sky: sky).root)
    closeWorld.addChildNode(closeRig.root)
    shot("room-cat-called-over", closeWorld, eye: eye, target: aim,
         fov: vertical, size: (390, 844), bg: (0.05, 0.06, 0.09))

    // The head is what the player actually looks at, and it must be completely
    // clear. The whole-body box is reported too, but a tail tip that sprawls
    // toward the camera and slips under the bar is not worth moving the cat for.
    let hudTop: Float = 844 - 150
    for (label, node) in [("head", closeRig.head), ("whole cat", closeRig.root)] {
        guard let b = screenBounds(node, eye: eye, target: aim,
                                   fovDegrees: vertical, width: 390, height: 844) else {
            print("  \(label) at lap spot: not on screen")
            continue
        }
        let hidden = max(0, b.maxY - hudTop)
        let visible = max(0, min(b.maxY, hudTop) - b.minY)
        let fraction = visible > 0 ? hidden / (hidden + visible) : 1
        print(String(format: "  %@ at lap spot: y[%.0f %.0f] x[%.0f %.0f]  %.0f%% behind the HUD (top %.0f)",
                     label as NSString, b.minY, b.maxY, b.minX, b.maxX, fraction * 100, hudTop))
    }
}
