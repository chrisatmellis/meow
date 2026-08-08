import Foundation

/// A cross-section of a lofted limb/body: an ellipse centred on the spine.
struct LoftRing {
    var center: Vec3
    var radiusX: Float
    var radiusY: Float

    init(center: Vec3, radiusX: Float, radiusY: Float) {
        self.center = center
        self.radiusX = radiusX
        self.radiusY = radiusY
    }

    init(z: Float, y: Float = 0, x: Float = 0, radius: Float) {
        self.center = Vec3(x: x, y: y, z: z)
        self.radiusX = radius
        self.radiusY = radius
    }
}

/// Accumulates triangles into raw vertex data.
/// Everything the cat is made of is generated here at runtime — no art assets to ship.
///
/// This deliberately produces no renderer type. `SceneKitAdapter` turns it into an
/// `SCNGeometry` when the scene is built; the verification harness rasterises the
/// same buffers directly without a graphics framework in the way.
final class MeshData {
    private(set) var positions: [Vec3] = []
    private(set) var normals: [Vec3] = []
    private(set) var uvs: [Vec2] = []
    private(set) var indices: [Int32] = []

    func addVertex(_ p: Vec3, uv: Vec2) -> Int32 {
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

    /// Area-weighted vertex normals, shared across coincident positions.
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
        weldNormalsAcrossSeams()
        for j in 0..<normals.count {
            normals[j] = normals[j].normalized
        }
    }

    /// Sums the normals of vertices that sit on top of each other, so both copies
    /// end up facing the same way.
    ///
    /// A closed loft needs two vertex columns at the same place: the sweep starts at
    /// angle 0 and ends at 2π, and the end column carries u = 1 where the start
    /// carries u = 0, so the texture has somewhere to wrap. But each column only
    /// borders the triangles on its own side, so each was averaging half the
    /// surface, and the two halves disagreed — a hard lighting crease running the
    /// length of every tube in the game: the torso, the neck, all four legs, all nine
    /// tail segments.
    ///
    /// Merging the *vertices* would fix the shading and ruin the texture, because the
    /// last facet would then run u from 1 back to 0 and mirror the coat across
    /// itself. Merging only the normals keeps the seam invisible in both.
    ///
    /// Called before normalising, so this is a sum of area-weighted face normals and
    /// stays area-weighted. Positions are quantised to a tenth of a millimetre, which
    /// is far below anything the cat is modelled at and far above float drift.
    func weldNormalsAcrossSeams(epsilon: Float = 1e-4) {
        var groups: [Key: [Int]] = [:]
        groups.reserveCapacity(positions.count)
        for (i, p) in positions.enumerated() {
            groups[Key(p, epsilon), default: []].append(i)
        }
        for (_, members) in groups where members.count > 1 {
            var sum = Vec3.zero
            for m in members { sum += normals[m] }
            for m in members { normals[m] = sum }
        }
    }

    private struct Key: Hashable {
        let x: Int32, y: Int32, z: Int32
        init(_ p: Vec3, _ epsilon: Float) {
            x = Int32((p.x / epsilon).rounded())
            y = Int32((p.y / epsilon).rounded())
            z = Int32((p.z / epsilon).rounded())
        }
    }

