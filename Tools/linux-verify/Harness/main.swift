// Headless verification harness. Runs the game's simulation, geometry and
// texture code on Linux against the framework shims and asserts invariants.
import Foundation
import SceneKit
import RealityKit

if CommandLine.arguments.contains("--profile") {
    runProfile()
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--emit-save") {
    let path = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "./meowroom-save.json"
    var save = GameSave()
    save.profile.name = "Mochi"
    save.profile.appearance = BreedPresets.appearance(for: .domesticShorthair)
    save.profile.personality = BreedPresets.personality(for: .domesticShorthair)
    save.profile.adoptedAt = Date()
    save.lastSeen = Date()
    save.bond = 0.5
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(save) {
        try? data.write(to: URL(fileURLWithPath: path))
        print("wrote \(data.count) bytes to \(path)")
        exit(0)
    }
    print("failed to encode save")
    exit(1)
}

if let i = CommandLine.arguments.firstIndex(of: "--maps") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "./maps"
    runMapDump(outputDirectory: dir)
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "./renders"
    runRender(outputDirectory: dir)
    exit(0)
}

var failures: [String] = []
var checks = 0

func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
    checks += 1
    if !condition { failures.append(message()) }
}

func finite(_ v: Float) -> Bool { v.isFinite }
func finite(_ v: SIMD3<Float>) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
func finite(_ v: Vec3) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }

func section(_ name: String, _ body: () -> Void) {
    let start = Date()
    let before = failures.count
    body()
    let added = failures.count - before
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    print(String(format: "%-28s %@  (%dms)", (name as NSString).utf8String!,
                 added == 0 ? "ok" : "\(added) FAILED", ms))
}

// MARK: - Math

section("math") {
    expect(clamp(1.5) == 1, "clamp upper")
    expect(clamp(-3, -1, 1) == -1, "clamp lower with bounds")
    expect(lerp(0, 10, 0.5) == 5, "lerp midpoint")
    expect(smoothstep(0, 1, 0.5) == 0.5, "smoothstep midpoint")
    expect(abs(angleDelta(deg(350), deg(10)) - deg(20)) < 1e-4, "angleDelta wraps forward")
    expect(abs(angleDelta(deg(10), deg(350)) + deg(20)) < 1e-4, "angleDelta wraps backward")
    expect(abs(approach(0, 1, rate: 10, dt: 10) - 1) < 1e-3, "approach converges")

    let a = SIMD3<Float>(x: 3, y: 4, z: 0)
    expect(abs(a.length - 5) < 1e-5, "length")
    expect(abs(a.normalized.length - 1) < 1e-5, "normalized")
    expect(abs(dot(SIMD3<Float>(x: 1, y: 0, z: 0), SIMD3<Float>(x: 0, y: 1, z: 0))) < 1e-6, "dot orthogonal")
    let c = cross(SIMD3<Float>(x: 1, y: 0, z: 0), SIMD3<Float>(x: 0, y: 1, z: 0))
    expect(abs(c.z - 1) < 1e-6, "cross right-handed")

    // yawTowards: +Z is the cat's forward.
    expect(abs(yawTowards(from: .zero, to: SIMD3<Float>(x: 0, y: 0, z: 1))) < 1e-5, "yaw forward is 0")
    expect(abs(yawTowards(from: .zero, to: SIMD3<Float>(x: 1, y: 0, z: 0)) - .pi / 2) < 1e-5, "yaw +X is 90°")

    var g = SeededGenerator(seed: 42)
    var g2 = SeededGenerator(seed: 42)
    expect(g.float() == g2.float(), "seeded RNG is deterministic")
    var g3 = SeededGenerator(seed: 7)
    for _ in 0..<2000 {
        let v = g3.float(-2, 5)
        expect(v >= -2 && v <= 5, "rng range")
    }
    let noise = ValueNoise(seed: 3)
    for i in 0..<500 {
        let v = noise.fbm(Float(i) * 0.37, Float(i) * 0.11, octaves: 4)
        expect(finite(v) && v >= -1.01 && v <= 1.01, "fbm bounded, got \(v)")
    }
}

// MARK: - Colour

section("colour") {
    let c = RGBColor(hex: 0x8040C0)
    expect(abs(c.r - 128.0 / 255) < 1e-3, "hex red")
    expect(abs(c.g - 64.0 / 255) < 1e-3, "hex green")
    expect(abs(c.b - 192.0 / 255) < 1e-3, "hex blue")
    expect(RGBColor(2, -1, 0.5).r == 1 && RGBColor(2, -1, 0.5).g == 0, "components clamp")
    expect(c.lightened(1) == RGBColor(1, 1, 1), "lightened to white")
    expect(c.darkened(1) == RGBColor(0, 0, 0), "darkened to black")
    expect(c.mixed(with: c, 0.5) == c, "mix with self")
}

// MARK: - World clock

section("world clock") {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var sawDay = false
    var sawNight = false
    var previousHour: Float = -1

    for month in [1, 4, 7, 10] {
        for hour in 0..<24 {
            var comps = DateComponents()
            comps.year = 2026; comps.month = month; comps.day = 15; comps.hour = hour
            guard let date = cal.date(from: comps) else { continue }
            let sky = WorldClock.sky(at: date, timeZone: TimeZone(identifier: "UTC")!)
            expect(finite(sky.sunElevation), "sun elevation finite")
            expect(sky.sunElevation > -1.6 && sky.sunElevation < 1.6, "sun elevation in range")
            expect(sky.sunAzimuth >= 0 && sky.sunAzimuth <= .pi * 2 + 1e-3, "azimuth in range")
            expect(sky.daylight >= 0 && sky.daylight <= 1, "daylight normalised")
            let d = sky.sunDirection
            let len = sqrtf(d.x * d.x + d.y * d.y + d.z * d.z)
            expect(abs(len - 1) < 1e-3, "sun direction is a unit vector")
            expect(finite(sky.skyZenithColor.r) && finite(sky.ambientColor.g), "sky colours finite")
            if sky.daylight > 0.5 { sawDay = true }
            if sky.sunElevation < -0.2 { sawNight = true }
            if hour > 0 { expect(sky.localHour > previousHour, "local hour advances") }
            previousHour = sky.localHour
        }
        previousHour = -1
    }
    expect(sawDay, "some hour is daylight")
    expect(sawNight, "some hour is night")

    // Noon should be brighter than midnight, in both hemispheres' summer.
    var noonComps = DateComponents(); noonComps.year = 2026; noonComps.month = 6; noonComps.day = 21; noonComps.hour = 12
    var midnightComps = noonComps; midnightComps.hour = 0
    let noon = WorldClock.sky(at: cal.date(from: noonComps)!, timeZone: TimeZone(identifier: "UTC")!)
    let midnight = WorldClock.sky(at: cal.date(from: midnightComps)!, timeZone: TimeZone(identifier: "UTC")!)
    expect(noon.sunElevation > midnight.sunElevation, "noon is higher than midnight")
    expect(noon.daylight > 0.6, "noon is daylight (got \(noon.daylight))")
    expect(midnight.daylight < 0.1, "midnight is dark (got \(midnight.daylight))")
    expect(midnight.wantsLampLight, "lamp wanted at midnight")
    expect(!noon.wantsLampLight, "lamp not wanted at noon")
}

// MARK: - Geometry

