// Linux typecheck shim mirroring the SceneKit API surface the game uses.
@_exported import Foundation
@_exported import CoreGraphics
@_exported import UIKit

// MARK: - Types

public struct SCNVector3 {
    public var x: Float
    public var y: Float
    public var z: Float
    public init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
    public init(_ x: Float, _ y: Float, _ z: Float) { self.x = x; self.y = y; self.z = z }
    public init() { x = 0; y = 0; z = 0 }
}

public struct SCNVector4 {
    public var x: Float, y: Float, z: Float, w: Float
    public init(x: Float, y: Float, z: Float, w: Float) { self.x = x; self.y = y; self.z = z; self.w = w }
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) { self.x = x; self.y = y; self.z = z; self.w = w }
}

/// Column-major 4x4, stored row by row as m[row][col] for readability.
public struct SCNMatrix4 {
    public var m: [Float]
    public init() { m = [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1] }
    public init(_ values: [Float]) { m = values }

    public subscript(r: Int, c: Int) -> Float {
        get { m[r * 4 + c] }
        set { m[r * 4 + c] = newValue }
    }

    public static func * (a: SCNMatrix4, b: SCNMatrix4) -> SCNMatrix4 {
        var out = SCNMatrix4()
        for r in 0..<4 {
            for c in 0..<4 {
                var sum: Float = 0
                for k in 0..<4 { sum += a[r, k] * b[k, c] }
                out[r, c] = sum
            }
        }
        return out
    }

    /// Transforms a point (w = 1).
    // SIMD3 overloads, because the game's own geometry now speaks that type and
    // the offline rasteriser consumes the game's geometry directly.
    public func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = apply(SCNVector3(x: p.x, y: p.y, z: p.z))
        return SIMD3<Float>(r.x, r.y, r.z)
    }
    public func applyVector(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let r = applyVector(SCNVector3(x: p.x, y: p.y, z: p.z))
        return SIMD3<Float>(r.x, r.y, r.z)
    }
    public func apply(_ p: SCNVector3) -> SCNVector3 {
        SCNVector3(x: self[0,0]*p.x + self[0,1]*p.y + self[0,2]*p.z + self[0,3],
                   y: self[1,0]*p.x + self[1,1]*p.y + self[1,2]*p.z + self[1,3],
                   z: self[2,0]*p.x + self[2,1]*p.y + self[2,2]*p.z + self[2,3])
    }

    /// Transforms a direction (w = 0).
    public func applyVector(_ p: SCNVector3) -> SCNVector3 {
        SCNVector3(x: self[0,0]*p.x + self[0,1]*p.y + self[0,2]*p.z,
                   y: self[1,0]*p.x + self[1,1]*p.y + self[1,2]*p.z,
                   z: self[2,0]*p.x + self[2,1]*p.y + self[2,2]*p.z)
    }

    /// General inverse via Gauss-Jordan; the transforms here are always invertible.
    public var inverted: SCNMatrix4 {
        var a = m
        var inv = SCNMatrix4().m
        for col in 0..<4 {
            var pivot = col
            for r in (col + 1)..<4 where abs(a[r * 4 + col]) > abs(a[pivot * 4 + col]) { pivot = r }
            if abs(a[pivot * 4 + col]) < 1e-12 { return SCNMatrix4() }
            if pivot != col {
                for k in 0..<4 {
                    a.swapAt(col * 4 + k, pivot * 4 + k)
                    inv.swapAt(col * 4 + k, pivot * 4 + k)
                }
            }
            let d = a[col * 4 + col]
            for k in 0..<4 { a[col * 4 + k] /= d; inv[col * 4 + k] /= d }
            for r in 0..<4 where r != col {
                let f = a[r * 4 + col]
                if f == 0 { continue }
                for k in 0..<4 {
                    a[r * 4 + k] -= f * a[col * 4 + k]
                    inv[r * 4 + k] -= f * inv[col * 4 + k]
                }
            }
        }
        return SCNMatrix4(inv)
    }
}

