// Linux typecheck shim mirroring the SwiftUI API surface the game uses.
// Modifiers all return `self`; the point is to check *our* symbols, bindings and
// view-builder arity, not to reimplement SwiftUI's layout system.
@_exported import Foundation
@_exported import CoreGraphics
@_exported import UIKit

// MARK: - Combine stand-ins (Combine is unavailable on Linux)

public protocol ObservableObject: AnyObject {
    var objectWillChange: ObservableObjectPublisherShim { get }
}

public final class ObservableObjectPublisherShim {
    public init() {}
    public func send() {}
}

private var _publishers = [ObjectIdentifier: ObservableObjectPublisherShim]()

extension ObservableObject {
    public var objectWillChange: ObservableObjectPublisherShim {
        let key = ObjectIdentifier(self)
        if let p = _publishers[key] { return p }
        let p = ObservableObjectPublisherShim()
        _publishers[key] = p
        return p
    }
}

@propertyWrapper
public struct Published<Value> {
    public var wrappedValue: Value
    public init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
    public init(initialValue: Value) { self.wrappedValue = initialValue }
    public var projectedValue: PublishedShim<Value> { PublishedShim() }
}

public struct PublishedShim<Value> {}

// MARK: - View & builder

public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

public struct EmptyView: View {
    public init() {}
    public var body: Never { fatalError() }
}


public struct AnyView: View {
    public init<V: View>(_ view: V) {}
    public var body: Never { fatalError() }
}

public struct TupleView<T>: View {
    public var body: Never { fatalError() }
}

public struct _ConditionalContent<T, F>: View {
    public var body: Never { fatalError() }
}

public struct Optionalish<T>: View {
    public var body: Never { fatalError() }
}

@resultBuilder
public enum ViewBuilder {
    public static func buildBlock() -> EmptyView { EmptyView() }
    public static func buildBlock<C0: View>(_ c0: C0) -> C0 { c0 }
    public static func buildBlock<C0: View, C1: View>(_ c0: C0, _ c1: C1) -> TupleView<(C0, C1)> { TupleView() }
    public static func buildBlock<C0: View, C1: View, C2: View>(_ c0: C0, _ c1: C1, _ c2: C2) -> TupleView<(C0, C1, C2)> { TupleView() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3) -> TupleView<(C0, C1, C2, C3)> { TupleView() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4) -> TupleView<(C0, C1, C2, C3, C4)> { TupleView() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5) -> TupleView<(C0, C1, C2, C3, C4, C5)> { TupleView() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6) -> TupleView<(C0, C1, C2, C3, C4, C5, C6)> { TupleView() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7)> { TupleView() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8)> { TupleView() }
    public static func buildBlock<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View, C6: View, C7: View, C8: View, C9: View>(_ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5, _ c6: C6, _ c7: C7, _ c8: C8, _ c9: C9) -> TupleView<(C0, C1, C2, C3, C4, C5, C6, C7, C8, C9)> { TupleView() }

    public static func buildIf<C: View>(_ content: C?) -> C? { content }
    public static func buildOptional<C: View>(_ content: C?) -> C? { content }
    public static func buildEither<T: View, F: View>(first: T) -> _ConditionalContent<T, F> { _ConditionalContent() }
    public static func buildEither<T: View, F: View>(second: F) -> _ConditionalContent<T, F> { _ConditionalContent() }
    public static func buildLimitedAvailability<C: View>(_ content: C) -> C { content }
    public static func buildExpression<C: View>(_ expression: C) -> C { expression }
}

extension Optional: View where Wrapped: View {
    public var body: Never { fatalError() }
}

// MARK: - Property wrappers

@propertyWrapper
public struct State<Value> {
    private final class Box { var value: Value; init(_ v: Value) { value = v } }
    private let box: Box
    public init(wrappedValue: Value) { box = Box(wrappedValue) }
    public init(initialValue: Value) { box = Box(initialValue) }
    public var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    public var projectedValue: Binding<Value> {
        Binding(get: { box.value }, set: { box.value = $0 })
    }
}

@propertyWrapper
@dynamicMemberLookup
public struct Binding<Value> {
    private let getter: () -> Value
    private let setter: (Value) -> Void
    public init(get: @escaping () -> Value, set: @escaping (Value) -> Void) {
        getter = get; setter = set
    }
    public var wrappedValue: Value {
        get { getter() }
        nonmutating set { setter(newValue) }
    }
    public var projectedValue: Binding<Value> { self }
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }
}

