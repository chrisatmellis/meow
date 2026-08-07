import Foundation
import SceneKit
import UIKit

/// Sun, moon, sky and bounce light, all driven by the device's real clock.
final class LightingRig {
    let root = SCNNode()

    private let sunNode = SCNNode()
    private let sun = SCNLight()
    private let moonNode = SCNNode()
    private let moon = SCNLight()
    private let ambient = SCNLight()
    private let bounceNode = SCNNode()
    private let bounce = SCNLight()
    private let windowGlowNode = SCNNode()
    private let windowGlow = SCNLight()

    init() {
        // --- Sun: the only shadow caster that matters.
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 6
        sun.shadowSampleCount = RenderQuality.shadowSampleCount
        sun.shadowMapSize = RenderQuality.shadowMapSize
        sun.shadowColor = UIColor(white: 0, alpha: 0.55)
        sun.orthographicScale = 3.2
        sun.zNear = 0.2
        sun.zFar = 22
        sun.intensity = 0
        sunNode.light = sun
        root.addChildNode(sunNode)

        // --- Moon: cool, soft, no shadows.
        moon.type = .directional
        moon.castsShadow = false
        moon.intensity = 0
        moon.color = UIColor(red: 0.62, green: 0.72, blue: 0.95, alpha: 1)
        moonNode.light = moon
        root.addChildNode(moonNode)

        // --- Sky ambient.
        ambient.type = .ambient
        ambient.intensity = 200
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        root.addChildNode(ambientNode)

        // --- Warm bounce off the tatami, sitting low in the room.
        bounce.type = .omni
        bounce.intensity = 0
        bounce.attenuationStartDistance = 0.5
        bounce.attenuationEndDistance = 6
        bounce.color = UIColor(red: 1.0, green: 0.90, blue: 0.72, alpha: 1)
        bounceNode.light = bounce
        bounceNode.position = SCNVector3(x: 0.1, y: 0.45, z: -0.4)
        root.addChildNode(bounceNode)

        // --- Soft light spilling in through the shoji, so the window reads as a source.
        windowGlow.type = .omni
        windowGlow.intensity = 0
        windowGlow.attenuationStartDistance = 0.4
        windowGlow.attenuationEndDistance = 5.5
        windowGlowNode.light = windowGlow
        windowGlowNode.position = SCNVector3(x: 0.2, y: 1.2, z: -RoomLayout.halfDepth + 0.25)
        root.addChildNode(windowGlowNode)
    }

    /// How far to stop the camera down for a given sky.
    ///
    /// The room spans a huge range of real brightness — a moonlit night and noon
    /// sun through paper are nowhere near each other — and one fixed exposure
    /// cannot serve both. At a setting dark enough to hold midday, night is
    /// unreadable; at one bright enough for night, midday clips the tatami, the
    /// walls and the shoji all to flat white and the cat washes out with them.
    /// So the camera stops down as the sun climbs, the way an eye or an
    /// auto-exposing camera does. SceneKit's own `wantsExposureAdaptation` would
    /// ramp visibly after launch; the sky is already known, so this is computed
    /// straight from it instead.
    static func exposureOffset(for sky: SkyState) -> CGFloat {
        CGFloat(-0.35 - 0.90 * sky.daylight)
    }

    func apply(sky: SkyState, scene: SCNScene, room: RoomNode, lanternOn: Bool) {
        // --- Sun placement.
        let d = sky.sunDirection
        let sunPos = SCNVector3(x: d.x * 9, y: max(0.2, d.y * 9), z: d.z * 9)
        sunNode.position = sunPos
        sunNode.look(at: SCNVector3(x: 0, y: 0.6, z: -0.2))

        let above = smoothstep(-0.06, 0.12, sky.sunElevation)
        sun.intensity = CGFloat(above * (170 + 540 * sky.daylight))
        sun.color = UIColor(sky.sunColor)
        sun.castsShadow = above > 0.05

        // --- Moon.
        let m = sky.moonDirection
        moonNode.position = SCNVector3(x: m.x * 9, y: max(0.2, m.y * 9), z: m.z * 9)
        moonNode.look(at: SCNVector3(x: 0, y: 0.6, z: -0.2))
        let moonUp = smoothstep(-0.05, 0.25, sky.moonElevation)
        moon.intensity = CGFloat(moonUp * 34 * (1 - sky.daylight))

        // --- Ambient from the sky colour.
        ambient.color = UIColor(sky.ambientColor)
        ambient.intensity = CGFloat(16 + 95 * sky.daylight)

        // --- Bounce and window glow.
        bounce.intensity = CGFloat(10 + 78 * sky.daylight)
        bounce.color = UIColor(sky.sunColor.mixed(with: RGBColor(hex: 0xC9B383), 0.45))
        windowGlow.intensity = CGFloat(14 + 115 * sky.daylight)
        windowGlow.color = UIColor(sky.skyHorizonColor.lightened(0.25))

        // --- Backlit shoji paper.
        let glow = CGFloat(0.03 + 0.30 * sky.daylight + 0.10 * sky.horizonWarmth)
        for mat in room.shojiMaterials {
            mat.emission.intensity = glow
            mat.emission.contents = UIColor(sky.skyHorizonColor.lightened(0.35 * sky.daylight))
        }

        // --- Garden outside.
        for mat in room.backdropMaterials {
            mat.diffuse.contents = TextureFactory.gardenBackdrop(sky: sky)
        }

        // --- Image-based lighting for believable PBR highlights.
        scene.lightingEnvironment.contents = TextureFactory.skyEnvironment(sky: sky)
        scene.lightingEnvironment.intensity = CGFloat(0.12 + 0.45 * sky.daylight)
        scene.background.contents = UIColor(sky.skyHorizonColor.darkened(0.4))

        // --- Paper lantern.
        if let light = room.lanternLight, let paper = room.lanternPaper {
            let target: CGFloat = lanternOn ? CGFloat(95 - 40 * sky.daylight) : 0
            light.intensity = target
            paper.emission.intensity = lanternOn ? 0.85 : 0.0
        }

        // --- Sun patch on the tatami.
        if let patch = room.sunPatch {
            let visible = smoothstep(0.02, 0.22, sky.sunElevation)
            patch.opacity = CGFloat(visible * 0.28)
            let p = RoomLayout.sunPatchPosition(sky: sky)
            patch.position = SCNVector3(x: p.x, y: 0.033, z: p.z)
            let stretch = 1.0 + 1.6 * (1 - clamp(sky.sunElevation / 0.9))
            patch.scale = SCNVector3(x: stretch, y: 1.0 + 0.4 * stretch, z: 1)
        }

        // --- Dust motes only show when there is a beam to catch.
        room.dustMotes?.isHidden = sky.daylight < 0.12 && !lanternOn
    }
}