section("mesh builder") {
    /// The generators used to be checked only for "did not crash". Now that they
    /// return raw mesh data rather than an opaque geometry object, the harness can
    /// assert the buffers are actually well formed.
    func validate(_ mesh: MeshData, _ label: String, smooth: Bool = true) {
        mesh.normalsIfNeeded()
        expect(!mesh.positions.isEmpty, "\(label) has vertices")
        expect(mesh.indices.count % 3 == 0, "\(label) index count is a whole number of triangles")
        expect(mesh.indices.count >= 3, "\(label) has triangles")
        expect(mesh.normals.count == mesh.positions.count, "\(label) has a normal per vertex")
        expect(mesh.uvs.count == mesh.positions.count, "\(label) has a uv per vertex")
        expect(mesh.indices.allSatisfy { $0 >= 0 && Int($0) < mesh.positions.count },
               "\(label) indices are in range")
        expect(mesh.positions.allSatisfy { finite($0) }, "\(label) positions are finite")
        expect(mesh.normals.allSatisfy { abs($0.length - 1) < 1e-3 }, "\(label) normals are unit length")

        // Vertices at the same place must face the same way. A closed loft keeps two
        // vertex columns at the seam so the texture has somewhere to wrap, and each
        // used to average only the triangles on its own side — a lighting crease down
        // every tube in the game. This is the regression test for that.
        //
        // Only for meshes that are smooth everywhere. A box's corner is three
        // vertices at one point that must face three different ways, and welding
        // those is the bug, not the fix — which is why the weld now works from
        // seams the generator declares rather than from coincident positions.
        if smooth {
            var byPosition: [String: Vec3] = [:]
            for (i, p) in mesh.positions.enumerated() {
                let key = "\(Int((p.x * 1e4).rounded()))|\(Int((p.y * 1e4).rounded()))|\(Int((p.z * 1e4).rounded()))"
                if let first = byPosition[key] {
                    expect(dot(first, mesh.normals[i]) > 0.9999,
                           "\(label) has no shading seam at coincident vertices")
                } else {
                    byPosition[key] = mesh.normals[i]
                }
            }
        }
    }

    let mesh = MeshData()
    let a = mesh.addVertex(Vec3(x: 0, y: 0, z: 0), uv: .zero)
    let b = mesh.addVertex(Vec3(x: 1, y: 0, z: 0), uv: .zero)
    let c = mesh.addVertex(Vec3(x: 0, y: 0, z: 1), uv: .zero)
    mesh.addTriangle(a, b, c)
    mesh.addTriangle(a, a, b)          // degenerate: must be dropped
    expect(mesh.indices.count == 3, "degenerate triangles are rejected")
    mesh.recomputeNormals()
    for n in mesh.normals {
        expect(finite(n) && abs(n.length - 1) < 1e-4, "normal is unit length")
    }
    // Winding: this triangle must face -Y given the CCW-from-below order.
    expect(mesh.normals[0].y < 0, "normal direction follows winding")

    // A loft's side faces must point away from the axis.
    let rings = (0...8).map { i -> LoftRing in
        LoftRing(center: Vec3(x: 0, y: 0, z: Float(i) * 0.1), radiusX: 0.2, radiusY: 0.2)
    }
    let loftMesh = MeshData()
    var ringIdx: [[Int32]] = []
    for (ri, ring) in rings.enumerated() {
        var row: [Int32] = []
        for s in 0...16 {
            let ang = Float(s) / 16 * 2 * .pi
            row.append(loftMesh.addVertex(Vec3(x: ring.center.x + cosf(ang) * ring.radiusX,
                                               y: ring.center.y + sinf(ang) * ring.radiusY,
                                               z: ring.center.z),
                                          uv: Vec2(x: Float(s), y: Float(ri))))
        }
        ringIdx.append(row)
    }
    for ri in 0..<(rings.count - 1) {
        for s in 0..<16 {
            loftMesh.addQuad(ringIdx[ri][s], ringIdx[ri][s + 1], ringIdx[ri + 1][s + 1], ringIdx[ri + 1][s])
        }
    }
    loftMesh.recomputeNormals()
    var outward = 0
    for (i, n) in loftMesh.normals.enumerated() {
        let p = loftMesh.positions[i]
        let radial = Vec3(x: p.x, y: p.y, z: 0).normalized
        if dot(n, radial) > 0.5 { outward += 1 }
    }
    expect(outward > loftMesh.normals.count * 9 / 10,
           "lofted side faces point outward (\(outward)/\(loftMesh.normals.count))")

    /// Every edge is shared by exactly two triangles — the mesh has no holes and no
    /// faces stacked on top of each other.
    ///
    /// `blob` used to leave a hole at each pole: `sinf(0)` collapses the end rings
    /// to a point, but the radius is floored at 0.6 mm to keep the loft well formed,
    /// so what was actually there was a 0.6 mm aperture ringed by slivers. On a 7 mm
    /// nose that is a pinprick lit from inside the head.
    func watertight(_ mesh: MeshData, _ label: String) {
        // Key on position, not index: the seam columns are separate vertices at the
        // same place, so an index-keyed edge count would report the seam as a hole.
        func key(_ i: Int32) -> String {
            let p = mesh.positions[Int(i)]
            return "\(Int((p.x * 1e5).rounded()))|\(Int((p.y * 1e5).rounded()))|\(Int((p.z * 1e5).rounded()))"
        }
        var edges: [String: Int] = [:]
        var t = 0
        while t + 2 < mesh.indices.count {
            let k = [key(mesh.indices[t]), key(mesh.indices[t + 1]), key(mesh.indices[t + 2])]
            for e in 0..<3 {
                let a = k[e], b = k[(e + 1) % 3]
                if a == b { continue }        // a sliver at a collapsed pole ring
                edges[a < b ? "\(a)>\(b)" : "\(b)>\(a)", default: 0] += 1
            }
            t += 3
        }
        let open = edges.filter { $0.value != 2 }
        expect(open.isEmpty, "\(label) is watertight (\(open.count) edges not shared by two faces)")
    }

    validate(MeshBuilder.blob(radius: 0.05), "blob")
    watertight(MeshBuilder.blob(radius: 0.05), "blob")
    watertight(MeshBuilder.blob(radius: 0.004, scaleY: 0.8, rings: 8, segments: 10), "nose-sized blob")
    watertight(MeshBuilder.tube(length: 0.2, radius: { _ in 0.01 }), "capped tube")
    validate(MeshBuilder.tube(length: 0.2, radius: { 0.01 + 0.01 * $0 }), "tube")
    validate(MeshBuilder.ear(length: 0.05, width: 0.03, thickness: 0.01, curl: 0.4), "ear")
    validate(MeshBuilder.strand(length: 0.05, thickness: 0.001, droop: 0.3), "strand")
    validate(MeshBuilder.quadXZ(width: 1, depth: 1), "quad")
    validate(MeshBuilder.loft([LoftRing(center: .zero, radiusX: 1, radiusY: 1)]), "degenerate loft")

    // MARK: The primitives RealityKit does not generate

    /// Every face points away from the centre of the shape.
    ///
    /// A single flipped quad is invisible in a triangle count and invisible in a
    /// watertightness check — it shows up on device as one facet lit from the
    /// wrong side, on a torus, at the top of a lantern. Checking the sign of
    /// `dot(normal, position)` catches all of it in one line per shape, and it is
    /// valid for anything star-shaped about its own origin, which every one of
    /// these is except the tube's inner wall.
    func facesOutward(_ mesh: MeshData, _ label: String, allowInward: Bool = false) {
        mesh.normalsIfNeeded()
        var wrong = 0
        for (i, n) in mesh.normals.enumerated() {
            let p = mesh.positions[i]
            guard p.length > 1e-5 else { continue }     // a cap centre says nothing
            if dot(n, p.normalized) < (allowInward ? -0.999 : 0.05) { wrong += 1 }
        }
        expect(wrong == 0, "\(label) has every face pointing outward (\(wrong) wrong)")
    }

    /// UVs stay inside the unit square, so a material's tile factor means what it
    /// says. A primitive that quietly ran u past 1 would tile at a different pitch
    /// to every other surface using the same factor.
    func unitUVs(_ mesh: MeshData, _ label: String) {
        let bad = mesh.uvs.filter { $0.x < -1e-4 || $0.x > 1.0001 || $0.y < -1e-4 || $0.y > 1.0001 }
        expect(bad.isEmpty, "\(label) keeps its uvs in the unit square (\(bad.count) outside)")
    }

    for chamfer in [Float(0), 0.002, 0.02] {
        let b = MeshBuilder.box(width: 0.4, height: 0.3, length: 0.2, chamfer: chamfer)
        validate(b, "box(chamfer: \(chamfer))", smooth: false)
        watertight(b, "box(chamfer: \(chamfer))")
        facesOutward(b, "box(chamfer: \(chamfer))")
        unitUVs(b, "box(chamfer: \(chamfer))")
    }

    // The chamfer is the point of generating boxes ourselves, so assert it does
    // something: a plain box has six normals, a chamfered one has twenty-six —
    // six faces, twelve bevels, eight corners — and those extra twenty are what
    // catch a highlight along an edge that used to be perfectly dark.
    func distinctNormals(_ mesh: MeshData) -> Int {
        mesh.normalsIfNeeded()
        var seen = Set<String>()
        for n in mesh.normals {
            seen.insert("\(Int((n.x * 100).rounded()))|\(Int((n.y * 100).rounded()))|\(Int((n.z * 100).rounded()))")
        }
        return seen.count
    }
    expect(distinctNormals(MeshBuilder.box(width: 0.4, height: 0.3, length: 0.2)) == 6,
           "a square box has exactly six distinct normals")
    expect(distinctNormals(MeshBuilder.box(width: 0.4, height: 0.3, length: 0.2, chamfer: 0.01)) == 26,
           "a chamfered box has six faces, twelve bevels and eight corners")

    // A chamfer cannot eat the box it is chamfering.
    let overChamfered = MeshBuilder.box(width: 0.1, height: 0.1, length: 0.1, chamfer: 5)
    watertight(overChamfered, "box with an absurd chamfer")
    facesOutward(overChamfered, "box with an absurd chamfer")

    let cyl = MeshBuilder.cylinder(radius: 0.05, height: 0.2)
    validate(cyl, "cylinder", smooth: false)
    watertight(cyl, "cylinder")
    facesOutward(cyl, "cylinder")
    unitUVs(cyl, "cylinder")
    watertight(MeshBuilder.cylinder(radius: 0.002, height: 0.4), "hair-thin cylinder")

    // The rim is a hard edge and has to stay one: the cap ring and the wall ring
    // are separate vertices, so a teacup's lip is a lip rather than a bulge.
    do {
        var atRim: [Vec3] = []
        for (i, p) in cyl.positions.enumerated() where abs(p.y - 0.1) < 1e-5 && p.length > 0.04 {
            atRim.append(cyl.normals[i])
        }
        expect(atRim.contains { $0.y > 0.99 } && atRim.contains { abs($0.y) < 0.01 },
               "the cylinder rim carries both the cap's normal and the wall's, unwelded")
    }

    let tube = MeshBuilder.pipe(innerRadius: 0.03, outerRadius: 0.05, height: 0.1)
    validate(tube, "pipe", smooth: false)
    watertight(tube, "pipe")
    unitUVs(tube, "pipe")
    do {
        // The inner wall must face the axis, or the tube is a solid cylinder with
        // an invisible second skin.
        // The wall is only two rings tall, and its vertices share both position and
        // radius with the annulus that closes the end — the normal is the only
        // thing that tells them apart, so it is what gets counted.
        var inward = 0, outward = 0, capward = 0
        for (i, p) in tube.positions.enumerated() {
            let radial = Vec3(x: p.x, y: 0, z: p.z)
            guard abs(radial.length - 0.03) < 1e-4 else { continue }
            let d = dot(tube.normals[i], radial.normalized)
            if d < -0.99 { inward += 1 } else if d > 0.99 { outward += 1 }
            if abs(tube.normals[i].y) > 0.99 { capward += 1 }
        }
        expect(inward > 0, "the pipe's inner wall faces the axis (\(inward) vertices)")
        expect(outward == 0, "nothing at the inner radius faces outward (\(outward) vertices)")
        expect(capward > 0, "the annulus at the inner radius faces along the axis (\(capward))")
    }

    let ring = MeshBuilder.torus(ringRadius: 0.06, pipeRadius: 0.0022)
    validate(ring, "torus")
    watertight(ring, "torus")
    unitUVs(ring, "torus")
    do {
        // Outward on a torus means away from the pipe's own centre line, not away
        // from the origin, so `facesOutward` cannot be used here.
        var wrong = 0
        for (i, p) in ring.positions.enumerated() {
            let axisward = Vec3(x: p.x, y: 0, z: p.z).normalized * 0.06
            let outFromPipe = (p - axisward).normalized
            if dot(ring.normals[i], outFromPipe) < 0.5 { wrong += 1 }
        }
        expect(wrong == 0, "torus faces point away from the pipe centre line (\(wrong) wrong)")
    }

    // The lantern's ribs are the reason the tessellation rule exists: a 2.2 mm
    // pipe at SceneKit's default 48 × 24 is 2,304 triangles per hoop, seven hoops,
    // more than the whole cat. Sized for its own radius it is a fraction of that.
    expect(ring.indices.count / 3 < 400,
           "a lantern rib costs under 400 triangles (\(ring.indices.count / 3))")

    let pl = MeshBuilder.plane(width: 0.5, height: 0.3)
    validate(pl, "plane")
    unitUVs(pl, "plane")
    expect(pl.normals.allSatisfy { $0.z > 0.99 }, "a plane faces +Z, as SCNPlane does")

    validate(MeshBuilder.sphere(radius: 0.004), "sphere")
    watertight(MeshBuilder.sphere(radius: 0.004), "sphere")
}

// MARK: - Cat rigs for every breed

section("cat builder") {
    for breed in CatBreed.allCases {
        for stage in LifeStage.allCases {
            var appearance = BreedPresets.appearance(for: breed)
            appearance.lifeStage = stage
            let rig = CatBuilder.build(appearance, preview: true)
            expect(rig.legs.count == 4, "\(breed.rawValue) has four legs")
            expect(!rig.tailSegments.isEmpty, "\(breed.rawValue) has a tail")
            expect(rig.bodyHeight > 0.02 && rig.bodyHeight < 1.0,
                   "\(breed.rawValue) body height sane: \(rig.bodyHeight)")
            expect(finite(rig.torsoLength) && rig.torsoLength > 0, "\(breed.rawValue) torso length")
            for leg in rig.legs {
                expect(leg.upperLength > 0 && leg.lowerLength > 0,
                       "\(breed.rawValue) leg segments positive")
                expect(finite(leg.restFoot), "\(breed.rawValue) rest foot finite")
            }
        }
    }

    // Extremes must not produce NaN or zero-size geometry.
    var extreme = CatAppearance()
    for value in [Float(0), 1] {
        extreme.furLength = value; extreme.furFluff = value; extreme.bodyLength = value
        extreme.bodyGirth = value; extreme.chonk = value; extreme.legLength = value
        extreme.legThickness = value; extreme.tailLength = value; extreme.tailThickness = value
        extreme.tailFluff = value; extreme.earLength = value; extreme.earWidth = value
        extreme.headWidth = value; extreme.headRoundness = value; extreme.muzzleLength = value
        extreme.eyeSize = value; extreme.pawSize = value; extreme.neckThickness = value
        for shape in TailShape.allCases {
            extreme.tailShape = shape
            let rig = CatBuilder.build(extreme, preview: true)
            expect(finite(rig.bodyHeight) && rig.bodyHeight > 0,
                   "extreme \(value) \(shape) body height")
        }
        for ear in EarShape.allCases {
            extreme.earShape = ear
            _ = CatBuilder.build(extreme, preview: true)
        }
    }
}

// MARK: - Animator

section("animator") {
    var appearance = BreedPresets.appearance(for: .maineCoon)
    appearance.collarStyle = .bell
    let rig = CatBuilder.build(appearance)
    let animator = CatAnimator(rig: rig)
    var motion = CatMotion()

    let poses: [CatPose] = [.standing, .walking, .trotting, .running, .sitting, .sittingTall,
                            .loaf, .lyingSide, .curled, .crouch, .stretching, .grooming,
                            .eating, .drinking, .litterCrouch, .playCrouch, .pounce,
                            .rearUp, .kneading, .scratchingPost]

    for pose in poses {
        motion.pose = pose
        motion.speed = pose.isLocomotion ? 1.2 : 0
        motion.position = SIMD3<Float>(x: 0.3, y: 0, z: -0.5)
        motion.yaw = 0.7
        motion.lookTarget = RoomLayout.cameraPosition
        motion.lookWeight = 1
        motion.eyeOpen = 0.5
        motion.purr = 0.4
        motion.tailAgitation = 0.6
        motion.earPin = 0.3
        for _ in 0..<240 {
            animator.update(dt: 1.0 / 60, motion: motion)
        }
        expect(finite(rig.body.position), "\(pose) body position finite")
        expect(finite(rig.spine.eulerAngles), "\(pose) spine angles finite")
        expect(finite(rig.head.eulerAngles), "\(pose) head angles finite")
        expect(finite(rig.neck.eulerAngles), "\(pose) neck angles finite")
        expect(finite(rig.tailPitch.eulerAngles), "\(pose) tail pitch finite")
        for (i, leg) in rig.legs.enumerated() {
            expect(finite(leg.hip.eulerAngles), "\(pose) leg \(i) hip finite")
            expect(finite(leg.knee.eulerAngles), "\(pose) leg \(i) knee finite")
            expect(finite(leg.ankle.eulerAngles), "\(pose) leg \(i) ankle finite")
            expect(abs(leg.hip.eulerAngles.x) < 6.4, "\(pose) leg \(i) hip angle bounded")
            expect(abs(leg.knee.eulerAngles.x) < 6.4, "\(pose) leg \(i) knee angle bounded")
        }
        for seg in rig.tailSegments {
            expect(finite(seg.eulerAngles), "\(pose) tail segment finite")
        }
        expect(finite(rig.earL.eulerAngles) && finite(rig.earR.eulerAngles), "\(pose) ears finite")
        expect(finite(rig.lidUpperL.eulerAngles), "\(pose) eyelids finite")
    }

    // Look-at must not drift: repeated frames aimed at a fixed point should settle.
    motion.pose = .sittingTall
    motion.speed = 0
    motion.lookTarget = SIMD3<Float>(x: 1, y: 0.5, z: 1)
    motion.lookWeight = 1
    for _ in 0..<120 { animator.update(dt: 1.0 / 60, motion: motion) }
    let firstYaw = rig.head.eulerAngles.y
    for _ in 0..<120 { animator.update(dt: 1.0 / 60, motion: motion) }
    expect(abs(rig.head.eulerAngles.y - firstYaw) < 1e-3,
           "look-at is stable, drifted \(rig.head.eulerAngles.y - firstYaw)")
}

// MARK: - Brain

section("cat brain") {
    for archetype in PersonalityArchetype.allCases {
        var save = GameSave()
        save.profile.appearance = BreedPresets.appearance(for: .bengal)
        save.profile.personality = CatPersonality.archetype(archetype)
        let brain = CatBrain(save: save)

        var seenActivities = Set<CatActivity>()
        var events = 0
        brain.onEvent = { _ in events += 1 }

        var sky = WorldClock.sky()
        // Four simulated hours at 20 Hz.
        for step in 0..<(4 * 3600 * 20) {
            if step % 2000 == 0 {
                sky = WorldClock.sky(at: Date().addingTimeInterval(Double(step) / 20))
            }
            brain.update(dt: 1.0 / 20, sky: sky)
            seenActivities.insert(brain.activity)

            let p = brain.motion.position
            expect(finite(p), "\(archetype) position finite")
            if !finite(p) { break }
            expect(p.x > -RoomLayout.halfWidth - 0.5 && p.x < RoomLayout.halfWidth + 0.5,
                   "\(archetype) stays inside X (\(p.x))")
            expect(p.z > -RoomLayout.halfDepth - 0.5 && p.z < RoomLayout.halfDepth + 0.5,
                   "\(archetype) stays inside Z (\(p.z))")
            expect(p.y >= -0.01 && p.y < 1.6, "\(archetype) stays near the floor (\(p.y))")
            expect(finite(brain.motion.yaw), "\(archetype) yaw finite")
        }

        for key in NeedKey.allCases {
            let v = brain.needs[key]
            expect(v >= 0 && v <= 1, "\(archetype) need \(key) in range: \(v)")
        }
        expect(brain.bond >= 0 && brain.bond <= 1, "\(archetype) bond in range")
        expect(seenActivities.count >= 4,
               "\(archetype) varies its behaviour (saw \(seenActivities.count))")
        expect(events > 0, "\(archetype) emitted events")
        expect(!brain.statusCaption.isEmpty, "\(archetype) has a status caption")
    }
}

