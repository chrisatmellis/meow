import Foundation
import RealityKit
import UIKit

/// Turns renderer-independent `MeshData` into a RealityKit `MeshResource`.
///
/// The only place in the game that knows how RealityKit wants its vertex buffers.
/// Everything upstream — `MeshBuilder`, `CatRig`, `RoomBuilder` — produces plain
/// arrays of `Vec3`/`Vec2` and stays testable on a machine with no graphics
/// framework at all.
///
/// This uses `MeshResource.Contents` rather than the simpler `MeshDescriptor` because
/// `Contents` is the path that carries skeletons and joint influences. The tail wants
/// to be one skinned mesh rather than nine jointed tubes with flat caps between them,
/// and that is only reachable from here.

#if DEBUG
/// Remembers which raw buffers a realised mesh came from.
///
/// The offline renderer draws the real generated meshes, and reaching them by
/// reading them back out of the renderer's own geometry would make looking at the
/// cat depend on the renderer being present. Recording the source mesh instead
/// lets it read the same buffers the generators produced.
///
/// Recording is off by default and bounded on purpose: the assertion suite builds
/// hundreds of rigs and has no use for this, so only the render pass switches it on.
enum MeshSourceRegistry {
    static var isRecording = false
    private static var table: [ObjectIdentifier: (MeshResource, MeshData)] = [:]

    static func record(_ resource: MeshResource, _ mesh: MeshData) {
        guard isRecording else { return }
        // The resource is retained alongside the mesh so its identifier cannot be
        // reused by a later allocation while the mapping is still live.
        table[ObjectIdentifier(resource)] = (resource, mesh)
    }

    static func mesh(for resource: MeshResource) -> MeshData? {
        table[ObjectIdentifier(resource)]?.1
    }

    static func reset() {
        table.removeAll()
    }
}
#endif

extension MeshData {

    /// - Parameter name: identifies the model inside the resource. RealityKit requires
    ///   model and instance ids to be unique within one resource, not across the scene.
    func meshResource(name: String = "mesh") -> MeshResource? {
        normalsIfNeeded()

        // One part per material slot. Every part carries the whole vertex buffer and
        // its own slice of the index buffer, which costs nothing — the vertices are
        // shared by reference — and keeps the slot numbering exactly as the mesh
        // declared it rather than renumbering by order of appearance.
        let ps = MeshBuffers.Positions(positions.map { SIMD3<Float>($0.x, $0.y, $0.z) })
        let ns = MeshBuffers.Normals(normals.map { SIMD3<Float>($0.x, $0.y, $0.z) })
        let ts = MeshBuffers.TextureCoordinates(uvs.map { SIMD2<Float>($0.x, $0.y) })

        var parts: [MeshResource.Part] = []
        for (i, group) in groups.enumerated() {
            var part = MeshResource.Part(id: "\(name)-part\(i)", materialIndex: group.material)
            part.positions = ps
            part.normals = ns
            part.textureCoordinates = ts
            // MeshData carries Int32 because that is what the rasteriser wanted;
            // RealityKit wants UInt32. Indices are never negative — `addTriangle`
            // only ever appends values returned by `addVertex` — so this is a
            // widening.
            part.triangleIndices = MeshBuffers.TriangleIndices(indices[group.range].map { UInt32($0) })
            parts.append(part)
        }

        var contents = MeshResource.Contents()
        contents.models = [MeshResource.Model(id: name, parts: parts)]
        contents.instances = [MeshResource.Instance(id: "\(name)-instance", model: name)]

        guard let resource = try? MeshResource.generate(from: contents) else { return nil }
        #if DEBUG
        MeshSourceRegistry.record(resource, self)
        #endif
        return resource
    }
}

// MARK: - Textures

/// Uploads a drawn `UIImage` to the GPU once and remembers it.
///
/// `TextureFactory` already caches the drawing, which is the expensive half, but
/// the same drawn image is asked for by several materials and gets re-uploaded
/// each time without this. Keyed on the image object rather than on a string, so
/// it cannot disagree with the cache upstream about which picture it is holding.
enum TextureBridge {
    private static var cache: [ObjectIdentifier: TextureResource] = [:]
    private static var retained: [UIImage] = []