public func SCNMatrix4MakeScale(_ sx: Float, _ sy: Float, _ sz: Float) -> SCNMatrix4 {
    var m = SCNMatrix4(); m[0,0] = sx; m[1,1] = sy; m[2,2] = sz; return m
}
public func SCNMatrix4MakeTranslation(_ tx: Float, _ ty: Float, _ tz: Float) -> SCNMatrix4 {
    var m = SCNMatrix4(); m[0,3] = tx; m[1,3] = ty; m[2,3] = tz; return m
}
public func SCNMatrix4MakeRotationX(_ a: Float) -> SCNMatrix4 {
    var m = SCNMatrix4(); m[1,1] = cosf(a); m[1,2] = -sinf(a); m[2,1] = sinf(a); m[2,2] = cosf(a); return m
}
public func SCNMatrix4MakeRotationY(_ a: Float) -> SCNMatrix4 {
    var m = SCNMatrix4(); m[0,0] = cosf(a); m[0,2] = sinf(a); m[2,0] = -sinf(a); m[2,2] = cosf(a); return m
}
public func SCNMatrix4MakeRotationZ(_ a: Float) -> SCNMatrix4 {
    var m = SCNMatrix4(); m[0,0] = cosf(a); m[0,1] = -sinf(a); m[1,0] = sinf(a); m[1,1] = cosf(a); return m
}
public let SCNMatrix4Identity = SCNMatrix4()

// MARK: - Materials

public enum SCNLightingModel: String {
    case blinn, constant, lambert, phong, physicallyBased, shadowOnly
}
public enum SCNWrapMode: Int { case clamp, `repeat`, clampToBorder, mirror }
public enum SCNFilterMode: Int { case none, nearest, linear }
public enum SCNTransparencyMode: Int { case aOne, rgbZero, singleLayer, dualLayer, `default` }
public enum SCNBlendMode: Int { case alpha, add, subtract, multiply, screen, replace, max }
public enum SCNCullMode: Int { case back, front }

open class SCNMaterialProperty: NSObject {
    open var contents: Any?
    open var intensity: CGFloat = 1
    open var wrapS: SCNWrapMode = .clamp
    open var wrapT: SCNWrapMode = .clamp
    open var minificationFilter: SCNFilterMode = .linear
    open var magnificationFilter: SCNFilterMode = .linear
    open var mipFilter: SCNFilterMode = .nearest
    open var contentsTransform: SCNMatrix4 = SCNMatrix4()
    open var maxAnisotropy: CGFloat = 1
}

open class SCNMaterial: NSObject {
    public override init() { super.init() }
    open var name: String?
    open var lightingModel: SCNLightingModel = .blinn
    public let diffuse = SCNMaterialProperty()
    public let ambient = SCNMaterialProperty()
    public let specular = SCNMaterialProperty()
    public let emission = SCNMaterialProperty()
    public let normal = SCNMaterialProperty()
    public let roughness = SCNMaterialProperty()
    public let metalness = SCNMaterialProperty()
    public let transparent = SCNMaterialProperty()
    public let ambientOcclusion = SCNMaterialProperty()
    public let selfIllumination = SCNMaterialProperty()
    public let displacement = SCNMaterialProperty()
    open var transparency: CGFloat = 1
    open var transparencyMode: SCNTransparencyMode = .aOne
    open var blendMode: SCNBlendMode = .alpha
    open var isDoubleSided: Bool = false
    open var cullMode: SCNCullMode = .back
    open var writesToDepthBuffer: Bool = true
    open var readsFromDepthBuffer: Bool = true
    open var shininess: CGFloat = 1
    open var fresnelExponent: CGFloat = 0
    open var locksAmbientWithDiffuse: Bool = true
    open var shaderModifiers: [String: String]?
}

// MARK: - Geometry

public enum SCNGeometryPrimitiveType: Int {
    case triangles, triangleStrip, line, point, polygon
}

open class SCNGeometrySource: NSObject {
    public var vertices: [SCNVector3] = []
    public var normals: [SCNVector3] = []
    public var uvs: [CGPoint] = []
    public convenience init(vertices: [SCNVector3]) { self.init(); self.vertices = vertices }
    public convenience init(normals: [SCNVector3]) { self.init(); self.normals = normals }
    public convenience init(textureCoordinates: [CGPoint]) { self.init(); self.uvs = textureCoordinates }
    public override init() { super.init() }
}

