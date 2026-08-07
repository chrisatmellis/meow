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

    // MARK: - Light budget

    /// The room's light in absolute terms: lux arriving in the middle of the floor.
    ///
    /// Everything else in this file is derived from this one struct, which is the
    /// whole point of it. Before, the sun, moon, ambient, bounce, window glow,
    /// lantern, shoji emission, image-based lighting and camera exposure were nine
    /// separate hand-fitted curves. Nothing anywhere meant "how bright is this
    /// room", so tuning any one of them to fix a screenshot quietly moved the
    /// others, and nothing was able to notice that late night had ended up
    /// brighter than noon.
    struct LightBudget {
        var sun: Float
        var sky: Float
        var moon: Float
        var lantern: Float

        /// What the camera meters.
        var key: Float { max(0.05, sun + sky + moon + lantern) }
    }

    /// A pleasant, well-lit interior. Exposure is defined relative to this.
    private static let referenceLux: Float = 500

    /// How much of the real brightness variation survives to the screen.
    ///
    /// A camera that compensates fully renders midnight and noon identically,
    /// which is exactly how every hour in this room ended up the same brightness.
    /// Compensating only partly keeps night reading as night: the frame lands at
    /// `reference * (key / reference) ^ retainedContrast`, so the ~6 stops between
    /// a lantern at midnight and full noon arrive as about 1.5 stops on screen —
    /// plainly different, still readable.
    private static let retainedContrast: Float = 0.25

    /// Lux by path, for the current sky. Daylight is overwhelmingly the sun and
    /// the sky through the opening; at night a paper lantern is worth far more
    /// than the moon, which is why a room with the lamp off really is dim.
    static func budget(sky: SkyState, lanternOn: Bool) -> LightBudget {
        let above = smoothstep(-0.06, 0.12, sky.sunElevation)
        let moonUp = smoothstep(-0.05, 0.25, sky.moonElevation)
        return LightBudget(sun: above * powf(max(0, sky.daylight), 1.5) * 1900,
                           sky: 3 + 660 * sky.daylight,
                           moon: moonUp * 9 * (1 - sky.daylight),
                           lantern: lanternOn ? 26 : 0)
    }

    /// Exposure in EV, metered off the budget the way a real camera would.
    /// SceneKit's own `wantsExposureAdaptation` would ramp visibly after launch;
    /// the sky is already known, so this is computed straight from it instead.
    static func exposureOffset(for budget: LightBudget) -> CGFloat {
        let ev = log2(budget.key / referenceLux) * (1 - retainedContrast)
        return CGFloat(min(4.2, max(-2.4, -ev)))
    }

    static func exposureOffset(sky: SkyState, lanternOn: Bool) -> CGFloat {
        exposureOffset(for: budget(sky: sky, lanternOn: lanternOn))
    }

    /// Where the frame should land in brightness once exposure has been applied.
    /// Only meaningful relative to itself — the tests use it to assert that a
    /// brighter room really does render brighter.
    static func renderedBrightness(for budget: LightBudget) -> Float {
        referenceLux * powf(budget.key / referenceLux, retainedContrast)
    }

    func apply(sky: SkyState, scene: SCNScene, room: RoomNode, lanternOn: Bool) {
        // --- Sun placement.
        let d = sky.sunDirection
        let sunPos = SCNVector3(x: d.x * 9, y: max(0.2, d.y * 9), z: d.z * 9)
        sunNode.position = sunPos
        sunNode.look(at: SCNVector3(x: 0, y: 0.6, z: -0.2))

        // Each light takes a share of the budget. The per-light factors differ
        // because SceneKit measures a directional light's intensity in lux but an
        // omni's in lumens; they convert between those units and set the overall
        // level. The ratios are what matter, and they all move together now.
        let budget = LightingRig.budget(sky: sky, lanternOn: lanternOn)

        sun.intensity = CGFloat(budget.sun * 0.30)
        sun.color = UIColor(sky.sunColor)
        sun.castsShadow = budget.sun > 30

        // --- Moon.
        let m = sky.moonDirection
        moonNode.position = SCNVector3(x: m.x * 9, y: max(0.2, m.y * 9), z: m.z * 9)
        moonNode.look(at: SCNVector3(x: 0, y: 0.6, z: -0.2))
        moon.intensity = CGFloat(budget.moon * 3.5)

        // --- Ambient from the sky colour.
        ambient.color = UIColor(sky.ambientColor)
        ambient.intensity = CGFloat(budget.sky * 0.14 + budget.lantern * 0.60)

        // --- Bounce and window glow.
        bounce.intensity = CGFloat(budget.sun * 0.03 + budget.sky * 0.06 + budget.lantern * 1.20)
        bounce.color = UIColor(sky.sunColor.mixed(with: RGBColor(hex: 0xC9B383), 0.45))
        windowGlow.intensity = CGFloat(budget.sky * 0.19)
        windowGlow.color = UIColor(sky.skyHorizonColor.lightened(0.25))

        // --- Backlit shoji paper. Its brightness is the sky outside and nothing
        // else: the flat floor this used to carry was what left the paper — and
        // the open half beside it — glowing at ten at night.
        let glow = CGFloat(min(0.52, budget.sky / LightingRig.referenceLux * 0.36))
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
        scene.lightingEnvironment.intensity = CGFloat(budget.sky / LightingRig.referenceLux * 0.43)
        scene.background.contents = UIColor(sky.skyHorizonColor.darkened(0.4))

        // --- Paper lantern.
        if let light = room.lanternLight, let paper = room.lanternPaper {
            light.intensity = CGFloat(budget.lantern * 3.4)
            // A lit lamp has a fixed luminance, so this does not track the sky.
            // At night exposure lifts it and the paper reads as the bright thing
            // in the room, which is what a lamp at night is.
            paper.emission.intensity = lanternOn ? 0.18 : 0.0
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
