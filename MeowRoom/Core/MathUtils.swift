import Foundation
import SceneKit

// MARK: - Scalar helpers

@inline(__always) func clamp(_ v: Float, _ lo: Float = 0, _ hi: Float = 1) -> Float {
    return min(max(v, lo), hi)
}

@inline(__always) func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    return min(max(v, lo), hi)
}

@inline(__always) func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + (b - a) * clamp(t)
}

/// Linear interpolation without clamping the parameter.
@inline(__always) func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
    return a + (b - a) * t
}

@inline(__always) func smoothstep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
    guard edge1 != edge0 else { return x < edge0 ? 0 : 1 }
    let t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3 - 2 * t)
}

/// Maps `v` from one range to another, clamped.
@inline(__always) func remap(_ v: Float, _ inLo: Float, _ inHi: Float, _ outLo: Float, _ outHi: Float) -> Float {
    guard inHi != inLo else { return outLo }
    return lerp(outLo, outHi, (v - inLo) / (inHi - inLo))
}

@inline(__always) func deg(_ d: Float) -> Float { d * .pi / 180 }

/// Shortest signed angular difference between two angles, in radians.
func angleDelta(_ from: Float, _ to: Float) -> Float {
    var d = (to - from).truncatingRemainder(dividingBy: .pi * 2)
    if d > .pi { d -= .pi * 2 }
    if d < -.pi { d += .pi * 2 }
    return d
}

/// Frame-rate independent exponential approach. `rate` is roughly "per second".
@inline(__always) func approach(_ current: Float, _ target: Float, rate: Float, dt: Float) -> Float {
    let t = 1 - expf(-max(rate, 0) * max(dt, 0))
    return current + (target - current) * t
}

func approachAngle(_ current: Float, _ target: Float, rate: Float, dt: Float) -> Float {
    let t = 1 - expf(-max(rate, 0) * max(dt, 0))
    return current + angleDelta(current, target) * t
}

// MARK: - SCNVector3 arithmetic

func + (l: SCNVector3, r: SCNVector3) -> SCNVector3 {
    SCNVector3(x: l.x + r.x, y: l.y + r.y, z: l.z + r.z)
}

func - (l: SCNVector3, r: SCNVector3) -> SCNVector3 {
    SCNVector3(x: l.x - r.x, y: l.y - r.y, z: l.z - r.z)
}

func * (l: SCNVector3, r: Float) -> SCNVector3 {
    SCNVector3(x: l.x * r, y: l.y * r, z: l.z * r)
}

func * (l: Float, r: SCNVector3) -> SCNVector3 { r * l }

func / (l: SCNVector3, r: Float) -> SCNVector3 {
    SCNVector3(x: l.x / r, y: l.y / r, z: l.z / r)
}

func += (l: inout SCNVector3, r: SCNVector3) { l = l + r }

extension SCNVector3 {
    static let zero = SCNVector3(x: 0, y: 0, z: 0)

    var length: Float { sqrtf(x * x + y * y + z * z) }

    var normalized: SCNVector3 {
        let l = length
        return l > 1e-6 ? self / l : SCNVector3(x: 0, y: 0, z: 1)
    }

    /// Distance ignoring the vertical axis — the room is effectively 2D for navigation.
    func planarDistance(to other: SCNVector3) -> Float {
        let dx = x - other.x, dz = z - other.z
        return sqrtf(dx * dx + dz * dz)
    }

    func lerped(to other: SCNVector3, _ t: Float) -> SCNVector3 {
        SCNVector3(x: mix(x, other.x, t), y: mix(y, other.y, t), z: mix(z, other.z, t))
    }
}

func dot(_ a: SCNVector3, _ b: SCNVector3) -> Float { a.x * b.x + a.y * b.y + a.z * b.z }

func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(x: a.y * b.z - a.z * b.y,
               y: a.z * b.x - a.x * b.z,
               z: a.x * b.y - a.y * b.x)
}

/// Yaw (rotation about +Y) that points -Z... in room space we treat +Z as the cat's forward.
func yawTowards(from: SCNVector3, to: SCNVector3) -> Float {
    return atan2f(to.x - from.x, to.z - from.z)
}

// MARK: - Deterministic randomness

/// Small, fast, seedable PRNG so a genome can be regenerated identically.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        // splitmix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func float(_ lo: Float = 0, _ hi: Float = 1) -> Float {
        Float.random(in: lo...hi, using: &self)
    }
}

/// Cheap value noise used for fur mottling, wood grain and idle motion.
struct ValueNoise {
    private let perm: [Int]

    init(seed: UInt64) {
        var g = SeededGenerator(seed: seed)
        var p = Array(0..<256)
        p.shuffle(using: &g)
        perm = p + p
    }

    private func grad(_ hash: Int) -> Float {
        Float(perm[hash & 511]) / 255.0 * 2 - 1
    }

    func value(_ x: Float, _ y: Float) -> Float {
        let xi = Int(floorf(x)) & 255
        let yi = Int(floorf(y)) & 255
        let xf = x - floorf(x)
        let yf = y - floorf(y)
        let u = xf * xf * (3 - 2 * xf)
        let v = yf * yf * (3 - 2 * yf)

        let aa = grad(perm[perm[xi] + yi])
        let ba = grad(perm[perm[xi + 1] + yi])
        let ab = grad(perm[perm[xi] + yi + 1])
        let bb = grad(perm[perm[xi + 1] + yi + 1])

        let x1 = mix(aa, ba, u)
        let x2 = mix(ab, bb, u)
        return mix(x1, x2, v)
    }

    func fbm(_ x: Float, _ y: Float, octaves: Int = 4, gain: Float = 0.5, lacunarity: Float = 2.0) -> Float {
        var sum: Float = 0
        var amp: Float = 1
        var freq: Float = 1
        var norm: Float = 0
        for _ in 0..<max(1, octaves) {
            sum += value(x * freq, y * freq) * amp
            norm += amp
            amp *= gain
            freq *= lacunarity
        }
        return norm > 0 ? sum / norm : 0
    }
}
