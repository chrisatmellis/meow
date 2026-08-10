// Linux typecheck shim mirroring the UIKit API surface the game uses.
@_exported import Foundation
@_exported import CoreGraphics

/// Not present in Linux Foundation; the game only ever passes #selector-shaped values.
public struct Selector: Hashable, ExpressibleByStringLiteral {
    public let name: String
    public init(stringLiteral value: String) { name = value }
    public init(_ name: String) { self.name = name }
}

open class UIColor {
    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {}
    public init(white: CGFloat, alpha: CGFloat) {}
    public init(hue: CGFloat, saturation: CGFloat, brightness: CGFloat, alpha: CGFloat) {}

    open var cgColor: CGColor { CGColor() }

    @discardableResult
    open func getRed(_ red: UnsafeMutablePointer<CGFloat>,
                     green: UnsafeMutablePointer<CGFloat>,
                     blue: UnsafeMutablePointer<CGFloat>,
                     alpha: UnsafeMutablePointer<CGFloat>) -> Bool { true }

    public static let black = UIColor(white: 0, alpha: 1)
    public static let white = UIColor(white: 1, alpha: 1)
    public static let clear = UIColor(white: 0, alpha: 0)
    public static let red = UIColor(white: 0, alpha: 1)
}

open class UIImage {
    private let backing: CGImage?
    public init() { backing = nil }
    public init(cgImage: CGImage) { backing = cgImage }

    /// Failable, because UIKit's is.
    ///
    /// The optionality is the whole point rather than a detail. A non-failable
    /// version here infers `() -> UIImage` for a caller's decoding closure, and
    /// its `guard ... else { return nil }` then fails to typecheck — a shim gap
    /// reported as an error in application code that is perfectly correct.
    public init?(data: Data) {
        guard !data.isEmpty else { return nil }
        backing = CGImage()
    }

    open var cgImage: CGImage? { backing ?? CGImage() }
}

open class UIGraphicsImageRendererFormat {
    open var scale: CGFloat = 1
    open var opaque: Bool = false
    open var preferredRange: Int = 0
    public init() {}
    open class func `default`() -> UIGraphicsImageRendererFormat { UIGraphicsImageRendererFormat() }
}

open class UIGraphicsImageRendererContext {
    open var cgContext: CGContext { CGContext() }
}

open class UIGraphicsImageRenderer {
    public init(size: CGSize, format: UIGraphicsImageRendererFormat) {}
    public init(size: CGSize) {}
    open func image(actions: (UIGraphicsImageRendererContext) -> Void) -> UIImage {
        actions(UIGraphicsImageRendererContext())
        return UIImage()
    }
}

// MARK: - Views & gestures

open class UIResponder: NSObject {}

open class UIView: UIResponder {
    open var backgroundColor: UIColor?
    open var isUserInteractionEnabled: Bool = true
    open var bounds: CGRect = .zero
    open var frame: CGRect = .zero
    open func addGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {}
    public override init() { super.init() }
}

open class UIGestureRecognizer: NSObject {
    public enum State: Int {
        case possible, began, changed, ended, cancelled, failed
        public static var recognized: State { .ended }
    }
    open var state: State = .possible
    public init(target: Any?, action: Selector?) {}
    open func location(in view: UIView?) -> CGPoint { .zero }
}

open class UITapGestureRecognizer: UIGestureRecognizer {
    open var numberOfTapsRequired: Int = 1
}

open class UIPanGestureRecognizer: UIGestureRecognizer {
    open var maximumNumberOfTouches: Int = .max
    open var minimumNumberOfTouches: Int = 1
    open func translation(in view: UIView?) -> CGPoint { .zero }
    open func velocity(in view: UIView?) -> CGPoint { .zero }
}

open class UIImpactFeedbackGenerator: NSObject {
    public enum FeedbackStyle: Int { case light, medium, heavy, soft, rigid }
    public init(style: FeedbackStyle) {}
    open func prepare() {}
    open func impactOccurred() {}
    open func impactOccurred(intensity: CGFloat) {}
}

open class UINotificationFeedbackGenerator: NSObject {
    public enum FeedbackType: Int { case success, warning, error }
    public override init() {}
    open func prepare() {}
    open func notificationOccurred(_ type: FeedbackType) {}
}

open class UISelectionFeedbackGenerator: NSObject {
    public override init() {}
    open func prepare() {}
    open func selectionChanged() {}
}
