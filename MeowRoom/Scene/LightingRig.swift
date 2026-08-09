import Foundation
import SceneKit
import UIKit

/// One sun outside the room, one moon behind it, and sky. Nothing else.
///
/// There used to be two omni lights floating *inside* the room as well — a
/// "bounce" about a metre above the tatami and a "window glow" beside the shoji —
/// and between them they carried most of the daylight. They are gone, because in
/// a room four metres across a light with a position always lights whatever it
/// happens to be nearest, and every symptom chased through a long evening of
/// tuning turned out to be one of them doing exactly that: a bright pool on the
/// floor, a white patch on the paper, each "fixed" by moving a bulb to where it
/// could do less obvious harm.
///
/// What replaces them is the sky itself — flat ambient plus the image-based
/// environment — neither of which has a location, so neither can put a bright
/// patch anywhere at all.
final class LightingRig {
    let root = SCNNode()

    private let sunNode = SCNNode()
    private let sun = SCNLight()
    private let moonNode = SCNNode()
    private let moon = SCNLight()
    private let ambient = SCNLight()

    init() {
        // --- Sun: the only shadow caster that matters.
        sun.type = .directional
        sun.castsShadow = true
        sun.shadowMode = .deferred
        sun.shadowRadius = 6
        sun.shadowSampleCount = RenderQuality.shadowSampleCount
        sun.shadowMapSize = RenderQuality.shadowMapSize
        sun.shadowColor = UIColor(white: 0, alpha: 0.55)
        // Wide enough to hold the whole room and its walls. With the interior
        // fills gone, the sun's shadow is what makes the window an aperture: the
        // walls block it, and the light that reaches the floor is the light that
        // came through the opening. That only works if the walls are inside the
        // shadow map.
        sun.orthographicScale = 4.6
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
                           // Raised with the exposure cut, not independently of
                           // it. A lamp is the only source that exists solely at
                           // night, so it is the one place night can be paid back
                           // for a stop taken off the whole day — and paying it
                           // back here cannot touch daylight, where the lantern is
                           // off and contributes nothing at all.
                           lantern: lanternOn ? 38 : 0)
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
        var lantern: Float

        var total: Float { sun + moon + ambient + lantern }
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
        // The sun keeps all of its own budget and the sky keeps all of its.
        //
        // There is nothing left to split it between: the two interior omni lights
        // that used to take most of it are gone. What is left has exactly the shape
        // a room has — one source outside, and sky everywhere.
        return LightIntensities(sun: b.sun * k,
                                moon: b.moon * k,
                                ambient: (b.sky + b.lantern * 0.25) * k,
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
    static func exposureOffset(for budget: LightBudget) -> CGFloat { -1.75 }

    static func exposureOffset(sky: SkyState, lanternOn: Bool) -> CGFloat {
        exposureOffset(for: budget(sky: sky, lanternOn: lanternOn))
    }

    /// What the room is actually lit by, which with exposure fixed is what
    /// reaches the screen. The tests use it to assert a brighter room renders
    /// brighter, and that the day is neither flat nor extreme.
    static func renderedBrightness(for budget: LightBudget) -> Float {
        intensities(for: budget).total
    }

    /// How far beyond the shoji the arc sits. Deliberately small: the point is
    /// that the light comes from outside, not that it comes from far to one side.
    static let windowOffset: Float = 0.34

    /// A direction on an arc that genuinely runs parallel to the window.
    ///
    /// The window is the -Z wall, so its plane is XY, and an arc parallel to it is
    /// one at constant Z: the sun rises at +X, passes overhead, sets at -X, and
    /// holds the same small distance beyond the glass the entire way. Its light
    /// therefore rakes across the opening at every hour and never once travels down
    /// the length of the room.
    ///
    /// The first attempt at this scaled the horizontal reach by `cos(elevation)`,
    /// which seemed harmless and was not: at solar noon the X term vanishes, and
    /// with nothing left but the offset the sun ends up square with the window.
    /// In midsummer that is hidden, because the sun is overhead and its horizontal
    /// bearing hardly matters — but in December the noon sun is low, and it lines
    /// up exactly. The bug only existed in the season it would have been worst in.
    ///
    /// So the arc's *shape* is fixed and only its progress is real. Season and hour
    /// still drive everything that reads as time of day — the length of the day,
    /// the colour, the whole light budget — through `elevation`, which this does
    /// not touch. What is given up is the sun sitting lower at noon in winter.
    /// What is bought is that no hour of no month can put a bar of sunlight across
    /// the floor, which is worth more here than the seasonal accuracy of an object
    /// the player can never actually see.
    static func arcDirection(azimuth: Float) -> SCNVector3 {
        // Real azimuth is 0 at north and increases eastward, so a southern sun runs
        // from roughly 90 degrees at sunrise to 270 at sunset. Clamped, because in
        // midsummer at this latitude it begins and ends outside that.
        let p = clamp(remap(azimuth, deg(90), deg(270), 0, 1))
        let theta = p * .pi
        return SCNVector3(x: cosf(theta), y: sinf(theta), z: -windowOffset).normalized
    }

    func apply(sky: SkyState, scene: SCNScene, room: RoomNode, lanternOn: Bool) {
        // --- Sun placement.
        let d = LightingRig.arcDirection(azimuth: sky.sunAzimuth)
        let sunPos = SCNVector3(x: d.x * 9, y: max(0.2, d.y * 9), z: d.z * 9)
        sunNode.position = sunPos
        sunNode.look(at: SCNVector3(x: 0, y: 0.6, z: -0.2))

        let budget = LightingRig.budget(sky: sky, lanternOn: lanternOn)
        let lit = LightingRig.intensities(for: budget)

        sun.intensity = CGFloat(lit.sun)
        sun.color = UIColor(sky.sunColor)
        sun.castsShadow = budget.sun > 30

        // --- Moon.
        let m = LightingRig.arcDirection(azimuth: sky.moonAzimuth)
        moonNode.position = SCNVector3(x: m.x * 9, y: max(0.2, m.y * 9), z: m.z * 9)
        moonNode.look(at: SCNVector3(x: 0, y: 0.6, z: -0.2))
        moon.intensity = CGFloat(lit.moon)

        // --- Ambient from the sky colour.
        ambient.color = UIColor(sky.ambientColor)
        ambient.intensity = CGFloat(lit.ambient)

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
        // The sky dome, and now the only fill with any sense of direction in it.
        // Flat ambient alone would light every surface identically regardless of
        // which way it faces, which is what makes a room read as a paper cut-out;
        // this is what puts the shape back without putting a bulb in the room.
        scene.lightingEnvironment.intensity = CGFloat(min(0.85, budget.sky * 0.0014))
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
