import Foundation
import SceneKit
import QuartzCore
import UIKit

/// Owns the SceneKit scene and drives it from the simulation every frame.
final class GameSceneController: NSObject, SCNSceneRendererDelegate {

    let scene = SCNScene()
    private(set) var brain: CatBrain
    private var rig: CatRig
    private var animator: CatAnimator
    private var room: RoomNode
    private let lighting = LightingRig()
    private let cameraNode = SCNNode()

    weak var viewModel: GameViewModel?

    private var lastTime: TimeInterval = 0
    private var skyRefresh: Float = 99
    private var sky: SkyState = WorldClock.sky()
    private var hudRefresh: Float = 0

    // Wand
    private let wandRoot = SCNNode()
    private let wandAnchor = SCNNode()
    private var lureNode = SCNNode()
    private var stringNode = SCNNode()
    private var lurePosition = SCNVector3(x: 0, y: 0.2, z: 0.2)
    private var lureVelocity = SCNVector3.zero
    private(set) var wandActive = false

    // Petting
    private var pettingActive = false
    private var lastPetPoint = CGPoint.zero
    private var petSpeed: Float = 0

    // Props
    private var treatNode: SCNNode?
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
        scene.rootNode.addChildNode(room.root)
        scene.rootNode.addChildNode(lighting.root)
        scene.rootNode.addChildNode(rig.root)

        let camera = SCNCamera()
        // Portrait phones are narrow: pin the field of view to the horizontal axis so
        // the whole room fits, instead of a keyhole view of the far wall.
        camera.projectionDirection = .horizontal
        camera.fieldOfView = 54
        camera.zNear = 0.02
        camera.zFar = 40
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.35
        camera.bloomThreshold = 0.85
        camera.bloomBlurRadius = 12
        camera.motionBlurIntensity = 0.0
        camera.wantsDepthOfField = true
        camera.focusDistance = 2.6
        camera.fStop = 8.0
        camera.focalBlurSampleCount = 8
        camera.screenSpaceAmbientOcclusionIntensity = 0.45
        camera.screenSpaceAmbientOcclusionRadius = 0.22
        camera.screenSpaceAmbientOcclusionDepthThreshold = 0.05
        camera.colorFringeStrength = 0.6
        camera.vignettingIntensity = 0.45
        camera.vignettingPower = 1.2
        camera.saturation = 1.04
        camera.contrast = 0.05

        cameraNode.camera = camera
        cameraNode.position = RoomLayout.cameraPosition
        cameraNode.eulerAngles = SCNVector3(x: RoomLayout.cameraPitch, y: 0, z: 0)
        scene.rootNode.addChildNode(cameraNode)

        buildWand()

