import Foundation
import SwiftUI
import UIKit

/// Codable colour used throughout the save file. Stored in extended sRGB components.
struct RGBColor: Codable, Equatable, Hashable {
    var r: Float
    var g: Float
    var b: Float

    init(_ r: Float, _ g: Float, _ b: Float) {
        self.r = clamp(r); self.g = clamp(g); self.b = clamp(b)
    }

    init(hex: UInt32) {
        self.init(Float((hex >> 16) & 0xFF) / 255,
                  Float((hex >> 8) & 0xFF) / 255,
                  Float(hex & 0xFF) / 255)
    }

    init(uiColor: UIColor) {
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        uiColor.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        self.init(Float(rr), Float(gg), Float(bb))
    }

    var uiColor: UIColor { UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }

    var color: Color { Color(uiColor) }

    /// Perceptual-ish luminance.
    var luminance: Float { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// Short, stable identity for cache keys.
    ///
    /// `TextureFactory.wood`, `.fabric` and `.ceramic` all take a colour *and* a
    /// name, and used to key on the name alone — two calls with the same name and
    /// different colours silently handed back the first one's texture. Nothing in
    /// the room triggers that today, but it is the kind of bug that only appears
    /// once someone adds a second cushion.
    var hexKey: String {
        String(format: "%02X%02X%02X",
               Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    func lightened(_ amount: Float) -> RGBColor {
        RGBColor(mix(r, 1, amount), mix(g, 1, amount), mix(b, 1, amount))
    }

    func darkened(_ amount: Float) -> RGBColor {
        RGBColor(mix(r, 0, amount), mix(g, 0, amount), mix(b, 0, amount))
    }

    func mixed(with other: RGBColor, _ t: Float) -> RGBColor {
        RGBColor(mix(r, other.r, t), mix(g, other.g, t), mix(b, other.b, t))
    }

    /// Slight hue-preserving saturation change.
    func saturated(_ amount: Float) -> RGBColor {
        let l = luminance
        return RGBColor(mix(l, r, 1 + amount), mix(l, g, 1 + amount), mix(l, b, 1 + amount))
    }

    static let white = RGBColor(1, 1, 1)
    static let black = RGBColor(0.06, 0.055, 0.06)
}

extension UIColor {
    convenience init(_ c: RGBColor, alpha: CGFloat = 1) {
        self.init(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: alpha)
    }
}