open class SCNGeometryElement: NSObject {
    public var indices: [Int32] = []
    public convenience init(indices: [Int32], primitiveType: SCNGeometryPrimitiveType) {
        self.init(); self.indices = indices
    }
    public convenience init(indices: [UInt16], primitiveType: SCNGeometryPrimitiveType) {
        self.init(); self.indices = indices.map(Int32.init)
    }
    public override init() { super.init() }
    /// Triangles in this element. Every element the game builds is a triangle list.
    open var primitiveCount: Int { indices.count / 3 }
}

open class SCNGeometry: NSObject {
    public override init() { super.init() }
    public var sources: [SCNGeometrySource] = []
    public var elements: [SCNGeometryElement] = []
    public convenience init(sources: [SCNGeometrySource], elements: [SCNGeometryElement]?) {
        self.init(); self.sources = sources; self.elements = elements ?? []
    }
    open var name: String?
    open var materials: [SCNMaterial] = []
    open var firstMaterial: SCNMaterial? { materials.first }
    open var levelsOfDetail: [SCNLevelOfDetail]?
    open override func copy() -> Any {
        let g = SCNGeometry()
        g.sources = sources; g.elements = elements; g.materials = materials; g.name = name
        return g
    }
    open func insertMaterial(_ material: SCNMaterial, at index: Int) {}

    /// Not part of SceneKit. The harness needs a triangle budget it can hold the
    /// room to, and the counts that matter come from the primitive tessellations,
    /// which are documented formulas rather than anything the shim has to guess at.
    /// Overridden per primitive; this base case covers geometry built from raw mesh
    /// data, where the element already knows.
    open var estimatedTriangles: Int {
        elements.reduce(0) { $0 + $1.primitiveCount }
    }
}

open class SCNLevelOfDetail: NSObject {}



open class SCNSphere: SCNGeometry {
    open var radius: CGFloat = 1
    // 48 on the device, not 24. The harness counts triangles against a budget, so
    // the default has to match the one the real framework uses or the budget is
    // measuring a phone that does not exist.
    open var segmentCount: Int = 48
    open var isGeodesic: Bool = false
    public convenience init(radius: CGFloat) { self.init(); self.radius = radius }
    // Longitudes × latitudes, two triangles each, minus the degenerate poles.
    open override var estimatedTriangles: Int { segmentCount * (segmentCount / 2) * 2 }
}

open class SCNBox: SCNGeometry {
    open var width: CGFloat = 1
    open var height: CGFloat = 1
    open var length: CGFloat = 1
    open var chamferRadius: CGFloat = 0
    open var chamferSegmentCount: Int = 5
    public convenience init(width: CGFloat, height: CGFloat, length: CGFloat, chamferRadius: CGFloat) {
        self.init(); self.width = width; self.height = height; self.length = length; self.chamferRadius = chamferRadius
    }
}

open class SCNCylinder: SCNGeometry {
    open var radius: CGFloat = 1
    open var height: CGFloat = 1
    open var radialSegmentCount: Int = 48
    open var heightSegmentCount: Int = 1
    public convenience init(radius: CGFloat, height: CGFloat) { self.init(); self.radius = radius; self.height = height }
    // Side quads plus a fan at each end.
    open override var estimatedTriangles: Int {
        radialSegmentCount * heightSegmentCount * 2 + radialSegmentCount * 2
    }
}

open class SCNTube: SCNGeometry {
    open var innerRadius: CGFloat = 0.25
    open var outerRadius: CGFloat = 0.5
    open var height: CGFloat = 1
    open var radialSegmentCount: Int = 48
    open var heightSegmentCount: Int = 1
    public convenience init(innerRadius: CGFloat, outerRadius: CGFloat, height: CGFloat) {
        self.init(); self.innerRadius = innerRadius; self.outerRadius = outerRadius; self.height = height
    }
    // Inner wall, outer wall, and an annulus at each end.
    open override var estimatedTriangles: Int {
        radialSegmentCount * heightSegmentCount * 4 + radialSegmentCount * 4
    }
}

