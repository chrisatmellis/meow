// Linux typecheck shim mirroring the CoreGraphics API surface the game uses.
// CGFloat / CGPoint / CGRect / CGSize already come from Foundation on Linux.
@_exported import Foundation

public final class CGColor { public init() {} }
public final class CGColorSpace { public init() {} }
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }

public final class CGGradient {
    public init?(colorsSpace space: CGColorSpace?, colors: CFArray, locations: UnsafePointer<CGFloat>?) {}
}

public typealias CFArray = [Any]

public struct CGGradientDrawingOptions: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let drawsBeforeStartLocation = CGGradientDrawingOptions(rawValue: 1)
    public static let drawsAfterEndLocation = CGGradientDrawingOptions(rawValue: 2)
}

public enum CGLineCap: UInt32 { case butt, round, square }
public enum CGBlendMode: Int32 { case normal, multiply, screen, overlay }

public final class CGContext {
    public init() {}
    public func setFillColor(_ color: CGColor) {}
    public func setStrokeColor(_ color: CGColor) {}
    public func setLineWidth(_ width: CGFloat) {}
    public func setLineCap(_ cap: CGLineCap) {}
    public func setBlendMode(_ mode: CGBlendMode) {}
    public func setAlpha(_ alpha: CGFloat) {}

    public func fill(_ rect: CGRect) {}
    public func clear(_ rect: CGRect) {}
    public func fillEllipse(in rect: CGRect) {}
    public func strokeEllipse(in rect: CGRect) {}
    public func addEllipse(in rect: CGRect) {}
    public func stroke(_ rect: CGRect) {}

    public func beginPath() {}
    public func closePath() {}
    public func move(to point: CGPoint) {}
    public func addLine(to point: CGPoint) {}
    public func addCurve(to end: CGPoint, control1: CGPoint, control2: CGPoint) {}
    public func addQuadCurve(to end: CGPoint, control: CGPoint) {}
    public func addRect(_ rect: CGRect) {}
    public func fillPath() {}
    public func strokePath() {}

    public func saveGState() {}
    public func restoreGState() {}
    public func clip() {}
    public func clip(to rect: CGRect) {}
    public func translateBy(x: CGFloat, y: CGFloat) {}
    public func scaleBy(x: CGFloat, y: CGFloat) {}
    public func rotate(by angle: CGFloat) {}

    public func drawLinearGradient(_ gradient: CGGradient, start: CGPoint, end: CGPoint,
                                   options: CGGradientDrawingOptions) {}
    public func drawRadialGradient(_ gradient: CGGradient,
                                   startCenter: CGPoint, startRadius: CGFloat,
                                   endCenter: CGPoint, endRadius: CGFloat,
                                   options: CGGradientDrawingOptions) {}
}