extension Binding {
    public subscript<Subject>(dynamicMember keyPath: WritableKeyPath<Value, Subject>) -> Binding<Subject> {
        Binding<Subject>(get: { self.wrappedValue[keyPath: keyPath] },
                         set: { newValue in
                             var copy = self.wrappedValue
                             copy[keyPath: keyPath] = newValue
                             self.wrappedValue = copy
                         })
    }
}

@propertyWrapper
public struct StateObject<ObjectType: ObservableObject> {
    private final class Box { var value: ObjectType?; init() {} }
    private let box = Box()
    private let make: () -> ObjectType
    public init(wrappedValue: @autoclosure @escaping () -> ObjectType) { make = wrappedValue }
    public var wrappedValue: ObjectType {
        if let v = box.value { return v }
        let v = make(); box.value = v; return v
    }
    public var projectedValue: ObservedObject<ObjectType>.Wrapper {
        ObservedObject.Wrapper(object: wrappedValue)
    }
}

@propertyWrapper
public struct ObservedObject<ObjectType: ObservableObject> {
    public var wrappedValue: ObjectType
    public init(wrappedValue: ObjectType) { self.wrappedValue = wrappedValue }
    @dynamicMemberLookup
    public struct Wrapper {
        let object: ObjectType
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
        }
    }
    public var projectedValue: Wrapper { Wrapper(object: wrappedValue) }
}

@propertyWrapper
public struct EnvironmentObject<ObjectType: ObservableObject> {
    private final class Box { var value: ObjectType? }
    private let box = Box()
    public init() {}
    public var wrappedValue: ObjectType { box.value! }
    @dynamicMemberLookup
    public struct Wrapper {
        let object: ObjectType?
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<ObjectType, Subject>) -> Binding<Subject> {
            Binding(get: { object![keyPath: keyPath] }, set: { object![keyPath: keyPath] = $0 })
        }
    }
    public var projectedValue: Wrapper { Wrapper(object: box.value) }
}

@propertyWrapper
public struct Environment<Value> {
    private let key: KeyPath<EnvironmentValues, Value>
    public init(_ keyPath: KeyPath<EnvironmentValues, Value>) { key = keyPath }
    public var wrappedValue: Value { EnvironmentValues()[keyPath: key] }
}

public struct DismissAction {
    public func callAsFunction() {}
}

public enum ScenePhase: Int { case background, inactive, active }

public struct EnvironmentValues {
    public init() {}
    public var dismiss: DismissAction { DismissAction() }
    public var scenePhase: ScenePhase { .active }
    public var colorScheme: ColorScheme { .dark }
    public var openURL: OpenURLActionShim { OpenURLActionShim() }
}

public struct OpenURLActionShim {
    public func callAsFunction(_ url: URL) {}
}

public enum ColorScheme: Int { case light, dark }

// MARK: - Colors, shapes, styles

public protocol ShapeStyle {}
public protocol Shape: View, ShapeStyle {}
extension Shape {
    public var body: Never { fatalError() }
}

public struct Color: View, ShapeStyle, Equatable, Hashable {
    public var body: Never { fatalError() }
    public init(_ uiColor: UIColor) {}
    public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {}
    public init(white: Double, opacity: Double = 1) {}
    public static let clear = Color(white: 0)
    public static let black = Color(white: 0)
    public static let white = Color(white: 1)
    public static let red = Color(white: 0)
    public static let orange = Color(white: 0)
    public static let yellow = Color(white: 0)
    public static let green = Color(white: 0)
    public static let blue = Color(white: 0)
    public static let pink = Color(white: 0)
    public static let purple = Color(white: 0)
    public static let gray = Color(white: 0)
    public static let accentColor = Color(white: 0)
    public static let primary = Color(white: 0)
    public static let secondary = Color(white: 0)
    public static let tertiary = Color(white: 0)
    public static let quaternary = Color(white: 0)
    public func opacity(_ o: Double) -> Color { self }
}

