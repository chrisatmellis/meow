import Foundation
import SceneKit
import UIKit

enum Materials {

    static func pbr(diffuse: Any,
                    roughness: Float = 0.8,
                    metalness: Float = 0.0,
                    tile: (Float, Float)? = nil,
                    doubleSided: Bool = false) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = diffuse
        m.roughness.contents = NSNumber(value: roughness)
        m.metalness.contents = NSNumber(value: metalness)
        m.isDoubleSided = doubleSided
        if let (u, v) = tile {
            for prop in [m.diffuse, m.roughness, m.metalness, m.emission, m.normal] {
                prop.wrapS = .repeat
                prop.wrapT = .repeat
            }
            m.diffuse.contentsTransform = SCNMatrix4MakeScale(u, v, 1)
        }
        return m
    }

    // MARK: - The cat

    static func catFur(_ a: CatAppearance, preview: Bool = false) -> SCNMaterial {
        let tex = preview ? TextureFactory.catCoatPreview(a) : TextureFactory.catCoat(a)
        let m = pbr(diffuse: tex,
                    roughness: a.hairless ? 0.42 : (0.95 - 0.45 * a.furGloss),
                    metalness: 0.0)
        // A hint of sheen so light rakes across the coat.
        m.specular.contents = UIColor(white: CGFloat(0.15 + 0.35 * a.furGloss), alpha: 1)
        // Warm sub-surface-ish bounce on thin fur, especially on the ears.
        m.emission.contents = UIColor(a.baseCoat.mixed(with: RGBColor(1, 0.7, 0.6), 0.5), alpha: 1)
        m.emission.intensity = CGFloat(a.hairless ? 0.035 : 0.02)
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        return m
    }

    /// Semi-transparent shells that give long-haired cats a soft silhouette.
    static func furShell(_ a: CatAppearance, layer: Int) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = TextureFactory.catCoatPreview(a)
        m.transparent.contents = TextureFactory.furShellMask(a)
        m.transparencyMode = .rgbZero
        m.transparency = CGFloat(0.85 - 0.22 * Float(layer))
        m.roughness.contents = NSNumber(value: 1.0)
        m.metalness.contents = NSNumber(value: 0.0)
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = true
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.transparent.wrapS = .repeat
        m.transparent.wrapT = .repeat
        m.transparent.contentsTransform = SCNMatrix4MakeScale(6, 6, 1)
        return m
    }

    static func eye(_ a: CatAppearance, right: Bool) -> SCNMaterial {
        let color = right && a.heterochromia ? a.eyeColorRight : a.eyeColor
        let tex = TextureFactory.iris(color: color, pupil: a.pupilShape,
                                      dilation: 0.5, brightness: a.eyeBrightness)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = tex
        m.roughness.contents = NSNumber(value: 0.08)
        m.metalness.contents = NSNumber(value: 0.0)
        m.emission.contents = tex
        m.emission.intensity = CGFloat(0.06 + 0.22 * a.eyeBrightness)
        return m
    }

    static func skin(_ color: RGBColor, gloss: Float = 0.5) -> SCNMaterial {
        pbr(diffuse: UIColor(color), roughness: 1 - gloss * 0.75, metalness: 0)
    }

    static func whisker(_ a: CatAppearance) -> SCNMaterial {
        let m = pbr(diffuse: UIColor(a.whiskerColor), roughness: 0.35, metalness: 0)
        m.emission.contents = UIColor(a.whiskerColor, alpha: 1)
        m.emission.intensity = 0.10
        m.isDoubleSided = true
        return m
    }

    // MARK: - Room surfaces

    static func tatami() -> SCNMaterial {
        pbr(diffuse: TextureFactory.tatami(), roughness: 0.92, metalness: 0, tile: (4, 4))
    }

    static func tatamiBorder() -> SCNMaterial {
        pbr(diffuse: TextureFactory.tatamiBorder(), roughness: 0.85, metalness: 0, tile: (6, 1))
    }

    static func darkWood() -> SCNMaterial {
        pbr(diffuse: TextureFactory.wood(base: RGBColor(hex: 0x4A3524), key: "dark"),
            roughness: 0.55, metalness: 0, tile: (2, 2))
    }

    static func lightWood() -> SCNMaterial {
        pbr(diffuse: TextureFactory.wood(base: RGBColor(hex: 0xB08A5C), key: "light"),
            roughness: 0.62, metalness: 0, tile: (2, 2))
    }

    static func hinoki() -> SCNMaterial {
        pbr(diffuse: TextureFactory.wood(base: RGBColor(hex: 0xD9C39A), key: "hinoki"),
            roughness: 0.70, metalness: 0, tile: (1, 3))
    }

    static func plaster() -> SCNMaterial {
        pbr(diffuse: TextureFactory.plaster(), roughness: 0.96, metalness: 0, tile: (3, 2))
    }

    /// Shoji paper: lit from behind, so its emission is driven by the outdoor light.
    static func shoji() -> SCNMaterial {
        let m = pbr(diffuse: TextureFactory.shojiPaper(), roughness: 0.9, metalness: 0, tile: (2, 3))
        m.emission.contents = UIColor(white: 1, alpha: 1)
        m.emission.intensity = 0.15
        m.isDoubleSided = true
        return m
    }

    static func futon() -> SCNMaterial {
        pbr(diffuse: TextureFactory.futonCover(), roughness: 0.95, metalness: 0, tile: (2, 3))
    }

    static func linen(_ color: RGBColor, key: String) -> SCNMaterial {
        pbr(diffuse: TextureFactory.fabric(color, key: key), roughness: 0.95, metalness: 0, tile: (3, 3))
    }

    static func sisal() -> SCNMaterial {
        pbr(diffuse: TextureFactory.sisal(), roughness: 0.98, metalness: 0, tile: (2, 6))
    }

    static func litter() -> SCNMaterial {
        pbr(diffuse: TextureFactory.litterSubstrate(), roughness: 1.0, metalness: 0, tile: (2, 2))
    }

    static func scroll() -> SCNMaterial {
        pbr(diffuse: TextureFactory.inkScroll(), roughness: 0.85, metalness: 0)
    }

    static func ceramic(_ color: RGBColor, key: String) -> SCNMaterial {
        pbr(diffuse: TextureFactory.ceramic(color, key: key), roughness: 0.18, metalness: 0.0)
    }

    static func plastic(_ color: RGBColor) -> SCNMaterial {
        pbr(diffuse: UIColor(color), roughness: 0.35, metalness: 0.0)
    }

    static func metal(_ color: RGBColor, roughness: Float = 0.25) -> SCNMaterial {
        pbr(diffuse: UIColor(color), roughness: roughness, metalness: 0.95)
    }

    static func water() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = UIColor(red: 0.62, green: 0.76, blue: 0.84, alpha: 1)
        m.roughness.contents = NSNumber(value: 0.03)
        m.metalness.contents = NSNumber(value: 0.0)
        m.transparency = 0.75
        m.blendMode = .alpha
        return m
    }

    static func foliage() -> SCNMaterial {
        let m = pbr(diffuse: TextureFactory.foliage(), roughness: 0.75, metalness: 0, tile: (2, 2))
        m.isDoubleSided = true
        return m
    }

    static func lanternPaper() -> SCNMaterial {
        let m = pbr(diffuse: TextureFactory.shojiPaper(), roughness: 0.9, metalness: 0)
        m.emission.contents = UIColor(red: 1.0, green: 0.86, blue: 0.62, alpha: 1)
        m.emission.intensity = 0.0
        m.isDoubleSided = true
        return m
    }

    /// The garden seen through the window. Unlit so it reads as "outside".
    static func backdrop(sky: SkyState) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = TextureFactory.gardenBackdrop(sky: sky)
        m.isDoubleSided = true
        return m
    }
}