// MARK: - Interaction

section("interaction") {
    var save = GameSave()
    save.profile.personality = CatPersonality.archetype(.lapCat)
    save.needs.social = 0.1
    let brain = CatBrain(save: save)
    let sky = WorldClock.sky()

    // Walk the cat over to the player, then pet it until it has had enough.
    var arrived = false
    for _ in 0..<20000 {
        brain.call()
        for _ in 0..<200 { brain.update(dt: 1.0 / 30, sky: sky) }
        if brain.canBePet { arrived = true; break }
    }
    expect(arrived, "a lap cat eventually comes when called")

    if arrived {
        var hissed = false
        brain.onEvent = { event in
            if case .hiss = event { hissed = true }
            if case .yowl = event { hissed = true }
        }
        brain.beginPetting(zone: .belly)
        for _ in 0..<60 * 60 {
            brain.updatePetting(zone: .belly, intensity: 1)
            brain.update(dt: 1.0 / 60, sky: sky)
            if brain.isOverstimulated { break }
        }
        expect(brain.isOverstimulated, "belly rubs overstimulate")
        expect(hissed, "overstimulation is audible")
        expect(!brain.canBePet, "an overstimulated cat cannot be pet")
        for _ in 0..<60 * 12 { brain.update(dt: 1.0 / 60, sky: sky) }
        expect(!brain.isOverstimulated, "the cat forgives")
    }

    // The wand must not leave the cat stuck.
    let brain2 = CatBrain(save: save)
    brain2.setWand(active: true, tip: SIMD3<Float>(x: 0, y: 0.2, z: 0))
    for i in 0..<6000 {
        brain2.setWand(active: true, tip: SIMD3<Float>(x: sinf(Float(i) * 0.01) * 0.8,
                                                     y: 0.15 + 0.3 * abs(sinf(Float(i) * 0.02)),
                                                     z: -0.4 + cosf(Float(i) * 0.013) * 0.6))
        brain2.update(dt: 1.0 / 30, sky: sky)
        expect(finite(brain2.motion.position), "wand chase position finite")
        if !finite(brain2.motion.position) { break }
    }
    brain2.setWand(active: false, tip: .zero)
    for _ in 0..<600 { brain2.update(dt: 1.0 / 30, sky: sky) }
    expect(brain2.activity != .chaseWand, "the cat stops chasing when the wand is put away")
    expect(brain2.needs.play > 0.3, "play need was satisfied by the wand: \(brain2.needs.play)")

    // Treats get eaten and cleaned up.
    let brain3 = CatBrain(save: save)
    brain3.needs.fullness = 0.3
    brain3.dropTreat(at: RoomLayout.playerLapSpot)
    var ate = false
    for _ in 0..<9000 {
        brain3.update(dt: 1.0 / 30, sky: sky)
        if brain3.treatPosition == nil { ate = true; break }
    }
    expect(ate, "the treat is eventually eaten")
}

// MARK: - Consumables

section("consumables") {
    var save = GameSave()
    save.room.feederFood = 0
    save.room.fountainWater = 0
    save.needs.fullness = 0.05
    save.needs.hydration = 0.05
    let brain = CatBrain(save: save)
    let sky = WorldClock.sky()
    for _ in 0..<20000 {
        brain.update(dt: 1.0 / 20, sky: sky)
        expect(brain.activity != .eat, "an empty feeder is never chosen")
        expect(brain.activity != .drink, "an empty fountain is never chosen")
        if brain.activity == .eat || brain.activity == .drink { break }
    }
    brain.refillFeeder()
    brain.refillFountain()
    var fed = false
    for _ in 0..<40000 {
        brain.update(dt: 1.0 / 20, sky: sky)
        if brain.needs.fullness > 0.5 { fed = true; break }
    }
    expect(fed, "a refilled feeder gets used (fullness \(brain.needs.fullness))")
}

// MARK: - Offline catch-up

section("offline") {
    for hours in [0.0, 0.5, 3, 12, 30, 200] as [Double] {
        var save = GameSave()
        save.lastSeen = Date().addingTimeInterval(-hours * 3600)
        let result = OfflineSimulator.catchUp(save: save)
        for key in NeedKey.allCases {
            let v = result.needs[key]
            expect(v >= 0 && v <= 1 && finite(v), "offline \(hours)h need \(key) in range: \(v)")
        }
        expect(result.room.feederFood >= 0 && result.room.feederFood <= 1, "offline feeder level")
        expect(result.elapsedHours <= 72.01, "offline elapsed is capped")
        if hours >= 3 { expect(!result.log.isEmpty, "offline \(hours)h produces a log") }
    }

    // A long absence should leave the cat worse off, not broken.
    var save = GameSave()
    save.lastSeen = Date().addingTimeInterval(-48 * 3600)
    save.room.feederFood = 0.05
    save.room.fountainWater = 0.05
    let starved = OfflineSimulator.catchUp(save: save)
    expect(starved.needs.fullness < 0.6, "a long absence with no food is felt")
    expect(starved.needs.social < 0.5, "a long absence is lonely")
}

// MARK: - Resuming after a gap

section("resume") {
    // Backgrounding the app and coming back hours later must advance the cat,
    // and the running simulation must accept the caught-up state.
    var save = GameSave()
    save.profile.personality = CatPersonality.archetype(.balanced)
    save.lastSeen = Date().addingTimeInterval(-6 * 3600)
    save.needs.social = 0.9
    save.needs.play = 0.9

    let brain = CatBrain(save: save)
    let before = brain.needs.social
    let result = OfflineSimulator.catchUp(save: save)
    expect(result.needs.social < before, "six hours away costs the cat company")
    expect(!result.log.isEmpty, "six hours away produces a log")

    brain.needs = result.needs
    brain.room = result.room
    let sky = WorldClock.sky()
    for _ in 0..<6000 { brain.update(dt: 1.0 / 30, sky: sky) }
    for key in NeedKey.allCases {
        expect(brain.needs[key] >= 0 && brain.needs[key] <= 1,
               "resumed need \(key) stays in range")
    }
    expect(finite(brain.motion.position), "resumed cat has a finite position")
}

// MARK: - Save round-trip

section("save file") {
    var save = GameSave()
    save.profile.name = "Yuzu"
    save.profile.appearance = BreedPresets.appearance(for: .turkishVan)
    save.profile.personality = CatPersonality.archetype(.gremlin)
    save.needs.play = 0.33
    save.bond = 0.6
    save.awayLog = ["a", "b"]

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    guard let data = try? encoder.encode(save) else {
        expect(false, "save encodes"); return
    }
    guard let restored = try? decoder.decode(GameSave.self, from: data) else {
        expect(false, "save decodes"); return
    }
    expect(restored.profile.name == "Yuzu", "name survives the round trip")
    expect(restored.profile.appearance == save.profile.appearance, "appearance survives")
    expect(restored.profile.personality == save.profile.personality, "personality survives")
    expect(abs(restored.needs.play - 0.33) < 1e-6, "needs survive")
    expect(restored.awayLog == ["a", "b"], "away log survives")

    // Garbage must not crash the loader.
    expect((try? decoder.decode(GameSave.self, from: Data("{}".utf8))) == nil ||
           (try? decoder.decode(GameSave.self, from: Data("{}".utf8))) != nil,
           "empty object decodes or fails cleanly")
    expect((try? decoder.decode(GameSave.self, from: Data("not json".utf8))) == nil,
           "garbage is rejected")
}

// MARK: - Room layout

section("room layout") {
    var g = SeededGenerator(seed: 5)
    for _ in 0..<5000 {
        let p = RoomLayout.randomFloorPoint(using: &g)
        expect(p.x >= -RoomLayout.halfWidth && p.x <= RoomLayout.halfWidth, "random point inside X")
        expect(p.z >= -RoomLayout.halfDepth && p.z <= RoomLayout.halfDepth, "random point inside Z")
    }
    for x in stride(from: Float(-4), through: 4, by: 0.25) {
        for z in stride(from: Float(-4), through: 4, by: 0.25) {
            let p = RoomLayout.clampToWalkable(SIMD3<Float>(x: x, y: 0, z: z))
            expect(p.x >= -RoomLayout.halfWidth && p.x <= RoomLayout.halfWidth,
                   "clamped X inside room (\(p.x))")
            expect(p.z >= -RoomLayout.halfDepth && p.z <= RoomLayout.halfDepth,
                   "clamped Z inside room (\(p.z))")
        }
    }

    // Every activity's spot must be reachable and sane.
    var rng = SeededGenerator(seed: 11)
    let sky = WorldClock.sky()
    for activity in CatActivity.allCases {
        let spot = activity.spot(sky: sky, rng: &rng)
        expect(finite(spot.position), "\(activity) spot finite")
        expect(spot.surfaceHeight >= 0 && spot.surfaceHeight < 1.5,
               "\(activity) surface height sane: \(spot.surfaceHeight)")
        expect(abs(spot.position.x) <= RoomLayout.halfWidth + 0.01,
               "\(activity) spot inside X: \(spot.position.x)")
        expect(abs(spot.position.z) <= RoomLayout.halfDepth + 0.01,
               "\(activity) spot inside Z: \(spot.position.z)")
        expect(!activity.caption.isEmpty, "\(activity) has a caption")
        let (lo, hi) = activity.duration
        expect(lo > 0 && hi >= lo, "\(activity) duration sane")
    }

    // The sun patch must track the sun without leaving the room.
    for hour in 0..<24 {
        var comps = DateComponents(); comps.year = 2026; comps.month = 6; comps.day = 21; comps.hour = hour
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let s = WorldClock.sky(at: cal.date(from: comps)!, timeZone: TimeZone(identifier: "UTC")!)
        let p = RoomLayout.sunPatchPosition(sky: s)
        expect(finite(p) && abs(p.x) < 2 && abs(p.z) < 2.5, "sun patch stays in the room")
    }
}

// MARK: - Textures & rooms (exercised for crashes and hangs)

section("textures") {
    for breed in CatBreed.allCases {
        let a = BreedPresets.appearance(for: breed)
        _ = TextureFactory.catCoatPreview(a)
        _ = TextureFactory.furShellMask(a)
        _ = TextureFactory.iris(color: a.eyeColor, pupil: a.pupilShape, dilation: 0.5, brightness: 0.5)
    }
    for pattern in CoatPattern.allCases {
        var a = BreedPresets.appearance(for: .domesticShorthair)
        a.pattern = pattern
        a.whiteSpotting = 0.5
        _ = TextureFactory.catCoatPreview(a)
    }
    _ = TextureFactory.tatami()
    _ = TextureFactory.tatamiBorder()
    _ = TextureFactory.shojiPaper()
    _ = TextureFactory.plaster()
    _ = TextureFactory.futonCover()
    _ = TextureFactory.sisal()
    _ = TextureFactory.litterSubstrate()
    _ = TextureFactory.inkScroll()
    _ = TextureFactory.foliage()
    for hour in 0..<24 {
        var comps = DateComponents(); comps.year = 2026; comps.month = 3; comps.day = 1; comps.hour = hour
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let sky = WorldClock.sky(at: cal.date(from: comps)!, timeZone: TimeZone(identifier: "UTC")!)
        _ = TextureFactory.gardenBackdrop(sky: sky)
        _ = TextureFactory.skyEnvironment(sky: sky)
    }
    expect(true, "textures generated without crashing")
}

section("room builder") {
    let sky = WorldClock.sky()
    let room = RoomBuilder.build(sky: sky)
    expect(room.root.children.count > 10, "room has content")
    expect(room.shojiPanels.count >= 2, "shoji panels captured")
    expect(room.backdropPanels.count >= 1, "backdrop captured")
    expect(room.lanternLight != nil, "lantern light captured")
    expect(room.foodPile != nil && room.waterSurface != nil, "consumable nodes captured")
    expect(room.sunPatch != nil, "sun patch captured")

    let lighting = LightingRig()
    // Every light, every emissive surface and the camera all come off one light
    // budget now, so the invariants worth holding are about that budget rather
    // than about any single curve.
    var samples: [(hour: Int, key: Float, exposure: Float, rendered: Float)] = []
    for hour in 0..<24 {
        var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 21; comps.hour = hour
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let s = WorldClock.sky(at: cal.date(from: comps)!, timeZone: TimeZone(identifier: "UTC")!)
        let lanternOn = s.wantsLampLight
        lighting.apply(sky: s, room: room, lanternOn: lanternOn)

        let b = LightingRig.budget(sky: s, lanternOn: lanternOn)
        let e = LightingRig.exposure(for: b)
        expect(b.key > 0, "something is lighting the room at \(hour):00")
        // Exposure is deliberately constant. Varying it with the sky rescales
        // every emissive in the room too — lantern paper, feeder LED, eye
        // catchlights, the garden — none of which are in the budget, and three
        // builds each broke a different hour that way. The day/night difference
        // lives in the lights instead.
        expect(abs(e - LightingRig.exposure(for: LightingRig.budget(sky: s, lanternOn: false))) < 1e-6,
               "exposure does not vary with the lantern at \(hour):00")
        // A multiplier now, not an EV offset: it scales the lights rather than the
        // rendered image, because RealityKit's camera has no exposure at all.
        expect(e > 0 && e <= 1.0, "exposure at \(hour):00 is in range (\(e))")
        samples.append((hour, b.key, e, LightingRig.renderedBrightness(for: b)))
    }

    // More lux must mean more light in the room. `renderedBrightness` is the sum
    // of what actually goes into the scene, so this is a check on the lights
    // themselves, not on a model of them — which is what the previous version
    // got wrong. The failure it guards against is a coefficient tuned to make
    // one hour look right inverting the order somewhere else.
    let byKey = samples.sorted { $0.key < $1.key }
    for (a, b) in zip(byKey, byKey.dropFirst()) {
        expect(b.rendered >= a.rendered - 1e-4,
               "more light renders brighter (\(a.hour):00 \(a.key)lx vs \(b.hour):00 \(b.key)lx)")
        expect(abs(b.exposure - a.exposure) < 1e-6,
               "exposure is the same at every hour (\(a.hour):00 vs \(b.hour):00)")
    }

    // ...and the day must still have visible contrast in it. Full compensation
    // would satisfy the ordering above while making every hour look identical,
    // which is the failure this pairs with.
    let darkest = byKey.first!, brightest = byKey.last!
    // These bounds are in light, not in pixels. SceneKit's tone mapper and sRGB
    // both compress hard at the bottom, so a 29x range in the room shows up as
    // a much smaller difference on screen — an earlier build with only 7.7x
    // between night and noon rendered them within 8% of each other. Hence a
    // floor well above "some difference": below about 4x, night stops reading
    // as night at all.
    let stops = log2(brightest.rendered / darkest.rendered)
    expect(stops > 2.0, "day is not flat: \(stops) stops between \(darkest.hour):00 and \(brightest.hour):00")
    expect(stops < 6.0, "day is not extreme: \(stops) stops")
    expect(brightest.key / darkest.key > 20,
           "the underlying light really does span a wide range (\(brightest.key / darkest.key)x)")
    expect(true, "lighting applied across a whole day")
}

