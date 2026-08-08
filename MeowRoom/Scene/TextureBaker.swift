import Foundation
import CoreGraphics
import UIKit

/// Turns a baked `[UInt8]` map into an image.
///
/// The colour textures are *drawn*, so they come out of a `CGContext`. The
/// material maps are *computed* — there is nothing to draw them with — so they go
/// straight from bytes to a `CGImage` and skip the drawing machinery entirely.
enum TextureBaker {

    /// - Parameter rgba: `size * size * 4` bytes, row-major from the top.
    ///
    /// The alpha byte is skipped rather than read. Every map here is opaque, and
    /// declaring `premultipliedLast` on data that was never premultiplied is a
    /// classic way to get a normal map that darkens toward its edges.
    ///
    /// Colour management is deliberately left to the material: a normal map must
    /// not be sRGB-decoded, and the renderer's texture semantic is the only place
    /// that knows whether it is about to be used as colour or as data. In
    /// RealityKit that is `TextureResource.CreateOptions(semantic:)` — `.normal`
    /// for the normal map, `.raw` for roughness and occlusion.
    static func image(rgba: [UInt8], size: Int) -> UIImage? {
        guard size > 0, rgba.count >= size * size * 4 else { return nil }
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        guard let cg = CGImage(width: size,
                               height: size,
                               bitsPerComponent: 8,
                               bitsPerPixel: 32,
                               bytesPerRow: size * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
