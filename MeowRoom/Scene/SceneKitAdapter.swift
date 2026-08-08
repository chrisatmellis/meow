import Foundation
import SceneKit
import UIKit

/// The one place raw mesh data becomes renderer geometry.
///
/// `MeshBuilder` and everything that calls it deal only in `MeshData`. Keeping the
/// conversion here means the generators stay portable and the verification harness
/// can rasterise the same buffers without a graphics framework present.

extension MeshData {
    func geometry() -> SCNGeometry {
        normalsIfNeeded()
        let vSource = SCNGeometrySource(vertices: positions.map { SCNVector3(x: $0.x, y: $0.y, z: $0.z) })
        let nSource = SCNGeometrySource(normals: normals.map { SCNVector3(x: $0.x, y: $0.y, z: $0.z) })
        let tSource = SCNGeometrySource(textureCoordinates: uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vSource, nSource, tSource], elements: [element])
    }
}

// MARK: - Node convenience

extension SCNNode {
    /// Node factory that realises mesh data and attaches a material in one step.
    static func make(_ mesh: MeshData, _ material: SCNMaterial, name: String? = nil) -> SCNNode {
        return make(mesh.geometry(), material, name: name)
    }

    /// The same, for the handful of props still built from SceneKit's own
    /// primitives rather than generated meshes.
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
