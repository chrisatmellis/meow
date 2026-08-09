import Foundation
import RealityKit
import QuartzCore
import UIKit

/// Owns the scene and drives it from the simulation every frame.
final class GameSceneController: NSObject {

    /// Everything in the world hangs off this, and `RealityView` adds it to its
    /// content. There is no scene object to own: RealityKit's scene belongs to the
    /// view, so the controller owns a root entity instead.
    let root = Entity()
    private(set) var brain: CatBrain
    private var rig: CatRig
    private var animator: CatAnimator
    private var room: RoomNode
    private let lighting = LightingRig()
    private let camera = PerspectiveCamera()

    weak var viewModel: GameViewModel?

    /// The frame-loop subscription, held here for the same reason a timer is: it
    /// is not documented whether the view's content retains it, and an
    /// unretained one is a frame loop that quietly stops — a still room with a
    /// HUD that carries on updating.
    var frameLoop: EventSubscription?

    private var skyRefresh: Float = 99
    /// The eased exposure the room is lit at.
    ///
    /// SceneKit had a camera exposure offset, which is where this used to live and
    /// is the one thing the port genuinely loses: RealityKit's camera has no
    /// exposure at all, because its lights are in real photometric units and the
    /// answer is meant to be that you light the room correctly. So the easing
    /// stays and the destination changes — `LightingRig` folds it into the light
    /// intensities instead. The lantern coming on at dusk is still a step change
    /// in the room's light, and the room should adapt to it the way an eye does
    /// rather than cutting.
    private var exposure: Float = 1
    private var exposureTarget: Float = 1
    private var sky: SkyState = WorldClock.sky()
    private var hudRefresh: Float = 0

    // Wand
    private let wandRoot = Entity()
    private let wandAnchor = Entity()
    private var lureNode = Entity()
    private var stringNode = Entity()
    private var lurePosition = SIMD3<Float>(x: 0, y: 0.2, z: 0.2)
    private var lureVelocity = SIMD3<Float>.zero
    private(set) var wandActive = false

    // Petting
    private var pettingActive = false
    private var lastPetPoint = CGPoint.zero
    private var petSpeed: Float = 0
    private var strokeDistance: Float = 0
    private var bellTimer: Float = 0

    // Props
    private var treatNode: Entity?
    private var teacupFalling = false

    var appearance: CatAppearance { rig.appearance }

    init(save: GameSave) {
        self.brain = CatBrain(save: save)
        self.rig = CatBuilder.build(save.profile.appearance)
        self.animator = CatAnimator(rig: rig)
        self.room = RoomBuilder.build(sky: WorldClock.sky())
        super.init()

        buildScene()
        wireEvents()
    }

    // MARK: - Scene assembly

    private func buildScene() {
        root.addChild(room.root)
        root.addChild(lighting.root)
        root.addChild(rig.root)

        // The cat is what gets touched, and the two toys, and nothing else. Under
        // SceneKit every surface in the room answered a hit test and the code then
        // discarded all but the cat; here the room simply never answers.
        rig.root.enableInput()
        room.toyMouse?.enableInput()
        room.toyBall?.enableInput()

        // Both the room and the cat, because the cat is a sibling of the room and
        // not a child of it — and with no ambient light to fall back on, anything
        // that receives no environment is lit by the sun alone and goes black on
        // its shadow side.
        lighting.attachEnvironment(to: root)

        // Portrait phones are narrow: pin the field of view to the horizontal axis so
        // the whole room fits, instead of a keyhole view of the far wall. RealityKit
        // defaults to vertical and derives the other axis from the aspect ratio,
        // which is the opposite of what a fixed room wants.
        var lens = PerspectiveCameraComponent()
        lens.fieldOfViewOrientation = .horizontal
        lens.fieldOfViewInDegrees = 54
        lens.near = 0.02
        lens.far = 40
        // What used to be twelve lines of camera post-processing is now split in
        // two. Depth of field, HDR and antialiasing are view-level rendering
        // effects and are set where the view is made. Bloom, vignette, colour
        // fringing, screen-space AO and the saturation lift have no equivalent —
        // `customPostProcessing` could carry them in Metal, and that is a separate
        // piece of work rather than something to smuggle into a port.
        //
        // The saturation lift is the loss worth naming: it existed because
        // SceneKit's tone curve desaturates as it compresses, so the brighter a
        // surface the greyer it came out. Measured, the tatami rendered
        // rgb(168,167,164) at midday — a neutral grey from an albedo that is
        // anything but — and rgb(119,97,69) at night from the same material.
        // Whether RealityKit's tone mapping does the same thing is a question for
        // a screenshot, not for a guess, so nothing is compensating for it yet.
        exposureTarget = LightingRig.exposure(sky: sky, lanternOn: sky.wantsLampLight)
        exposure = exposureTarget

        camera.camera = lens
        camera.position = RoomLayout.cameraPosition
        camera.eulerAngles = SIMD3<Float>(x: RoomLayout.cameraPitch, y: 0, z: 0)
        root.addChild(camera)

        buildWand()
        Haptics.prepare()

        // The cat starts wherever the brain decided.
        rig.root.position = brain.motion.position
    }

