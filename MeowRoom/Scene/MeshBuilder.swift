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
/// This deliberately produces no renderer type. `RealityKitAdapter` turns it into a
/// `MeshResource` when the scene is built; the verification harness rasterises the
/// same buffers directly without a graphics framework in the way.
final class MeshData {
    private(set) var positions: [Vec3] = []
    private(set) var normals: [Vec3] = []
    private(set) var uvs: [Vec2] = []
    private(set) var indices: [Int32] = []

    /// Pairs of vertices that are the same point on the surface wearing two
    /// different texture coordinates. See `weldNormalsAcrossSeams`.
    private var seams: [(Int32, Int32)] = []

    /// Where each material's run of triangles starts, as an index into `indices`.
    /// Empty means the whole mesh takes one material, which is nearly everything.
    private(set) var groupStarts: [(material: Int, start: Int)] = []

    init() {}

    /// Adopts buffers that were built somewhere else — the one asset in the game
    /// arrives already triangulated, with normals and texture coordinates, and
    /// there is nothing for the generators to do to it.
    init(positions: [Vec3], normals: [Vec3], uvs: [Vec2], indices: [Int32]) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.indices = indices
    }

    /// A copy of this surface pushed out along its own normals.
    ///
    /// For fur shells. Scaling a copy about the origin is the obvious thing and
    /// the wrong one: the cat's origin is at its pelvis, so a uniform scale gives
    /// a centimetre of "fur" at the nose and almost none at the hips, and slides
    /// the shell's texture off the hairs painted underneath. The original normals
    /// are kept rather than recomputed — recomputing them on an offset surface
    /// flips them wherever the surface was concave.
    func offsetAlongNormals(_ distance: Float) -> MeshData {
        normalsIfNeeded()
        let moved = zip(positions, normals).map { $0 + $1 * distance }
        let out = MeshData(positions: moved, normals: normals, uvs: uvs, indices: indices)
        return out
    }

    /// Swaps the vertex positions, keeping everything else. The shaping pass
    /// moves vertices without adding or removing any, so the indices, the texture
    /// coordinates and the seam links all stay valid.
    func replacePositions(_ p: [Vec3]) {
        guard p.count == positions.count else { return }
        positions = p
    }

    /// Swaps the vertex normals, keeping everything else. Skinning produces both
    /// at once — a rigid joint transform carries a normal as readily as a point —
    /// so there is nothing to recompute afterwards.
    func replaceNormals(_ n: [Vec3]) {
        guard n.count == normals.count else { return }
        normals = n
    }

    func addVertex(_ p: Vec3, uv: Vec2) -> Int32 {
        positions.append(p)
        normals.append(.zero)
        uvs.append(uv)
        return Int32(positions.count - 1)
    }

    /// Declares that two vertices are the same point on the surface, so they must
    /// end up with the same normal however the triangles around them are split.
    func linkSeam(_ a: Int32, _ b: Int32) {
        guard a != b else { return }
        seams.append((a, b))
    }

    /// Sends the triangles added from here on to a different material slot.
    ///
    /// A tatami mat is woven rush on the two faces you can see and bound cloth on
    /// the four edges — one box, two materials. SceneKit spelled that as an array
    /// on the geometry; RealityKit spells it as several parts in one mesh, each
    /// naming a material index.
    func beginGroup(_ material: Int) {
        if let last = groupStarts.last, last.start == indices.count {
            groupStarts[groupStarts.count - 1] = (material, indices.count)
        } else {
            groupStarts.append((material, indices.count))
        }
    }

    /// The triangle ranges for each material, in the order they were declared.
    var groups: [(material: Int, range: Range<Int>)] {
        guard !groupStarts.isEmpty else { return [(0, 0..<indices.count)] }
        var out: [(Int, Range<Int>)] = []
        // A mesh that starts adding triangles before declaring a group still has to
        // put them somewhere, and slot zero is where a single-material mesh's go.
        if groupStarts[0].start > 0 { out.append((0, 0..<groupStarts[0].start)) }
        for (i, g) in groupStarts.enumerated() {
            let end = i + 1 < groupStarts.count ? groupStarts[i + 1].start : indices.count
            if end > g.start { out.append((g.material, g.start..<end)) }
        }
        return out
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

    /// Sums the normals of vertices that are the same point on the surface, so both
    /// copies end up facing the same way.
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
    /// This used to find those pairs by hashing positions, which was right for a room
    /// made only of lofted curves and became wrong the moment it also had to contain
    /// boxes. A cube's corner is three vertices at one point that must face three
    /// different ways; hashing positions welds them and rounds the cube off. There is
    /// no angle threshold that separates the two cases either — a six-sided whisker's
    /// seam columns are a full 60° apart, further than the 45° of a chamfer that has
    /// to stay sharp. So the generators say which vertices are seam twins instead of
    /// leaving it to be guessed, and everything else keeps its own normal.
    ///
    /// Called before normalising, so this is a sum of area-weighted face normals and
    /// stays area-weighted.
    func weldNormalsAcrossSeams() {
        guard !seams.isEmpty else { return }

        // Seam links are transitive: a pole vertex can be twinned with several
        // others, so the groups are connected components, not pairs.
        var parent = Array(0..<positions.count)
        func find(_ i: Int) -> Int {
            var r = i
            while parent[r] != r { r = parent[r] }
            var c = i
            while parent[c] != c { let n = parent[c]; parent[c] = r; c = n }
            return r
        }
        for (a, b) in seams {
            let ra = find(Int(a)), rb = find(Int(b))
            if ra != rb { parent[ra] = rb }
        }

        var groups: [Int: [Int]] = [:]
        for (a, b) in seams {
            for i in [Int(a), Int(b)] { groups[find(i), default: []].append(i) }
        }
        for (_, members) in groups {
            var sum = Vec3.zero
            var seen = Set<Int>()
            for m in members where seen.insert(m).inserted { sum += normals[m] }
            for m in seen { normals[m] = sum }
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
            // The two ends of the ring are the same point wearing u = 0 and u = 1.
            mesh.linkSeam(row[0], row[segments])
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

    // MARK: - The shapes RealityKit will not generate
    //
    // `MeshResource` generates a box, a plane, a sphere, a cone, a cylinder and
    // text. The room is built from twenty-seven boxes, nineteen cylinders, six
    // tori and five hollow tubes, so the last two have nowhere to come from, and
    // the rest arrive with SceneKit's tessellation baked in rather than sized for
    // a room whose every dimension is known.
    //
    // Axes and winding deliberately match SceneKit's primitives — a box is
    // width × height × length on X/Y/Z, a cylinder and a tube stand on Y, a torus
    // lies in XZ, a plane faces +Z — so that every placement in `RoomBuilder`
    // stays valid and this is a change of renderer rather than a re-layout of the
    // room.

    /// A box, optionally with its twelve edges chamfered.
    ///
    /// The chamfer is the reason this is worth generating rather than taking from
    /// `MeshResource.generateBox`. The walls, the floor and the ceiling are the
    /// largest surfaces in frame and they meet at perfect right angles, so no edge
    /// in the room ever catches a highlight — the single cheapest thing that reads
    /// as "untextured 3D". A two-millimetre chamfer gives every edge a sliver that
    /// faces the light differently from both surfaces it joins.
    ///
    /// Each face, bevel strip and corner gets its own vertices and no seam links,
    /// so every piece shades flat and the edges stay crisp.
    /// - Parameter faceMaterials: when true, each face gets its own material slot,
    ///   numbered as SceneKit numbered them: +Z, +X, -Z, -X, +Y, -Y. The bevels and
    ///   corners go to slot zero, which is right for the case that wants this — a
    ///   tatami mat is woven rush on its two faces and bound cloth round its edge,
    ///   and the cloth is exactly what should wrap the chamfer.
    static func box(width: Float, height: Float, length: Float,
                    chamfer: Float = 0, faceMaterials: Bool = false) -> MeshData {
        let mesh = MeshData()
        let hw = width * 0.5, hh = height * 0.5, hd = length * 0.5
        let c = max(0, min(chamfer, min(hw, min(hh, hd)) * 0.9))

        // Untouched faces, in the order SceneKit numbers them: +Z, +X, -Z, -X, +Y, -Y.
        // Each is given as its centre, its two in-plane axes, and its half extents,
        // which keeps the winding correct without six copies of the same quad code.
        let faces: [(n: Vec3, u: Vec3, v: Vec3, eu: Float, ev: Float, d: Float)] = [
            (Vec3(x: 0, y: 0, z: 1), Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 1, z: 0), hw, hh, hd),
            (Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 0, z: -1), Vec3(x: 0, y: 1, z: 0), hd, hh, hw),
            (Vec3(x: 0, y: 0, z: -1), Vec3(x: -1, y: 0, z: 0), Vec3(x: 0, y: 1, z: 0), hw, hh, hd),
            (Vec3(x: -1, y: 0, z: 0), Vec3(x: 0, y: 0, z: 1), Vec3(x: 0, y: 1, z: 0), hd, hh, hw),
            (Vec3(x: 0, y: 1, z: 0), Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 0, z: -1), hw, hd, hh),
            (Vec3(x: 0, y: -1, z: 0), Vec3(x: 1, y: 0, z: 0), Vec3(x: 0, y: 0, z: 1), hw, hd, hh),
        ]

        /// The point on face `f` at signed in-plane fractions, inset by the chamfer.
        func corner(_ f: (n: Vec3, u: Vec3, v: Vec3, eu: Float, ev: Float, d: Float),
                    _ su: Float, _ sv: Float) -> Vec3 {
            f.n * f.d + f.u * (su * (f.eu - c)) + f.v * (sv * (f.ev - c))
        }

        for (fi, f) in faces.enumerated() {
            if faceMaterials { mesh.beginGroup(fi) }
            let p = [corner(f, -1, -1), corner(f, 1, -1), corner(f, 1, 1), corner(f, -1, 1)]
            let uv = [Vec2(x: 0, y: 1), Vec2(x: 1, y: 1), Vec2(x: 1, y: 0), Vec2(x: 0, y: 0)]
            let i = (0..<4).map { mesh.addVertex(p[$0], uv: uv[$0]) }
            mesh.addQuad(i[0], i[1], i[2], i[3])
        }

        if faceMaterials { mesh.beginGroup(0) }

        if c > 0 {
            // Twelve bevels and eight corner triangles, enumerated from the eight
            // box corners rather than by hand: for each corner, the three points
            // that replace it, one pushed out along each axis.
            let hs = Vec3(x: hw, y: hh, z: hd)
            func trio(_ s: Vec3) -> [Vec3] {
                [Vec3(x: s.x * hs.x, y: s.y * (hs.y - c), z: s.z * (hs.z - c)),
                 Vec3(x: s.x * (hs.x - c), y: s.y * hs.y, z: s.z * (hs.z - c)),
                 Vec3(x: s.x * (hs.x - c), y: s.y * (hs.y - c), z: s.z * hs.z)]
            }
            let signs = [-1, 1].flatMap { x in [-1, 1].flatMap { y in [-1, 1].map { z in
                Vec3(x: Float(x), y: Float(y), z: Float(z)) } } }

            func addTri(_ a: Vec3, _ b: Vec3, _ c0: Vec3) {
                let ia = mesh.addVertex(a, uv: Vec2(x: 0, y: 0))
                let ib = mesh.addVertex(b, uv: Vec2(x: 1, y: 0))
                let ic = mesh.addVertex(c0, uv: Vec2(x: 0.5, y: 1))
                mesh.addTriangle(ia, ib, ic)
            }
            func addQuadFlat(_ a: Vec3, _ b: Vec3, _ c0: Vec3, _ d: Vec3) {
                let ia = mesh.addVertex(a, uv: Vec2(x: 0, y: 0))
                let ib = mesh.addVertex(b, uv: Vec2(x: 1, y: 0))
                let ic = mesh.addVertex(c0, uv: Vec2(x: 1, y: 1))
                let id = mesh.addVertex(d, uv: Vec2(x: 0, y: 1))
                mesh.addQuad(ia, ib, ic, id)
            }

            // Corner triangles. Winding follows the sign of the octant so all eight
            // face outward without a special case.
            for s in signs {
                let t = trio(s)
                if s.x * s.y * s.z > 0 { addTri(t[0], t[1], t[2]) } else { addTri(t[0], t[2], t[1]) }
            }

            // Edge bevels: for each axis, the four edges running parallel to it.
            // `along` indexes the axis the edge runs along; the other two axes carry
            // the signs that pick which of the four.
            for along in 0..<3 {
                let a1 = (along + 1) % 3, a2 = (along + 2) % 3
                for s1 in [Float(-1), 1] {
                    for s2 in [Float(-1), 1] {
                        var lo = Vec3.zero, hi = Vec3.zero
                        lo[along] = -1; hi[along] = 1
                        lo[a1] = s1; hi[a1] = s1
                        lo[a2] = s2; hi[a2] = s2
                        let tl = trio(lo), th = trio(hi)
                        // The bevel joins the two faces normal to a1 and a2, so it
                        // spans the a1-pushed and a2-pushed points at each end.
                        let p = [tl[a1], tl[a2], th[a2], th[a1]]
                        // With (e_along, e_a1, e_a2) a right-handed cycle, this
                        // ordering's cross product comes out along s2·e_a1 + s1·e_a2,
                        // which is the outward direction only when the two signs
                        // agree. Otherwise it is the mirror of it.
                        if s1 * s2 > 0 {
                            addQuadFlat(p[0], p[1], p[2], p[3])
                        } else {
                            addQuadFlat(p[3], p[2], p[1], p[0])
                        }
                    }
                }
            }
        }

        mesh.recomputeNormals()
        return mesh
    }

    /// A flat quad in the XY plane facing +Z, matching `SCNPlane`.
    static func plane(width: Float, height: Float) -> MeshData {
        let mesh = MeshData()
        let hw = width * 0.5, hh = height * 0.5
        let a = mesh.addVertex(Vec3(x: -hw, y: -hh, z: 0), uv: Vec2(x: 0, y: 1))
        let b = mesh.addVertex(Vec3(x: hw, y: -hh, z: 0), uv: Vec2(x: 1, y: 1))
        let c = mesh.addVertex(Vec3(x: hw, y: hh, z: 0), uv: Vec2(x: 1, y: 0))
        let d = mesh.addVertex(Vec3(x: -hw, y: hh, z: 0), uv: Vec2(x: 0, y: 0))
        mesh.addQuad(a, b, c, d)
        mesh.recomputeNormals()
        return mesh
    }

    /// A cylinder standing on Y, centred at the origin, matching `SCNCylinder`.
    ///
    /// The rim is a hard edge: the cap ring and the wall ring are separate vertices
    /// with no seam link between them, so the wall shades smooth all the way round
    /// while the lip stays a lip. Sharing them would round the rim off, which on a
    /// teacup is the difference between porcelain and a balloon.
    static func cylinder(radius: Float, height: Float,
                         segments: Int? = nil,
                         capTop: Bool = true, capBottom: Bool = true) -> MeshData {
        let mesh = MeshData()
        let n = max(3, segments ?? Tessellation.around(radius))
        let hh = height * 0.5

        var top: [Int32] = [], bottom: [Int32] = []
        for s in 0...n {
            let a = Float(s) / Float(n) * 2 * .pi
            let x = cosf(a) * radius, z = -sinf(a) * radius
            let u = Float(s) / Float(n)
            top.append(mesh.addVertex(Vec3(x: x, y: hh, z: z), uv: Vec2(x: u, y: 0)))
            bottom.append(mesh.addVertex(Vec3(x: x, y: -hh, z: z), uv: Vec2(x: u, y: 1)))
        }
        mesh.linkSeam(top[0], top[n])
        mesh.linkSeam(bottom[0], bottom[n])
        for s in 0..<n {
            mesh.addQuad(top[s], bottom[s], bottom[s + 1], top[s + 1])
        }

        if capTop { addDisc(mesh, radius: radius, y: hh, segments: n, up: true) }
        if capBottom { addDisc(mesh, radius: radius, y: -hh, segments: n, up: false) }

        mesh.recomputeNormals()
        return mesh
    }

    /// A hollow tube standing on Y, matching `SCNTube`: an outer wall, an inner
    /// wall facing inward, and an annulus closing each end.
    static func pipe(innerRadius: Float, outerRadius: Float, height: Float,
                     segments: Int? = nil) -> MeshData {
        let mesh = MeshData()
        let n = max(3, segments ?? Tessellation.around(outerRadius))
        let hh = height * 0.5

        func wall(_ radius: Float, outward: Bool) {
            var top: [Int32] = [], bottom: [Int32] = []
            for s in 0...n {
                let a = Float(s) / Float(n) * 2 * .pi
                let x = cosf(a) * radius, z = -sinf(a) * radius
                let u = Float(s) / Float(n)
                top.append(mesh.addVertex(Vec3(x: x, y: hh, z: z), uv: Vec2(x: u, y: 0)))
                bottom.append(mesh.addVertex(Vec3(x: x, y: -hh, z: z), uv: Vec2(x: u, y: 1)))
            }
            mesh.linkSeam(top[0], top[n])
            mesh.linkSeam(bottom[0], bottom[n])
            for s in 0..<n {
                if outward {
                    mesh.addQuad(top[s], bottom[s], bottom[s + 1], top[s + 1])
                } else {
                    mesh.addQuad(top[s + 1], bottom[s + 1], bottom[s], top[s])
                }
            }
        }
        wall(outerRadius, outward: true)
        wall(innerRadius, outward: false)

        for (y, up) in [(hh, true), (-hh, false)] {
            var inner: [Int32] = [], outer: [Int32] = []
            for s in 0...n {
                let a = Float(s) / Float(n) * 2 * .pi
                let cx = cosf(a), cz = -sinf(a)
                let u = Float(s) / Float(n)
                inner.append(mesh.addVertex(Vec3(x: cx * innerRadius, y: y, z: cz * innerRadius),
                                            uv: Vec2(x: u, y: 0)))
                outer.append(mesh.addVertex(Vec3(x: cx * outerRadius, y: y, z: cz * outerRadius),
                                            uv: Vec2(x: u, y: 1)))
            }
            mesh.linkSeam(inner[0], inner[n])
            mesh.linkSeam(outer[0], outer[n])
            for s in 0..<n {
                if up {
                    mesh.addQuad(inner[s], outer[s], outer[s + 1], inner[s + 1])
                } else {
                    mesh.addQuad(inner[s + 1], outer[s + 1], outer[s], inner[s])
                }
            }
        }

        mesh.recomputeNormals()
        return mesh
    }

    /// A torus lying in the XZ plane, matching `SCNTorus`.
    ///
    /// Both directions wrap, so the seam links form a cross: the last ring column
    /// twins the first, the last pipe row twins the first, and the four vertices at
    /// the corner are all one point — which the union of seam links resolves
    /// without any of it being spelled out.
    static func torus(ringRadius: Float, pipeRadius: Float,
                      ringSegments: Int? = nil, pipeSegments: Int? = nil) -> MeshData {
        let mesh = MeshData()
        let sized = Tessellation.torus(ring: ringRadius, pipe: pipeRadius)
        let rn = max(3, ringSegments ?? sized.ring)
        let pn = max(3, pipeSegments ?? sized.pipe)

        var grid: [[Int32]] = []
        for i in 0...rn {
            let theta = Float(i) / Float(rn) * 2 * .pi
            let cx = cosf(theta), cz = -sinf(theta)
            var row: [Int32] = []
            for j in 0...pn {
                let phi = Float(j) / Float(pn) * 2 * .pi
                let r = ringRadius + cosf(phi) * pipeRadius
                let p = Vec3(x: cx * r, y: sinf(phi) * pipeRadius, z: cz * r)
                row.append(mesh.addVertex(p, uv: Vec2(x: Float(i) / Float(rn),
                                                      y: Float(j) / Float(pn))))
            }
            mesh.linkSeam(row[0], row[pn])
            grid.append(row)
        }
        for j in 0...pn { mesh.linkSeam(grid[0][j], grid[rn][j]) }

        for i in 0..<rn {
            for j in 0..<pn {
                mesh.addQuad(grid[i][j], grid[i + 1][j], grid[i + 1][j + 1], grid[i][j + 1])
            }
        }

        mesh.recomputeNormals()
        return mesh
    }

    /// A sphere centred at the origin. `blob` already does this and is what the cat
    /// uses; this is the room-side spelling, sized from its own radius.
    static func sphere(radius: Float, segments: Int? = nil) -> MeshData {
        let n = segments ?? Tessellation.sphere(radius)
        return blob(radius: radius, rings: max(4, n / 2), segments: max(4, n))
    }

    /// A flat disc in the XZ plane. Used for cylinder and cone caps, where the rim
    /// has to stay sharp, so it carries its own ring of vertices.
    private static func addDisc(_ mesh: MeshData, radius: Float, y: Float,
                                segments: Int, up: Bool) {
        let centre = mesh.addVertex(Vec3(x: 0, y: y, z: 0), uv: Vec2(x: 0.5, y: 0.5))
        var ring: [Int32] = []
        for s in 0..<segments {
            let a = Float(s) / Float(segments) * 2 * .pi
            let cx = cosf(a), cz = -sinf(a)
            ring.append(mesh.addVertex(Vec3(x: cx * radius, y: y, z: cz * radius),
                                       uv: Vec2(x: 0.5 + cx * 0.5, y: 0.5 + cz * 0.5)))
        }
        for s in 0..<segments {
            let a = ring[s], b = ring[(s + 1) % segments]
            if up { mesh.addTriangle(centre, a, b) } else { mesh.addTriangle(centre, b, a) }
        }
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