    /// Normals are computed lazily so callers that build raw triangles do not have
    /// to remember to ask; the generators below all call `recomputeNormals` anyway.
    func normalsIfNeeded() {
        if normals.allSatisfy({ $0.length < 1e-5 }) { recomputeNormals() }
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
                     vRepeat: Float = 1) -> MeshData {
        // A single ring cannot be swept into anything; a small blob keeps the caller
        // visible in the scene rather than silently drawing nothing.
        guard rings.count >= 2 else { return blob(radius: 0.02) }
        let mesh = MeshData()

        var ringIndices: [[Int32]] = []
        for (ri, ring) in rings.enumerated() {
            var row: [Int32] = []
            let v = Float(ri) / Float(rings.count - 1) * vRepeat
            for s in 0...segments {
                let a = Float(s) / Float(segments) * 2 * .pi
                let p = Vec3(x: ring.center.x + cosf(a) * ring.radiusX,
                             y: ring.center.y + sinf(a) * ring.radiusY,
                             z: ring.center.z)
                let u = Float(s) / Float(segments) * uRepeat
                row.append(mesh.addVertex(p, uv: Vec2(x: u, y: v)))
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
            let c = mesh.addVertex(first.center, uv: Vec2(x: 0.5, y: 0))
            let row = ringIndices[0]
            for s in 0..<segments {
                mesh.addTriangle(c, row[s + 1], row[s])
            }
        }
        if capEnd, let last = rings.last {
            let c = mesh.addVertex(last.center, uv: Vec2(x: 0.5, y: vRepeat))
            let row = ringIndices[rings.count - 1]
            for s in 0..<segments {
                mesh.addTriangle(c, row[s], row[s + 1])
            }
        }

        mesh.recomputeNormals()
        return mesh
    }

    /// A tapered tube from `count` samples of a radius function. Handy for legs and tails.
    /// `vSpan` is how much of the coat texture this part should cover along its
    /// length. Without it every part — a 3 cm tail segment as much as the torso —
    /// maps the whole texture over itself, and the cat comes out looking bandaged.
    static func tube(length: Float,
                     count: Int = 8,
                     segments: Int = 12,
                     radius: (Float) -> Float,
                     offset: ((Float) -> Vec3)? = nil,
                     capStart: Bool = true,
                     capEnd: Bool = true,
                     vSpan: Float = 1) -> MeshData {
        var rings: [LoftRing] = []
        for i in 0...max(1, count) {
            let t = Float(i) / Float(max(1, count))
            let r = max(0.0008, radius(t))
            let o = offset?(t) ?? .zero
            rings.append(LoftRing(center: Vec3(x: o.x, y: o.y, z: t * length + o.z),
                                  radiusX: r, radiusY: r))
        }
        return loft(rings, segments: segments, capStart: capStart, capEnd: capEnd, vRepeat: vSpan)
    }

    /// Flattened cone used for ears — a triangle with thickness and a rounded base.
    static func ear(length: Float, width: Float, thickness: Float, curl: Float,
                    vSpan: Float = 1) -> MeshData {
        var rings: [LoftRing] = []
        let steps = 8
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let taper = powf(1 - t, 0.85)
            let bend = curl * t * t * length * 0.55
            rings.append(LoftRing(center: Vec3(x: 0, y: -bend, z: t * length),
                                  radiusX: width * 0.5 * taper + 0.0008,
                                  radiusY: thickness * 0.5 * taper + 0.0006))
        }
        return loft(rings, segments: 10, capStart: true, capEnd: true, vRepeat: vSpan)
    }

    /// A rounded, slightly squashed sphere. Used for skulls, muzzles, paws and cushions.
    ///
    /// The poles are capped rather than left open. `sinf(0)` is zero, so the first
    /// and last rings collapse to a point — except that the radius was floored at
    /// 0.6 mm to keep the loft well-formed, which left a 0.6 mm hole at each pole
    /// ringed by degenerate slivers. On a 7 mm nose and on every paw that is a
    /// visible pinprick that catches the light from inside the mesh.
    static func blob(radius: Float,
                     scaleX: Float = 1, scaleY: Float = 1, scaleZ: Float = 1,
                     rings ringCount: Int = 14,
                     segments: Int = 18,
                     vSpan: Float = 1) -> MeshData {
        var rings: [LoftRing] = []
        for i in 0...ringCount {
            let t = Float(i) / Float(ringCount)
            let phi = t * Float.pi
            let r = sinf(phi)
            let z = -cosf(phi) * radius * scaleZ
            rings.append(LoftRing(center: Vec3(x: 0, y: 0, z: z),
                                  radiusX: max(0.0006, r * radius * scaleX),
                                  radiusY: max(0.0006, r * radius * scaleY)))
        }
        // Capped at both ends: the caps are the size of the floored radius, so they
        // are two tiny fans and cost nothing, and the surface closes.
        return loft(rings, segments: segments, capStart: true, capEnd: true, vRepeat: vSpan)
    }

    /// A flat quad in the XZ plane, e.g. a futon top or a rug.
    static func quadXZ(width: Float, depth: Float, y: Float = 0) -> MeshData {
        let mesh = MeshData()
        let hw = width * 0.5, hd = depth * 0.5
        let a = mesh.addVertex(Vec3(x: -hw, y: y, z: -hd), uv: Vec2(x: 0, y: 0))
        let b = mesh.addVertex(Vec3(x: hw, y: y, z: -hd), uv: Vec2(x: 1, y: 0))
        let c = mesh.addVertex(Vec3(x: hw, y: y, z: hd), uv: Vec2(x: 1, y: 1))
        let d = mesh.addVertex(Vec3(x: -hw, y: y, z: hd), uv: Vec2(x: 0, y: 1))
        mesh.addQuad(a, d, c, b)   // normal points +Y
        mesh.recomputeNormals()
        return mesh
    }

    /// Thin strands (whiskers, sisal fibres) drawn as very skinny tapered tubes.
    ///
    /// Six sides rather than four. A whisker is one of the few things on a cat that
    /// is routinely seen against a bright window, in silhouette, where a four-sided
    /// tube is a square prism and reads as one — and it costs 5 triangles a whisker
    /// to fix across the fourteen the cat has.
    static func strand(length: Float, thickness: Float, droop: Float, segments: Int = 6) -> MeshData {
        return tube(length: length, count: 5, segments: max(3, segments), radius: { t in
            thickness * (1 - t * 0.85) + 0.00015
        }, offset: { t in
            Vec3(x: 0, y: -droop * t * t * length, z: 0)
        }, capStart: true, capEnd: true, vSpan: 0.05)
    }
}