    /// A bell on the collar rings whenever the cat lands or bolts.
    private var wearsBell: Bool {
        rig.appearance.collarStyle != .none &&
            (rig.appearance.collarHasBell || rig.appearance.collarStyle == .bell)
    }

    private func wireEvents() {
        brain.onEvent = { [weak self] event in
            guard let self else { return }
            CatVoice.shared.play(event, personality: self.brain.personality)
            switch event {
            case .meow, .trill, .chirp:
                self.animator.triggerMeow()
            case .yowl:
                self.animator.triggerMeow()
                Haptics.warning()
            case .teacupKnocked:
                self.knockTeacup()
                Haptics.thud()
            case .thud:
                Haptics.thud()
                if self.wearsBell { CatVoice.shared.play(.bell) }
            case .bell:
                Haptics.jingle()
            case .hiss, .overstimulated:
                Haptics.warning()
            case .activityChanged(let a):
                DispatchQueue.main.async { self.viewModel?.activityCaption = a.caption }
            default:
                break
            }
        }
    }

    // MARK: - Wand

    private func buildWand() {
        wandRoot.position = SIMD3<Float>(x: 0.20, y: -0.30, z: -0.22)
        wandRoot.eulerAngles = SIMD3<Float>(x: deg(-38), y: deg(-16), z: deg(18))
        camera.addChild(wandRoot)

        let stick = MeshBuilder.cylinder(radius: 0.006, height: 0.62)
        let stickNode = Entity.make(stick, Materials.pbr(color: RGBColor(hex: 0x6B4A2E), roughness: 0.6))
        stickNode.position = SIMD3<Float>(x: 0, y: 0.31, z: 0)
        wandRoot.addChild(stickNode)

        let grip = MeshBuilder.cylinder(radius: 0.0085, height: 0.10)
        let gripNode = Entity.make(grip, Materials.linen(RGBColor(hex: 0x3A3A42), key: "grip"))
        gripNode.position = SIMD3<Float>(x: 0, y: 0.05, z: 0)
        wandRoot.addChild(gripNode)

        wandAnchor.position = SIMD3<Float>(x: 0, y: 0.63, z: 0)
        wandRoot.addChild(wandAnchor)

        // The lure lives in world space so it can trail behind the wand tip.
        let feather = MeshBuilder.blob(radius: 0.030, scaleX: 0.45, scaleY: 0.45, scaleZ: 1.9, rings: 8, segments: 10)
        lureNode = Entity.make(feather, Materials.linen(RGBColor(hex: 0xC0563F), key: "feather"))
        root.addChild(lureNode)

        let string = MeshBuilder.cylinder(radius: 0.0012, height: 1.0)
        stringNode = Entity.make(string, Materials.pbr(color: RGBColor(repeating: 0.9), roughness: 0.8))
        root.addChild(stringNode)

        setWand(active: false)
    }

    func setWand(active: Bool) {
        wandActive = active
        wandRoot.isHidden = !active
        lureNode.isHidden = !active
        stringNode.isHidden = !active
        if active {
            lurePosition = wandAnchor.worldPosition
            lurePosition.y = max(0.06, lurePosition.y - 0.55)
            lureVelocity = .zero
        }
        brain.setWand(active: active, tip: lurePosition)
    }

    /// Swings the wand from a drag on screen.
    func moveWand(dx: Float, dy: Float) {
        guard wandActive else { return }
        let yaw = clamp(wandRoot.eulerAngles.y - dx * 0.9, deg(-70), deg(50))
        let pitch = clamp(wandRoot.eulerAngles.x - dy * 0.9, deg(-75), deg(5))
        wandRoot.eulerAngles = SIMD3<Float>(x: pitch, y: yaw, z: wandRoot.eulerAngles.z)
    }

