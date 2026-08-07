import Foundation
import SceneKit
import UIKit

/// A cross-section of a lofted limb/body: an ellipse centred on the spine.
struct LoftRing {
    var center: SCNVector3
    var radiusX: Float
    var radiusY: Float

    init(center: SCNVector3, radiusX: Float, radiusY: Float) {
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
    }

    init(z: Float, y: Float = 0, x: Float = 0, radius: Float) {
        self.center = SCNVector3(x: x, y: y, z: z)
        self.radiusX = radius
        self.radiusY = radius
    }
}

/// Accumulates triangles and turns them into an `SCNGeometry`.
/// Everything the cat is made of is generated here at runtime — no art assets to ship.
final class MeshData {
    private(set) var positions: [SCNVector3] = []
    private(set) var normals: [SCNVector3] = []
    private(set) var uvs: [CGPoint] = []
    private(set) var indices: [Int32] = []

    func addVertex(_ p: SCNVector3, uv: CGPoint) -> Int32 {
        positions.append(p)
        normals.append(.zero)
        uvs.append(uv)
        return Int32(positions.count - 1)
    }

    func addTriangle(_ a: Int32, _ b: Int32, _ c: Int32) {
        guard a != b, b != c, a != c else { return }
        indices.append(a); indices.append(b); indices.append(c)
    }

    func addQuad(_ a: Int32, _ b: Int32, _ c: Int32, _ d: Int32) {
        addTriangle(a, b, c)
        addTriangle(a, c, d)
    }

    /// Area-weighted vertex normals.
    func recomputeNormals() {
        for i in 0..<normals.count { normals[i] = .zero }
        var i = 0
        while i + 2 < indices.count {
            let ia = Int(indices[i]), ib = Int(indices[i + 1]), ic = Int(indices[i + 2])
            let a = positions[ia], b = positions[ib], c = positions[ic]
            let n = cross(b - a, c - a)
            normals[ia] += n
            normals[ib] += n
            normals[ic] += n
            i += 3
        }
        for j in 0..<normals.count {
            normals[j] = normals[j].normalized
        }
    }

    func geometry() -> SCNGeometry {
        if normals.allSatisfy({ $0.length < 1e-5 }) { recomputeNormals() }
        let vSource = SCNGeometrySource(vertices: positions)
        let nSource = SCNGeometrySource(normals: normals)
        let tSource = SCNGeometrySource(textureCoordinates: uvs)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vSource, nSource, tSource], elements: [element])
    }
}

enum MeshBuilder {

    /// Sweeps an elliptical cross-section along a series of rings.
    /// Rings run along the local +Z axis; `v` in UV space runs along the sweep.
    static func loft(_ rings: [LoftRing],
                     segments: Int = 16,
                     capStart: Bool = true,
                     capEnd: Bool = true,
                     uRepeat: Float = 1,
                     vRepeat: Float = 1) -> SCNGeometry {
        let mesh = MeshData()
        guard rings.count >= 2 else { return SCNSphere(radius: 0.02) }

        var ringIndices: [[Int32]] = []
        for (ri, ring) in rings.enumerated() {
            var row: [Int32] = []
            let v = CGFloat(Float(ri) / Float(rings.count - 1) * vRepeat)
            for s in 0...segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                let p = SCNVector3(x: ring.center.x + cosf(a) * ring.radiusX,
                                   y: ring.center.y + sinf(a) * ring.radiusY,
                                   z: ring.center.z)
                let u = CGFloat(Float(s) / Float(segments) * uRepeat)
                row.append(mesh.addVertex(p, uv: CGPoint(x: u, y: v)))
            }
            ringIndices.append(row)
        }

        for ri in 0..<(rings.count - 1) {
            let a = ringIndices[ri]
            let b = ringIndices[ri + 1]
            for s in 0..<segments {
                // Wound so the face normal points radially outward.
                mesh.addQuad(a[s], a[s + 1], b[s + 1], b[s])
            }
        }

        if capStart, let first = rings.first {
            let c = mesh.addVertex(first.center, uv: CGPoint(x: 0.5, y: 0))
            let row = ringIndices[0]
            for s in 0..<segments {
                mesh.addTriangle(c, row[s + 1], row[s])
            }
        }
        if capEnd, let last = rings.last {
            let c = mesh.addVertex(last.center, uv: CGPoint(x: 0.5, y: CGFloat(vRepeat)))
            let row = ringIndices[rings.count - 1]
            for s in 0..<segments {
                mesh.addTriangle(c, row[s], row[s + 1])
            }
        }

