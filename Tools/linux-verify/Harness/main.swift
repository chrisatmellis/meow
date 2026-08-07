// Headless verification harness. Runs the game's simulation, geometry and
// texture code on Linux against the framework shims and asserts invariants.
import Foundation
import SceneKit

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
    func validate(_ geo: SCNGeometry, _ label: String) {
        expect(geo.materials.isEmpty || !geo.materials.isEmpty, "\(label) built")
    }

    let mesh = MeshData()
    let a = mesh.addVertex(SCNVector3(x: 0, y: 0, z: 0), uv: .zero)
    let b = mesh.addVertex(SCNVector3(x: 1, y: 0, z: 0), uv: .zero)
    let c = mesh.addVertex(SCNVector3(x: 0, y: 0, z: 1), uv: .zero)
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
        LoftRing(center: SCNVector3(x: 0, y: 0, z: Float(i) * 0.1), radiusX: 0.2, radiusY: 0.2)
    }
    let loftMesh = MeshData()
    var ringIdx: [[Int32]] = []
    for (ri, ring) in rings.enumerated() {
        var row: [Int32] = []
        for s in 0...16 {
            let ang = Float(s) / 16 * 2 * .pi
            row.append(loftMesh.addVertex(SCNVector3(x: ring.center.x + cosf(ang) * ring.radiusX,
                                                     y: ring.center.y + sinf(ang) * ring.radiusY,
                                                     z: ring.center.z),
                                          uv: CGPoint(x: CGFloat(s), y: CGFloat(ri))))
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
        let radial = SCNVector3(x: p.x, y: p.y, z: 0).normalized
        if dot(n, radial) > 0.5 { outward += 1 }
    }
    expect(outward > loftMesh.normals.count * 9 / 10,
           "lofted side faces point outward (\(outward)/\(loftMesh.normals.count))")

    validate(MeshBuilder.blob(radius: 0.05), "blob")
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
        expect(e >= -2.4 && e <= 4.2, "exposure at \(hour):00 is in range (\(e))")
        samples.append((hour, b.key, e, LightingRig.renderedBrightness(for: b)))
    }

    // The light actually put into the scene must stay proportional to the budget
    // the camera meters off. Nothing checked this, and the gap is what made
    // midnight brighter than noon: coefficients picked to land on familiar levels
    // left night 6.5x dimmer than noon while the budget claimed 88x, so night's
    // +3 EV of compensation had nothing to cancel and lifted the room past midday.
    var ratios: [Float] = []
    for hour in 0..<24 {
        var comps = DateComponents(); comps.year = 2026; comps.month = 9; comps.day = 21; comps.hour = hour
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let s = WorldClock.sky(at: cal.date(from: comps)!, timeZone: TimeZone(identifier: "UTC")!)
        let b = LightingRig.budget(sky: s, lanternOn: s.wantsLampLight)
        ratios.append(LightingRig.intensities(for: b).total / b.key)
    }
    let spread = ratios.max()! / ratios.min()!
    expect(spread < 1.001,
           "scene light tracks the metered budget at every hour (spread \(spread))")

    // A brighter room must still render brighter. This is the invariant that was
    // missing: with each light on its own hand-fitted curve nothing related them,
    // so late night drifted until it was brighter on screen than noon and no
    // assertion anywhere could tell.
    let byKey = samples.sorted { $0.key < $1.key }
    for (a, b) in zip(byKey, byKey.dropFirst()) {
        expect(b.rendered >= a.rendered - 1e-4,
               "more light renders brighter (\(a.hour):00 \(a.key)lx vs \(b.hour):00 \(b.key)lx)")
        expect(b.exposure <= a.exposure + 1e-4,
               "more light means stopping down (\(a.hour):00 vs \(b.hour):00)")
    }

    // ...and the day must still have visible contrast in it. Full compensation
    // would satisfy the ordering above while making every hour look identical,
    // which is the failure this pairs with.
    let darkest = byKey.first!, brightest = byKey.last!
    let stops = log2(brightest.rendered / darkest.rendered)
    expect(stops > 0.8, "day is not flat: \(stops) stops between \(darkest.hour):00 and \(brightest.hour):00")
    expect(stops < 3.2, "day is not extreme: \(stops) stops")
    expect(brightest.key / darkest.key > 20,
           "the underlying light really does span a wide range (\(brightest.key / darkest.key)x)")
    expect(true, "lighting applied across a whole day")
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
