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
func finite(_ v: SCNVector3) -> Bool { v.x.isFinite && v.y.isFinite && v.z.isFinite }
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

    let a = SCNVector3(x: 3, y: 4, z: 0)
    expect(abs(a.length - 5) < 1e-5, "length")
    expect(abs(a.normalized.length - 1) < 1e-5, "normalized")
    expect(abs(dot(SCNVector3(x: 1, y: 0, z: 0), SCNVector3(x: 0, y: 1, z: 0))) < 1e-6, "dot orthogonal")
    let c = cross(SCNVector3(x: 1, y: 0, z: 0), SCNVector3(x: 0, y: 1, z: 0))
    expect(abs(c.z - 1) < 1e-6, "cross right-handed")

    // yawTowards: +Z is the cat's forward.
    expect(abs(yawTowards(from: .zero, to: SCNVector3(x: 0, y: 0, z: 1))) < 1e-5, "yaw forward is 0")
    expect(abs(yawTowards(from: .zero, to: SCNVector3(x: 1, y: 0, z: 0)) - .pi / 2) < 1e-5, "yaw +X is 90°")

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
    func validate(_ mesh: MeshData, _ label: String) {
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
        motion.position = SCNVector3(x: 0.3, y: 0, z: -0.5)
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
    motion.lookTarget = SCNVector3(x: 1, y: 0.5, z: 1)
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
    brain2.setWand(active: true, tip: SCNVector3(x: 0, y: 0.2, z: 0))
    for i in 0..<6000 {
        brain2.setWand(active: true, tip: SCNVector3(x: sinf(Float(i) * 0.01) * 0.8,
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
            let p = RoomLayout.clampToWalkable(SCNVector3(x: x, y: 0, z: z))
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
    expect(room.root.childNodes.count > 10, "room has content")
    expect(room.shojiMaterials.count >= 2, "shoji materials captured")
    expect(room.backdropMaterials.count >= 1, "backdrop captured")
    expect(room.lanternLight != nil, "lantern light captured")
    expect(room.foodPile != nil && room.waterSurface != nil, "consumable nodes captured")
    expect(room.sunPatch != nil, "sun patch captured")

    let lighting = LightingRig()
    let scene = SCNScene()
    // Every light, every emissive surface and the camera all come off one light
    // budget now, so the invariants worth holding are about that budget rather
    // than about any single curve.
    var samples: [(hour: Int, key: Float, exposure: CGFloat, rendered: Float)] = []
    for hour in 0..<24 {
        var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 21; comps.hour = hour
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let s = WorldClock.sky(at: cal.date(from: comps)!, timeZone: TimeZone(identifier: "UTC")!)
        let lanternOn = s.wantsLampLight
        lighting.apply(sky: s, scene: scene, room: room, lanternOn: lanternOn)

        let b = LightingRig.budget(sky: s, lanternOn: lanternOn)
        let e = LightingRig.exposureOffset(for: b)
        expect(b.key > 0, "something is lighting the room at \(hour):00")
        // Exposure is deliberately constant. Varying it with the sky rescales
        // every emissive in the room too — lantern paper, feeder LED, eye
        // catchlights, the garden — none of which are in the budget, and three
        // builds each broke a different hour that way. The day/night difference
        // lives in the lights instead.
        expect(abs(e - LightingRig.exposureOffset(for: LightingRig.budget(sky: s, lanternOn: false))) < 1e-6,
               "exposure does not vary with the lantern at \(hour):00")
        expect(e >= -2.0 && e <= 0.05, "exposure at \(hour):00 is in range (\(e))")
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
        guard let resource = try? mesh.meshResource(name: label),
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

section("translucency") {
    var a = BreedPresets.appearance(for: .domesticShorthair)
    a.seed = 11
    let rig = CatBuilder.build(a)

    expect(rig.translucentParts.count >= 7,
           "ears, inner ears, nose and four pads are registered (\(rig.translucentParts.count))")
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
    let at = SCNVector3(x: 0, y: 0.2, z: -0.6)
    let behindCat = (at - RoomLayout.cameraPosition).normalized
    let behindPlayer = SCNVector3(x: -behindCat.x, y: -behindCat.y, z: -behindCat.z)
    let back = Translucency.backlight(at: at, lightDirection: behindCat)
    let front = Translucency.backlight(at: at, lightDirection: behindPlayer)
    expect(back > 0.98, "a light directly beyond the cat backlights it fully (\(back))")
    expect(front == 0, "a light behind the player does not backlight anything (\(front))")

    // Forward-scattered, so it falls away fast rather than linearly. A light 60° off
    // axis should already be most of the way gone.
    let side = Translucency.backlight(
        at: at,
        lightDirection: SCNVector3(x: behindCat.x * 0.5 + 0.866, y: behindCat.y * 0.5,
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
        let level = rig.translucentParts.map { Float($0.material.emission.intensity) }.max() ?? 0
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
    func level(at position: SCNVector3) -> Float {
        rig.root.position = position
        Translucency.apply(rig.translucentParts, sky: noon, lanternOn: false)
        return rig.translucentParts.map { Float($0.material.emission.intensity) }.max() ?? 0
    }
    let byWindow = level(at: SCNVector3(x: 0, y: 0, z: -1.9))
    let atPlayer = level(at: SCNVector3(x: 0, y: 0, z: 1.6))
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
    let lanternOff = rig.translucentParts.map { Float($0.material.emission.intensity) }.max() ?? 0
    Translucency.apply(rig.translucentParts, sky: night, lanternOn: true)
    let lanternOn = rig.translucentParts.map { Float($0.material.emission.intensity) }.max() ?? 0
    expect(lanternOn > lanternOff, "the lantern warms the ears at night (\(lanternOff) → \(lanternOn))")
}

section("triangle budget") {
    /// Walks a node tree adding up geometry, counting each instance separately.
    func triangles(_ node: SCNNode) -> Int {
        var total = node.geometry?.estimatedTriangles ?? 0
        for child in node.childNodes { total += triangles(child) }
        return total
    }

    /// The heaviest single piece of geometry under a node, and what it is.
    func worst(_ node: SCNNode, path: String = "") -> (Int, String) {
        var best = (node.geometry?.estimatedTriangles ?? 0, path)
        for child in node.childNodes {
            let sub = worst(child, path: "\(path)/\(child.name ?? "?")")
            if sub.0 > best.0 { best = sub }
        }
        return best
    }

    // The room, without the cat.
    //
    // The point of a budget is that fidelity work cannot quietly cost 200,000
    // triangles. It also catches the specific failure this replaces: SceneKit
    // tessellates a primitive at 48 segments whether it is a floor cushion or a
    // 2.2 mm wire hoop, and the paper lantern's seven ribs were spending 16,128
    // triangles between them — more than the entire cat.
    let room = RoomBuilder.build(sky: WorldClock.sky())
    let roomTris = triangles(room.root)
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
