import Foundation
import SceneKit
import UIKit

/// A part thin enough that light comes through it.
///
/// Ears mostly, but also the nose leather, the paw pads and the toe webbing —
/// anywhere the tissue is a couple of millimetres thick over blood.
struct TranslucentPart {
    let node: SCNNode
    let material: SCNMaterial
    /// 0 is opaque, 1 is an ear held up to a window.
    let amount: Float
    /// The colour that comes through. Always warmer and redder than the surface,
    /// because what you are seeing is light that has been through blood.
    let tint: RGBColor
}

/// Drives translucency from where the sun actually is.
///
/// The reference texture sets that inspired this carry a `SubsurfaceAmount` map:
/// black over the body, bright at the ears, nose and toes. That map says *where*
/// light comes through, which is the half that a texture can express. It cannot say
/// *when*, and when is most of the effect — an ear only glows lit from behind, and
/// a glow that is always on is just a lighter ear.
///
/// So the mask is not a texture here. Our ears, nose and pads are already separate
/// meshes with their own materials, so "where" is free, and this supplies the part a
/// map cannot.
///
/// The test is simply whether the light and the viewer are on opposite sides of the
/// part. The player never moves, so that reduces to one dot product per part, and it
/// needs nothing about the part's own orientation — which is just as well, since the
/// ear's own normal points wherever the ear is currently swivelled.
enum Translucency {

    /// How backlit a point is: 1 when the light is directly behind it from the
    /// player's seat, 0 once the light is anywhere in front.
    ///
    /// - Parameter focus: how tightly the effect is concentrated behind the part.
    ///   Transmission through tissue is forward-scattered, so a point source falls
    ///   off much faster than a diffuse term would — an ear goes from lantern to
    ///   ordinary ear within a step or two. A broad source like a lit window is much
    ///   more forgiving, because some part of it is behind the ear over a wide range
    ///   of angles.
    static func backlight(at position: SIMD3<Float>, lightDirection: SIMD3<Float>,
                          focus: Float = 3) -> Float {
        let toCamera = (RoomLayout.cameraPosition - position).normalized
        let aligned = -dot(toCamera, lightDirection.normalized)
        return powf(max(0, aligned), focus)
    }

    /// Recomputes every part's transmitted light. Cheap enough to run per frame:
    /// a handful of parts, one dot product each.
    ///
    /// - Parameter lanternGlow: the paper lantern is close to the floor and warm, so
    ///   it lights ears from behind too whenever the cat walks past it. Not directional
    ///   in the same way, so it contributes a floor rather than a lobe.
    static func apply(_ parts: [TranslucentPart], sky: SkyState, lanternOn: Bool) {
        // The same directions `LightingRig` aims the sun and moon lights along, so
        // an ear can never glow from a sun that is lighting the room from elsewhere.
        let s = sky.sunDirection, m = sky.moonDirection
        let sun = SIMD3<Float>(x: s.x, y: s.y, z: s.z)
        let moon = SIMD3<Float>(x: m.x, y: m.y, z: m.z)

        // Above the horizon or it is not lighting anything.
        let sunUp = max(0, min(1, sky.sunElevation * 6))
        let moonUp = max(0, min(1, sky.moonElevation * 6))

        // How much light there is to transmit, not just which way it points. A cat
        // sitting in a dark room does not have glowing ears.
        let sunPower = sunUp * sky.daylight
        let moonPower = moonUp * (1 - sky.daylight) * 0.06
        let lanternPower: Float = lanternOn ? 0.10 : 0

        for part in parts {
            let p = part.node.simdWorldPosition

            // The window, and it is the main event.
            //
            // Aiming this at the sun alone very nearly made it dead code. The player
            // sits with their back to the north wall looking south at the shoji, and
            // through most of a year at this latitude a southern sun is either too
            // high to be behind anything or off to one side — checked across a whole
            // summer's day and the ears never once lit up.
            //
            // But that is not how a cat by a window works. What is behind the cat is
            // a two-metre panel of lit paper, not a point, and it is behind the cat
            // for the whole day because it is a wall. The sun still contributes its
            // own sharp lobe on top, for the hour or two it lines up.
            let toWindow = (RoomLayout.windowCenter - p).normalized
            // Deliberately conservative. Screenshots are unavailable, midday already
            // measures bright, and emission is added after tone mapping — so an ear
            // that is slightly too subtle costs nothing, while one that is too strong
            // clips and cannot be told apart from a bug. Worth raising once there are
            // eyes on it.
            let windowPower = sky.daylight * 0.50
            let transmitted = backlight(at: p, lightDirection: toWindow, focus: 1.5) * windowPower
                + backlight(at: p, lightDirection: sun) * sunPower
                + backlight(at: p, lightDirection: moon) * moonPower
                + lanternPower
            let level = part.amount * min(1, transmitted)
            part.material.emission.contents = UIColor(part.tint, alpha: 1)
            part.material.emission.intensity = CGFloat(min(0.55, level))
        }
    }
}