    private func updateWand(dt: Float) {
        guard wandActive else { return }
        let anchor = wandAnchor.worldPosition

        // Damped spring toward a point hanging below the wand tip.
        let rest = SIMD3<Float>(x: anchor.x, y: anchor.y - 0.60, z: anchor.z)
        let toRest = rest - lurePosition
        let stiffness: Float = 26
        let damping: Float = 6.5
        lureVelocity += (toRest * stiffness - lureVelocity * damping) * dt
        lurePosition += lureVelocity * dt
        lurePosition.y = max(0.045, lurePosition.y)

        lureNode.position = lurePosition
        let dir = (lurePosition - anchor).normalized
        // Aim the feather's +Z axis down the string.
        lureNode.eulerAngles = SIMD3<Float>(x: -asinf(clamp(dir.y, -1, 1)),
                                          y: atan2f(dir.x, dir.z),
                                          z: 0)

        // Stretch the string between the tip and the lure.
        let mid = (anchor + lurePosition) * 0.5
        let len = (lurePosition - anchor).length
        stringNode.position = mid
        stringNode.scale = SIMD3<Float>(x: 1, y: max(0.01, len), z: 1)
        stringNode.look(at: lurePosition, from: mid, upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
        // `look` aims -Z; a cylinder stands on +Y, so tip it a quarter turn.
        stringNode.orientation = stringNode.orientation
            * simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))