public struct HierarchicalShapeStyle: ShapeStyle {
    public static let primary = HierarchicalShapeStyle()
    public static let secondary = HierarchicalShapeStyle()
    public static let tertiary = HierarchicalShapeStyle()
    public static let quaternary = HierarchicalShapeStyle()
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
    public static var primary: HierarchicalShapeStyle { .primary }
    public static var secondary: HierarchicalShapeStyle { .secondary }
    public static var tertiary: HierarchicalShapeStyle { .tertiary }
    public static var quaternary: HierarchicalShapeStyle { .quaternary }
}

extension ShapeStyle where Self == Color {
    public static var clear: Color { Color.clear }
    public static var black: Color { Color.black }
    public static var white: Color { Color.white }
    public static var red: Color { Color.red }
    public static var orange: Color { Color.orange }
    public static var yellow: Color { Color.yellow }
    public static var green: Color { Color.green }
    public static var blue: Color { Color.blue }
    public static var pink: Color { Color.pink }
    public static var purple: Color { Color.purple }
    public static var gray: Color { Color.gray }
    public static var accentColor: Color { Color.accentColor }
}

extension ShapeStyle where Self == Material {
    public static var ultraThinMaterial: Material { Material.ultraThinMaterial }
    public static var thinMaterial: Material { Material.thinMaterial }
    public static var regularMaterial: Material { Material.regularMaterial }
    public static var thickMaterial: Material { Material.thickMaterial }
    public static var bar: Material { Material.bar }
}

public struct Material: ShapeStyle {
    public static let ultraThinMaterial = Material()
    public static let thinMaterial = Material()
    public static let regularMaterial = Material()
    public static let thickMaterial = Material()
    public static let bar = Material()
}

public struct LinearGradient: View, ShapeStyle {
    public var body: Never { fatalError() }
    public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {}
    public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {}
}

public struct RadialGradient: View, ShapeStyle {
    public var body: Never { fatalError() }
    public init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {}
}

public struct Gradient {
    public init(colors: [Color]) {}
}

public struct UnitPoint {
    public static let top = UnitPoint()
    public static let bottom = UnitPoint()
    public static let leading = UnitPoint()
    public static let trailing = UnitPoint()
    public static let center = UnitPoint()
    public static let topLeading = UnitPoint()
    public static let bottomTrailing = UnitPoint()
}

public struct Circle: Shape { public init() {} }
public struct Capsule: Shape { public init(style: RoundedCornerStyle = .circular) {} }
public struct Rectangle: Shape { public init() {} }
public struct RoundedRectangle: Shape {
    public init(cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {}
}
public enum RoundedCornerStyle { case circular, continuous }

extension Shape {
    public func fill<S: ShapeStyle>(_ style: S) -> some View { self }
    public func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> some View { self }
    public func strokeBorder<S: ShapeStyle>(_ style: S, lineWidth: CGFloat = 1) -> some View { self }
    public func inset(by amount: CGFloat) -> some Shape { self }
}

// MARK: - Text & images

public struct Text: View {
    public var body: Never { fatalError() }
    public init(_ content: String) {}
    public init<S: StringProtocol>(_ content: S) {}
    public init(_ date: Date, style: DateStyleShim) {}
    public func font(_ f: Font?) -> Text { self }
    public func foregroundColor(_ c: Color?) -> Text { self }
    public func bold() -> Text { self }
    public static func + (lhs: Text, rhs: Text) -> Text { lhs }
}

public struct DateStyleShim { public static let time = DateStyleShim() }

public struct Image: View {
    public var body: Never { fatalError() }
    public init(systemName: String) {}
    public init(uiImage: UIImage) {}
    public func resizable() -> Image { self }
    public func renderingMode(_ m: Int) -> Image { self }
}

public struct Label<Title, Icon>: View {
    public var body: Never { fatalError() }
}
extension Label where Title == Text, Icon == Image {
    public init(_ title: String, systemImage: String) {}
}

public struct Font {
    public static let largeTitle = Font()
    public static let title = Font()
    public static let title2 = Font()
    public static let title3 = Font()
    public static let headline = Font()
    public static let subheadline = Font()
    public static let body = Font()
    public static let callout = Font()
    public static let footnote = Font()
    public static let caption = Font()
    public static let caption2 = Font()
    public static func system(size: CGFloat, weight: FontWeight = .regular) -> Font { Font() }
    public func weight(_ w: FontWeight) -> Font { self }
    public func monospacedDigit() -> Font { self }
    public var bold: Font { self }
    public var semibold: Font { self }
    public var medium: Font { self }
}

public struct FontWeight {
    public static let regular = FontWeight()
    public static let medium = FontWeight()
    public static let semibold = FontWeight()
    public static let bold = FontWeight()
    public static let heavy = FontWeight()
    public static let light = FontWeight()
}

// MARK: - Layout containers

public struct HStack<Content: View>: View {
    public var body: Never { fatalError() }
    public init(alignment: VerticalAlignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {}
}

public struct VStack<Content: View>: View {
    public var body: Never { fatalError() }
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {}
}

public struct ZStack<Content: View>: View {
    public var body: Never { fatalError() }
    public init(alignment: Alignment = .center, @ViewBuilder content: () -> Content) {}
}

public struct LazyVStack<Content: View>: View {
    public var body: Never { fatalError() }
    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: () -> Content) {}
}

public struct LazyVGrid<Content: View>: View {
    public var body: Never { fatalError() }
    public init(columns: [GridItem], alignment: HorizontalAlignment = .center,
                spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {}
}

public struct GridItem {
    public enum Size { case flexible(minimum: CGFloat = 10, maximum: CGFloat = .infinity)
                       case fixed(CGFloat)
                       case adaptive(minimum: CGFloat, maximum: CGFloat = .infinity) }
    public init(_ size: Size = .flexible(), spacing: CGFloat? = nil, alignment: Alignment? = nil) {}
    public static var flexible: Size { .flexible() }
}

public struct ScrollView<Content: View>: View {
    public var body: Never { fatalError() }
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true,
                @ViewBuilder content: () -> Content) {}
}

public enum Axis {
    public struct Set: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let horizontal = Set(rawValue: 1)
        public static let vertical = Set(rawValue: 2)
    }
}

