import Foundation
import RealityKit

/// A baked skeletal animation clip — one specific walk cycle, sampled dense
/// (one recorded pose per frame, not sparse keyframes) because that's what the
/// source already is: a Blender action, baked frame-by-frame by its own USD
/// exporter and turned into this flat binary by `Tools/usd/export-anim.py`.
///
/// This exists for one reason: the procedural leg IK in `CatAnimator` is
/// correct but plain — it swings a foot through a sine-shaped arc, which reads
/// as adequate rather than alive. The source `.blend` came with an actual
/// authored/mocap-smooth walk cycle sitting unused; this plays it back.
///
/// It replaces leg motion only, not the whole animator — see
/// `CatAnimator.applyWalkClip`. A clip like this is baked for one specific set
/// of bone lengths (whatever the source model's were), so it is a prototype
/// tradeoff in the same spirit as `TextureFactory.catCoatBaked`: real, smooth
/// motion for the one cat this was authored on, at the cost of the leg-length
/// adaptability the IK solver has for other breeds. See `Tools/usd/TASKS.md`.
struct CatWalkClip {
    /// The skeleton this clip was baked against. Not enforced against
    /// `CatMeshAsset.jointCount` at load time — a mismatch shows up as a joint
    /// index out of range when applied, not as a load failure, because the two
    /// files are versioned independently and a stale clip should not crash the
    /// whole cat, only fail to animate.
    let jointCount: Int
    let frameCount: Int
    let fps: Float
    /// Raw joint indices (same space as `CatMeshAsset.parents`) this clip has
    /// data for, in the order its per-frame arrays are laid out.
    let drivenJoints: [Int]
    /// Per frame, per entry in `drivenJoints`: local rotation then translation
    /// (metres), flattened frame-major.
    private let rotations: [simd_quatf]
    private let translations: [SIMD3<Float>]

    var duration: Float { Float(frameCount) / fps }

    enum LoadError: Error { case missing, malformed }

    static func load(_ name: String, in bundle: Bundle = .main) throws -> CatWalkClip {
        guard let url = bundle.url(forResource: name, withExtension: "catanim") else {
            throw LoadError.missing
        }
        return try CatWalkClip(data: try Data(contentsOf: url))
    }

    init(data: Data) throws {
        var at = 0
        func need(_ n: Int) throws { guard at + n <= data.count else { throw LoadError.malformed } }
        func u32() throws -> Int {
            try need(4)
            defer { at += 4 }
            return Int(UInt32(data[at]) | UInt32(data[at + 1]) << 8
                       | UInt32(data[at + 2]) << 16 | UInt32(data[at + 3]) << 24)
        }
        func u16() throws -> Int {
            try need(2)
            defer { at += 2 }
            return Int(UInt16(data[at]) | UInt16(data[at + 1]) << 8)
        }
        func f32() throws -> Float {
            try need(4)
            defer { at += 4 }
            let bits = UInt32(data[at]) | UInt32(data[at + 1]) << 8
                | UInt32(data[at + 2]) << 16 | UInt32(data[at + 3]) << 24
            return Float(bitPattern: bits)
        }

        try need(8)
        guard data[0..<8].elementsEqual("MEOWANM1".utf8) else { throw LoadError.malformed }
        at = 8

        let jc = try u32()
        let fc = try u32()
        let fpsValue = try f32()
        let dc = try u32()
        guard jc > 0, fc > 0, fpsValue > 0, dc > 0, dc <= jc else { throw LoadError.malformed }

        var driven: [Int] = []
        driven.reserveCapacity(dc)
        for _ in 0..<dc {
            let j = try u16()
            guard j < jc else { throw LoadError.malformed }
            driven.append(j)
        }

        var rots: [simd_quatf] = []
        var trans: [SIMD3<Float>] = []
        rots.reserveCapacity(fc * dc)
        trans.reserveCapacity(fc * dc)
        for _ in 0..<(fc * dc) {
            let qx = try f32(), qy = try f32(), qz = try f32(), qw = try f32()
            let tx = try f32(), ty = try f32(), tz = try f32()
            rots.append(simd_quatf(ix: qx, iy: qy, iz: qz, r: qw))
            trans.append(SIMD3<Float>(tx, ty, tz))
        }

        jointCount = jc
        frameCount = fc
        fps = fpsValue
        drivenJoints = driven
        rotations = rots
        translations = trans
    }

    /// Samples every driven joint at `time` seconds, looping, interpolating
    /// between the two nearest baked frames — slerp for rotation, lerp for
    /// translation. `time` is expected to already be phase-scaled by the
    /// caller (see `CatAnimator`'s `gait` accumulator) rather than wall-clock,
    /// so playback speed follows how fast the cat is actually moving, the same
    /// way the procedural stride does.
    ///
    /// - Parameter apply: called once per driven joint with its raw joint
    ///   index and the sampled local rotation/translation. The caller decides
    ///   which joints to actually act on — see `CatAnimator.applyWalkClip`,
    ///   which only accepts leg and hip joints and leaves the rest of what
    ///   this clip carries (spine, tail, ears) unused, so as not to fight the
    ///   procedural systems already driving those.
    func sample(time: Float, apply: (_ joint: Int, _ rotation: simd_quatf, _ translation: SIMD3<Float>) -> Void) {
        guard duration > 0 else { return }
        var t = time.truncatingRemainder(dividingBy: duration)
        if t < 0 { t += duration }
        let f = t * fps
        let f0 = Int(f) % frameCount
        let f1 = (f0 + 1) % frameCount
        let frac = f - Float(Int(f))

        let dc = drivenJoints.count
        let base0 = f0 * dc
        let base1 = f1 * dc
        for i in 0..<dc {
            let r = simd_slerp(rotations[base0 + i], rotations[base1 + i], frac)
            let p = simd_mix(translations[base0 + i], translations[base1 + i], SIMD3<Float>(repeating: frac))
            apply(drivenJoints[i], r, p)
        }
    }
}
