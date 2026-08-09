import Foundation

/// Engine-neutral vectors for the mesh layer.
///
/// Everything the cat and the room are made of is generated as raw triangles, and
/// that generation deliberately knows nothing about the renderer underneath it.
/// Two things depend on that: the Linux verification harness rasterises this data
/// directly rather than going through a graphics framework, and swapping the
/// renderer becomes a change at the boundary instead of a rewrite of every
/// generator. `SCNVector3` is fine for scene-graph work — it just has no business
/// in the vertex buffers.

struct Vec3: Equatable {
    var x: Float
    var y: Float
    var z: Float

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }

    init(_ x: Float, _ y: Float, _ z: Float) {
        self.init(x: x, y: y, z: z)
    }

    static let zero = Vec3(x: 0, y: 0, z: 0)

    var length: Float { sqrtf(x * x + y * y + z * z) }

    var normalized: Vec3 {
        let l = length
        return l > 1e-6 ? self / l : Vec3(x: 0, y: 0, z: 1)
    }

    /// Axis access by index, so code that has to treat the three axes alike can say
    /// so. A box's twelve edges are four edges repeated for each axis in turn; with
    /// named components that is three copies of the same arithmetic, and three
    /// chances to get one of them wrong.
    subscript(axis: Int) -> Float {
        get {
            switch axis {
            case 0: return x
            case 1: return y
            default: return z
            }
        }
        set {
            switch axis {
            case 0: x = newValue
            case 1: y = newValue
            default: z = newValue
            }
        }
    }
}

func + (l: Vec3, r: Vec3) -> Vec3 { Vec3(x: l.x + r.x, y: l.y + r.y, z: l.z + r.z) }
func - (l: Vec3, r: Vec3) -> Vec3 { Vec3(x: l.x - r.x, y: l.y - r.y, z: l.z - r.z) }
func * (l: Vec3, r: Float) -> Vec3 { Vec3(x: l.x * r, y: l.y * r, z: l.z * r) }
func * (l: Float, r: Vec3) -> Vec3 { r * l }
func / (l: Vec3, r: Float) -> Vec3 { Vec3(x: l.x / r, y: l.y / r, z: l.z / r) }
func += (l: inout Vec3, r: Vec3) { l = l + r }

func dot(_ a: Vec3, _ b: Vec3) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }

func cross(_ a: Vec3, _ b: Vec3) -> Vec3 {
    Vec3(x: a.y * b.z - a.z * b.y,
         y: a.z * b.x - a.x * b.z,
         z: a.x * b.y - a.y * b.x)
}

/// Texture coordinate.
struct Vec2: Equatable {
    var x: Float
    var y: Float

    init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }

    init(_ x: Float, _ y: Float) {
        self.init(x: x, y: y)
    }

    static let zero = Vec2(x: 0, y: 0)
}