public struct Spacer: View {
    public var body: Never { fatalError() }
    public init(minLength: CGFloat? = nil) {}
}

public struct Divider: View {
    public var body: Never { fatalError() }
    public init() {}
}

public struct Group<Content: View>: View {
    public var body: Never { fatalError() }
    public init(@ViewBuilder content: () -> Content) {}
}

public struct GeometryProxy {
    public var size: CGSize { .zero }
    public var safeAreaInsets: EdgeInsetsShim { EdgeInsetsShim() }
}
public struct EdgeInsetsShim { public var top: CGFloat = 0; public var bottom: CGFloat = 0 }

public struct GeometryReader<Content: View>: View {
    public var body: Never { fatalError() }
    public init(@ViewBuilder content: @escaping (GeometryProxy) -> Content) {}
}

public struct ForEach<Data, ID, Content: View>: View {
    public var body: Never { fatalError() }
}

extension ForEach where Data: RandomAccessCollection, Content: View, Data.Element: Identifiable, ID == Data.Element.ID {
    public init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}
extension ForEach where Data: RandomAccessCollection, Content: View, ID: Hashable {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {}
}

public struct VerticalAlignment { public static let top = VerticalAlignment(); public static let center = VerticalAlignment(); public static let bottom = VerticalAlignment(); public static let firstTextBaseline = VerticalAlignment() }
public struct HorizontalAlignment { public static let leading = HorizontalAlignment(); public static let center = HorizontalAlignment(); public static let trailing = HorizontalAlignment() }
public struct Alignment {
    public static let center = Alignment()
    public static let top = Alignment()
    public static let bottom = Alignment()
    public static let leading = Alignment()
    public static let trailing = Alignment()
    public static let topLeading = Alignment()
    public static let topTrailing = Alignment()
    public static let bottomLeading = Alignment()
    public static let bottomTrailing = Alignment()
}
public struct TextAlignment { public static let leading = TextAlignment(); public static let center = TextAlignment(); public static let trailing = TextAlignment() }
public struct Edge {
    public struct Set: OptionSet {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let top = Set(rawValue: 1)
        public static let bottom = Set(rawValue: 2)
        public static let leading = Set(rawValue: 4)
        public static let trailing = Set(rawValue: 8)
        public static let all = Set(rawValue: 15)
        public static let horizontal = Set(rawValue: 12)
        public static let vertical = Set(rawValue: 3)
    }
    public static let top = Edge()
    public static let bottom = Edge()
    public static let leading = Edge()
    public static let trailing = Edge()
}