open class SCNTorus: SCNGeometry {
    open var ringRadius: CGFloat = 0.5
    open var pipeRadius: CGFloat = 0.25
    open var ringSegmentCount: Int = 48
    open var pipeSegmentCount: Int = 24
    public convenience init(ringRadius: CGFloat, pipeRadius: CGFloat) { self.init(); self.ringRadius = ringRadius; self.pipeRadius = pipeRadius }
    open override var estimatedTriangles: Int { ringSegmentCount * pipeSegmentCount * 2 }
}

open class SCNCone: SCNGeometry {
    public convenience init(topRadius: CGFloat, bottomRadius: CGFloat, height: CGFloat) { self.init() }
}

open class SCNCapsule: SCNGeometry {
    public convenience init(capRadius: CGFloat, height: CGFloat) { self.init() }
}

open class SCNPlane: SCNGeometry {
    open var width: CGFloat = 1
    open var height: CGFloat = 1
    open var cornerRadius: CGFloat = 0
    public convenience init(width: CGFloat, height: CGFloat) { self.init(); self.width = width; self.height = height }
}

open class SCNText: SCNGeometry {}

// MARK: - Lights & cameras

public enum SCNShadowMode: Int { case forward, deferred, modulated }

open class SCNLight: NSObject {
    public struct LightType: RawRepresentable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = LightType(rawValue: "ambient")
        public static let omni = LightType(rawValue: "omni")
        public static let directional = LightType(rawValue: "directional")
        public static let spot = LightType(rawValue: "spot")
        public static let IES = LightType(rawValue: "IES")
        public static let probe = LightType(rawValue: "probe")
        public static let area = LightType(rawValue: "area")
    }
    public override init() { super.init() }
    open var type: LightType = .omni
    open var color: Any = UIColor.white
    open var intensity: CGFloat = 1000
    open var temperature: CGFloat = 6500
    open var castsShadow: Bool = false
    open var shadowMode: SCNShadowMode = .forward
    open var shadowRadius: CGFloat = 3
    open var shadowSampleCount: Int = 0
    open var shadowMapSize: CGSize = .zero
    open var shadowColor: Any = UIColor.black
    open var shadowBias: CGFloat = 1
    open var orthographicScale: CGFloat = 1
    open var zNear: CGFloat = 1
    open var zFar: CGFloat = 100
    open var attenuationStartDistance: CGFloat = 0
    open var attenuationEndDistance: CGFloat = 0
    open var spotInnerAngle: CGFloat = 0
    open var spotOuterAngle: CGFloat = 45
    open var categoryBitMask: Int = -1
}

public enum SCNCameraProjectionDirection: Int { case vertical, horizontal }

open class SCNCamera: NSObject {
    public override init() { super.init() }
    open var name: String?
    open var fieldOfView: CGFloat = 60
    open var projectionDirection: SCNCameraProjectionDirection = .vertical
    open var zNear: Double = 1
    open var zFar: Double = 100
    open var usesOrthographicProjection: Bool = false
    open var orthographicScale: Double = 1
    open var wantsHDR: Bool = false
    open var wantsExposureAdaptation: Bool = true
    open var exposureOffset: CGFloat = 0
    open var averageGray: CGFloat = 0.18
    open var whitePoint: CGFloat = 1
    open var bloomThreshold: CGFloat = 0.5
    open var bloomIntensity: CGFloat = 0
    open var bloomBlurRadius: CGFloat = 4
    open var motionBlurIntensity: CGFloat = 0
    open var wantsDepthOfField: Bool = false
    open var focusDistance: CGFloat = 2.5
    open var focalBlurSampleCount: Int = 25
    open var fStop: CGFloat = 5.6
    open var apertureBladeCount: Int = 6
    open var screenSpaceAmbientOcclusionIntensity: CGFloat = 0
    open var screenSpaceAmbientOcclusionRadius: CGFloat = 5
    open var screenSpaceAmbientOcclusionBias: CGFloat = 0.03
    open var screenSpaceAmbientOcclusionDepthThreshold: CGFloat = 0.97
    open var screenSpaceAmbientOcclusionNormalThreshold: CGFloat = 0.3
    open var colorFringeStrength: CGFloat = 0
    open var colorFringeIntensity: CGFloat = 0
    open var vignettingIntensity: CGFloat = 0
    open var vignettingPower: CGFloat = 0
    open var saturation: CGFloat = 1
    open var contrast: CGFloat = 0
}

