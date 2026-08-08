import Foundation
import RealityKit

/// Turns renderer-independent `MeshData` into a RealityKit `MeshResource`.
///
/// The mirror of `SceneKitAdapter`, and the only place in the game that knows how
/// RealityKit wants its vertex buffers. Everything upstream — `MeshBuilder`, `CatRig`,
/// `RoomBuilder` — produces plain arrays of `Vec3`/`Vec2` and stays testable on a
/// machine with no graphics framework at all.
///
/// This uses `MeshResource.Contents` rather than the simpler `MeshDescriptor` because
/// `Contents` is the path that carries skeletons and joint influences. The tail wants
/// to be one skinned mesh rather than nine jointed tubes with flat caps between them,
/// and that is only reachable from here.
extension MeshData {

    /// - Parameter name: identifies the model inside the resource. RealityKit requires
    ///   model and instance ids to be unique within one resource, not across the scene.
    func meshResource(name: String = "mesh") throws -> MeshResource {
        normalsIfNeeded()

        var part = MeshResource.Part(id: "\(name)-part", materialIndex: 0)
        part.positions = MeshBuffers.Positions(positions.map { SIMD3<Float>($0.x, $0.y, $0.z) })
        part.normals = MeshBuffers.Normals(normals.map { SIMD3<Float>($0.x, $0.y, $0.z) })
        part.textureCoordinates = MeshBuffers.TextureCoordinates(uvs.map { SIMD2<Float>($0.x, $0.y) })

        // MeshData carries Int32 because that is what the rasteriser and SceneKit both
        // wanted; RealityKit wants UInt32. Indices are never negative — `addTriangle`
        // only ever appends values returned by `addVertex` — so this is a widening.
        part.triangleIndices = MeshBuffers.TriangleIndices(indices.map { UInt32($0) })

        var contents = MeshResource.Contents()
        contents.models = [MeshResource.Model(id: name, parts: [part])]
        contents.instances = [MeshResource.Instance(id: "\(name)-instance", model: name)]
        return try MeshResource.generate(from: contents)
    }
}