// MARK: - Controls

public struct Button<Label: View>: View {
    public var body: Never { fatalError() }
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {}
}
extension Button where Label == Text {
    public init(_ title: String, action: @escaping () -> Void) {}
    public init(_ title: String, role: ButtonRole?, action: @escaping () -> Void) {}
}

public struct ButtonRole { public static let destructive = ButtonRole(); public static let cancel = ButtonRole() }

public struct ButtonStyleShim {
    public static let plain = ButtonStyleShim()
    public static let bordered = ButtonStyleShim()
    public static let borderedProminent = ButtonStyleShim()
    public static let borderless = ButtonStyleShim()
    public static let automatic = ButtonStyleShim()
}

public struct Toggle<Label: View>: View {
    public var body: Never { fatalError() }
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {}
}
extension Toggle where Label == Text {
    public init(_ title: String, isOn: Binding<Bool>) {}
}

public struct Slider<Label: View, ValueLabel: View>: View {
    public var body: Never { fatalError() }
}
extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>) where V.Stride: BinaryFloatingPoint {}
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride) where V.Stride: BinaryFloatingPoint {}
}

public struct TextField<Label: View>: View {
    public var body: Never { fatalError() }
}
extension TextField where Label == Text {
    public init(_ title: String, text: Binding<String>) {}
}

public struct TextFieldStyleShim {
    public static let roundedBorder = TextFieldStyleShim()
    public static let plain = TextFieldStyleShim()
}

public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    public var body: Never { fatalError() }
}
extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    public init() {}
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {}
}

public struct ColorPicker<Label: View>: View {
    public var body: Never { fatalError() }
}
extension ColorPicker where Label == Text {
    public init(_ title: String, selection: Binding<Color>, supportsOpacity: Bool = true) {}
}

public struct LabeledContent<Label: View, Content: View>: View {
    public var body: Never { fatalError() }
}
extension LabeledContent where Label == Text, Content == Text {
    public init(_ title: String, value: String) {}
}

public struct Form<Content: View>: View {
    public var body: Never { fatalError() }
    public init(@ViewBuilder content: () -> Content) {}
}

public struct Section<Parent, Content, Footer>: View {
    public var body: Never { fatalError() }
}
extension Section where Parent == Text, Content: View, Footer == EmptyView {
    public init(_ title: String, @ViewBuilder content: () -> Content) {}
}
extension Section where Parent == EmptyView, Content: View, Footer == EmptyView {
    public init(@ViewBuilder content: () -> Content) {}
}

public struct NavigationStack<Data, Root: View>: View {
    public var body: Never { fatalError() }
}
extension NavigationStack where Data == Never {
    public init(@ViewBuilder root: () -> Root) {}
}

public struct ToolbarItem<ID, Content: View>: View {
    public var body: Never { fatalError() }
}
extension ToolbarItem where ID == Void {
    public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {}
}
public struct ToolbarItemPlacement {
    public static let automatic = ToolbarItemPlacement()
    public static let confirmationAction = ToolbarItemPlacement()
    public static let cancellationAction = ToolbarItemPlacement()
    public static let topBarTrailing = ToolbarItemPlacement()
}

public struct NavigationBarItemShim {
    public struct TitleDisplayMode {
        public static let inline = TitleDisplayMode()
        public static let large = TitleDisplayMode()
        public static let automatic = TitleDisplayMode()
    }
}

public struct PresentationDetent: Hashable {
    private let id: String
    public static let medium = PresentationDetent(id: "medium")
    public static let large = PresentationDetent(id: "large")
    public static func height(_ h: CGFloat) -> PresentationDetent { PresentationDetent(id: "h\(h)") }
    public static func fraction(_ f: CGFloat) -> PresentationDetent { PresentationDetent(id: "f\(f)") }
}

// MARK: - Animation

public struct Animation {
    public static let `default` = Animation()
    public static func easeInOut(duration: Double) -> Animation { Animation() }
    public static func easeIn(duration: Double) -> Animation { Animation() }
    public static func easeOut(duration: Double) -> Animation { Animation() }
    public static func linear(duration: Double) -> Animation { Animation() }
    public static func spring(duration: Double = 0.5, bounce: Double = 0) -> Animation { Animation() }
    public static let easeInOut = Animation()
}