// MARK: - RealityKit stand-in

// The stand-in cannot be checked against Apple's framework — that is the gap the
// README is honest about. What it can be checked for is self-consistency, and
// that is where the real danger is: a transposed matrix or a quaternion with the
// wrong handedness typechecks, runs, and silently mangles every joint on device.
section("realitykit shim") {
    func approxEqual(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ tol: Float = 1e-4) -> Bool {
        simd_length(a - b) < tol
    }

    // Identity really is identity.
    let identity = Transform.identity.matrix
    for c in 0..<4 {
        for r in 0..<4 {
            expect(abs(identity[c, r] - (c == r ? 1 : 0)) < 1e-6, "identity transform is identity")
        }
    }

    // Matrix multiply is not commutative and does compose in the documented order.
    let t = Transform(scale: SIMD3<Float>(2, 3, 4),
                      rotation: simd_quatf(angle: 0.7, axis: SIMD3<Float>(0, 1, 0)),
                      translation: SIMD3<Float>(1, -2, 5))
    let roundTrip = Transform(matrix: t.matrix)
    expect(approxEqual(roundTrip.translation, t.translation), "transform decompose recovers translation")
    expect(approxEqual(roundTrip.scale, t.scale, 1e-3), "transform decompose recovers scale")
    let probe = SIMD3<Float>(0.3, -0.4, 0.9)
    expect(approxEqual(roundTrip.rotation.act(probe), t.rotation.act(probe), 1e-3),
           "transform decompose recovers rotation")

    // Inverse is a real inverse.
    let back = t.matrix.inverse * t.matrix
    for c in 0..<4 {
        for r in 0..<4 {
            expect(abs(back[c, r] - (c == r ? 1 : 0)) < 1e-4, "matrix inverse undoes the matrix")
        }
    }

    // Quaternion and matrix agree about what a rotation does.
    for (angle, axis) in [(Float(0.4), SIMD3<Float>(1, 0, 0)),
                          (Float(-1.2), SIMD3<Float>(0, 1, 0)),
                          (Float(2.6), SIMD3<Float>(0, 0, 1)),
                          (Float(0.9), SIMD3<Float>(0.3, 0.5, -0.8))] {
        let q = simd_quatf(angle: angle, axis: simd_normalize(axis))
        let viaQuat = q.act(probe)
        let m = q.matrix
        let v4 = m * SIMD4<Float>(probe, 1)
        expect(approxEqual(viaQuat, SIMD3<Float>(v4.x, v4.y, v4.z), 1e-4),
               "quaternion and its matrix rotate alike (angle \(angle))")
        expect(abs(simd_length(viaQuat) - simd_length(probe)) < 1e-4, "rotation preserves length")
        // And the matrix reads back as the same rotation.
        expect(approxEqual(simd_quatf(m).act(probe), viaQuat, 1e-3), "matrix converts back to its quaternion")
        // Inverse undoes it.
        expect(approxEqual((q.inverse * q).act(probe), probe, 1e-4), "quaternion inverse undoes it")
    }

    // World transforms compose through the parent chain.
    let root = Entity()
    root.transform = Transform(translation: SIMD3<Float>(1, 0, 0))
    let mid = Entity()
    mid.transform = Transform(rotation: simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 1, 0)),
                              translation: SIMD3<Float>(0, 2, 0))
    let leaf = Entity()
    leaf.transform = Transform(translation: SIMD3<Float>(0, 0, 3))
    root.addChild(mid)
    mid.addChild(leaf)

    // Rotating +90° about Y sends local +Z to world +X.
    expect(approxEqual(leaf.worldPosition, SIMD3<Float>(4, 2, 0), 1e-4),
           "world transform composes through parents (got \(leaf.worldPosition))")
    expect(leaf.parent === mid && mid.parent === root, "parent links are wired")
    expect(root.findEntity(named: "") === root, "findEntity matches by name")

    // Space conversion is the inverse of itself.
    let inLeaf = SIMD3<Float>(0.5, -1, 2)
    let inWorld = leaf.convert(position: inLeaf, to: nil)
    expect(approxEqual(leaf.convert(position: inWorld, from: nil), inLeaf, 1e-3),
           "convert to and from world round-trips")
    let inRoot = leaf.convert(position: inLeaf, to: root)
    expect(approxEqual(leaf.convert(position: inRoot, from: root), inLeaf, 1e-3),
           "convert between entities round-trips")

    // --- MeshData -> MeshResource must not lose or reorder anything.
    //
    // The adapter is the one place the game's renderer-independent vertex buffers
    // become RealityKit's, so it is worth asserting the conversion is faithful rather
    // than merely type-correct. A silent index or winding change here would show up
    // much later as inside-out geometry that no other test would catch.
    for (label, mesh) in [("blob", MeshBuilder.blob(radius: 0.1)),
                          ("tube", MeshBuilder.tube(length: 0.4, radius: { 0.05 + 0.02 * $0 })),
                          ("ear", MeshBuilder.ear(length: 0.08, width: 0.05,
                                                  thickness: 0.012, curl: 0.3))] {
        guard let resource = mesh.meshResource(name: label),
              let part = resource.contents.models.first?.parts.first else {
            expect(false, "\(label) converts to a MeshResource")
            continue
        }
        expect(part.positions.count == mesh.positions.count, "\(label) keeps every vertex")
        expect(part.normals?.count == mesh.normals.count, "\(label) keeps every normal")
        expect(part.textureCoordinates?.count == mesh.uvs.count, "\(label) keeps every uv")
        expect(part.triangleIndices?.count == mesh.indices.count, "\(label) keeps every index")
        expect(resource.contents.instances.count == 1, "\(label) has one instance")
        expect(resource.expectedMaterialCount == 1, "\(label) wants one material")

        for (i, p) in part.positions.enumerated() {
            let q = mesh.positions[i]
            expect(abs(p.x - q.x) < 1e-6 && abs(p.y - q.y) < 1e-6 && abs(p.z - q.z) < 1e-6,
                   "\(label) vertex \(i) survives the conversion unmoved")
        }
        // Winding, and therefore which way the surface faces, is carried entirely by
        // index order. Int32 -> UInt32 is a widening for non-negative values, but only
        // if the order is untouched.
        if let idx = part.triangleIndices {
            for (i, v) in idx.enumerated() {
                expect(v == UInt32(mesh.indices[i]), "\(label) index \(i) keeps its place")
            }
        }
    }

    // Directions ignore translation; points do not.
    let dir = leaf.convert(direction: SIMD3<Float>(0, 0, 1), from: nil)
    expect(abs(simd_length(dir) - 1) < 1e-4, "direction conversion preserves length")

    // look(at:) actually aims -Z at the target. The SceneKit stand-in left this
    // empty, which is why the sun and moon aiming went unchecked for so long.
    let aimer = Entity()
    let targetPoint = SIMD3<Float>(3, 0, 0)
    aimer.look(at: targetPoint, from: SIMD3<Float>(0, 0, 0), relativeTo: nil)
    let forward = aimer.orientation.act(SIMD3<Float>(0, 0, -1))
    expect(approxEqual(forward, simd_normalize(targetPoint), 1e-3),
           "look(at:) points -Z at the target (got \(forward))")
    expect(approxEqual(aimer.position, SIMD3<Float>(0, 0, 0), 1e-4), "look(at:) places the entity at `from`")

    // A skeleton keeps its joints, and a pose built from it starts at rest.
    let jointNames = ["root", "spine", "head"]
    let skeleton = MeshResource.Skeleton(
        id: "cat",
        jointNames: jointNames,
        inverseBindPoseMatrices: Array(repeating: matrix_identity_float4x4, count: 3),
        restPoseTransforms: [Transform(translation: SIMD3<Float>(0, 1, 0)),
                             Transform(translation: SIMD3<Float>(0, 2, 0)),
                             Transform(translation: SIMD3<Float>(0, 3, 0))],
        parentIndices: [nil, 0, 1])
    expect(skeleton != nil, "skeleton builds from matching-length arrays")
    expect(skeleton?.joints.count == 3, "skeleton keeps every joint")
    expect(skeleton?.joints[2].parentIndex == 1, "skeleton keeps the joint hierarchy")

    // Mismatched lengths must fail rather than silently truncate.
    expect(MeshResource.Skeleton(id: "bad", jointNames: jointNames,
                                 inverseBindPoseMatrices: [matrix_identity_float4x4]) == nil,
           "skeleton rejects mismatched joint arrays")

    if let skeleton = skeleton {
        var pose = SkeletalPose(id: "cat", from: skeleton)
        expect(pose.jointNames == jointNames, "pose takes its joint names from the skeleton")
        expect(pose.jointTransforms.count == 3, "pose has a transform per joint")
        expect(pose["head"] != nil, "pose is addressable by joint name")
        pose["head"] = Transform(translation: SIMD3<Float>(9, 9, 9))
        expect(approxEqual(pose["head"]!.translation, SIMD3<Float>(9, 9, 9)),
               "posing a joint by name sticks")
        expect(approxEqual(pose["spine"]!.translation, SIMD3<Float>(0, 2, 0)),
               "posing one joint leaves the others alone")

        let component = SkeletalPosesComponent(poses: [pose])
        expect(component.poses["cat"] != nil, "pose set is addressable by id")
        expect(component.poses["nope"] == nil, "pose set does not invent poses")
    }

    // Components are stored and retrieved by type, not by accident.
    let entity = Entity()
    entity.components.set(DirectionalLightComponent(intensity: 1234))
    expect(entity.components[DirectionalLightComponent.self]?.intensity == 1234,
           "component round-trips through the set")
    expect(entity.components[PointLightComponent.self] == nil,
           "component set does not confuse component types")
    entity.components.remove(DirectionalLightComponent.self)
    expect(entity.components[DirectionalLightComponent.self] == nil, "component removal works")

    // The scalar material parameters take float literals in the real framework,
    // so `material.roughness = 0.8` compiles there. If it does not compile here,
    // the port is being written against a stricter API than the one it ships on
    // and the device build finds out first.
    var pbr = PhysicallyBasedMaterial()
    pbr.roughness = 0.8
    pbr.metallic = 0.0
    pbr.clearcoat = 0.9
    expect(pbr.roughness.scale == 0.8 && pbr.clearcoat.scale == 0.9,
           "float literals assign to scalar material parameters")
    expect(pbr.roughness.texture == nil, "a scalar assigned by literal carries no texture")

    // Transparency is an enum with a payload, not a `transparency` scalar. The
    // shape matters: it is impossible to set an opacity without also declaring
    // the material transparent, which is the mistake SceneKit let you make.
    pbr.blending = .transparent(opacity: 0.75)
    if case let .transparent(opacity) = pbr.blending {
        expect(opacity.scale == 0.75, "transparent blending carries its opacity")
    } else {
        expect(false, "blending stays transparent once set")
    }

    // A skinned part carries its influences and its skeleton binding.
    var part = MeshResource.Part(id: "body", materialIndex: 0)
    part.positions = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0)]
    part.triangleIndices = [0, 1, 0]
    part.skeletonID = "cat"
    part.jointInfluences = MeshResource.JointInfluences(
        influences: [MeshJointInfluence(jointIndex: 0, weight: 1),
                     MeshJointInfluence(jointIndex: 1, weight: 0)],
        influencesPerVertex: 1)
    expect(part.jointInfluences?.influencesPerVertex == 1, "part records influences per vertex")
    expect(part.jointInfluences?.influences.count == part.positions.count,
           "one influence per vertex at one influence per vertex")

    var contents = MeshResource.Contents()
    contents.models = [MeshResource.Model(id: "cat", parts: [part])]
    if let skeleton = skeleton { contents.skeletons = [skeleton] }
    if let mesh = try? MeshResource.generate(from: contents) {
        expect(mesh.contents.models.first?.parts.first?.skeletonID == "cat",
               "generated mesh keeps its skeleton binding")
        expect(mesh.expectedMaterialCount == 1, "material count follows the highest material index")
    } else {
        expect(false, "mesh generates from contents")
    }
}

// MARK: - Euler angles across the renderer boundary

