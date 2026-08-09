import SwiftUI
import RealityKit

/// Live turntable preview of the cat being designed. Reuses the exact same
/// builder and animator the game uses, so what you see is what you adopt.
final class CatPreviewController: NSObject, ObservableObject {
    let root = Entity()
    private var rig: CatRig
    private var animator: CatAnimator
    private var motion = CatMotion()
    /// Seconds since the preview opened, used only to rate-limit rebuilds.
    private var clock: TimeInterval = 0
    private var turntable: Float = 0
    private var blinkTimer: Float = 2
    private var blinkPhase: Float = -1
    private var poseTimer: Float = 6
    private var poseIndex = 0
    private let pivot = Entity()
    let camera = PerspectiveCamera()
    private let environment = Entity()
    /// Held for the same reason the game's is: see `GameSceneController.frameLoop`.
    var frameLoop: EventSubscription?

    private var pendingAppearance: CatAppearance?
    private var lastRebuild: TimeInterval = 0
    private(set) var appearance: CatAppearance

    private let poses: [CatPose] = [.sittingTall, .standing, .loaf, .sitting, .stretching]

    init(appearance: CatAppearance) {
        self.appearance = appearance
        self.rig = CatBuilder.build(appearance, preview: true)
        self.animator = CatAnimator(rig: rig)
        super.init()

        root.addChild(pivot)
        pivot.addChild(rig.root)

        motion.pose = .sittingTall
        motion.position = SIMD3<Float>(x: 0, y: 0, z: 0)
        motion.eyeOpen = 1

        setupStage()
    }

    private func setupStage() {
        // A soft studio: key, fill, rim, and a warm floor disc.
        //
        // The ambient light this used to have is gone, because RealityKit has
        // none. Its job — keeping the shadow side of the cat from going black —
        // is done by the environment map instead, which does it better: an
        // ambient term lights the underside of a chin exactly as brightly as the
        // top of a head, and the environment does not.
        let key = Entity()
        key.components.set(DirectionalLightComponent(
            color: UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1), intensity: 430))
        key.components.set(DirectionalLightComponent.Shadow(maximumDistance: 3, depthBias: 1))
        key.look(at: SIMD3<Float>(0, 0.16, 0), from: SIMD3<Float>(0.8, 1.2, 1.1),
                 upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
        root.addChild(key)

        let fill = Entity()
        fill.components.set(PointLightComponent(
            color: UIColor(red: 0.72, green: 0.82, blue: 1.0, alpha: 1),
            intensity: 130, attenuationRadius: 4))
        fill.position = SIMD3<Float>(x: -1.0, y: 0.7, z: 0.6)
        root.addChild(fill)

        let rim = Entity()
        rim.components.set(PointLightComponent(
            color: UIColor(red: 1.0, green: 0.86, blue: 0.68, alpha: 1),
            intensity: 175, attenuationRadius: 4))
        rim.position = SIMD3<Float>(x: -0.3, y: 0.8, z: -1.1)
        root.addChild(rim)

        let floor = MeshBuilder.cylinder(radius: 0.55, height: 0.012)
        let floorNode = Entity.make(floor, Materials.tatami())
        floorNode.position = SIMD3<Float>(x: 0, y: -0.006, z: 0)
        root.addChild(floorNode)

        // A close portrait lens. Vertical here rather than horizontal: the preview
        // is a head-and-shoulders shot in a tall panel, so it is the height that
        // has to stay framed.
        var lens = PerspectiveCameraComponent()
        lens.fieldOfViewOrientation = .vertical
        lens.fieldOfViewInDegrees = 34
        lens.near = 0.02
        lens.far = 20
        camera.camera = lens
        camera.look(at: SIMD3<Float>(0, 0.17, 0), from: SIMD3<Float>(0.0, 0.30, 0.95),
                    upVector: SIMD3<Float>(0, 1, 0), relativeTo: nil)
        root.addChild(camera)

        if let cg = TextureFactory.skyEnvironment(sky: WorldClock.sky()).cgImage,
           let resource = try? EnvironmentResource(
               equirectangular: cg,
               options: .init(samplingQuality: .normal, specularCubeDimension: 64)) {
            environment.components.set(ImageBasedLightComponent(source: .single(resource),
                                                               intensityExponent: log2f(0.28)))
            root.addChild(environment)
            root.components.set(ImageBasedLightReceiverComponent(imageBasedLight: environment))
        }
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
        rig.root.removeFromParent()
        rig = CatBuilder.build(pending, preview: true)
        animator = CatAnimator(rig: rig)
        pivot.addChild(rig.root)
        motion.pose = currentPose
    }

    func cyclePose() {
        poseIndex = (poseIndex + 1) % poses.count
        motion.pose = poses[poseIndex]
        poseTimer = 12
    }

    /// Called once per frame by the view.
    func update(deltaTime: Float) {
        let dt = min(max(deltaTime, 0), 0.1)
        clock += TimeInterval(dt)
        rebuildIfNeeded(now: clock)
        guard dt > 0 else { return }

        turntable += dt * 0.28
        pivot.eulerAngles = SIMD3<Float>(x: 0, y: sinf(turntable) * 0.85 + 0.35, z: 0)

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
        motion.lookTarget = SIMD3<Float>(x: 0, y: 0.30, z: 1.2)
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

struct CatPreviewView: View {
    let appearance: CatAppearance
    let controller: CatPreviewController

    var body: some View {
        RealityView { content in
            content.camera = .virtual
            content.add(controller.root)
            controller.frameLoop = content.subscribe(to: SceneEvents.Update.self) { event in
                controller.update(deltaTime: Float(event.deltaTime))
            }
        } update: { _ in
            controller.request(appearance: appearance)
        }
        .onTapGesture { controller.cyclePose() }
    }
}
