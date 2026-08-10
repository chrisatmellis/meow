import Foundation
import RealityKit
import UIKit

enum Materials {

    /// - Parameter maps: normal, roughness and occlusion for this surface. Passing
    ///   them replaces the flat `roughness` scalar, which is the whole point — a
    ///   single number cannot say that the raised cords of a tatami mat are polished
    ///   and the gaps between them are not.
    ///
    /// - Parameter tile: how many times the maps repeat across the surface. This is
    ///   one transform on the material rather than one per channel, which removes a
    ///   whole class of bug the SceneKit version had to guard against by hand: there,
    ///   only `diffuse` got the transform at first, so a normal map stretched one
    ///   repeat of the relief across four of the albedo's and the floor lit as
    ///   though the weave ran at a different pitch to the weave you could see.
    static func pbr(diffuse: UIImage? = nil,
                    tint: UIColor = .white,
                    roughness: Float = 0.8,
                    metalness: Float = 0.0,
                    tile: (Float, Float)? = nil,
                    doubleSided: Bool = false,
                    maps: TextureFactory.MapSet? = nil) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: tint, texture: diffuse.flatMap { TextureBridge.tiling($0, semantic: .color) })
        m.roughness = .init(scale: roughness)
        m.metallic = .init(scale: metalness)
        m.faceCulling = doubleSided ? .none : .back

        if let maps {
            // Semantics, not defaults. A normal map read as colour is sRGB-decoded
            // and every slope comes out wrong by the gamma curve, while still
            // looking exactly like a normal map.
            if let n = maps.normal, let t = TextureBridge.tiling(n, semantic: .normal) {
                m.normal = .init(texture: t)
            }
            if let r = maps.roughness, let t = TextureBridge.tiling(r, semantic: .raw) {
                // Scale 1, not `roughness`. RealityKit multiplies the scalar by
                // the texture, where SceneKit replaced one with the other, and the
                // maps are authored as absolute values — `SurfaceMaps` gives each
                // surface its own base and variation. Passing both would quietly
                // polish every mapped surface by whatever its scalar happened to be.
                m.roughness = .init(scale: 1, texture: t)
            }
            if let o = maps.occlusion, let t = TextureBridge.tiling(o, semantic: .raw) {
                m.ambientOcclusion = .init(texture: t)
            }
        }

        if let (u, v) = tile {
            m.textureCoordinateTransform = .init(scale: SIMD2<Float>(u, v))
        }
        return m
    }

    static func pbr(color: RGBColor,
                    roughness: Float = 0.8,
                    metalness: Float = 0.0,
                    doubleSided: Bool = false) -> PhysicallyBasedMaterial {
        pbr(diffuse: nil, tint: UIColor(color), roughness: roughness,
            metalness: metalness, doubleSided: doubleSided)
    }

    // MARK: - The cat

    static func catFur(_ a: CatAppearance, preview: Bool = false) -> PhysicallyBasedMaterial {
        // The baked coat wins when present (see `TextureFactory.catCoatBaked`) —
        // real painted fur instead of the procedural approximation, for the
        // prototype cat. No baked normal/roughness/occlusion maps exist for it yet
        // (that's the high-poly sculpt-and-bake pass in `Tools/usd/TASKS.md`'s
        // longer-term list), so `maps` stays nil on this path: a flat roughness
        // scalar rather than a mismatched procedural relief map.
        let baked = TextureFactory.catCoatBaked
        let tex = baked ?? (preview ? TextureFactory.catCoatPreview(a) : TextureFactory.catCoat(a))
        var m = pbr(diffuse: tex,
                    roughness: a.hairless ? 0.42 : (0.95 - 0.45 * a.furGloss),
                    metalness: 0.0,
                    maps: baked == nil ? TextureFactory.catCoatMaps(a, preview: preview) : nil)
        // Gloss is carried by the coat's roughness map, which varies along each
        // hair, so light rakes across the fur instead of washing the whole cat
        // evenly. The `specular` line this replaced was ignored entirely under
        // physically-based lighting and did nothing at all.
        //
        // Emission starts at zero. It used to be a flat 0.02 over the whole cat,
        // standing in for light coming through thin tissue — which is a real effect
        // in the wrong place: it is strong at the ears, nose and pads and absent
        // over the body, and it only happens when the light is *behind* the cat.
        // `Translucency` drives it per part, per frame, from where the light is.
        m.emissiveColor = .init(color: UIColor(a.baseCoat.mixed(with: RGBColor(1, 0.7, 0.6), 0.5)))
        m.emissiveIntensity = 0
        return m
    }

    /// Semi-transparent shells that give long-haired cats a soft silhouette.
    ///
    /// Three stacked opacity controls in the SceneKit version — a transparency
    /// scalar, a blend mode and a mask whose alpha was read through `.rgbZero` —
    /// collapse into one here, because RealityKit's transparency carries both its
    /// scalar and its mask in a single value. It is not possible to set an opacity
    /// on a material that never became transparent, which is the mistake the old
    /// three-part spelling invited.
    static func furShell(_ a: CatAppearance, layer: Int) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(texture: TextureBridge.tiling(TextureFactory.catCoatPreview(a), semantic: .color))
        m.roughness = .init(scale: 1.0)
        m.metallic = .init(scale: 0.0)
        m.faceCulling = .none
        m.writesDepth = false

        let mask = TextureBridge.tiling(TextureFactory.furShellMask(a), semantic: .raw)
        m.blending = .transparent(opacity: .init(scale: 0.85 - 0.22 * Float(layer), texture: mask))
        // The mask is drawn at a much finer pitch than the coat beneath it, so the
        // hairs it cuts out land between the hairs the coat painted.
        m.secondaryTextureCoordinateTransform = .init(scale: SIMD2<Float>(6, 6))
        return m
    }

    static func eye(_ a: CatAppearance, right: Bool) -> PhysicallyBasedMaterial {
        let color = right && a.heterochromia ? a.eyeColorRight : a.eyeColor
        let tex = TextureFactory.iris(color: color, pupil: a.pupilShape,
                                      dilation: 0.5, brightness: a.eyeBrightness)
        // A real iris is a pleated muscle, and this is where the player is looking.
        // Flat, it reads as a printed disc behind glass.
        var m = pbr(diffuse: tex, roughness: 0.08, maps: TextureFactory.irisMaps())
        m.emissiveColor = .init(color: .white,
                                texture: TextureBridge.tiling(tex, semantic: .color))
        m.emissiveIntensity = 0.06 + 0.22 * a.eyeBrightness
        // The cornea over it. Two scalars, and the single most reads-as-alive
        // detail available: a dry eye is a doll's eye.
        m.clearcoat = .init(scale: 1.0)
        m.clearcoatRoughness = .init(scale: 0.03)
        return m
    }

    /// The inside of the mouth. Dark, wet, and mostly in shadow — what matters is
    /// that it is *not a hole*. The jaw opens for meows, eating, drinking, grooming
    /// and yawns, and behind it was the inside of the skull.
    static func oralCavity(_ color: RGBColor) -> PhysicallyBasedMaterial {
        // Both sides: the cavity is seen from inside, through the gap the jaw opens.
        pbr(color: color.darkened(0.45), roughness: 0.30, doubleSided: true)
    }

    static func tongue(_ color: RGBColor) -> PhysicallyBasedMaterial {
        var m = pbr(diffuse: TextureFactory.tongue(color), roughness: 0.25,
                    maps: TextureFactory.tongueMaps())
        m.clearcoat = .init(scale: 0.7)
        m.clearcoatRoughness = .init(scale: 0.12)
        return m
    }

    static func skin(_ color: RGBColor, gloss: Float = 0.5) -> PhysicallyBasedMaterial {
        pbr(color: color, roughness: 1 - gloss * 0.75)
    }

    /// A cat's nose, and the pads under its toes: wet, and thin enough that light
    /// comes through them.
    static func noseLeather(_ color: RGBColor) -> PhysicallyBasedMaterial {
        var m = pbr(color: color, roughness: 0.22)
        m.clearcoat = .init(scale: 0.85)
        m.clearcoatRoughness = .init(scale: 0.08)
        return m
    }

    static func whisker(_ a: CatAppearance) -> PhysicallyBasedMaterial {
        var m = pbr(color: a.whiskerColor, roughness: 0.35, doubleSided: true)
        m.emissiveColor = .init(color: UIColor(a.whiskerColor))
        m.emissiveIntensity = 0.10
        return m
    }

    // MARK: - Room surfaces

    static func tatami() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.tatami(), roughness: 0.92, tile: (8, 8),
            maps: TextureFactory.tatamiMaps())
    }

    static func tatamiBorder() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.tatamiBorder(), roughness: 0.85, tile: (6, 1),
            maps: TextureFactory.tatamiBorderMaps())
    }

    static func darkWood() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.wood(base: RGBColor(hex: 0x4A3524), key: "dark"),
            roughness: 0.55, tile: (2, 2), maps: TextureFactory.woodMaps(key: "dark"))
    }

    static func lightWood() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.wood(base: RGBColor(hex: 0xB08A5C), key: "light"),
            roughness: 0.62, tile: (2, 2), maps: TextureFactory.woodMaps(key: "light"))
    }

    static func hinoki() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.wood(base: RGBColor(hex: 0xD9C39A), key: "hinoki"),
            roughness: 0.70, tile: (1, 3), maps: TextureFactory.woodMaps(key: "hinoki"))
    }

    static func plaster() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.plaster(), roughness: 0.96, tile: (3, 2),
            maps: TextureFactory.plasterMaps())
    }

    /// Shoji paper: lit from behind, so its emission is driven by the outdoor light.
    static func shoji() -> PhysicallyBasedMaterial {
        var m = pbr(diffuse: TextureFactory.shojiPaper(), roughness: 0.9, tile: (2, 3),
                    doubleSided: true, maps: TextureFactory.shojiMaps())
        m.emissiveColor = .init(color: .white)
        m.emissiveIntensity = 0.15
        return m
    }

    static func futon() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.futonCover(), roughness: 0.95, tile: (2, 3),
            maps: TextureFactory.futonMaps())
    }

    static func linen(_ color: RGBColor, key: String) -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.fabric(color, key: key), roughness: 0.95, tile: (3, 3),
            maps: TextureFactory.fabricMaps(key: key))
    }

    static func sisal() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.sisal(), roughness: 0.98, tile: (2, 6),
            maps: TextureFactory.sisalMaps())
    }

    static func litter() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.litterSubstrate(), roughness: 1.0, tile: (2, 2),
            maps: TextureFactory.litterMaps())
    }

    static func scroll() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.inkScroll(), roughness: 0.85)
    }

    static func ceramic(_ color: RGBColor, key: String) -> PhysicallyBasedMaterial {
        var m = pbr(diffuse: TextureFactory.ceramic(color, key: key), roughness: 0.18)
        // Glaze, which is what makes a teacup read as fired rather than moulded.
        m.clearcoat = .init(scale: 0.6)
        m.clearcoatRoughness = .init(scale: 0.06)
        return m
    }

    static func plastic(_ color: RGBColor) -> PhysicallyBasedMaterial {
        pbr(color: color, roughness: 0.35)
    }

    static func metal(_ color: RGBColor, roughness: Float = 0.25) -> PhysicallyBasedMaterial {
        pbr(color: color, roughness: roughness, metalness: 0.95)
    }

    static func water() -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 0.62, green: 0.76, blue: 0.84, alpha: 1))
        m.roughness = .init(scale: 0.03)
        m.metallic = .init(scale: 0.0)
        m.blending = .transparent(opacity: .init(scale: 0.25))
        return m
    }

    static func foliage() -> PhysicallyBasedMaterial {
        pbr(diffuse: TextureFactory.foliage(), roughness: 0.75, tile: (2, 2), doubleSided: true)
    }

    static func lanternPaper() -> PhysicallyBasedMaterial {
        var m = pbr(diffuse: TextureFactory.shojiPaper(), roughness: 0.9,
                    doubleSided: true, maps: TextureFactory.shojiMaps())
        m.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1))
        m.emissiveIntensity = 0.0
        return m
    }

    /// The garden beyond the window.
    ///
    /// Carried on emission rather than base colour so it can exceed 1. Outdoors is
    /// something like fifty times brighter than a room lit through a window, and
    /// an 8-bit texture cannot say that — as a plain diffuse colour the night sky
    /// rendered *brighter* than the day sky, because the texture only darkens by
    /// about ten while exposure was swinging the other way by far more. As HDR
    /// emission, `LightingRig` can scale it by the actual daylight, so the view
    /// blows out at noon the way a real window does and goes properly black at
    /// night.
    static func backdrop(sky: SkyState) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .black)
        m.roughness = .init(scale: 1)
        m.metallic = .init(scale: 0)
        m.faceCulling = .none
        m.emissiveColor = gardenEmission(sky: sky)
        m.emissiveIntensity = 1        // LightingRig drives this from the sky.
        return m
    }

    /// The garden, as an emissive colour.
    ///
    /// Tinted by the sky rather than by white, which matters when the texture
    /// fails to upload. `EmissiveColor(color:texture:)` multiplies the two, so a
    /// white tint with a missing texture is a *white emissive panel* — a flat grey
    /// card exactly the size of the window, unaffected by any light in the room,
    /// which is precisely what a window with nothing behind it looks like and
    /// precisely what was there. Tinted by the sky it degrades to the sky's own
    /// colour instead: still wrong, but wrong in a way that reads as sky.
    static func gardenEmission(sky: SkyState) -> PhysicallyBasedMaterial.EmissiveColor {
        .init(color: UIColor(sky.skyHorizonColor.mixed(with: sky.skyZenithColor, 0.4)),
              texture: TextureBridge.tiling(TextureFactory.gardenBackdrop(sky: sky),
                                            semantic: .color))
    }
}