        brain.setWand(active: true, tip: lurePosition)
    }

    // MARK: - Player actions

    func callCat() {
        brain.call()
        viewModel?.flash("You call \(viewModel?.catName ?? "your cat")…")
    }

    func dropTreat() {
        let spot = SIMD3<Float>(x: RoomLayout.playerLapSpot.x + Float.random(in: -0.25...0.25),
                              y: 0.02,
                              z: RoomLayout.playerLapSpot.z + Float.random(in: -0.15...0.15))
        treatNode?.removeFromParent()
        let treat = MeshBuilder.blob(radius: 0.014, scaleX: 1.0, scaleY: 0.7, scaleZ: 1.3, rings: 6, segments: 8)
        let n = Entity.make(treat, Materials.pbr(color: RGBColor(hex: 0xB5763C), roughness: 0.8))
        n.position = spot
        root.addChild(n)
        treatNode = n
        brain.dropTreat(at: spot)
        CatVoice.shared.play(.bell)
    }

    func refillFeeder() {
        brain.refillFeeder()
        CatVoice.shared.play(.crunch)
        brain.startle(intensity: 0.3)
    }

    func refillFountain() {
        brain.refillFountain()
        CatVoice.shared.play(.lap)
    }

    func cleanLitter() {
        brain.cleanLitter()
    }

    func toggleFountain() {
        brain.room.fountainOn.toggle()
    }

    func toggleLantern() {
        brain.room.lanternAuto = false
        brain.room.lanternOn.toggle()
    }

    // MARK: - Touch handling

    /// A tap on an entity, resolved by the view's gesture.
    func handleTap(on entity: Entity, at worldPoint: SIMD3<Float>) {
        if isCatEntity(entity) {
            let zone = petZone(entity: entity, worldPoint: worldPoint)
            if brain.canBePet {
                brain.beginPetting(zone: zone)
                brain.updatePetting(zone: zone, intensity: 0.3)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                    if self?.pettingActive == false { self?.brain.endPetting() }
                }
            } else {
                brain.call()
            }
            return
        }
        // Tapping a toy nudges it, which the cat notices.
        if named(entity, prefix: "toy") { brain.startle(intensity: 0.2) }
    }

    func beginPan(at point: CGPoint, on entity: Entity?, worldPoint: SIMD3<Float>) {
        lastPetPoint = point
        petSpeed = 0
        strokeDistance = 0
        guard !wandActive else { return }
        guard let entity, isCatEntity(entity), brain.canBePet else { return }
        pettingActive = true
        brain.beginPetting(zone: petZone(entity: entity, worldPoint: worldPoint))
    }

    func updatePan(at point: CGPoint, translationDelta: CGPoint,
                   on entity: Entity?, worldPoint: SIMD3<Float>) {
        if wandActive {
            moveWand(dx: Float(translationDelta.x) * 0.012, dy: Float(translationDelta.y) * 0.012)
            return
        }
        guard pettingActive else { return }
        let d = hypot(point.x - lastPetPoint.x, point.y - lastPetPoint.y)
        lastPetPoint = point
        petSpeed = approach(petSpeed, Float(d) * 0.06, rate: 8, dt: 1.0 / 60.0)

        guard let entity, isCatEntity(entity) else {
            endPan()          // hand slipped off the cat
            return
        }
        brain.updatePetting(zone: petZone(entity: entity, worldPoint: worldPoint),
                            intensity: min(1, petSpeed))
        strokeDistance += Float(d)
        if strokeDistance > 55 {
            strokeDistance = 0
            Haptics.petStroke(intensity: petSpeed)
        }
    }

    func endPan() {
        if pettingActive {
            pettingActive = false
            brain.endPetting()
        }
    }

    private func isCatEntity(_ entity: Entity) -> Bool {
        var n: Entity? = entity
        while let current = n {
            if current === rig.root { return true }
            n = current.parent
        }
        return false
    }

    /// Whether an entity or any of its ancestors is named with this prefix.
    ///
    /// Walking up matters now in a way it did not before: a hit used to land on
    /// whatever node carried the geometry, and a gesture lands on whichever
    /// ancestor carries the collision shape, which is usually a level or two up.
    private func named(_ entity: Entity, prefix: String) -> Bool {
        var n: Entity? = entity
        while let current = n {
            if current.name.hasPrefix(prefix) { return true }
            n = current.parent
        }
        return false
    }

    /// Works out which part of the cat was touched from where the touch landed.
    private func petZone(entity: Entity, worldPoint: SIMD3<Float>) -> PetZone {
        if named(entity, prefix: "ear") { return .head }
        if named(entity, prefix: "tail") { return .tail }

        let local = rig.spine.convert(position: worldPoint, from: nil)
        let L = rig.torsoLength
        let R = rig.torsoRadius

        if local.z > L * 0.52 {
            return abs(local.x) > R * 0.55 ? .cheek : (local.y < -R * 0.25 ? .chin : .head)
        }
        if local.z < -L * 0.48 { return .tail }
        if local.y < -R * 0.30 { return .belly }
        if local.y < -R * 0.75 { return .paw }
        return .back
    }

    // MARK: - Cat rebuild (used when the player edits their cat)

    func applyAppearance(_ appearance: CatAppearance, personality: CatPersonality) {
        rig.root.removeFromParent()
        rig = CatBuilder.build(appearance)
        animator = CatAnimator(rig: rig)
        brain.appearance = appearance
        brain.personality = personality
        root.addChild(rig.root)
        rig.root.enableInput()
        rig.root.position = brain.motion.position
    }

    // MARK: - Props

    /// The teacup's fall, as state rather than as an action.
    ///
    /// `SCNAction` has no RealityKit equivalent, and for one prop that is no loss:
    /// the frame loop is already running and already has `dt`, so the tween lives
    /// where every other moving thing in the room lives instead of in a parallel
    /// animation system that only one object uses.
    private var teacupFall: Float = 0

    private func knockTeacup() {
        guard room.teacup != nil, !teacupFalling else { return }
        teacupFalling = true
        teacupFall = 0
    }

    private static let teacupRest = SIMD3<Float>(x: RoomLayout.tableCenter.x + 0.20,
                                                 y: RoomLayout.tableTop + 0.043,
                                                 z: RoomLayout.tableCenter.z - 0.10)

    private func updateTeacup(dt: Float) {
        guard teacupFalling, let cup = room.teacup else { return }
        teacupFall += dt

        let fallTime: Float = 0.55
        if teacupFall <= fallTime {
            // Ease in, because it is falling: the old action said `.easeIn` and a
            // squared ramp is what that is.
            let t = teacupFall / fallTime
            let e = t * t
            cup.position = Self.teacupRest
                + SIMD3<Float>(x: 0.18, y: -RoomLayout.tableTop, z: 0.10) * e
            cup.eulerAngles = SIMD3<Float>(x: deg(120), y: deg(40), z: deg(90)) * e
            return
        }
        // Six seconds on the floor, then it is quietly back on the table.
        if teacupFall > fallTime + 6 {
            cup.position = Self.teacupRest
            cup.eulerAngles = .zero
            teacupFalling = false
        }
    }

    private func updateRoomProps(dt: Float) {
        let state = brain.room

        if let food = room.foodPile {
            let level = max(0.02, state.feederFood)
            food.scale = SIMD3<Float>(x: 1, y: level, z: 1)
            food.position = SIMD3<Float>(x: RoomLayout.feederBowl.x,
                                       y: 0.006 + 0.015 * level,
                                       z: RoomLayout.feederBowl.z)
            food.isHidden = state.feederFood < 0.02
        }
        if let water = room.waterSurface {
            let level = max(0.02, state.fountainWater)
            water.position = SIMD3<Float>(x: RoomLayout.fountainBase.x - 0.20,
                                        y: 0.012 + 0.048 * level,
                                        z: RoomLayout.fountainBase.z)
            water.isHidden = state.fountainWater < 0.02
        }
        if let stream = room.fountainStream {
            let on = state.fountainOn && state.fountainWater > 0.05
            stream.isHidden = !on
            if on {
                // Cheap shimmer.
                stream.scale = SIMD3<Float>(x: 1 + sinf(Float(CACurrentMediaTime()) * 22) * 0.12, y: 1, z: 1)
            }
        }
        if let litter = room.litterSurface {
            // Soiled litter is darker. SceneKit dimmed the diffuse channel's
            // intensity; RealityKit tints the base colour instead, which is the
            // same idea said in the place it belongs.
            let v = CGFloat(0.55 + 0.45 * state.litterCleanliness)
            litter.withMaterial { $0.baseColor.tint = UIColor(white: v, alpha: 1) }
        }
        if let treat = treatNode, brain.treatPosition == nil {
            treat.removeFromParent()
            treatNode = nil
        }
        if let pom = room.root.findEntity(named: "pompom") {
            let t = Float(CACurrentMediaTime())
            pom.position.x = RoomLayout.catTreeBase.x + 0.20 + sinf(t * 0.9) * 0.012
        }
    }

    // MARK: - Frame loop

    /// Called once per frame by the view.
    func update(deltaTime: Float) {
        let dt = min(max(deltaTime, 0), 0.1)
        guard dt > 0 else { return }

        // Refresh the sky a few times a minute — it only moves with the real clock.
        skyRefresh += dt
        if skyRefresh > 4 {
            skyRefresh = 0
            sky = WorldClock.sky()
            let lanternOn = brain.room.lanternAuto ? sky.wantsLampLight : brain.room.lanternOn
            if brain.room.lanternAuto { brain.room.lanternOn = lanternOn }
            lighting.apply(sky: sky, room: room, lanternOn: lanternOn)
            exposureTarget = LightingRig.exposure(sky: sky, lanternOn: lanternOn)
        }

        // Ease toward the exposure the sky wants, then hand it to the rig, which
        // is where it now has to be applied.
        let eased = approach(exposure, exposureTarget, rate: 0.7, dt: dt)
        if abs(eased - exposure) > 1e-4 {
            exposure = eased
            lighting.setExposure(exposure)
        }

        brain.update(dt: dt, sky: sky)
        animator.update(dt: dt, motion: brain.motion)

        // After the animator, because it reads where the ears actually ended up,
        // and every frame rather than with the sky refresh: the sun barely moves in
        // four seconds but the cat crosses the room, and it is the cat's position
        // relative to the sun and the player that decides whether its ears light up.
        Translucency.apply(rig.translucentParts, sky: sky,
                           lanternOn: brain.room.lanternOn)

        updateWand(dt: dt)
        updateRoomProps(dt: dt)
        updateTeacup(dt: dt)

        CatVoice.shared.setPurr(level: brain.motion.purr)
        if pettingActive { Haptics.purr(level: brain.motion.purr) }
        updateCollarBell(dt: dt)
        CatVoice.shared.setAmbience(fountainOn: brain.room.fountainOn && brain.room.fountainWater > 0.05,
                                    level: 0.7)

        hudRefresh += dt
        if hudRefresh > 0.25 {
            hudRefresh = 0
            pushHUD()
        }
    }

    /// The bell keeps time with the cat's stride.
    private func updateCollarBell(dt: Float) {
        guard wearsBell else { return }
        guard brain.motion.speed > 0.35, !brain.motion.pose.isSleep else {
            bellTimer = 0
            return
        }
        bellTimer -= dt
        if bellTimer <= 0 {
            bellTimer = 0.42 - 0.12 * min(1, brain.motion.speed / 2)
            CatVoice.shared.play(.bell)
        }
    }

    private func pushHUD() {
        guard let vm = viewModel else { return }
        DispatchQueue.main.async {
            vm.needs = self.brain.needs
            vm.room = self.brain.room
            vm.bond = self.brain.bond
            vm.activityCaption = self.brain.statusCaption
            vm.isOverstimulated = self.brain.isOverstimulated
            vm.canPet = self.brain.canBePet
            vm.purring = self.brain.motion.purr > 0.15
            vm.timeString = WorldClock.clockString()
            vm.phaseName = self.sky.phase.displayName
        }
    }

    // MARK: - Persistence

    func writeBack(to save: inout GameSave) {
        brain.writeBack(to: &save)
    }

    /// Push the results of an offline catch-up into the running simulation, so
    /// coming back after a few hours away actually shows a few hours having passed.
    func applyCatchUp(needs: CatNeeds, room: RoomState) {
        brain.needs = needs
        brain.room = room
        skyRefresh = 99          // force a lighting refresh on the next frame
    }
}