// The port's single sharpest edge. SceneKit poses a node with three angles;
// RealityKit poses an entity with a quaternion. The cat is authored in angles —
// thirty-nine sites write them — so the conversion runs on every joint of every
// frame, and if the composition order is wrong it is wrong *everywhere at once*,
// in a way that reads as bad animation rather than bad maths.
//
// So it is pinned here against the thing it has to agree with: SceneKit itself.
// Not a restatement of the formula in `EulerRotation` — that would only prove the
// formula equals itself — but the actual `Rx · Ry · Rz` matrix product the
// SceneKit shim builds, compared by where it sends probe vectors.
section("euler convention") {

    let probes = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 0, 1),
                  SIMD3<Float>(0.37, -0.82, 0.44), SIMD3<Float>(-0.6, 0.2, 0.77)]

    // Angles chosen to include every awkward case: single axis, two axes (where
    // order first bites), all three, negatives, and past ±180°.
    let cases: [SIMD3<Float>] = [
        SIMD3<Float>(0, 0, 0),
        SIMD3<Float>(0.7, 0, 0), SIMD3<Float>(0, 0.7, 0), SIMD3<Float>(0, 0, 0.7),
        SIMD3<Float>(0.4, 0.9, 0), SIMD3<Float>(0.4, 0, 0.9), SIMD3<Float>(0, 0.4, 0.9),
        SIMD3<Float>(0.3, -0.6, 1.1), SIMD3<Float>(-1.2, 0.45, -0.8),
        SIMD3<Float>(2.9, -2.4, 1.7), SIMD3<Float>(-0.05, 0.02, -0.03),
        SIMD3<Float>(deg(-75), deg(50), 0), SIMD3<Float>(deg(5), deg(-70), deg(12)),
    ]

    // 1. The quaternion agrees with SceneKit's matrix, vector for vector.
    for e in cases {
        let node = SCNNode()
        node.simdEulerAngles = e
        let m = node.localTransform          // t · Rx · Ry · Rz · s, both identity here
        let q = EulerRotation.quaternion(e)
        for p in probes {
            let byMatrix = m.applyVector(p)
            let byQuat = q.act(p)
            expect(simd_length(byMatrix - byQuat) < 1e-4,
                   "euler \(e) rotates \(p) the same way SceneKit does "
                     + "(scenekit \(byMatrix), quaternion \(byQuat))")
        }
    }

    // 2. Order is the thing being asserted, so prove the wrong order is visibly
    //    wrong. Without this, a symmetric bug would sail through test 1.
    let twoAxis = SIMD3<Float>(0.4, 0.9, 0)
    let reversed = simd_quatf(angle: twoAxis.z, axis: SIMD3<Float>(0, 0, 1))
        * simd_quatf(angle: twoAxis.y, axis: SIMD3<Float>(0, 1, 0))
        * simd_quatf(angle: twoAxis.x, axis: SIMD3<Float>(1, 0, 0))
    let probe = SIMD3<Float>(0, 0, 1)
    expect(simd_length(EulerRotation.quaternion(twoAxis).act(probe) - reversed.act(probe)) > 0.05,
           "Rz·Ry·Rx would be a different rotation, so the order under test is load-bearing")

    // 3. One rotation whose answer can be read off by eye, as a check that the
    //    whole chain is not self-consistently mirrored.
    let quarterYaw = EulerRotation.quaternion(SIMD3<Float>(0, .pi / 2, 0))
    expect(simd_length(quarterYaw.act(SIMD3<Float>(0, 0, 1)) - SIMD3<Float>(1, 0, 0)) < 1e-5,
           "a +90° yaw takes +Z to +X")
    let quarterPitch = EulerRotation.quaternion(SIMD3<Float>(.pi / 2, 0, 0))
    // Right-hand rule about +X sends +Y to +Z and +Z to *minus* Y, which is worth
    // stating out loud: the sign here is the one a person gets wrong by eye.
    expect(simd_length(quarterPitch.act(SIMD3<Float>(0, 0, 1)) - SIMD3<Float>(0, -1, 0)) < 1e-5,
           "a +90° pitch takes +Z to -Y")
    expect(simd_length(quarterPitch.act(SIMD3<Float>(0, 1, 0)) - SIMD3<Float>(0, 0, 1)) < 1e-5,
           "a +90° pitch takes +Y to +Z")

    // 4. Decomposition inverts composition. Angles in the principal range come
    //    back as themselves; anything else has to come back as the same rotation.
    for e in cases {
        let q = EulerRotation.quaternion(e)
        let back = EulerRotation.angles(q)
        let requantised = EulerRotation.quaternion(back)
        for p in probes {
            expect(simd_length(q.act(p) - requantised.act(p)) < 1e-4,
                   "euler \(e) survives a round trip through the quaternion "
                     + "(came back as \(back))")
        }
        if abs(e.x) < .pi / 2 && abs(e.y) < 1.5 && abs(e.z) < .pi / 2 {
            expect(simd_length(back - e) < 1e-4, "euler \(e) round-trips to itself")
        }
    }

    // 5. Gimbal lock resolves to a choice, not a NaN. Yaw at exactly ±90° makes
    //    pitch and roll the same axis; only their sum survives, and the rotation
    //    must still be reproduced.
    for yaw in [Float.pi / 2, -Float.pi / 2] {
        for (pitch, roll) in [(Float(0.6), Float(0.0)), (Float(0.0), Float(0.6)),
                              (Float(0.35), Float(0.25)), (Float(-0.4), Float(0.9))] {
            let e = SIMD3<Float>(pitch, yaw, roll)
            let q = EulerRotation.quaternion(e)
            let back = EulerRotation.angles(q)
            expect(finite(back), "gimbal lock at yaw \(yaw) gives finite angles")
            for p in probes {
                expect(simd_length(EulerRotation.quaternion(back).act(p) - q.act(p)) < 1e-3,
                       "locked pose \(e) still reproduces its rotation (as \(back))")
            }
        }
    }

    // 6. A whole hierarchy composes the same in both renderers. Test 1 covers one
    //    joint; the cat is joints inside joints, and a convention that is right
    //    locally can still be wrong once parents multiply through.
    do {
        let angles = [SIMD3<Float>(0.3, -0.5, 0.2),
                      SIMD3<Float>(-0.7, 0.25, 0.9),
                      SIMD3<Float>(1.1, 0.6, -0.4)]
        let offsets = [SIMD3<Float>(0, 0.2, 0), SIMD3<Float>(0.1, 0, -0.05), SIMD3<Float>(0, 0.12, 0)]

        var node = SCNNode(), root = node
        var entity = Entity(), rootEntity = entity
        for (i, e) in angles.enumerated() {
            if i > 0 {
                let n = SCNNode(); node.addChildNode(n); node = n
                let c = Entity(); entity.addChild(c); entity = c
            }
            node.simdEulerAngles = e
            node.simdPosition = offsets[i]
            entity.eulerAngles = e
            entity.position = offsets[i]
        }
        _ = root; _ = rootEntity

        let sk = node.simdWorldPosition
        let rk = entity.worldPosition
        expect(simd_length(sk - rk) < 1e-4,
               "three nested joints put the leaf in the same place (scenekit \(sk), realitykit \(rk))")
    }

    // 7. The angles an entity was posed with come back exactly, including past the
    //    principal range where decomposition alone would silently rewrite them.
    //    The wand drags by accumulating its own yaw, so a value that shifts on
    //    read-back would drift the wand every frame.
    do {
        let e = SIMD3<Float>(2.9, -2.4, 1.7)
        let entity = Entity()
        entity.eulerAngles = e
        expect(entity.eulerAngles == e, "an entity remembers the angles it was posed with")

        // ...but not if someone went behind its back and set the quaternion.
        entity.orientation = simd_quatf(angle: 0.5, axis: SIMD3<Float>(0, 1, 0))
        let after = entity.eulerAngles
        expect(abs(after.y - 0.5) < 1e-4 && abs(after.x) < 1e-4 && abs(after.z) < 1e-4,
               "setting the orientation directly invalidates the remembered angles (got \(after))")
    }

    // 8. Accumulating a drag, the way the wand actually does it: read the angle,
    //    add to it, write it back, a hundred times. Any read-back that is not
    //    exact turns into visible drift over a gesture.
    do {
        let entity = Entity()
        var expected = SIMD3<Float>(0, 0, 0)
        for i in 0..<100 {
            let d = Float(i % 7) * 0.01 - 0.03
            entity.eulerAngles = SIMD3<Float>(entity.eulerAngles.x,
                                              entity.eulerAngles.y + d,
                                              entity.eulerAngles.z)
            expected.y += d
        }
        expect(abs(entity.eulerAngles.y - expected.y) < 1e-5,
               "a hundred incremental yaws do not drift (got \(entity.eulerAngles.y), want \(expected.y))")
    }
}

// MARK: - The modelled cat

