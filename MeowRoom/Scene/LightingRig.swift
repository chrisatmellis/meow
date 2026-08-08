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

    /// How the budget is split across the actual lights.
    ///
    /// Every entry is a share of one source's lux, and the shares of each source
    /// sum to one, so the mix between lights is fixed by the budget and only the
    /// overall level moves. Picking a coefficient per light so one screenshot
    /// looks right is how this went wrong before: that is hand-fitting the
    /// sources again, one layer down, and it left night only 6.5x dimmer than
    /// noon while the budget claimed 88x.
    struct LightIntensities {
        var sun: Float
        var moon: Float
        var ambient: Float
        var windowGlow: Float
        var bounce: Float
        var lantern: Float

        var total: Float { sun + moon + ambient + windowGlow + bounce + lantern }
    }

    /// Total SceneKit intensity at full daylight, and the lux that corresponds to.
    private static let noonIntensity: Float = 430
    private static let noonLux: Float = 2563

    /// How much of the budget's range reaches the lights.
    ///
    /// Not 1, because SceneKit is not a linear-light renderer: its tone mapper
    /// saturates, so driving intensities to the tens of thousands buys nothing
    /// and then needs a huge negative exposure to bring back, which crushes the
    /// scene. Measured directly — two builds computing an identical "effective
    /// light" of 263 at midday rendered at mean 126 and mean 67. Keeping the
    /// numbers in a range the tone mapper treats roughly linearly is what makes
    /// the budget's ratios survive to the screen.
    private static let intensityGamma: Float = 0.65

    /// Lux to SceneKit intensity for a given budget. Compressive, so a moonlit
    /// room is dimmer than noon by a believable amount rather than by the full
    /// physical 88x, which no display could show anyway.
    private static func scale(_ key: Float) -> Float {
        noonIntensity * powf(key / noonLux, intensityGamma) / max(key, 0.05)
    }

    static func intensities(for b: LightBudget) -> LightIntensities {
        let k = scale(b.key)
        return LightIntensities(sun: b.sun * 0.85 * k,
                                moon: b.moon * 1.00 * k,
                                ambient: (b.sky * 0.30 + b.lantern * 0.10) * k,
                                windowGlow: b.sky * 0.45 * k,
                                bounce: (b.sun * 0.15 + b.sky * 0.25 + b.lantern * 0.15) * k,
                                lantern: b.lantern * 0.75 * k)
    }

    /// Exposure is fixed, and that is the point.
    ///
    /// Three builds tried to vary it with the sky and each broke a different
    /// hour. Positive exposure at night multiplies every emissive in the room —
    /// lantern paper, the feeder's LED, eye catchlights, the garden — none of
    /// which are in the budget, and midnight came out brighter than midday.
    /// Anchoring it so it only ever stops down fixed that and crushed daylight
    /// instead, because a large negative exposure cannot be paid for by raising
    /// intensities past where the tone mapper saturates.
    ///
    /// The day/night difference belongs in the lights, where it is a property of
    /// the room, not in the camera, where it silently rescales everything else
    /// as well. So the budget drives `intensities(for:)` and this stays put.
    static func exposureOffset(for budget: LightBudget) -> CGFloat { -0.35 }

    static func exposureOffset(sky: SkyState, lanternOn: Bool) -> CGFloat {
        exposureOffset(for: budget(sky: sky, lanternOn: lanternOn))
    }

    /// What the room is actually lit by, which with exposure fixed is what
    /// reaches the screen. The tests use it to assert a brighter room renders
    /// brighter, and that the day is neither flat nor extreme.
    static func renderedBrightness(for budget: LightBudget) -> Float {
        intensities(for: budget).total
    }

    func apply(sky: SkyState, scene: SCNScene, room: RoomNode, lanternOn: Bool) {
        // --- Sun placement.
        let d = sky.sunDirection
        let sunPos = SCNVector3(x: d.x * 9, y: max(0.2, d.y * 9), z: d.z * 9)
        sunNode.position = sunPos
        sunNode.look(at: SCNVector3(x: 0, y: 0.6, z: -0.2))

        let budget = LightingRig.budget(sky: sky, lanternOn: lanternOn)
        let lit = LightingRig.intensities(for: budget)

        sun.intensity = CGFloat(lit.sun)
        sun.color = UIColor(sky.sunColor)
        sun.castsShadow = budget.sun > 30

        // --- Moon.
        let m = sky.moonDirection
        moonNode.position = SCNVector3(x: m.x * 9, y: max(0.2, m.y * 9), z: m.z * 9)
        moonNode.look(at: SCNVector3(x: 0, y: 0.6, z: -0.2))
        moon.intensity = CGFloat(lit.moon)

        // --- Ambient from the sky colour.
        ambient.color = UIColor(sky.ambientColor)
        ambient.intensity = CGFloat(lit.ambient)

        // --- Bounce and window glow.
        bounce.intensity = CGFloat(lit.bounce)
        bounce.color = UIColor(sky.sunColor.mixed(with: RGBColor(hex: 0xC9B383), 0.45))
        windowGlow.intensity = CGFloat(lit.windowGlow)
        windowGlow.color = UIColor(sky.skyHorizonColor.lightened(0.25))

        // --- Backlit shoji paper. Its brightness is the sky outside and nothing
        // else: the flat floor this used to carry was what left the paper — and
        // the open half beside it — glowing at ten at night.
        let glow = CGFloat(min(0.28, budget.sky * 0.0004))
        for mat in room.shojiMaterials {
            mat.emission.intensity = glow
            mat.emission.contents = UIColor(sky.skyHorizonColor.lightened(0.35 * sky.daylight))
        }

        // --- Garden outside.
        // Outdoors is far brighter than the room it is seen from, so this runs
        // well past 1 in daylight and the window blows out, as it should.
        let outdoor = CGFloat(min(0.62, 0.28 + budget.sky * 0.0005))
        for mat in room.backdropMaterials {
            mat.emission.contents = TextureFactory.gardenBackdrop(sky: sky)
            mat.emission.intensity = outdoor
        }

        // --- Image-based lighting for believable PBR highlights.
        scene.lightingEnvironment.contents = TextureFactory.skyEnvironment(sky: sky)
        scene.lightingEnvironment.intensity = CGFloat(min(0.62, budget.sky * 0.0009))
        scene.background.contents = UIColor(sky.skyHorizonColor.darkened(0.4))

        // --- Paper lantern.
        if let light = room.lanternLight, let paper = room.lanternPaper {
            light.intensity = CGFloat(lit.lantern)
            // A lit lamp has a fixed luminance, so this does not track the sky.
            // At night exposure lifts it and the paper reads as the bright thing
            // in the room, which is what a lamp at night is.
            paper.emission.intensity = lanternOn ? 0.12 : 0.0
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