@discardableResult
public func withAnimation<Result>(_ animation: Animation? = nil, _ body: () throws -> Result) rethrows -> Result {
    try body()
}

public struct AnyTransition {
    public static let opacity = AnyTransition()
    public static let identity = AnyTransition()
    public static let scale = AnyTransition()
    public static func move(edge: Edge) -> AnyTransition { AnyTransition() }
    public func combined(with other: AnyTransition) -> AnyTransition { self }
}

// MARK: - View modifiers

extension View {
    public func font(_ f: Font?) -> some View { self }
    public func padding(_ length: CGFloat) -> some View { self }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View { self }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View { self }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil,
                      alignment: Alignment = .center) -> some View { self }
    public func background<S: ShapeStyle, T: Shape>(_ style: S, in shape: T) -> some View { self }
    public func background<S: ShapeStyle>(_ style: S) -> some View { self }
    public func background<V: View>(_ view: V, alignment: Alignment = .center) -> some View { self }
    public func background<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View { self }
    public func overlay<V: View>(_ view: V, alignment: Alignment = .center) -> some View { self }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View { self }
    public func foregroundColor(_ c: Color?) -> some View { self }
    public func tint<S: ShapeStyle>(_ style: S?) -> some View { self }
    public func tint(_ tint: Color?) -> some View { self }
    public func opacity(_ o: Double) -> some View { self }
    public func clipped() -> some View { self }
    public func clipShape<S: Shape>(_ shape: S) -> some View { self }
    public func cornerRadius(_ r: CGFloat) -> some View { self }
    public func lineLimit(_ n: Int?) -> some View { self }
    public func multilineTextAlignment(_ a: TextAlignment) -> some View { self }
    public func labelsHidden() -> some View { self }
    public func allowsHitTesting(_ enabled: Bool) -> some View { self }
    public func ignoresSafeArea(_ regions: Int = 0, edges: Edge.Set = .all) -> some View { self }
    public func transition(_ t: AnyTransition) -> some View { self }
    public func animation<V: Equatable>(_ a: Animation?, value: V) -> some View { self }
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View { self }
    public func gesture<G>(_ gesture: G) -> some View { self }
    public func onAppear(perform action: (() -> Void)? = nil) -> some View { self }
    public func onDisappear(perform action: (() -> Void)? = nil) -> some View { self }
    public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                       _ action: @escaping (V, V) -> Void) -> some View { self }
    public func sheet<C: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> C) -> some View { self }
    public func fullScreenCover<C: View>(isPresented: Binding<Bool>,
                                         @ViewBuilder content: @escaping () -> C) -> some View { self }
    public func alert<A: View, M: View>(_ title: String, isPresented: Binding<Bool>,
                                        @ViewBuilder actions: () -> A,
                                        @ViewBuilder message: () -> M) -> some View { self }
    public func alert<A: View>(_ title: String, isPresented: Binding<Bool>,
                               @ViewBuilder actions: () -> A) -> some View { self }
    public func confirmationDialog<A: View>(_ title: String, isPresented: Binding<Bool>,
                                            @ViewBuilder actions: () -> A) -> some View { self }
    public func presentationDetents(_ detents: Set<PresentationDetent>) -> some View { self }
    public func presentationDragIndicator(_ v: Int) -> some View { self }
    public func buttonStyle(_ style: ButtonStyleShim) -> some View { self }
    public func textFieldStyle(_ style: TextFieldStyleShim) -> some View { self }
    public func navigationTitle(_ title: String) -> some View { self }
    public func navigationBarTitleDisplayMode(_ mode: NavigationBarItemShim.TitleDisplayMode) -> some View { self }
    public func toolbar<C: View>(@ViewBuilder content: () -> C) -> some View { self }
    public func environmentObject<T: ObservableObject>(_ object: T) -> some View { self }
    public func preferredColorScheme(_ scheme: ColorScheme?) -> some View { self }
    public func statusBarHidden(_ hidden: Bool = true) -> some View { self }
    public func persistentSystemOverlays(_ v: Int) -> some View { self }
    public func shadow(color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View { self }
    public func scaleEffect(_ s: CGFloat) -> some View { self }
    public func rotationEffect(_ a: AngleShim) -> some View { self }
    public func fixedSize(horizontal: Bool = false, vertical: Bool = false) -> some View { self }
    public func contentShape<S: Shape>(_ shape: S) -> some View { self }
    public func disabled(_ disabled: Bool) -> some View { self }
    public func id<T: Hashable>(_ id: T) -> some View { self }
    public func accessibilityLabel(_ label: String) -> some View { self }
    public func accessibilityHint(_ hint: String) -> some View { self }
    public func accessibilityElement(children: AccessibilityChildBehaviorShim = .ignore) -> some View { self }
    public func accessibilityAddTraits(_ traits: Int) -> some View { self }
    public func task(_ action: @escaping @Sendable () async -> Void) -> some View { self }
}