// MARK: - Actions

public enum SCNActionTimingMode: Int { case linear, easeIn, easeOut, easeInEaseOut }

open class SCNAction: NSObject {
    open var duration: TimeInterval = 0
    open var timingMode: SCNActionTimingMode = .linear
    open class func move(by delta: SCNVector3, duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func move(to location: SCNVector3, duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func rotateBy(x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func rotateTo(x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func scale(to scale: CGFloat, duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func fadeIn(duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func fadeOut(duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func fadeOpacity(to opacity: CGFloat, duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func wait(duration: TimeInterval) -> SCNAction { SCNAction() }
    open class func group(_ actions: [SCNAction]) -> SCNAction { SCNAction() }
    open class func sequence(_ actions: [SCNAction]) -> SCNAction { SCNAction() }
    open class func repeatForever(_ action: SCNAction) -> SCNAction { SCNAction() }
    open class func run(_ block: @escaping (SCNNode) -> Void) -> SCNAction { SCNAction() }
    open class func customAction(duration: TimeInterval,
                                 action: @escaping (SCNNode, CGFloat) -> Void) -> SCNAction { SCNAction() }
}

// MARK: - Particles

public enum SCNParticleBirthLocation: Int { case surface, volume, vertex }
public enum SCNParticleBirthDirection: Int { case constant, surfaceNormal, random }
public enum SCNParticleBlendMode: Int { case additive, subtract, multiply, screen, alpha, replace }
public enum SCNParticleOrientationMode: Int { case billboardScreenAligned, billboardViewAligned, free, billboardYAligned }

open class SCNParticleSystem: NSObject {
    public override init() { super.init() }
    open var birthRate: CGFloat = 1
    open var birthRateVariation: CGFloat = 0
    open var emissionDuration: CGFloat = 1
    open var loops: Bool = true
    open var warmupDuration: CGFloat = 0
    open var particleLifeSpan: CGFloat = 1
    open var particleLifeSpanVariation: CGFloat = 0
    open var particleSize: CGFloat = 1
    open var particleSizeVariation: CGFloat = 0
    open var particleColor: UIColor = .white
    open var particleColorVariation: SCNVector4 = SCNVector4(x: 0, y: 0, z: 0, w: 0)
    open var particleVelocity: CGFloat = 0
    open var particleVelocityVariation: CGFloat = 0
    open var particleAngularVelocity: CGFloat = 0
    open var acceleration: SCNVector3 = SCNVector3()
    open var spreadingAngle: CGFloat = 0
    open var emitterShape: SCNGeometry?
    open var birthLocation: SCNParticleBirthLocation = .surface
    open var birthDirection: SCNParticleBirthDirection = .constant
    open var blendMode: SCNParticleBlendMode = .additive
    open var orientationMode: SCNParticleOrientationMode = .billboardScreenAligned
    open var isLightingEnabled: Bool = false
    open var isAffectedByGravity: Bool = false
    open var isAffectedByPhysicsFields: Bool = false
    open var particleImage: Any?
    open var particleMass: CGFloat = 1
    open var dampingFactor: CGFloat = 0
}

// MARK: - Nodes

open class SCNNode: NSObject {
    public override init() { super.init() }
    public convenience init(geometry: SCNGeometry?) { self.init(); self.geometry = geometry }

    open var name: String?
    open var position: SCNVector3 = SCNVector3()
    open var eulerAngles: SCNVector3 = SCNVector3()
    open var scale: SCNVector3 = SCNVector3(x: 1, y: 1, z: 1)
    open var pivot: SCNMatrix4 = SCNMatrix4()
    open var transform: SCNMatrix4 = SCNMatrix4()
    open var worldPosition: SCNVector3 {
        get { worldTransform.apply(SCNVector3()) }
        set { position = parent.map { $0.worldTransform.inverted.apply(newValue) } ?? newValue }
    }
    open var opacity: CGFloat = 1
    open var isHidden: Bool = false
    open var castsShadow: Bool = true
    open var renderingOrder: Int = 0
    open var categoryBitMask: Int = 1

    open var geometry: SCNGeometry?
    open var light: SCNLight?
    open var camera: SCNCamera?
    open var morpher: SCNMorpher?
    open var skinner: SCNSkinner?

    open internal(set) var parent: SCNNode?
    open internal(set) var childNodes: [SCNNode] = []

    open func addChildNode(_ child: SCNNode) {
        child.removeFromParentNode()
        childNodes.append(child)
        child.parent = self
    }
    open func removeFromParentNode() {
        guard let parent else { return }
        parent.childNodes.removeAll { $0 === self }
        self.parent = nil
    }
    open func insertChildNode(_ child: SCNNode, at index: Int) {}
    open func childNode(withName name: String, recursively: Bool) -> SCNNode? {
        for child in childNodes {
            if child.name == name { return child }
            if recursively, let hit = child.childNode(withName: name, recursively: true) { return hit }
        }
        return nil
    }
    open func childNodes(passingTest predicate: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Bool) -> [SCNNode] { [] }
    open func clone() -> SCNNode { SCNNode() }
    open func flattenedClone() -> SCNNode { SCNNode() }

    /// Local transform: scale, then euler (Rx·Ry·Rz), then translate.
    public var localTransform: SCNMatrix4 {
        let t = SCNMatrix4MakeTranslation(position.x, position.y, position.z)
        let rx = SCNMatrix4MakeRotationX(eulerAngles.x)
        let ry = SCNMatrix4MakeRotationY(eulerAngles.y)
        let rz = SCNMatrix4MakeRotationZ(eulerAngles.z)
        let sc = SCNMatrix4MakeScale(scale.x, scale.y, scale.z)
        return t * rx * ry * rz * sc
    }

    public var worldTransform: SCNMatrix4 {
        if let parent { return parent.worldTransform * localTransform }
        return localTransform
    }

    // The simd-typed accessors. Real SceneKit has had these for years; the game
    // now uses them everywhere so that its own data is SIMD3<Float> — the type
    // RealityKit speaks — while still rendering through SceneKit. That is what
    // lets the port happen as two verified steps rather than one blind jump.
    open func simdLook(at target: SIMD3<Float>, up: SIMD3<Float>, localFront: SIMD3<Float>) {
        look(at: SCNVector3(x: target.x, y: target.y, z: target.z),
             up: SCNVector3(x: up.x, y: up.y, z: up.z),
             localFront: SCNVector3(x: localFront.x, y: localFront.y, z: localFront.z))
    }
    open var simdPosition: SIMD3<Float> {
        get { SIMD3<Float>(position.x, position.y, position.z) }
        set { position = SCNVector3(x: newValue.x, y: newValue.y, z: newValue.z) }
    }
    open var simdEulerAngles: SIMD3<Float> {
        get { SIMD3<Float>(eulerAngles.x, eulerAngles.y, eulerAngles.z) }
        set { eulerAngles = SCNVector3(x: newValue.x, y: newValue.y, z: newValue.z) }
    }
    open var simdScale: SIMD3<Float> {
        get { SIMD3<Float>(scale.x, scale.y, scale.z) }
        set { scale = SCNVector3(x: newValue.x, y: newValue.y, z: newValue.z) }
    }
    open var simdWorldPosition: SIMD3<Float> {
        let p = worldPosition
        return SIMD3<Float>(p.x, p.y, p.z)
    }
    open func simdConvertPosition(_ position: SIMD3<Float>, to node: SCNNode?) -> SIMD3<Float> {
        let r = convertPosition(SCNVector3(x: position.x, y: position.y, z: position.z), to: node)
        return SIMD3<Float>(r.x, r.y, r.z)
    }
    open func simdConvertPosition(_ position: SIMD3<Float>, from node: SCNNode?) -> SIMD3<Float> {
        let r = convertPosition(SCNVector3(x: position.x, y: position.y, z: position.z), from: node)
        return SIMD3<Float>(r.x, r.y, r.z)
    }

    open func convertPosition(_ position: SCNVector3, from node: SCNNode?) -> SCNVector3 {
        let world = node?.worldTransform.apply(position) ?? position
        return worldTransform.inverted.apply(world)
    }

    open func convertPosition(_ position: SCNVector3, to node: SCNNode?) -> SCNVector3 {
        let world = worldTransform.apply(position)
        guard let node else { return world }
        return node.worldTransform.inverted.apply(world)
    }

    open func convertVector(_ vector: SCNVector3, from node: SCNNode?) -> SCNVector3 {
        let world = node?.worldTransform.applyVector(vector) ?? vector
        return worldTransform.inverted.applyVector(world)
    }

    open func look(at worldTarget: SCNVector3) {}
    open func look(at worldTarget: SCNVector3, up worldUp: SCNVector3, localFront: SCNVector3) {}

    open func runAction(_ action: SCNAction) {}
    open func runAction(_ action: SCNAction, completionHandler: (() -> Void)?) {}
    open func runAction(_ action: SCNAction, forKey key: String?) {}
    open func removeAllActions() {}

    open func addParticleSystem(_ system: SCNParticleSystem) {}
    open func removeAllParticleSystems() {}
}

open class SCNMorpher: NSObject {}
open class SCNSkinner: NSObject {}

// MARK: - Scene

open class SCNScene: NSObject {
    public override init() { super.init() }
    public let rootNode = SCNNode()
    public let background = SCNMaterialProperty()
    public let lightingEnvironment = SCNMaterialProperty()
    open var fogColor: Any = UIColor.white
    open var fogStartDistance: CGFloat = 0
    open var fogEndDistance: CGFloat = 0
    open var fogDensityExponent: CGFloat = 1
    open var isPaused: Bool = false
}

// MARK: - Rendering & hit testing

public enum SCNAntialiasingMode: Int {
    case none, multisampling2X, multisampling4X, multisampling8X, multisampling16X
}

public struct SCNHitTestOption: RawRepresentable, Hashable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let searchMode = SCNHitTestOption(rawValue: "searchMode")
    public static let backFaceCulling = SCNHitTestOption(rawValue: "backFaceCulling")
    public static let boundingBoxOnly = SCNHitTestOption(rawValue: "boundingBoxOnly")
    public static let ignoreHiddenNodes = SCNHitTestOption(rawValue: "ignoreHiddenNodes")
    public static let ignoreChildNodes = SCNHitTestOption(rawValue: "ignoreChildNodes")
    public static let rootNode = SCNHitTestOption(rawValue: "rootNode")
    public static let categoryBitMask = SCNHitTestOption(rawValue: "categoryBitMask")
}

public enum SCNHitTestSearchMode: Int { case closest, all, any }

open class SCNHitTestResult: NSObject {
    open var node: SCNNode { SCNNode() }
    open var geometryIndex: Int { 0 }
    open var faceIndex: Int { 0 }
    open var worldCoordinates: SCNVector3 { SCNVector3() }
    open var localCoordinates: SCNVector3 { SCNVector3() }
    open var worldNormal: SCNVector3 { SCNVector3() }
}

public protocol SCNSceneRenderer: AnyObject {
    var scene: SCNScene? { get set }
    var isPlaying: Bool { get set }
    var sceneTime: TimeInterval { get set }
}

public protocol SCNSceneRendererDelegate: AnyObject {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval)
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval)
}

public extension SCNSceneRendererDelegate {
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {}
    func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {}
}

open class SCNView: UIView, SCNSceneRenderer {
    public var scene: SCNScene?
    public var isPlaying: Bool = false
    public var sceneTime: TimeInterval = 0
    open weak var delegate: SCNSceneRendererDelegate?
    open var rendersContinuously: Bool = false
    open var allowsCameraControl: Bool = false
    open var antialiasingMode: SCNAntialiasingMode = .none
    open var preferredFramesPerSecond: Int = 60
    open var autoenablesDefaultLighting: Bool = false
    open var isJitteringEnabled: Bool = false
    open var showsStatistics: Bool = false
    open var pointOfView: SCNNode?
    open func hitTest(_ point: CGPoint, options: [SCNHitTestOption: Any]?) -> [SCNHitTestResult] { [] }
    open func prepare(_ object: Any, shouldAbortBlock block: (() -> Bool)?) -> Bool { true }
    open func snapshot() -> UIImage { UIImage() }
}
