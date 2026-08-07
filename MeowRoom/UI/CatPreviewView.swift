import SwiftUI
import SceneKit

/// Live turntable preview of the cat being designed. Reuses the exact same
/// builder and animator the game uses, so what you see is what you adopt.
final class CatPreviewController: NSObject, SCNSceneRendererDelegate, ObservableObject {
    let scene = SCNScene()
    private var rig: CatRig
    private var animator: CatAnimator
    private var motion = CatMotion()
    private var lastTime: TimeInterval = 0
    private var turntable: Float = 0
    private var blinkTimer: Float = 2
    private var blinkPhase: Float = -1
    private var poseTimer: Float = 6
    private var poseIndex = 0
    private let pivot = SCNNode()

    private var pendingAppearance: CatAppearance?
    private var lastRebuild: TimeInterval = 0
    private(set) var appearance: CatAppearance

    private let poses: [CatPose] = [.sittingTall, .standing, .loaf, .sitting, .stretching]

    init(appearance: CatAppearance) {
        self.appearance = appearance
        self.rig = CatBuilder.build(appearance, preview: true)
        self.animator = CatAnimator(rig: rig)
        super.init()

        scene.rootNode.addChildNode(pivot)
        pivot.addChildNode(rig.root)

        motion.pose = .sittingTall
        motion.position = SCNVector3(x: 0, y: 0, z: 0)
        motion.eyeOpen = 1

        setupStage()
    }

    private func setupStage() {
        // A soft studio: key, fill, rim, plus a warm floor disc.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 1150
        key.color = UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 8
        key.shadowSampleCount = 12
        key.shadowColor = UIColor(white: 0, alpha: 0.4)
        key.orthographicScale = 0.6
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(x: 0.8, y: 1.2, z: 1.1)
        keyNode.look(at: SCNVector3(x: 0, y: 0.16, z: 0))
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 380
        fill.color = UIColor(red: 0.72, green: 0.82, blue: 1.0, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(x: -1.0, y: 0.7, z: 0.6)
        scene.rootNode.addChildNode(fillNode)

        let rim = SCNLight()
        rim.type = .omni
        rim.intensity = 520
        rim.color = UIColor(red: 1.0, green: 0.86, blue: 0.68, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(x: -0.3, y: 0.8, z: -1.1)
        scene.rootNode.addChildNode(rimNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 130
        ambient.color = UIColor(red: 0.55, green: 0.58, blue: 0.70, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let floor = SCNCylinder(radius: 0.55, height: 0.012)
        let floorNode = SCNNode.make(floor, Materials.tatami())
        floorNode.position = SCNVector3(x: 0, y: -0.006, z: 0)
        scene.rootNode.addChildNode(floorNode)

        let camera = SCNCamera()
        camera.fieldOfView = 34
        camera.zNear = 0.02
        camera.zFar = 20
        camera.wantsHDR = true
        camera.bloomIntensity = 0.25
        camera.bloomThreshold = 0.9
        camera.wantsDepthOfField = true
        camera.focusDistance = 0.95
        camera.fStop = 5.0
        camera.vignettingIntensity = 0.4
        camera.screenSpaceAmbientOcclusionIntensity = 0.4
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.position = SCNVector3(x: 0.0, y: 0.30, z: 0.95)
        camNode.look(at: SCNVector3(x: 0, y: 0.17, z: 0))
        scene.rootNode.addChildNode(camNode)

        scene.background.contents = UIColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)
        scene.lightingEnvironment.contents = TextureFactory.skyEnvironment(sky: WorldClock.sky())
        scene.lightingEnvironment.intensity = 0.6
    }

    /// Coalesced rebuilds — sliders fire far faster than we want to rebuild meshes.
    func request(appearance new: CatAppearance) {
        guard new != appearance else { return }
        pendingAppearance = new
    }

    private func rebuildIfNeeded(now: TimeInterval) {
        guard let pending = pendingAppearance, now - lastRebuild > 0.12 else { return }
        pendingAppearance = nil
        lastRebuild = now
        appearance = pending

        let currentPose = motion.pose
        rig.root.removeFromParentNode()
        rig = CatBuilder.build(pending, preview: true)
        animator = CatAnimator(rig: rig)
        pivot.addChildNode(rig.root)
        motion.pose = currentPose
    }

    func cyclePose() {
        poseIndex = (poseIndex + 1) % poses.count
        motion.pose = poses[poseIndex]
        poseTimer = 12
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if lastTime == 0 { lastTime = time }
        let dt = min(Float(time - lastTime), 0.1)
        lastTime = time
        rebuildIfNeeded(now: time)
        guard dt > 0 else { return }

        turntable += dt * 0.28
        pivot.eulerAngles = SCNVector3(x: 0, y: sinf(turntable) * 0.85 + 0.35, z: 0)

        // Idle life: blinking, breathing, a slow tail.
        blinkTimer -= dt
        if blinkTimer <= 0 { blinkTimer = Float.random(in: 2.5...6.5); blinkPhase = 0 }
        var open: Float = 1
        if blinkPhase >= 0 {
            blinkPhase += dt / 0.16
            if blinkPhase >= 1 { blinkPhase = -1 } else { open = abs(cosf(blinkPhase * .pi)) }
        }
        motion.eyeOpen = open
        motion.breathRate = 0.85
        motion.tailAgitation = 0.12
        motion.lookTarget = SCNVector3(x: 0, y: 0.30, z: 1.2)
        motion.lookWeight = 0.55

        poseTimer -= dt
        if poseTimer <= 0 {
            poseTimer = Float.random(in: 8...16)
            poseIndex = (poseIndex + 1) % poses.count
            motion.pose = poses[poseIndex]
        }

        animator.update(dt: dt, motion: motion)
    }
}

struct CatPreviewView: UIViewRepresentable {
    let appearance: CatAppearance
    let controller: CatPreviewController

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.delegate = controller
        view.rendersContinuously = true
        view.isPlaying = true
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 60
        view.backgroundColor = .clear
        view.allowsCameraControl = false

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        controller.request(appearance: appearance)
    }

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    final class Coordinator: NSObject {
        let controller: CatPreviewController
        init(controller: CatPreviewController) { self.controller = controller }
        @objc func tapped() { controller.cyclePose() }
    }
}