public struct AccessibilityChildBehaviorShim {
    public static let ignore = AccessibilityChildBehaviorShim()
    public static let combine = AccessibilityChildBehaviorShim()
    public static let contain = AccessibilityChildBehaviorShim()
}

public struct AngleShim {
    public static func degrees(_ d: Double) -> AngleShim { AngleShim() }
    public static func radians(_ r: Double) -> AngleShim { AngleShim() }
}

// MARK: - App & scenes

public protocol Scene {
    associatedtype Body: Scene
    @SceneBuilder var body: Body { get }
}


@resultBuilder
public enum SceneBuilder {
    public static func buildBlock<S: Scene>(_ s: S) -> S { s }
}

public struct WindowGroup<Content: View>: Scene {
    public var body: Never { fatalError() }
    public init(@ViewBuilder content: () -> Content) {}
}

public protocol App {
    associatedtype Body: Scene
    init()
    @SceneBuilder var body: Body { get }
}

extension App {
    public static func main() {}
}

extension Never: View, Scene {
    public var body: Never { return fatalError() }
}

// SwiftUI provides this bridge on Apple platforms.
extension UIColor {
    public convenience init(_ color: Color) { self.init(white: 0, alpha: 1) }
}

// MARK: - UIKit bridging

public protocol UIViewRepresentable: View {
    associatedtype UIViewType: UIView
    associatedtype Coordinator = Void
    func makeUIView(context: Context) -> UIViewType
    func updateUIView(_ uiView: UIViewType, context: Context)
    func makeCoordinator() -> Coordinator
    typealias Context = UIViewRepresentableContext<Self>
}

public struct UIViewRepresentableContext<Representable: UIViewRepresentable> {
    public var coordinator: Representable.Coordinator
    public var environment: EnvironmentValues { EnvironmentValues() }
}

extension UIViewRepresentable {
    public var body: Never { fatalError() }
}

extension UIViewRepresentable where Coordinator == Void {
    public func makeCoordinator() -> Void { () }
}


// MARK: - Gestures
//
// Enough of the gesture surface to typecheck the scene hosts. The values these
// carry — a screen point, a 3D location, and (once targeted) the entity that was
// hit — are what the game reads, so those are real; the recognition is not.

public protocol Gesture {
    associatedtype Value
}

public struct DragGesture: Gesture {
    public struct Value {
        public var location: CGPoint
        public var startLocation: CGPoint
        public var translation: CGSize
        public init(location: CGPoint = .zero, startLocation: CGPoint = .zero,
                    translation: CGSize = CGSize(width: 0, height: 0)) {
            self.location = location
            self.startLocation = startLocation
            self.translation = translation
        }
    }

    public init(minimumDistance: CGFloat = 10, coordinateSpace: Int = 0) {}

    public func onChanged(_ action: @escaping (Value) -> Void) -> DragGesture { self }
    public func onEnded(_ action: @escaping (Value) -> Void) -> DragGesture { self }
}

public struct SpatialTapGesture: Gesture {
    /// No `location3D`. It exists on visionOS and not on iOS, and taking it on
    /// faith is what sent the first port of this file to the compiler with a
    /// three-dimensional touch point that iOS does not have.
    public struct Value {
        public var location: CGPoint
        public init(location: CGPoint = .zero) { self.location = location }
    }

    public init(count: Int = 1, coordinateSpace: Int = 0) {}

    public func onEnded(_ action: @escaping (Value) -> Void) -> SpatialTapGesture { self }
}