// The one art asset in the game, and therefore the one thing here that cannot be
// re-derived if it is wrong. Everything else is generated from parameters; this
// is a file, and a file can be exported badly, exported from the wrong model, or
// silently truncated.
//
// The bundle does not exist on this machine, so the file is read from the source
// tree — which is the same bytes the app ships.
section("modelled cat") {
    guard let data = FileManager.default.contents(atPath: "MeowRoom/Resources/cat.catmesh"),
          let asset = try? CatMeshAsset(data: data) else {
        expect(false, "the exported cat mesh is present and parses")
        return
    }

    let mesh = asset.mesh
    expect(mesh.positions.count > 1000, "the cat has vertices (\(mesh.positions.count))")
    expect(mesh.indices.count % 3 == 0, "the cat is whole triangles")
    expect(mesh.normals.count == mesh.positions.count, "a normal per vertex")
    expect(mesh.uvs.count == mesh.positions.count, "a uv per vertex")
    expect(mesh.indices.allSatisfy { $0 >= 0 && Int($0) < mesh.positions.count },
           "every index is in range")
    expect(mesh.positions.allSatisfy { finite($0) }, "positions are finite")
    expect(mesh.normals.allSatisfy { abs($0.length - 1) < 1e-2 }, "normals are unit length")

    // The UVs are the entire reason this file exists — the mesh arrived without
    // any, which would have made every coat pattern and material map inapplicable
    // and left one flat grey cat.
    expect(mesh.uvs.allSatisfy { $0.x >= -0.001 && $0.x <= 2.001 },
           "u stays within one wrap and its seam duplicates")
    expect(mesh.uvs.contains { $0.x > 0.6 } && mesh.uvs.contains { $0.x < 0.4 },
           "u actually goes around the body rather than collapsing")
    let vSpan = (mesh.uvs.map(\.y).max() ?? 0) - (mesh.uvs.map(\.y).min() ?? 0)
    expect(vSpan > 0.5, "v runs along the cat (\(vSpan) of a texture repeat)")

    // Skinning. A weight that does not sum to one is a vertex that shrinks toward
    // the origin as soon as anything moves.
    let n = asset.influencesPerVertex
    expect(n >= 1 && n <= 8, "a sane number of influences per vertex (\(n))")
    expect(asset.jointIndices.count == mesh.positions.count * n, "an index per influence")
    expect(asset.jointWeights.count == mesh.positions.count * n, "a weight per influence")
    var worstWeight: Float = 0
    for v in 0..<mesh.positions.count {
        var sum: Float = 0
        for k in 0..<n { sum += asset.jointWeights[v * n + k] }
        worstWeight = max(worstWeight, abs(sum - 1))
    }
    expect(worstWeight < 0.02, "skin weights sum to one (worst error \(worstWeight))")
    expect(asset.jointIndices.allSatisfy { Int($0) < asset.jointCount },
           "every influence names a joint that exists")

    // The skeleton is a tree with exactly one root, and no joint precedes its
    // parent — which is what lets the pose be evaluated in one pass.
    expect(asset.parents.filter { $0 < 0 }.count == 1, "exactly one root joint")
    expect(asset.parents.enumerated().allSatisfy { $0.element < $0.offset },
           "parents come before their children")

    // The bind pose is a matrix per joint, and a matrix has two plausible
    // layouts. USD is row-major and transforms row vectors; simd is column-major
    // and transforms column vectors. Emit the rows verbatim and every joint's
    // translation reads as (0, 0, 0) — a skeleton collapsed to a point, which
    // then produces a cat of zero height with legs of zero length and no error
    // anywhere. So: the skeleton has to have some size.
    let span = asset.restPositions.reduce(into: (lo: SIMD3<Float>(repeating: .infinity),
                                                 hi: SIMD3<Float>(repeating: -.infinity))) {
        $0.lo = SIMD3<Float>(min($0.lo.x, $1.x), min($0.lo.y, $1.y), min($0.lo.z, $1.z))
        $0.hi = SIMD3<Float>(max($0.hi.x, $1.x), max($0.hi.y, $1.y), max($0.hi.z, $1.z))
    }
    let extent = span.hi - span.lo
    expect(extent.x > 0.2 && extent.y > 0.1 && extent.z > 0.02,
           "the skeleton has the extent of a cat (\(extent)) rather than collapsing to a point")
    expect(asset.bind.allSatisfy { abs($0[3].w - 1) < 1e-4 },
           "every bind matrix is affine, which it is not if the layout is transposed")

    // Every role the animator can drive resolved. This is the part that was
    // inferred from the rest pose rather than read from the file, because the
    // conversion stripped the joint names.
    for role in CatMeshAsset.Role.allCases {
        expect(asset.joint(role) != nil, "the skeleton has a \(role)")
    }

    // ...and resolved to the *right* joints, which is a different claim. Checked
    // against the shape of a cat rather than against the numbers that came out:
    // the head is forward of the hips, the ears above the head, the jaw below it,
    // the tail behind, and all four feet on the floor.
    func at(_ r: CatMeshAsset.Role) -> SIMD3<Float> { asset.restPositions[asset.joint(r)!] }
    let hips = at(.hips), head = at(.head)
    expect(head.x > hips.x, "the head is in front of the hips")
    expect(at(.earL).y > head.y && at(.earR).y > head.y, "the ears are above the head")
    expect(at(.jaw).y < head.y, "the jaw is below the head")
    expect(at(.jaw).x > hips.x, "the jaw is at the front end")
    expect(at(.tail3).x < at(.tail0).x, "the tail runs backwards")
    expect(at(.tail3).x < hips.x, "the tail is behind the hips")
    let floor = min(at(.forePawL).y, min(at(.forePawR).y,
                    min(at(.hindPawL).y, at(.hindPawR).y)))
    expect(floor < hips.y * 0.25, "all four feet reach the floor")
    expect(at(.foreHipL).z * at(.foreHipR).z < 0, "the fore legs are on opposite sides")
    expect(at(.hindHipL).z * at(.hindHipR).z < 0, "the hind legs are on opposite sides")
    expect(at(.foreHipL).x > at(.hindHipL).x, "the fore legs are in front of the hind legs")

    // The rig the animator is handed.
    var a = BreedPresets.appearance(for: .domesticShorthair)
    a.seed = 11
    let rig = CatBuilder.build(a, using: asset)
    expect(rig.legs.count == 4, "four legs (\(rig.legs.count))")
    expect(rig.tailSegments.count >= 3, "a tail with segments (\(rig.tailSegments.count))")
    expect(rig.skinnedBody != nil, "the rig carries a skinned surface")
    expect(rig.skinJoints.count == asset.jointCount, "a posable entity per joint")

    // The face. Every one of these is placed in the model's axes and then
    // converted into the skull bone's frame, and the bind pose is not the
    // identity — so "a head-radius forward" is meaningless until it is said in
    // the right frame. Measured in body space, where the cat faces +Z.
    func inBody(_ e: Entity) -> SIMD3<Float> { e.position(relativeTo: rig.body) }
    let headAt = inBody(rig.head)
    if let nose = rig.skinnedBody?.parent?.findEntity(named: "nose") ?? rig.head.findEntity(named: "nose") {
        let d = inBody(nose) - headAt
        expect(d.z > 0, "the nose is on the front of the head (offset \(d))")
        expect(abs(d.x) < abs(d.z), "the nose is on the midline, not out to one side")
    } else {
        expect(false, "the cat has a nose")
    }
    do {
        // A whisker's tip is its root plus its own +Z, since that is the axis
        // strands are built along. It has to end up forward of where it started
        // and out to the side — not swept back over the skull, which is where
        // Euler angles put them: `Rx · Ry · Rz` yaws before it pitches, so once
        // the yaw has laid a whisker along X a pitch about X does nothing at all.
        var checked = 0
        for root in rig.whiskerRoots {
            for w in root.children where w.name == "whisker" {
                let tip = w.convert(position: SIMD3<Float>(0, 0, 0.05), to: rig.body)
                let d = tip - inBody(root)
                expect(d.z > 0, "a whisker points forward (\(d))")
                checked += 1
            }
        }
        expect(checked >= 8, "whiskers exist to check (\(checked))")
    }

    // The frame conversion, which is where a quarter turn in the wrong direction
    // would leave the cat walking sideways for the rest of the project. The model
    // faces +X and the game's body space faces +Z, so after conversion the nose
    // must lead and the feet must stand on the floor the animator measures to.
    let noseZ = rig.head.position(relativeTo: rig.body).z
    let hipZ = rig.legs.first(where: { !$0.isFront })!.hip.position(relativeTo: rig.body).z
    expect(noseZ > hipZ, "the cat faces +Z once framed (head \(noseZ), hip \(hipZ))")
    for leg in rig.legs {
        expect(abs(leg.restFoot.y + rig.bodyHeight) < 1e-5,
               "a resting foot is on the floor, not at the ankle")
        let x = leg.hip.position(relativeTo: rig.body).x
        expect(x * leg.side > 0,
               "leg side matches where the leg actually is (side \(leg.side), x \(x))")
    }
    // Diagonal pairs. Getting this wrong gives a cat that paces like a camel
    // instead of trotting like a cat.
    //
    // Spelled out rather than force-unwrapped: "no such leg" is a real outcome
    // worth naming, and an assertion suite that crashes tells you less than one
    // that says which of the four it could not find.
    let corners = rig.legs.map { "\($0.isFront ? "fore" : "hind")\($0.side < 0 ? "L" : "R")" }
    expect(Set(corners).count == 4, "one leg at each corner (found \(corners.sorted()))")
    if let fl = rig.legs.first(where: { $0.isFront && $0.side < 0 }),
       let br = rig.legs.first(where: { !$0.isFront && $0.side > 0 }),
       let fr = rig.legs.first(where: { $0.isFront && $0.side > 0 }) {
        expect(abs(fl.gaitPhase - br.gaitPhase) < 1e-6, "diagonal feet share a gait phase")
        expect(abs(fl.gaitPhase - fr.gaitPhase) > 0.4, "feet on the same end do not")
    }

    // Nothing on the head may reach further out to the side than the head does.
    //
    // The model has whiskers of its own — two flat cards on joints of their own,
    // meant for an alpha texture this game does not have — and drawn alongside the
    // generated ones they read as grey wings sticking out of the cat's face. They
    // are folded away by `CatShape`, and this is what says they stayed folded.
    do {
        let shaped = CatShape.shape(asset, to: a)
        let n = shaped.influencesPerVertex
        var reach = [Float](repeating: 0, count: shaped.jointCount)
        for v in 0..<shaped.mesh.positions.count {
            var bestW: Float = 0
            var best = -1
            for k in 0..<n where shaped.jointWeights[v * n + k] > bestW {
                bestW = shaped.jointWeights[v * n + k]
                best = Int(shaped.jointIndices[v * n + k])
            }
            if best >= 0 { reach[best] = max(reach[best], abs(shaped.mesh.positions[v].x)) }
        }
        guard let head = shaped.joint(.head) else { return }
        var descendants: Set<Int> = [head]
        for j in 0..<shaped.jointCount where shaped.parents[j] >= 0 {
            if descendants.contains(shaped.parents[j]) { descendants.insert(j) }
        }
        for j in descendants.sorted() where reach[j] > 0 {
            expect(reach[j] <= reach[head] * 1.02,
                   "joint \(j)'s flesh stays inside the head's width "
                   + "(\(reach[j]) m vs \(reach[head]) m)")
        }
    }

    // The rest pose has to be orientation-free, because that is the whole of the
    // contract between the modelled skeleton and an animator that writes pitch,
    // yaw and roll. A joint that rests at an angle has that angle *replaced* the
    // first time anything writes `eulerAngles`, not composed with.
    for (i, j) in rig.skinJoints.enumerated() {
        let q = j.orientation
        expect(abs(abs(q.real) - 1) < 1e-5 && simd_length(q.imag) < 1e-5,
               "joint \(i) rests unrotated (\(q.vector))")
        expect(abs(j.scale.x - 1) < 1e-5, "joint \(i) rests unscaled")
    }

    // It has to survive being animated, which is the only way to find out whether
    // the joints the animator addresses are the joints it thinks they are.
    let animator = CatAnimator(rig: rig)
    var motion = CatMotion()
    motion.pose = .standing
    motion.speed = 0.9
    for i in 0..<400 {
        motion.position = SIMD3<Float>(0, 0, Float(i) * 0.002)
        animator.update(dt: 1.0 / 60, motion: motion)
    }
    CatBuilder.syncPose(rig)
    for (i, j) in rig.skinJoints.enumerated() {
        expect(finite(j.position), "joint \(i) has a finite position after 400 frames")
        expect(finite(j.eulerAngles), "joint \(i) has finite angles after 400 frames")
    }

    // ...and the skin has to survive it too, which is a different claim and the
    // one that actually matters. Every check above passed while the cat was
    // rendering as a ball of fur: the joints were finite, the roles were right,
    // the mesh was whole — and the first posed frame folded the whole animal into
    // a heap, because the pose was being written in a frame the animator did not
    // know about. Nothing that only reads the rest pose can see that. So the skin
    // is applied here exactly as the renderer applies it, and the result is
    // measured.
    do {
        // The posed skin, read straight out of the buffers the renderer draws.
        // Not a reimplementation of the skinning: `CatSkin` writes into the mesh
        // the entity carries, so this is the production deformation, and a fault
        // in it fails here rather than being papered over by a second, correct
        // copy of the same arithmetic living in the test.
        let shaped = CatShape.shape(asset, to: a)
        guard let skinnedMesh = rig.skinMesh else {
            expect(false, "the rig exposes the surface it deforms")
            return
        }
        let posed = skinnedMesh.positions.map { SIMD3<Float>($0.x, $0.y, $0.z) }
        expect(posed.count == shaped.mesh.positions.count, "a posed vertex per modelled vertex")
        expect(posed.allSatisfy { finite($0) }, "the posed skin is finite")

        let inf = shaped.influencesPerVertex
        var owner = [Int](repeating: -1, count: posed.count)
        for v in 0..<posed.count {
            var bestW: Float = 0
            for k in 0..<inf where shaped.jointWeights[v * inf + k] > bestW {
                bestW = shaped.jointWeights[v * inf + k]
                owner[v] = Int(shaped.jointIndices[v * inf + k])
            }
        }

        /// The bounding box of a set of points.
        func box(_ pts: [SIMD3<Float>]) -> (lo: SIMD3<Float>, hi: SIMD3<Float>) {
            pts.reduce(into: (SIMD3<Float>(repeating: .infinity),
                              SIMD3<Float>(repeating: -.infinity))) {
                $0.0 = SIMD3<Float>(min($0.0.x, $1.x), min($0.0.y, $1.y), min($0.0.z, $1.z))
                $0.1 = SIMD3<Float>(max($0.1.x, $1.x), max($0.1.y, $1.y), max($0.1.z, $1.z))
            }
        }
        let rest = box(shaped.mesh.positions.map { SIMD3<Float>($0.x, $0.y, $0.z) })
        let now = box(posed)
        let restSize = rest.hi - rest.lo
        let nowSize = now.hi - now.lo
        // A standing cat is the same size as a cat. Collapsing the skeleton is
        // what this is here to catch, so the floor matters more than the ceiling —
        // but a fold that turns the animal inside out inflates the box instead, so
        // both ends are named.
        for (axis, i) in [("length", 2), ("height", 1), ("width", 0)] {
            let ratio = nowSize[i] / max(1e-5, restSize[i])
            expect(ratio > 0.6 && ratio < 1.6,
                   "posing keeps the cat's \(axis) (\(ratio)× of \(restSize[i]) m)")
        }

        // A standing cat stands on all four feet.
        //
        // Per paw, not off the silhouette: a leg swung to the wrong angle still
        // leaves *something* near the floor, so the outline of the animal says
        // almost nothing. The IK solves for a direction and a joint takes a
        // rotation, and those are the same number only if the bone rests pointing
        // straight down — which this model's forelegs do not, by most of a right
        // angle. Solved as though they did, the paws end up nowhere near the
        // ground they were aimed at.
        for (i, leg) in rig.legs.enumerated() {
            let paw = leg.paw.position(relativeTo: rig.body)
            expect(abs(paw.y + rig.bodyHeight) < 0.035,
                   "leg \(i)'s paw is on the floor (\(paw.y) m against \(-rig.bodyHeight) m)")
        }

        /// Where the flesh a bone owns has ended up.
        func centre(_ roles: [CatMeshAsset.Role]) -> SIMD3<Float>? {
            let wanted = Set(roles.compactMap { shaped.joint($0) })
            var sum = SIMD3<Float>.zero
            var count = 0
            for v in 0..<posed.count where wanted.contains(owner[v]) {
                sum += posed[v]; count += 1
            }
            return count > 0 ? sum / Float(count) : nil
        }
        if let nose = centre([.head, .jaw]), let tail = centre([.tail2, .tail3]),
           let feet = centre([.forePawL, .forePawR, .hindPawL, .hindPawR]) {
            expect(nose.z - tail.z > 0.12,
                   "the head is still a cat's length ahead of the tail (\(nose.z - tail.z) m)")
            expect(nose.y > feet.y + 0.05,
                   "the head is still above the feet (\(nose.y - feet.y) m)")
            expect(abs(nose.x) < 0.05, "the head is still on the midline (\(nose.x) m)")
        } else {
            expect(false, "the posed skin has a head, a tail and four feet")
        }
    }
}