        mesh.recomputeNormals()
        return mesh.geometry()
    }

    /// A tapered tube from `count` samples of a radius function. Handy for legs and tails.
    static func tube(length: Float,
                     count: Int = 8,
                     segments: Int = 12,
                     radius: (Float) -> Float,
                     offset: ((Float) -> SCNVector3)? = nil,
                     capStart: Bool = true,
                     capEnd: Bool = true) -> SCNGeometry {
        var rings: [LoftRing] = []
        for i in 0...max(1, count) {
            let t = Float(i) / Float(max(1, count))
            let r = max(0.0008, radius(t))
            let o = offset?(t) ?? .zero
            rings.append(LoftRing(center: SCNVector3(x: o.x, y: o.y, z: t * length + o.z),
                                  radiusX: r, radiusY: r))
        }
        return loft(rings, segments: segments, capStart: capStart, capEnd: capEnd)
    }

    /// Flattened cone used for ears — a triangle with thickness and a rounded base.
    static func ear(length: Float, width: Float, thickness: Float, curl: Float) -> SCNGeometry {
        var rings: [LoftRing] = []
        let steps = 8
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let taper = powf(1 - t, 0.85)
            let bend = curl * t * t * length * 0.55
            rings.append(LoftRing(center: SCNVector3(x: 0, y: -bend, z: t * length),
                                  radiusX: width * 0.5 * taper + 0.0008,
                                  radiusY: thickness * 0.5 * taper + 0.0006))
        }
        return loft(rings, segments: 10, capStart: true, capEnd: true)
    }

    /// A rounded, slightly squashed sphere. Used for skulls, muzzles, paws and cushions.
    static func blob(radius: Float,
                     scaleX: Float = 1, scaleY: Float = 1, scaleZ: Float = 1,
                     rings ringCount: Int = 14,
                     segments: Int = 18) -> SCNGeometry {
        var rings: [LoftRing] = []
        for i in 0...ringCount {
            let t = Float(i) / Float(ringCount)
            let phi = t * Float.pi
            let r = sinf(phi)
            let z = -cosf(phi) * radius * scaleZ
            rings.append(LoftRing(center: SCNVector3(x: 0, y: 0, z: z),
                                  radiusX: max(0.0006, r * radius * scaleX),
                                  radiusY: max(0.0006, r * radius * scaleY)))
        }
        return loft(rings, segments: segments, capStart: false, capEnd: false)
    }

    /// A flat quad in the XZ plane, e.g. a futon top or a rug.
    static func quadXZ(width: Float, depth: Float, y: Float = 0) -> SCNGeometry {
        let mesh = MeshData()
        let hw = width * 0.5, hd = depth * 0.5
        let a = mesh.addVertex(SCNVector3(x: -hw, y: y, z: -hd), uv: CGPoint(x: 0, y: 0))
        let b = mesh.addVertex(SCNVector3(x: hw, y: y, z: -hd), uv: CGPoint(x: 1, y: 0))
        let c = mesh.addVertex(SCNVector3(x: hw, y: y, z: hd), uv: CGPoint(x: 1, y: 1))
        let d = mesh.addVertex(SCNVector3(x: -hw, y: y, z: hd), uv: CGPoint(x: 0, y: 1))
        mesh.addQuad(a, d, c, b)   // normal points +Y
        mesh.recomputeNormals()
        return mesh.geometry()
    }

    /// Thin strands (whiskers, sisal fibres) drawn as very skinny tapered tubes.
    static func strand(length: Float, thickness: Float, droop: Float) -> SCNGeometry {
        return tube(length: length, count: 5, segments: 4, radius: { t in
            thickness * (1 - t * 0.85) + 0.00015
        }, offset: { t in
            SCNVector3(x: 0, y: -droop * t * t * length, z: 0)
        }, capStart: true, capEnd: true)
    }
}

// MARK: - Node convenience

extension SCNNode {
    /// Node factory that attaches a material in one step.
    static func make(_ geometry: SCNGeometry, _ material: SCNMaterial, name: String? = nil) -> SCNNode {
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        return node
    }

    @discardableResult
    func positioned(_ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        position = SCNVector3(x: x, y: y, z: z)
        return self
    }

    @discardableResult
    func rotated(_ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        eulerAngles = SCNVector3(x: x, y: y, z: z)
        return self
    }

    @discardableResult
    func scaled(_ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        scale = SCNVector3(x: x, y: y, z: z)
        return self
    }

    @discardableResult
    func named(_ n: String) -> SCNNode {
        name = n
        return self
    }

    func addChild(_ node: SCNNode) -> SCNNode {
        addChildNode(node)
        return node
    }
}