        // The cat starts wherever the brain decided.
        rig.root.position = brain.motion.position
    }

    private func wireEvents() {
        brain.onEvent = { [weak self] event in
            guard let self else { return }
            CatVoice.shared.play(event, personality: self.brain.personality)
            switch event {
            case .meow, .trill, .yowl, .chirp:
                self.animator.triggerMeow()
            case .teacupKnocked:
                self.knockTeacup()
            case .activityChanged(let a):
                DispatchQueue.main.async { self.viewModel?.activityCaption = a.caption }
            default:
                break
            }
        }
    }

    // MARK: - Wand

    private func buildWand() {
        wandRoot.position = SCNVector3(x: 0.20, y: -0.30, z: -0.22)
        wandRoot.eulerAngles = SCNVector3(x: deg(-38), y: deg(-16), z: deg(18))
        cameraNode.addChildNode(wandRoot)

        let stick = SCNCylinder(radius: 0.006, height: 0.62)
        let stickNode = SCNNode.make(stick, Materials.pbr(diffuse: UIColor(RGBColor(hex: 0x6B4A2E)), roughness: 0.6))
        stickNode.position = SCNVector3(x: 0, y: 0.31, z: 0)
        wandRoot.addChildNode(stickNode)

        let grip = SCNCylinder(radius: 0.0085, height: 0.10)
        let gripNode = SCNNode.make(grip, Materials.linen(RGBColor(hex: 0x3A3A42), key: "grip"))
        gripNode.position = SCNVector3(x: 0, y: 0.05, z: 0)
        wandRoot.addChildNode(gripNode)

        wandAnchor.position = SCNVector3(x: 0, y: 0.63, z: 0)
        wandRoot.addChildNode(wandAnchor)

        // The lure lives in world space so it can trail behind the wand tip.
        let feather = MeshBuilder.blob(radius: 0.030, scaleX: 0.45, scaleY: 0.45, scaleZ: 1.9, rings: 8, segments: 10)
        lureNode = SCNNode.make(feather, Materials.linen(RGBColor(hex: 0xC0563F), key: "feather"))
        lureNode.castsShadow = true
        scene.rootNode.addChildNode(lureNode)

        let string = SCNCylinder(radius: 0.0012, height: 1.0)
        stringNode = SCNNode.make(string, Materials.pbr(diffuse: UIColor(white: 0.9, alpha: 1), roughness: 0.8))
        stringNode.castsShadow = false
        scene.rootNode.addChildNode(stringNode)

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
        wandRoot.eulerAngles = SCNVector3(x: pitch, y: yaw, z: wandRoot.eulerAngles.z)
    }

    private func updateWand(dt: Float) {
        guard wandActive else { return }
        let anchor = wandAnchor.worldPosition

        // Damped spring toward a point hanging below the wand tip.
        let rest = SCNVector3(x: anchor.x, y: anchor.y - 0.60, z: anchor.z)
        let toRest = rest - lurePosition
        let stiffness: Float = 26
        let damping: Float = 6.5
        lureVelocity += (toRest * stiffness - lureVelocity * damping) * dt
        lurePosition += lureVelocity * dt
        lurePosition.y = max(0.045, lurePosition.y)

        lureNode.position = lurePosition
        let dir = (lurePosition - anchor).normalized
        // Aim the feather's +Z axis down the string.
        lureNode.eulerAngles = SCNVector3(x: -asinf(clamp(dir.y, -1, 1)),
                                          y: atan2f(dir.x, dir.z),
                                          z: 0)

        // Stretch the string between the tip and the lure.
        let mid = (anchor + lurePosition) * 0.5
        let len = (lurePosition - anchor).length
        stringNode.position = mid
        stringNode.scale = SCNVector3(x: 1, y: max(0.01, len), z: 1)
        stringNode.look(at: lurePosition, up: SCNVector3(x: 0, y: 1, z: 0),
                        localFront: SCNVector3(x: 0, y: 1, z: 0))

        brain.setWand(active: true, tip: lurePosition)
    }

    // MARK: - Player actions

    func callCat() {
        brain.call()
        viewModel?.flash("You call \(viewModel?.catName ?? "your cat")…")
    }

    func dropTreat() {
        let spot = SCNVector3(x: RoomLayout.playerLapSpot.x + Float.random(in: -0.25...0.25),
                              y: 0.02,
                              z: RoomLayout.playerLapSpot.z + Float.random(in: -0.15...0.15))
        treatNode?.removeFromParentNode()
        let treat = MeshBuilder.blob(radius: 0.014, scaleX: 1.0, scaleY: 0.7, scaleZ: 1.3, rings: 6, segments: 8)
        let n = SCNNode.make(treat, Materials.pbr(diffuse: UIColor(RGBColor(hex: 0xB5763C)), roughness: 0.8))
        n.position = spot
        scene.rootNode.addChildNode(n)
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

    /// A tap: greet the cat, or bat at whatever was touched.
    func handleTap(at point: CGPoint, in view: SCNView) {
        let hits = view.hitTest(point, options: [SCNHitTestOption.searchMode: SCNHitTestSearchMode.all.rawValue])
        if let hit = hits.first(where: { isCatNode($0.node) }) {
            let zone = petZone(for: hit)
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
        if let hit = hits.first, let name = hit.node.name, name.hasPrefix("toy") {
            brain.startle(intensity: 0.2)
        }
    }

    func beginPan(at point: CGPoint, in view: SCNView) {
        lastPetPoint = point
        petSpeed = 0
        guard !wandActive else { return }
        let hits = view.hitTest(point, options: nil)
        if let hit = hits.first(where: { isCatNode($0.node) }), brain.canBePet {
            pettingActive = true
            brain.beginPetting(zone: petZone(for: hit))
        }
    }

    func updatePan(at point: CGPoint, translationDelta: CGPoint, in view: SCNView) {
        if wandActive {
            moveWand(dx: Float(translationDelta.x) * 0.012, dy: Float(translationDelta.y) * 0.012)
            return
        }
        guard pettingActive else { return }
        let d = hypot(point.x - lastPetPoint.x, point.y - lastPetPoint.y)
        lastPetPoint = point
        petSpeed = approach(petSpeed, Float(d) * 0.06, rate: 8, dt: 1.0 / 60.0)

        let hits = view.hitTest(point, options: nil)
        if let hit = hits.first(where: { isCatNode($0.node) }) {
            brain.updatePetting(zone: petZone(for: hit), intensity: min(1, petSpeed))
        } else {
            // Hand slipped off the cat.
            endPan()
        }
    }

    func endPan() {
        if pettingActive {
            pettingActive = false
            brain.endPetting()
        }
    }

    private func isCatNode(_ node: SCNNode) -> Bool {
        var n: SCNNode? = node
        while let current = n {
            if current === rig.root { return true }
            n = current.parent
        }
        return false
    }

    /// Works out which part of the cat was touched from the hit position.
    private func petZone(for hit: SCNHitTestResult) -> PetZone {
        if let name = hit.node.name {
            if name.hasPrefix("ear") { return .head }
            if name.hasPrefix("tail") { return .tail }
        }
        let local = rig.spine.convertPosition(hit.worldCoordinates, from: nil)
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
        rig.root.removeFromParentNode()
        rig = CatBuilder.build(appearance)
        animator = CatAnimator(rig: rig)
        brain.appearance = appearance
        brain.personality = personality
        scene.rootNode.addChildNode(rig.root)
        rig.root.position = brain.motion.position
    }

    // MARK: - Props

    private func knockTeacup() {
        guard let cup = room.teacup, !teacupFalling else { return }
        teacupFalling = true
        let fall = SCNAction.group([
            SCNAction.move(by: SCNVector3(x: 0.18, y: -RoomLayout.tableTop, z: 0.10), duration: 0.55),
            SCNAction.rotateBy(x: CGFloat(deg(120)), y: CGFloat(deg(40)), z: CGFloat(deg(90)), duration: 0.55)
        ])
        fall.timingMode = .easeIn
        let restore = SCNAction.sequence([
            SCNAction.wait(duration: 6),
            SCNAction.fadeOut(duration: 0.4),
            SCNAction.run { [weak self] node in
                node.position = SCNVector3(x: RoomLayout.tableCenter.x + 0.20,
                                           y: RoomLayout.tableTop + 0.043,
                                           z: RoomLayout.tableCenter.z - 0.10)
                node.eulerAngles = .zero
                self?.teacupFalling = false
            },
            SCNAction.fadeIn(duration: 0.4)
        ])
        cup.runAction(SCNAction.sequence([fall, restore]))
    }

    private func updateRoomProps(dt: Float) {
        let state = brain.room

        if let food = room.foodPile {
            let level = max(0.02, state.feederFood)
            food.scale = SCNVector3(x: 1, y: level, z: 1)
            food.position = SCNVector3(x: RoomLayout.feederBowl.x,
                                       y: 0.006 + 0.015 * level,
                                       z: RoomLayout.feederBowl.z)
            food.isHidden = state.feederFood < 0.02
        }
        if let water = room.waterSurface {
            let level = max(0.02, state.fountainWater)
            water.position = SCNVector3(x: RoomLayout.fountainBase.x - 0.20,
                                        y: 0.012 + 0.048 * level,
                                        z: RoomLayout.fountainBase.z)
            water.isHidden = state.fountainWater < 0.02
        }
        if let stream = room.fountainStream {
            let on = state.fountainOn && state.fountainWater > 0.05
            stream.isHidden = !on
            if on {
                // Cheap shimmer.
                stream.scale = SCNVector3(x: 1 + sinf(Float(CACurrentMediaTime()) * 22) * 0.12, y: 1, z: 1)
            }
        }
        if let litter = room.litterSurface, let mat = litter.geometry?.firstMaterial {
            mat.diffuse.intensity = CGFloat(0.55 + 0.45 * state.litterCleanliness)
        }
        if let treat = treatNode, brain.treatPosition == nil {
            treat.removeFromParentNode()
            treatNode = nil
        }
        if let pom = room.root.childNode(withName: "pompom", recursively: true) {
            let t = Float(CACurrentMediaTime())
            pom.position.x = RoomLayout.catTreeBase.x + 0.20 + sinf(t * 0.9) * 0.012
        }
    }

    // MARK: - Frame loop

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastTime == 0 { lastTime = time }
        var dt = Float(time - lastTime)
        lastTime = time
        dt = min(max(dt, 0), 0.1)
        guard dt > 0 else { return }

        // Refresh the sky a few times a minute — it only moves with the real clock.
        skyRefresh += dt
        if skyRefresh > 4 {
            skyRefresh = 0
            sky = WorldClock.sky()
            let lanternOn = brain.room.lanternAuto ? sky.wantsLampLight : brain.room.lanternOn
            if brain.room.lanternAuto { brain.room.lanternOn = lanternOn }
            lighting.apply(sky: sky, scene: scene, room: room, lanternOn: lanternOn)
        }

        brain.update(dt: dt, sky: sky)
        animator.update(dt: dt, motion: brain.motion)
        updateWand(dt: dt)
        updateRoomProps(dt: dt)

        CatVoice.shared.setPurr(level: brain.motion.purr)
        CatVoice.shared.setAmbience(fountainOn: brain.room.fountainOn && brain.room.fountainWater > 0.05,
                                    level: 0.7)

        hudRefresh += dt
        if hudRefresh > 0.25 {
            hudRefresh = 0
            pushHUD()
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
}
