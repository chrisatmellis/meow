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
        // Raised, and with a much gentler falloff, because of what it now carries.
        //
        // At 45 cm above the tatami holding 15% of the sun this was a plausible
        // warm kick off the floor. Holding 55% it became a floodlight pointed
        // straight down: the render came out with a bright pool in the middle of
        // the room and the floor's texture washed out inside it, while the level
        // as a whole measured fine. Bounced light does not have a hotspot — that
        // is the one thing it is definitionally free of.
        bounce.attenuationStartDistance = 2.0
        bounce.attenuationEndDistance = 8
        bounce.color = UIColor(red: 1.0, green: 0.90, blue: 0.72, alpha: 1)
        bounceNode.light = bounce
        bounceNode.position = SCNVector3(x: 0.1, y: 0.95, z: -0.5)
        root.addChildNode(bounceNode)

        // --- Soft light spilling in through the shoji, so the window reads as a source.
        windowGlow.type = .omni
        windowGlow.intensity = 0
        windowGlow.attenuationStartDistance = 1.8
        windowGlow.attenuationEndDistance = 7
        windowGlowNode.light = windowGlow
        // Nearly a metre in from the shoji, not a quarter of one.
        //
        // The point of this light is the room, but at 0.25 m the nearest surface to
        // it by far was the paper itself, so the panels were lit from inside and
        // came out white with their own texture washed off them. Backing it into
        // the room lights the room.
        windowGlowNode.position = SCNVector3(x: 0.2, y: 1.15, z: -RoomLayout.halfDepth + 0.95)
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
    /// Measured, not guessed: at 430 the room rendered at mean luma 182 with the
    /// tatami blown to near-white and no detail left in it. A lit interior sits
    /// closer to 110-120 — bright, but with the floor still made of something.
    private static let noonIntensity: Float = 290
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
        // The sun's share moved from the directional light to the soft one: 0.85/0.15
        // to 0.45/0.55. Nothing about the budget changed, so the day/night ordering
        // and the totals are exactly as they were — only the *character* of daylight
        // is different, and that is the point.
        //
        // A room screened with paper does not get hard sunlight. Shoji is a diffuser;
        // that is what it is for. Sending most of the sun through the omni fill makes
        // the light arrive from the whole window rather than from a point 9 metres
        // away, which is both what actually happens and what stops the room reading
        // as though someone opened a skylight.
        // The sky's share leans toward ambient now: 0.42/0.28/0.30 rather than
        // 0.30/0.45/0.25. Ambient is the only source in the room with no position,
        // so it is the only one that cannot put a bright patch anywhere, and
        // daylight through paper is the case with least business having one.
        return LightIntensities(sun: b.sun * 0.45 * k,
                                moon: b.moon * 1.00 * k,
                                ambient: (b.sky * 0.42 + b.lantern * 0.10) * k,
                                windowGlow: b.sky * 0.28 * k,
                                bounce: (b.sun * 0.55 + b.sky * 0.30 + b.lantern * 0.15) * k,
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
    /// Still fixed. Just lower, and measured rather than guessed.
    ///
    /// Cutting `noonIntensity` from 430 to 290 — a third of the light gone —
    /// moved the rendered mean from 182 to 176. Three percent. That is the tone
    /// mapper saturating: past a certain point more or less intensity buys almost
    /// nothing, which is the same wall three earlier attempts hit from the other
    /// side when they tried to *raise* intensities to pay for a negative exposure.
    ///
    /// So in daylight the light level is not the lever at all, and exposure is the
    /// only thing left that still moves the picture. Fixed is what matters — a
    /// value that varies with the sky rescales every emissive in the room and is
    /// what once made midnight brighter than midday. A constant cannot do that to
    /// the ordering; it only ever stops the whole day down together.
    static func exposureOffset(for budget: LightBudget) -> CGFloat { -1.5 }

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
        // Barely tinted, because this light is now doing most of the work.
        //
        // Mixing 45% toward tatami straw was reasonable while bounce carried 15%
        // of the sun. It carries 55% now, and at that share the tint stopped
        // reading as warmth off the floor and started reading as a green cast over
        // the entire room — walls, ceiling, cat and all. A bounce light's colour
        // has to get weaker as its share gets stronger, or it stops being bounce
        // and becomes a colour filter.
        // Back up from 0.16, which overcorrected. The green cast that prompted
        // that cut was a product of this tint *and* a room rendering at mean 182;
        // with the exposure fixed the room came out grey instead, the tatami
        // reading as pale concrete rather than as straw. This is a room whose
        // floor is dried rush — daylight in it should carry some of that.
        bounce.color = UIColor(sky.sunColor.mixed(with: RGBColor(hex: 0xC9B383), 0.30))
        windowGlow.intensity = CGFloat(lit.windowGlow)
        windowGlow.color = UIColor(sky.skyHorizonColor.lightened(0.25))

        // --- Backlit shoji paper. Its brightness is the sky outside and nothing
        // else: the flat floor this used to carry was what left the paper — and
        // the open half beside it — glowing at ten at night.
        // Halved. Paper backlit by an overcast sky is bright, but it is not a
        // light box — at 0.28 the panels clipped, taking their own texture with
        // them, so the shoji read as a white rectangle rather than as paper.
        let glow = CGFloat(min(0.14, budget.sky * 0.0002))
        for mat in room.shojiMaterials {
            mat.emission.intensity = glow
            mat.emission.contents = UIColor(sky.skyHorizonColor.lightened(0.35 * sky.daylight))
        }

        // --- Garden outside.
        //
        // Outdoors really is far brighter than the room it is seen from, and the
        // previous value leaned on that: the window blew out "as it should". Two
        // things were wrong with it. The blowout was not confined to the window —
        // bloom carried it across the whole frame — and a window that clips to
        // white throws away the garden behind it, which is drawn and then never
        // seen. Bright enough to read as outside, dim enough to still be a garden.
        let outdoor = CGFloat(min(0.34, 0.16 + budget.sky * 0.00027))
        for mat in room.backdropMaterials {
            mat.emission.contents = TextureFactory.gardenBackdrop(sky: sky)
            mat.emission.intensity = outdoor
        }

        // --- Image-based lighting for believable PBR highlights.
        scene.lightingEnvironment.contents = TextureFactory.skyEnvironment(sky: sky)
        scene.lightingEnvironment.intensity = CGFloat(min(0.45, budget.sky * 0.0007))
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
            // Additive, on a floor that is already the brightest surface in the
            // room, at an opacity that made it glare. It stays because the cat
            // seeks it out and the brain has opinions about sunbathing, but as a
            // warm tint rather than a shaft of light on the tatami.
            let visible = smoothstep(0.02, 0.22, sky.sunElevation)
            patch.opacity = CGFloat(visible * 0.07)
            let p = RoomLayout.sunPatchPosition(sky: sky)
            patch.position = SCNVector3(x: p.x, y: 0.033, z: p.z)
            let stretch = 1.0 + 1.6 * (1 - clamp(sky.sunElevation / 0.9))
            patch.scale = SCNVector3(x: stretch, y: 1.0 + 0.4 * stretch, z: 1)
        }

        // --- Dust motes only show when there is a beam to catch.
        room.dustMotes?.isHidden = sky.daylight < 0.12 && !lanternOn
    }
}