section("height fields") {

    func decode(_ b: UInt8) -> Float { Float(b) / 255 * 2 - 1 }

    // The sign convention, pinned. This is the single most likely thing in the
    // material pipeline to be inverted, and inverted normals do not look broken —
    // they look like the light is coming from the wrong side, which is exactly the
    // kind of wrongness that survives review and ships.
    do {
        let n = 32
        var ramp = HeightField(size: n, fill: 0)
        for y in 0..<n {
            for x in 0..<n { ramp[x, y] = Float(x) / Float(n - 1) }
        }
        let map = ramp.normalMap(slopeScale: 4)
        var allLeaning = true
        // Skip the last column: a ramp is not periodic, so the wrap there is a cliff.
        for y in 0..<n {
            for x in 1..<(n - 1) {
                if map[(y * n + x) * 4 + 0] >= 128 { allLeaning = false }
            }
        }
        expect(allLeaning, "a surface rising along +u tilts its normal toward -u (R < 0.5)")

        var down = HeightField(size: n, fill: 0)
        for y in 0..<n {
            for x in 0..<n { down[x, y] = Float(y) / Float(n - 1) }
        }
        let dmap = down.normalMap(slopeScale: 4, flipGreen: true)
        expect(dmap[(8 * n + 8) * 4 + 1] > 128,
               "with flipGreen the green channel points up the image, not down it")
        let dflip = down.normalMap(slopeScale: 4, flipGreen: false)
        expect(dflip[(8 * n + 8) * 4 + 1] < 128, "flipGreen actually flips green")
    }

    // Wellformedness: unit length, facing out, and averaging to flat.
    do {
        let n = 64
        var f = HeightField(size: n, fill: 0.5)
        f.addNoise(seed: 99, cells: 8, octaves: 3, amplitude: 0.25)
        f.addGrain(seed: 7, cells: 32, stretch: 6, amplitude: 0.08, along: 0)
        f.normalize()
        let map = f.normalMap(slopeScale: 2)

        var unit = true, facing = true
        var sx: Float = 0, sy: Float = 0, sz: Float = 0
        for i in 0..<(n * n) {
            let x = decode(map[i * 4 + 0]), y = decode(map[i * 4 + 1]), z = decode(map[i * 4 + 2])
            let len = sqrtf(x * x + y * y + z * z)
            if abs(len - 1) > 0.01 { unit = false }
            if z < 0.5 { facing = false }
            sx += x; sy += y; sz += z
        }
        let count = Float(n * n)
        expect(unit, "every baked normal is unit length")
        expect(facing, "no baked normal leans past 60 degrees (B >= 0.5)")
        expect(abs(sx / count) < 0.02 && abs(sy / count) < 0.02,
               "relief is balanced — the mean normal has no lateral bias")
        expect(sz / count > 0.9, "the mean normal points out of the surface")
    }

    // Tiling. This is what removes the visible grid from the floor and walls, and
    // it only holds because the noise is periodic and the Sobel wraps.
    do {
        let n = 48
        var f = HeightField(size: n, fill: 0.5)
        f.addNoise(seed: 4242, cells: 6, octaves: 4, amplitude: 0.3)
        var wraps = true
        for y in 0..<n {
            if abs(f[-1, y] - f[n - 1, y]) > 1e-6 { wraps = false }
            if abs(f[n, y] - f[0, y]) > 1e-6 { wraps = false }
        }
        expect(wraps, "sampling wraps around the tile")

        // The real test: the gradient across the seam must match the gradient
        // anywhere else. If the noise did not tile, column 0 and column n-1 would
        // be unrelated and the seam would bake as a ridge.
        let map = f.normalMap(slopeScale: 3)
        var seamSlope: Float = 0, interiorSlope: Float = 0
        for y in 0..<n {
            seamSlope += abs(decode(map[(y * n + 0) * 4 + 0]))
            interiorSlope += abs(decode(map[(y * n + n / 2) * 4 + 0]))
        }
        expect(seamSlope < interiorSlope * 3,
               "the tile seam is no steeper than the middle of the tile")

        let shifted = HeightField.tileableNoise(6, 3.25, period: 6, seed: 1)
        let same = HeightField.tileableNoise(0, 3.25, period: 6, seed: 1)
        expect(abs(shifted - same) < 1e-6, "tileable noise repeats at exactly its period")
    }

    // Solving for tilt. This is the control the whole material library is authored
    // against, so it has to be accurate over the range of fields in use — from a
    // near-smooth sheet of paper to gravel.
    do {
        for cells in [4, 16, 64] {
            for target in [Float(2), 6, 12, 20] {
                var f = HeightField(size: 96, fill: 0.5)
                f.addNoise(seed: UInt64(cells) &* 31 &+ 7, cells: cells, octaves: 3, amplitude: 0.4)
                f.normalize()
                let s = f.slopeScale(forRMSTilt: target)
                let got = f.measuredRMSTilt(slopeScale: s)
                expect(abs(got - target) < max(0.5, target * 0.1),
                       "asking \(cells)-cell noise for \(target)° gives \(got)°")
            }
        }
        // A flat field cannot be tilted, and must not try to divide its way there.
        let flat = HeightField(size: 16, fill: 0.5)
        expect(flat.slopeScale(forRMSTilt: 10) == 0, "a flat field solves to zero slope, not infinity")
    }

    // Physical scaling. The same map on two differently-tiled surfaces implies
    // different real depths — a texture repeated more often covers less ground.
    do {
        let coarse = SurfaceRelief(surfaceMetres: 3.6, tile: 2, mapSize: 512)
        let dense = SurfaceRelief(surfaceMetres: 3.6, tile: 6, mapSize: 512)
        expect(abs(coarse.texelMetres - 3.6 / 1024) < 1e-6, "texel size is metres per repeat per texel")
        expect(dense.reliefMetres(slopeScale: 0.3) < coarse.reliefMetres(slopeScale: 0.3) / 2.9,
               "the same slope on a more densely tiled surface is shallower relief")
        expect(coarse.texelsPerMetre > 256, "the tatami-sized case clears the density floor")
        expect(abs(coarse.reliefMetres(slopeScale: 0.28) - 0.28 * 3.6 / 1024) < 1e-9,
               "relief is slope times texel size")
    }

    // Flat stays flat, and does not divide by zero on the way.
    do {
        var flat = HeightField(size: 8, fill: 0.3)
        flat.normalize()
        expect(flat.samples.allSatisfy { $0.isFinite }, "normalizing a flat field stays finite")
        let map = flat.normalMap(slopeScale: 10)
        expect(map[0] == 128 && map[1] == 128 && map[2] == 255,
               "a flat field bakes to the flat normal")
        let ao = flat.occlusionMap()
        expect(ao.enumerated().allSatisfy { $0.offset % 4 == 3 || $0.element == 255 },
               "a flat field has no cavity occlusion")
    }

    // Cavity: a groove must read darker than the plateau beside it.
    do {
        let n = 32
        var f = HeightField(size: n, fill: 1)
        for y in 0..<n { for x in 14...17 { f[x, y] = 0 } }
        let ao = f.occlusionMap(radius: 6, strength: 1)
        expect(ao[(16 * n + 15) * 4] < ao[(16 * n + 4) * 4],
               "the floor of a groove is more occluded than the plateau")
        expect(ao[(16 * n + 4) * 4] == 255, "flat ground away from the groove is unoccluded")
    }

    // Strokes and discs wrap rather than clipping at the edge — the reason tiled
    // surfaces currently carry a grid is that the CG generators do not do this.
    do {
        let n = 32
        var f = HeightField(size: n, fill: 0)
        f.addStroke(x0: -4, y0: 8, x1: 4, y1: 8, width: 3, height: 1)
        expect(f[n - 2, 8] > 0, "a stroke running off the left edge reappears on the right")
        var d = HeightField(size: n, fill: 0)
        d.addDisc(cx: 0, cy: 0, radius: 4, height: 1)
        expect(d[n - 1, n - 1] > 0, "a disc at the origin wraps into the opposite corner")
    }

    // Roughness responds to relief, in the direction asked for.
    do {
        let n = 16
        var f = HeightField(size: n, fill: 0.5)
        f[4, 4] = 1.0
        f[8, 8] = 0.0
        let r = f.roughnessMap(base: 0.6, variation: 0.3)
        expect(r[(4 * n + 4) * 4] < r[(8 * n + 8) * 4],
               "raised parts are smoother than recesses at positive variation")
        let inverted = f.roughnessMap(base: 0.6, variation: -0.3)
        expect(inverted[(4 * n + 4) * 4] > inverted[(8 * n + 8) * 4],
               "negative variation makes the peaks the rough ones")
        expect(r.allSatisfy { $0 <= 255 }, "roughness stays in range")
    }
}

section("sun arc") {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!

    // Sampled across a whole year, because the failure this guards against is
    // seasonal: the real azimuth wanders far more in June than in December, and a
    // constraint that only holds at the equinox holds for about a fortnight.
    var samples: [(month: Int, hour: Int, dir: SIMD3<Float>, elevation: Float)] = []
    for month in [1, 4, 6, 9, 12] {
        for hour in 0..<24 {
            var comps = DateComponents()
            comps.year = 2026; comps.month = month; comps.day = 21; comps.hour = hour
            let sky = WorldClock.sky(at: cal.date(from: comps)!,
                                     timeZone: TimeZone(identifier: "UTC")!)
            let d = LightingRig.arcDirection(azimuth: sky.sunAzimuth)
            samples.append((month, hour, d, sky.sunElevation))
        }
    }

    for s in samples {
        expect(finite(s.dir), "sun direction is finite at \(s.month)/\(s.hour):00")
        expect(abs(s.dir.length - 1) < 1e-4, "sun direction is a unit vector")

        // The whole point. The window is the -Z wall, so a sun with any meaningful
        // +Z is behind the room, and one with a large -Z is square with the window
        // and shining straight down it. It has to stay off to the side.
        expect(s.dir.z < 0, "the sun is always outside the window at \(s.month)/\(s.hour):00 (z \(s.dir.z))")
        expect(s.dir.z > -0.42,
               "the sun never squares up with the window at \(s.month)/\(s.hour):00 (z \(s.dir.z))")

        // Constant Z is what "parallel to the window" means, and it is the whole
        // guarantee: if it holds, there is no hour at which the sun's light can
        // travel down the length of the room.
        expect(abs(s.dir.z - samples[0].dir.z) < 1e-4,
               "the arc stays parallel to the window at \(s.month)/\(s.hour):00 (z \(s.dir.z))")
    }

    // And it is an arc: east in the morning, west in the evening.
    for month in [1, 4, 6, 9, 12] {
        let day = samples.filter { $0.month == month }
        guard let morning = day.first(where: { $0.hour == 8 && $0.elevation > 0 }),
              let evening = day.first(where: { $0.hour == 16 && $0.elevation > 0 }) else { continue }
        expect(morning.dir.x > evening.dir.x,
               "the sun travels east to west in month \(month) (\(morning.dir.x) → \(evening.dir.x))")
    }

    // Every light left in the room is either outside it or has no position at all,
    // which is what stops any of them putting a bright patch on a nearby surface.
    let rig = LightingRig()
    var positioned = 0
    func countPositioned(_ e: Entity) {
        if e.components.has(PointLightComponent.self) || e.components.has(SpotLightComponent.self) {
            positioned += 1
        }
        for c in e.children { countPositioned(c) }
    }
    countPositioned(rig.root)
    expect(positioned == 0,
           "no light sits inside the room (\(positioned) point/spot lights found)")
}

// The jaw, which used to be checked by looking for a separate oral cavity mesh
// behind it. There is no such mesh now and there should not be: the model's head
// is one closed surface, so opening the jaw stretches the skin over it instead of
// revealing a hole. What is worth checking is that the jaw is a real bone in the
// right place and that working it does not tear the cat apart.
section("jaw") {
    guard let asset = CatAsset.shared else {
        expect(false, "the cat asset loads")
        return
    }
    for breed in CatBreed.allCases {
        var a = BreedPresets.appearance(for: breed)
        a.seed = 3
        let rig = CatBuilder.build(a, using: asset)
        let animator = CatAnimator(rig: rig)

        var motion = CatMotion()
        motion.pose = .sittingTall
        for _ in 0..<30 { animator.update(dt: 1.0 / 60, motion: motion) }
        let closedSettled = rig.jaw.eulerAngles
        animator.triggerMeow()
        animator.update(dt: 1.0 / 60, motion: motion)
        animator.update(dt: 1.0 / 60, motion: motion)
        let open = rig.jaw.eulerAngles
        expect(abs(open.x - closedSettled.x) > 0.002,
               "\(breed.rawValue) opens its jaw when it meows (\(closedSettled.x) -> \(open.x))")
        expect(finite(open), "\(breed.rawValue) jaw angles stay finite")

        // The jaw hangs off the skull and in front of the neck, which is the part
        // the exported role inference could plausibly have got wrong.
        let jawWorld = rig.jaw.worldPosition
        let headWorld = rig.head.worldPosition
        let neckWorld = rig.neck.worldPosition
        expect(jawWorld.y < headWorld.y + 1e-4, "\(breed.rawValue) jaw sits below the skull")
        expect((jawWorld - neckWorld).length > (headWorld - neckWorld).length * 0.4,
               "\(breed.rawValue) jaw is out at the muzzle, not back at the neck")
    }
}

section("translucency") {
    var a = BreedPresets.appearance(for: .domesticShorthair)
    a.seed = 11
    let rig = CatBuilder.build(a)

    // Two inner ears and a nose.
    //
    // Fewer than the generated cat had, and for a reason worth writing down:
    // translucency is driven per material, and the modelled body is one skinned
    // surface wearing one material. Its ears and paw pads cannot glow on their
    // own without becoming separate meshes, which would mean editing the model.
    // So the pieces that genuinely need to transmit are generated just inside the
    // ears and on the tip of the muzzle — which is also where a backlit cat
    // actually lights up.
    expect(rig.translucentParts.count >= 3,
           "the inner ears and the nose are registered (\(rig.translucentParts.count))")
    expect(rig.translucentParts.allSatisfy { $0.amount > 0 && $0.amount <= 1 },
           "every translucent amount is a sensible fraction")
    // The ears must be the strongest. If the body ever out-glows them the effect is
    // upside down, and an evenly glowing cat looks like a lamp, not like a cat.
    let strongest = rig.translucentParts.map { $0.amount }.max() ?? 0
    expect(strongest >= 0.6, "the thinnest part transmits most (\(strongest))")
    expect(rig.translucentParts.allSatisfy { $0.tint.r > $0.tint.b },
           "transmitted light is warmer than it is cool — it has been through blood")

    // The geometry of the effect. The player sits at +Z looking down the room, so a
    // light beyond the cat is backlighting and a light behind the player is not.
    let at = SIMD3<Float>(x: 0, y: 0.2, z: -0.6)
    let behindCat = (at - RoomLayout.cameraPosition).normalized
    let behindPlayer = SIMD3<Float>(x: -behindCat.x, y: -behindCat.y, z: -behindCat.z)
    let back = Translucency.backlight(at: at, lightDirection: behindCat)
    let front = Translucency.backlight(at: at, lightDirection: behindPlayer)
    expect(back > 0.98, "a light directly beyond the cat backlights it fully (\(back))")
    expect(front == 0, "a light behind the player does not backlight anything (\(front))")

    // Forward-scattered, so it falls away fast rather than linearly. A light 60° off
    // axis should already be most of the way gone.
    let side = Translucency.backlight(
        at: at,
        lightDirection: SIMD3<Float>(x: behindCat.x * 0.5 + 0.866, y: behindCat.y * 0.5,
                                   z: behindCat.z * 0.5).normalized)
    expect(side < back * 0.3, "transmission falls off sharply off-axis (\(side) vs \(back))")

    // And over a real day. Night must be dark: an ear cannot transmit light that is
    // not there, and this is the failure mode that a mask alone cannot prevent.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var levels: [(Int, Float)] = []
    for hour in 0..<24 {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 21; comps.hour = hour
        let sky = WorldClock.sky(at: cal.date(from: comps)!, timeZone: TimeZone(identifier: "UTC")!)
        Translucency.apply(rig.translucentParts, sky: sky, lanternOn: false)
        let level = rig.translucentParts.map { $0.entity.pbrMaterial?.emissiveIntensity ?? 0 }.max() ?? 0
        expect(level.isFinite && level >= 0 && level <= 0.55,
               "transmitted light at \(hour):00 is in range (\(level))")
        levels.append((hour, level))
    }
    let darkest = levels.min { $0.1 < $1.1 }!
    let brightest = levels.max { $0.1 < $1.1 }!
    expect(darkest.1 < 0.02, "ears do not glow in the dark (\(darkest.1) at \(darkest.0):00)")
    expect(brightest.1 > 0.05,
           "ears do light up at some point in the day (best \(brightest.1) at \(brightest.0):00)")

    // Spatial: a cat between the player and the window is backlit; a cat behind the
    // player's shoulder is not. This is the property that makes it worth doing per
    // frame rather than baking a mask.
    var midday = DateComponents()
    midday.year = 2026; midday.month = 6; midday.day = 21; midday.hour = 12
    let noon = WorldClock.sky(at: cal.date(from: midday)!, timeZone: TimeZone(identifier: "UTC")!)
    func level(at position: SIMD3<Float>) -> Float {
        rig.root.position = position
        Translucency.apply(rig.translucentParts, sky: noon, lanternOn: false)
        return rig.translucentParts.map { $0.entity.pbrMaterial?.emissiveIntensity ?? 0 }.max() ?? 0
    }
    let byWindow = level(at: SIMD3<Float>(x: 0, y: 0, z: -1.9))
    let atPlayer = level(at: SIMD3<Float>(x: 0, y: 0, z: 1.6))
    expect(byWindow > atPlayer * 2,
           "a cat at the window is backlit; one beside the player is not (\(byWindow) vs \(atPlayer))")
    rig.root.position = .zero

    if CommandLine.arguments.contains("--budget") {
        print("    ear transmission by hour: " +
              levels.map { String(format: "%d:%.2f", $0.0, $0.1) }.joined(separator: " "))
    }

    // The lantern gives a floor, so a cat in a lit room at night is not stone.
    var midnight = DateComponents()
    midnight.year = 2026; midnight.month = 6; midnight.day = 21; midnight.hour = 1
    let night = WorldClock.sky(at: cal.date(from: midnight)!, timeZone: TimeZone(identifier: "UTC")!)
    Translucency.apply(rig.translucentParts, sky: night, lanternOn: false)
    let lanternOff = rig.translucentParts.map { $0.entity.pbrMaterial?.emissiveIntensity ?? 0 }.max() ?? 0
    Translucency.apply(rig.translucentParts, sky: night, lanternOn: true)
    let lanternOn = rig.translucentParts.map { $0.entity.pbrMaterial?.emissiveIntensity ?? 0 }.max() ?? 0
    expect(lanternOn > lanternOff, "the lantern warms the ears at night (\(lanternOff) → \(lanternOn))")

    // The same both-ends check as the triangle budget, for the same reason: the
    // level is read back off a material now, and a part that never got one would
    // report zero and quietly satisfy every comparison above.
    var wrote = 0
    Translucency.apply(rig.translucentParts, sky: WorldClock.sky(), lanternOn: true)
    for part in rig.translucentParts where (part.entity.pbrMaterial?.emissiveIntensity ?? 0) > 0 {
        wrote += 1
    }
    expect(wrote > 0, "translucency actually reaches the materials (\(wrote) parts)")

}

