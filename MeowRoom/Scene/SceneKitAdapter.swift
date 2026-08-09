import Foundation
import SceneKit
import UIKit

/// The one place raw mesh data becomes renderer geometry.
///
/// `MeshBuilder` and everything that calls it deal only in `MeshData`. Keeping the
/// conversion here means the generators stay portable and the verification harness
/// can rasterise the same buffers without a graphics framework present.

#if DEBUG
/// Remembers which raw buffers a realised geometry came from.
///
/// The offline renderer draws the real generated meshes, and it used to reach them
/// by reading them back out of `SCNGeometry` — which meant looking at the cat
/// depended on the renderer being present and on hand-written tessellation for
/// every primitive type. Recording the source mesh instead lets it read the same
/// buffers the generators produced.
///
/// Recording is off by default and bounded on purpose: the assertion suite builds
/// hundreds of rigs and has no use for this, so only the render pass switches it on.
enum MeshSourceRegistry {
    static var isRecording = false
    private static var table: [ObjectIdentifier: (SCNGeometry, MeshData)] = [:]

    static func record(_ geometry: SCNGeometry, _ mesh: MeshData) {
        guard isRecording else { return }
        // The geometry is retained alongside the mesh so its identifier cannot be
        // reused by a later allocation while the mapping is still live.
        table[ObjectIdentifier(geometry)] = (geometry, mesh)
    }

    static func mesh(for geometry: SCNGeometry) -> MeshData? {
        table[ObjectIdentifier(geometry)]?.1
    }

    static func reset() {
        table.removeAll()
    }
}
#endif

extension MeshData {
    func geometry() -> SCNGeometry {
        normalsIfNeeded()
        let vSource = SCNGeometrySource(vertices: positions.map { SCNVector3(x: $0.x, y: $0.y, z: $0.z) })
        let nSource = SCNGeometrySource(normals: normals.map { SCNVector3(x: $0.x, y: $0.y, z: $0.z) })
        let tSource = SCNGeometrySource(textureCoordinates: uvs.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vSource, nSource, tSource], elements: [element])
        #if DEBUG
        MeshSourceRegistry.record(geometry, self)
        #endif
        return geometry
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
        simdPosition = SIMD3<Float>(x: x, y: y, z: z)
        return self
    }

    @discardableResult
    func rotated(_ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        simdEulerAngles = SIMD3<Float>(x: x, y: y, z: z)
        return self
    }

    @discardableResult
    func scaled(_ x: Float, _ y: Float, _ z: Float) -> SCNNode {
        simdScale = SIMD3<Float>(x: x, y: y, z: z)
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