    /// - Parameter semantic: what the pixels *mean*, which decides the colour space
    ///   they are read in. A normal map read as sRGB still looks like a normal map;
    ///   it just has every slope wrong by the gamma curve. There is no way to spot
    ///   that by looking, so it is stated at every call site rather than defaulted.
    static func resource(_ image: UIImage,
                         semantic: TextureResource.Semantic) -> TextureResource? {
        let key = ObjectIdentifier(image)
        if let hit = cache[key] { return hit }
        guard let cg = image.cgImage else { return nil }
        guard let made = try? TextureResource(image: cg,
                                              withName: nil,
                                              options: .init(semantic: semantic)) else { return nil }
        cache[key] = made
        retained.append(image)
        return made
    }

    /// A material parameter texture that repeats. RealityKit's default sampler
    /// clamps, which on a surface with a tile factor shows one repeat and then a
    /// smear — a failure that reads as a broken UV rather than a broken sampler.
    static func tiling(_ image: UIImage,
                       semantic: TextureResource.Semantic) -> MaterialParameters.Texture? {
        guard let resource = resource(image, semantic: semantic) else { return nil }
        var sampler = MaterialParameters.Texture.Sampler()
        sampler.modify { descriptor in
            descriptor.sAddressMode = .repeat
            descriptor.tAddressMode = .repeat
        }
        return MaterialParameters.Texture(resource, sampler: sampler)
    }

    static func clearCache() {
        cache.removeAll()
        retained.removeAll()
    }
}

// MARK: - Entity convenience

extension Entity {

    /// Entity factory that realises mesh data and attaches a material in one step.
    static func make(_ mesh: MeshData, _ material: RealityKit.Material, name: String? = nil) -> Entity {
        make(mesh, [material], name: name)
    }

    /// The several-material case: a box whose faces do not all want the same
    /// surface. Slots are indexed as the mesh declared them.
    static func make(_ mesh: MeshData, _ materials: [RealityKit.Material], name: String? = nil) -> Entity {
        let entity = ModelEntity()
        if let resource = mesh.meshResource(name: name ?? "mesh") {
            entity.model = ModelComponent(mesh: resource, materials: materials)
        }
        entity.name = name ?? ""
        return entity
    }

    @discardableResult
    func positioned(_ x: Float, _ y: Float, _ z: Float) -> Entity {
        position = SIMD3<Float>(x, y, z)
        return self
    }

    @discardableResult
    func rotated(_ x: Float, _ y: Float, _ z: Float) -> Entity {
        eulerAngles = SIMD3<Float>(x, y, z)
        return self
    }

    @discardableResult
    func scaled(_ x: Float, _ y: Float, _ z: Float) -> Entity {
        scale = SIMD3<Float>(x, y, z)
        return self
    }

    @discardableResult
    func named(_ n: String) -> Entity {
        name = n
        return self
    }

    /// Adds a child and hands it back, so a hierarchy can be written as one
    /// expression rather than a variable per joint.
    @discardableResult
    func adding(_ child: Entity) -> Entity {
        addChild(child)
        return child
    }

    /// `SCNNode.isHidden` in RealityKit's spelling. Inverted, which is worth
    /// stating: `isEnabled = false` also stops a hidden subtree being simulated,
    /// where SceneKit's hidden node carried on.
    var isHidden: Bool {
        get { !isEnabled }
        set { isEnabled = !newValue }
    }

    /// Makes this entity, and everything under it, something a gesture can land
    /// on.
    ///
    /// Nothing is touchable in RealityKit by default — a hit test used to see
    /// every surface in the room and the code sifted for one belonging to the cat,
    /// and now only what asks gets seen. The trap is that forgetting this is
    /// silent: the scene renders exactly as before and simply never responds.
    func enableInput(recursive: Bool = true) {
        if let model = (self as? ModelEntity)?.model {
            let shape = ShapeResource.generateConvex(from: model.mesh)
            components.set(CollisionComponent(shapes: [shape], isStatic: true))
            components.set(InputTargetComponent())
        }
        guard recursive else { return }
        for child in children { child.enableInput() }
    }

    /// This entity's material, for reading. Writing goes through `withMaterial`.
    var pbrMaterial: PhysicallyBasedMaterial? {
        (self as? ModelEntity)?.model?.materials.first as? PhysicallyBasedMaterial
    }

    /// The material on this entity's model, if it has one. Materials are values in
    /// RealityKit, so changing one means reading it out, editing it and putting it
    /// back — there is no shared object to mutate the way `SCNMaterial` was.
    func withMaterial(_ body: (inout PhysicallyBasedMaterial) -> Void) {
        guard let model = (self as? ModelEntity)?.model,
              var material = model.materials.first as? PhysicallyBasedMaterial else { return }
        body(&material)
        (self as? ModelEntity)?.model?.materials = [material]
    }
}