section("triangle budget") {
    /// Walks a node tree adding up geometry, counting each instance separately.
    ///
    /// The count comes from the source mesh rather than from the realised
    /// resource, which is the same buffers the generators produced and does not
    /// need the renderer to hand them back.
    func ownTriangles(_ entity: Entity) -> Int {
        guard let resource = (entity as? ModelEntity)?.model?.mesh,
              let mesh = MeshSourceRegistry.mesh(for: resource) else { return 0 }
        return mesh.indices.count / 3
    }

    func triangles(_ entity: Entity) -> Int {
        var total = ownTriangles(entity)
        for child in entity.children { total += triangles(child) }
        return total
    }

    /// The heaviest single piece of geometry under an entity, and what it is.
    func worst(_ entity: Entity, path: String = "") -> (Int, String) {
        var best = (ownTriangles(entity), path)
        for child in entity.children {
            let sub = worst(child, path: "\(path)/\(child.name)")
            if sub.0 > best.0 { best = sub }
        }
        return best
    }

    // Counting needs the source meshes, and recording them is off by default so
    // that building hundreds of rigs elsewhere costs nothing.
    MeshSourceRegistry.isRecording = true
    defer { MeshSourceRegistry.isRecording = false; MeshSourceRegistry.reset() }

    // The room, without the cat.
    //
    // The point of a budget is that fidelity work cannot quietly cost 200,000
    // triangles. It also catches the specific failure this replaces: SceneKit
    // tessellates a primitive at 48 segments whether it is a floor cushion or a
    // 2.2 mm wire hoop, and the paper lantern's seven ribs were spending 16,128
    // triangles between them — more than the entire cat.
    let room = RoomBuilder.build(sky: WorldClock.sky())
    let roomTris = triangles(room.root)
    // Both ends. A budget test that counts nothing passes, and counting nothing
    // is exactly what happens if the source registry is not recording — which is
    // easy to get wrong now that the count comes from there rather than from the
    // renderer's own geometry.
    expect(roomTris > 5_000, "the room's triangles are actually being counted (\(roomTris))")
    expect(roomTris < 90_000, "the room fits its triangle budget (\(roomTris))")
    let heaviest = worst(room.root)
    expect(heaviest.0 < 12_000,
           "no single room object dominates (\(heaviest.0) at \(heaviest.1))")

    // Every breed of cat, at every render tier that changes its geometry.
    for breed in CatBreed.allCases {
        var a = BreedPresets.appearance(for: breed)
        a.seed = 7
        let rig = CatBuilder.build(a)
        let tris = triangles(rig.root)
        expect(tris < 60_000, "\(breed.rawValue) fits its triangle budget (\(tris))")
        expect(tris > 3_000, "\(breed.rawValue) has enough geometry to be a cat (\(tris))")
    }

    // And the two together, which is what actually ships a frame.
    var a = BreedPresets.appearance(for: .maineCoon)
    a.seed = 7
    let total = roomTris + triangles(CatBuilder.build(a).root)
    expect(total < 140_000, "room plus the heaviest cat fits the frame budget (\(total))")
    if CommandLine.arguments.contains("--budget") {
        print("    room \(roomTris), heaviest object \(heaviest.0) at \(heaviest.1)")
        print("    maine coon \(triangles(CatBuilder.build(a).root)), total \(total)")
    }
}

section("surface maps") {

    func decode(_ b: UInt8) -> Float { Float(b) / 255 * 2 - 1 }

    // name, spec, the size TextureFactory declares for it, and whether it is a
    // large surface that the player is looking straight at.
    let surfaces: [(String, SurfaceMaps.Spec, Int, Bool)] = [
        ("tatami", SurfaceMaps.tatami(), 512, true),
        ("tatamiBorder", SurfaceMaps.tatamiBorder(), 128, false),
        ("wood", SurfaceMaps.wood(), 512, true),
        ("hinoki", SurfaceMaps.hinoki(), 512, true),
        ("plaster", SurfaceMaps.plaster(), 512, true),
        ("shoji", SurfaceMaps.shojiPaper(), 512, true),
        ("fabric", SurfaceMaps.fabric(), 256, true),
        ("futon", SurfaceMaps.futonCover(), 256, true),
        ("sisal", SurfaceMaps.sisal(), 256, false),
        ("litter", SurfaceMaps.litterSubstrate(), 256, false),
    ]

    for (name, spec, declaredSize, inFrame) in surfaces {
        // The size TextureFactory budgets for must be the size actually produced,
        // or the cache accounting is a fiction.
        expect(spec.field.size == declaredSize,
               "\(name) is \(spec.field.size)², but TextureFactory budgets \(declaredSize)²")
        expect(spec.relief.mapSize == spec.field.size,
               "\(name) relief map size agrees with its field")

        expect(spec.field.samples.allSatisfy { $0.isFinite && $0 >= -0.001 && $0 <= 1.001 },
               "\(name) is normalized into 0...1 and finite")

        // Texel density, from the room's real dimensions. Below ~150 px/m a
        // surface reads as mush; the big surfaces need considerably better.
        expect(spec.relief.texelsPerMetre >= 150,
               "\(name) resolves at \(Int(spec.relief.texelsPerMetre)) px/m, under the 150 floor")
        if inFrame {
            expect(spec.relief.texelsPerMetre >= 256,
                   "\(name) is a surface in frame and resolves at only \(Int(spec.relief.texelsPerMetre)) px/m")
        }

        // The tilt asked for is the tilt achieved. Without this, reworking a
        // field's structure quietly changes how strong its surface looks.
        let measured = spec.field.measuredRMSTilt(slopeScale: spec.slopeScale)
        expect(abs(measured - spec.tiltDegrees) < max(0.6, spec.tiltDegrees * 0.12),
               "\(name) asked for \(spec.tiltDegrees)° of tilt and bakes to \(measured)°")

        // Physical plausibility, derived from the slope rather than authored, and
        // bounded per material rather than by one loose global band. This is the
        // check that keeps the tilt targets from turning plaster into stucco: if a
        // surface cannot hit its angle inside its real depth, its features are too
        // broad and the field needs tightening, not the number.
        let mm = spec.reliefMetres * 1000
        expect(spec.plausibleMillimetres.contains(mm),
               "\(name) implies \(mm) mm of relief, outside \(spec.plausibleMillimetres) for that material")

        // The baked normals must describe a surface, not a cliff face.
        let map = spec.field.normalMap(slopeScale: spec.slopeScale)
        var minZ: Float = 1
        var sumZ: Float = 0
        var unit = true
        let texels = spec.field.size * spec.field.size
        for i in 0..<texels {
            let x = decode(map[i * 4 + 0]), y = decode(map[i * 4 + 1]), z = decode(map[i * 4 + 2])
            if abs(sqrtf(x * x + y * y + z * z) - 1) > 0.01 { unit = false }
            minZ = min(minZ, z)
            sumZ += z
        }
        expect(unit, "\(name) bakes unit normals")
        expect(minZ > 0.20, "\(name) has a normal leaning past 78 degrees — relief is too steep")
        expect(sumZ / Float(texels) > 0.80,
               "\(name) averages \(sumZ / Float(texels)) out of the surface — relief is too strong overall")

        let rough = spec.field.roughnessMap(base: spec.roughnessBase, variation: spec.roughnessVariation)
        expect(rough.count == texels * 4, "\(name) roughness map is the right size")
        let ao = spec.field.occlusionMap(radius: spec.occlusionRadius, strength: spec.occlusionStrength)
        var anyOccluded = false
        for i in 0..<texels where ao[i * 4] < 250 { anyOccluded = true; break }
        expect(anyOccluded || name == "tatamiBorder",
               "\(name) has some cavity occlusion — a map of solid white is doing nothing")
    }

    // The coat follows the cat, so check it across the range of cats.
    for breed in CatBreed.allCases {
        var a = BreedPresets.appearance(for: breed)
        a.seed = 4242
        let spec = SurfaceMaps.catCoat(a, size: 256)
        expect(spec.field.size == 256, "\(breed.rawValue) coat field is the size asked for")
        expect(spec.field.samples.allSatisfy { $0.isFinite }, "\(breed.rawValue) coat relief is finite")
        expect(spec.relief.texelsPerMetre >= 256,
               "\(breed.rawValue) coat resolves at \(Int(spec.relief.texelsPerMetre)) px/m")
        let map = spec.field.normalMap(slopeScale: spec.slopeScale)
        var minZ: Float = 1
        for i in 0..<(256 * 256) { minZ = min(minZ, decode(map[i * 4 + 2])) }
        expect(minZ > 0.20, "\(breed.rawValue) fur relief stays inside 78 degrees")
        expect(spec.roughnessBase >= 0 && spec.roughnessBase <= 1,
               "\(breed.rawValue) coat roughness is in range")
        let mm = spec.reliefMetres * 1000
        expect(spec.plausibleMillimetres.contains(mm),
               "\(breed.rawValue) coat implies \(mm) mm of fur relief, outside \(spec.plausibleMillimetres)")
    }

    // A long-haired cat must get more relief than a short-haired one, or the whole
    // furLength axis of the character creator does nothing to how the cat lights.
    var shortHair = BreedPresets.appearance(for: .domesticShorthair)
    shortHair.seed = 1
    var longHair = shortHair
    longHair.furLength = 1
    expect(SurfaceMaps.catCoat(longHair, size: 128).tiltDegrees >
           SurfaceMaps.catCoat(shortHair, size: 128).tiltDegrees * 1.5,
           "long fur reads as deeper relief than short fur")
}

section("texture cache") {
    TextureFactory.clearCache()
    expect(TextureFactory.cacheBytes == 0, "a cleared cache accounts for nothing")

    _ = TextureFactory.tatami()
    let afterOne = TextureFactory.cacheBytes
    expect(afterOne == TextureFactory.textureBytes(512),
           "a 512² texture costs 512² × 4 bytes, not one slot")
    _ = TextureFactory.tatami()
    expect(TextureFactory.cacheBytes == afterOne, "a second call is a hit, not a second entry")

    // The collision the old keys allowed: same name, different colour.
    _ = TextureFactory.wood(base: RGBColor(hex: 0x4A3524), key: "dark")
    _ = TextureFactory.wood(base: RGBColor(hex: 0xB08A5C), key: "dark")
    expect(TextureFactory.cacheCount == 3,
           "two woods with the same name and different bases are two textures")

    // Pinning: a night of sky transitions must not cost the room its floor.
    TextureFactory.clearCache()
    _ = TextureFactory.tatami()
    _ = TextureFactory.plaster()
    let pinnedKeys = ["tatami", "plaster"]
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    for h in 0..<48 {
        let sky = WorldClock.sky(at: start.addingTimeInterval(Double(h) * 1800))
        _ = TextureFactory.gardenBackdrop(sky: sky)
        _ = TextureFactory.skyEnvironment(sky: sky)
    }
    for key in pinnedKeys {
        expect(TextureFactory.cacheContains(key), "\(key) survives a 48-hour sky sweep")
    }
    expect(TextureFactory.cacheBytes <= TextureFactory.byteBudget,
           "the cache stays inside its byte budget")
}

// MARK: - Report

print("")
if failures.isEmpty {
    print("\(checks) checks passed")
    exit(0)
} else {
    print("\(failures.count) of \(checks) checks FAILED:")
    var seen = Set<String>()
    for f in failures where seen.insert(f).inserted {
        print("  • \(f)")
        if seen.count > 40 { print("  … and more"); break }
    }
    exit(1)
}
