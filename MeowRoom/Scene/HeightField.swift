import Foundation

/// A tileable greyscale relief map, and the maps derived from it.
///
/// Every surface in the room is currently albedo-only: the tatami weave, the wood
/// grain and the fur are *painted* shading, so they are lit identically from every
/// direction and never move with the sun. This is where that gets fixed — a real
/// height field, from which normals, roughness and cavity occlusion all fall out.
///
/// Deliberately pure Foundation over `[Float]`. Core Graphics is a no-op in the
/// Linux shim, so anything drawn with `CGContext` cannot be checked without a
/// device. Everything here can, which matters a great deal while CI is unavailable.
///
/// **Convention.** Row 0 is the top, matching Core Graphics' y-down image space, so
/// the albedo drawn by `TextureFactory` and the relief drawn here line up sample for
/// sample. `normalMap` takes a `flipGreen` for the one axis this makes ambiguous.
///
/// **Everything wraps.** Sampling, blurring and every draw call use wrapped indices,
/// and the noise is periodic by construction. A tiled floor made from this has no
/// grid in it, which is the single most common giveaway in procedural rooms.
struct HeightField {

    let size: Int
    private(set) var samples: [Float]

    init(size: Int, fill: Float = 0.5) {
        precondition(size > 0, "a height field needs at least one texel")
        self.size = size
        self.samples = [Float](repeating: fill, count: size * size)
    }

    // MARK: - Access

    /// Wrapping access. Out-of-range coordinates fold back around the tile, which is
    /// what makes the blur and the Sobel seamless at the edges rather than clamping
    /// into a visible border.
    subscript(x: Int, y: Int) -> Float {
        get { samples[index(x, y)] }
        set { samples[index(x, y)] = newValue }
    }

    private func index(_ x: Int, _ y: Int) -> Int {
        let wx = ((x % size) + size) % size
        let wy = ((y % size) + size) % size
        return wy * size + wx
    }

    /// Bilinear sample in texel coordinates, wrapping.
    func sample(_ x: Float, _ y: Float) -> Float {
        let x0 = Int(floorf(x)), y0 = Int(floorf(y))
        let fx = x - floorf(x), fy = y - floorf(y)
        let a = mix(self[x0, y0], self[x0 + 1, y0], fx)
        let b = mix(self[x0, y0 + 1], self[x0 + 1, y0 + 1], fx)
        return mix(a, b, fy)
    }

    // MARK: - Generators

    /// Fractal value noise that tiles exactly.
    ///
    /// `ValueNoise` in `MathUtils` wraps its permutation table at 256 lattice cells,
    /// so it only tiles at that one period — no use here, where the period has to be
    /// whatever the feature size demands. This uses an integer hash taken modulo an
    /// explicit period instead, and each octave gets its own period, so every octave
    /// tiles and therefore so does the sum.
    ///
    /// - Parameter cells: lattice cells across the tile at the first octave.
    mutating func addNoise(seed: UInt64,
                           cells: Int,
                           octaves: Int = 4,
                           amplitude: Float = 1,
                           gain: Float = 0.5) {
        var amp = amplitude
        var period = max(1, cells)
        var octave: UInt64 = 0
        for _ in 0..<max(1, octaves) {
            let scale = Float(period) / Float(size)
            for y in 0..<size {
                for x in 0..<size {
                    let v = HeightField.tileableNoise(Float(x) * scale,
                                                      Float(y) * scale,
                                                      period: period,
                                                      seed: seed &+ octave &* 0x9E37)
                    samples[y * size + x] += (v * 2 - 1) * amp
                }
            }
            amp *= gain
            period *= 2
            octave &+= 1
        }
    }

    /// Directional fibre: noise stretched along one axis, which is what reads as
    /// wood grain, woven rush, and combed fur rather than as generic lumpiness.
    ///
    /// - Parameter along: 0 stretches across x (grain runs horizontally), 1 along y.
    mutating func addGrain(seed: UInt64,
                           cells: Int,
                           stretch: Float = 8,
                           amplitude: Float = 0.1,
                           along: Int = 0) {
        let period = max(1, cells)
        // The stretched axis needs an integer period too, or the grain will not meet
        // itself across the tile edge. Rounding here, rather than dividing the float
        // scale, is what keeps that exact.
        let longPeriod = max(1, Int((Float(period) / max(1, stretch)).rounded()))
        for y in 0..<size {
            for x in 0..<size {
                let u = Float(x) / Float(size)
                let v = Float(y) / Float(size)
                let nx = along == 0 ? u * Float(longPeriod) : u * Float(period)
                let ny = along == 0 ? v * Float(period) : v * Float(longPeriod)
                let px = along == 0 ? longPeriod : period
                let py = along == 0 ? period : longPeriod
                let n = HeightField.tileableNoise2(nx, ny, periodX: px, periodY: py, seed: seed)
                samples[y * size + x] += (n * 2 - 1) * amplitude
            }
        }
    }

    /// A soft capsule: the primitive behind a fur hair, a rush fibre and a sisal strand.
    /// Coordinates are in texels and may run off the tile — they wrap.
    mutating func addStroke(x0: Float, y0: Float, x1: Float, y1: Float,
                            width: Float, height: Float) {
        let r = max(0.5, width * 0.5)
        let minX = Int(floorf(min(x0, x1) - r)), maxX = Int(ceilf(max(x0, x1) + r))
        let minY = Int(floorf(min(y0, y1) - r)), maxY = Int(ceilf(max(y0, y1) + r))
        let dx = x1 - x0, dy = y1 - y0
        let lenSq = max(1e-6, dx * dx + dy * dy)
        for y in minY...maxY {
            for x in minX...maxX {
                let px = Float(x) - x0, py = Float(y) - y0
                let t = min(max((px * dx + py * dy) / lenSq, 0), 1)
                let cx = px - dx * t, cy = py - dy * t
                let d = sqrtf(cx * cx + cy * cy)
                if d > r { continue }
                // Smooth falloff across the width, so a hair is a rounded ridge
                // rather than a rectangular kerb that Sobel turns into a hard wall.
                let f = 1 - d / r
                self[x, y] += height * f * f * (3 - 2 * f)
            }
        }
    }

    /// A soft round bump — a pebble of litter, a plaster nib, a paw-pad dome.
    mutating func addDisc(cx: Float, cy: Float, radius: Float, height: Float, falloff: Float = 2) {
        let r = max(0.5, radius)
        let minX = Int(floorf(cx - r)), maxX = Int(ceilf(cx + r))
        let minY = Int(floorf(cy - r)), maxY = Int(ceilf(cy + r))
        for y in minY...maxY {
            for x in minX...maxX {
                let px = Float(x) - cx, py = Float(y) - cy
                let d = sqrtf(px * px + py * py)
                if d > r { continue }
                self[x, y] += height * powf(1 - d / r, falloff)
            }
        }
    }

    // MARK: - Filters

    /// Rescales the whole field into `range`. Called before baking so `reliefMetres`
    /// means what it says: the full span of the field is exactly that many metres.
    mutating func normalize(to range: ClosedRange<Float> = 0...1) {
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for s in samples { lo = min(lo, s); hi = max(hi, s) }
        let span = hi - lo
        let outSpan = range.upperBound - range.lowerBound
        if span < 1e-6 {
            // A flat field has no relief to stretch; park it in the middle rather
            // than dividing by zero and filling the map with NaN.
            for i in samples.indices { samples[i] = (range.lowerBound + range.upperBound) * 0.5 }
            return
        }
        for i in samples.indices {
            samples[i] = range.lowerBound + (samples[i] - lo) / span * outSpan
        }
    }

    /// Separable box blur, wrapping. Used for the cavity term.
    func blurred(radius: Int) -> HeightField {
        guard radius > 0 else { return self }
        let r = min(radius, size / 2)
        let inv = 1 / Float(r * 2 + 1)
        var pass = self
        var out = self
        for y in 0..<size {
            for x in 0..<size {
                var sum: Float = 0
                for k in -r...r { sum += self[x + k, y] }
                pass[x, y] = sum * inv
            }
        }
        for y in 0..<size {
            for x in 0..<size {
                var sum: Float = 0
                for k in -r...r { sum += pass[x, y + k] }
                out[x, y] = sum * inv
            }
        }
        return out
    }

    // MARK: - Baking

    /// Tangent-space normal map, RGBA8, row-major from the top.
    ///
    /// - Parameter slopeScale: metres of relief per metre of surface — that is,
    ///   `reliefMetres / texelMetres`. Passing a bare "strength" instead is the trap
    ///   the plan called out: the same field baked for a surface tiled 2× and one
    ///   tiled 6× needs different slopes, or the denser tiling comes out flattened.
    ///   Use `SurfaceRelief.slopeScale` rather than guessing.
    /// - Parameter flipGreen: the field is authored y-down, so the v derivative runs
    ///   opposite to the usual OpenGL-style green-up convention. Default `true`
    ///   produces green-up; flip it if the renderer disagrees.
    func normalMap(slopeScale: Float, flipGreen: Bool = true) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                // Central difference, not Sobel.
                //
                // Sobel averages across three rows, which is the right call for
                // scanned or noisy height data and the wrong one here: this field
                // is computed, so it has no noise to reject, and its finest
                // features — a tatami cord about three texels wide, a single fur
                // hair about one — are narrower than Sobel's kernel. Sobel turned
                // the tatami weave into a 4.7° suggestion of a weave. This keeps it.
                let dx = (self[x + 1, y] - self[x - 1, y]) * 0.5
                let dy = (self[x, y + 1] - self[x, y - 1]) * 0.5

                // The normal leans *against* the slope: uphill in +u tilts the
                // normal toward -u. This is the sign the harness pins with a ramp.
                var nx = -dx * slopeScale
                var ny = -dy * slopeScale
                if flipGreen { ny = -ny }
                let nz: Float = 1
                let inv = 1 / sqrtf(nx * nx + ny * ny + nz * nz)
                nx *= inv; ny *= inv
                let z = nz * inv

                let o = (y * size + x) * 4
                out[o + 0] = HeightField.encode(nx)
                out[o + 1] = HeightField.encode(ny)
                out[o + 2] = HeightField.encode(z)
                out[o + 3] = 255
            }
        }
        return out
    }

    /// Roughness from relief: the raised parts of a woven or grained surface catch
    /// the light and are smoother; the recesses hold dust and are rougher.
    /// `variation` is signed — pass a negative value where the *peaks* should be the
    /// rough ones, as on plaster.
    func roughnessMap(base: Float, variation: Float) -> [UInt8] {
        var out = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let v = min(max(base - (samples[i] - 0.5) * 2 * variation, 0), 1)
            let g = UInt8(min(max(v * 255, 0), 255))
            out[i * 4 + 0] = g; out[i * 4 + 1] = g; out[i * 4 + 2] = g
        }
        return out
    }

    /// Cavity occlusion: how far below its own neighbourhood each texel sits.
    /// Cheap, stable, and exactly the detail that screen-space AO cannot resolve.
    func occlusionMap(radius: Int = 6, strength: Float = 1) -> [UInt8] {
        let wide = blurred(radius: radius)
        var out = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let cavity = max(0, wide.samples[i] - samples[i])
            let ao = min(max(1 - cavity * 2 * strength, 0), 1)
            let g = UInt8(min(max(ao * 255, 0), 255))
            out[i * 4 + 0] = g; out[i * 4 + 1] = g; out[i * 4 + 2] = g
        }
        return out
    }

    /// Rounds rather than truncates. Truncating puts flat at 127, which is a
    /// permanent half-step lean across every surface in the game — invisible on its
    /// own, and exactly the sort of bias that shows up as a mystery once it is
    /// multiplied by a low sun angle.
    /// RMS gradient of the field, in height units per texel.
    ///
    /// The bridge between "how bumpy is this field" and "how strong will the map
    /// look", and the reason the surfaces below are specified by angle rather than
    /// by depth. Depth alone does not predict appearance: wood grain 0.12 mm deep
    /// spread across a 3 mm line is a 2% slope, which is physically right and
    /// completely invisible. Measured across the whole field, this is.
    func rmsGradient() -> Float {
        var sum: Float = 0
        for y in 0..<size {
            for x in 0..<size {
                let dx = (self[x + 1, y] - self[x - 1, y]) * 0.5
                let dy = (self[x, y + 1] - self[x, y - 1]) * 0.5
                sum += dx * dx + dy * dy
            }
        }
        return sqrtf(sum / Float(size * size))
    }

    /// The slope scale that makes this field bake to roughly `degrees` of RMS tilt.
    ///
    /// Solved rather than guessed, so a field can be reworked — more octaves, finer
    /// grain, a different feature size — without silently changing how strong the
    /// surface looks. The harness measures the achieved tilt and holds it to this.
    func slopeScale(forRMSTilt degrees: Float) -> Float {
        let g = rmsGradient()
        guard g > 1e-6 else { return 0 }
        return tanf(degrees * .pi / 180) / g
    }

    /// What the baked map actually achieves, measured the way a renderer sees it:
    /// the RMS angle between each normal and straight out.
    func measuredRMSTilt(slopeScale: Float) -> Float {
        var sum: Float = 0
        for y in 0..<size {
            for x in 0..<size {
                let dx = (self[x + 1, y] - self[x - 1, y]) * 0.5 * slopeScale
                let dy = (self[x, y + 1] - self[x, y - 1]) * 0.5 * slopeScale
                let a = atanf(sqrtf(dx * dx + dy * dy))
                sum += a * a
            }
        }
        return sqrtf(sum / Float(size * size)) * 180 / .pi
    }

    private static func encode(_ v: Float) -> UInt8 {
        UInt8(min(max(((v * 0.5 + 0.5) * 255).rounded(), 0), 255))
    }

    // MARK: - Periodic noise

    /// Integer hash to a unit float. The lattice coordinate is reduced modulo the
    /// period *before* hashing, which is the whole trick: opposite edges of the tile
    /// hash to the same corner values, so the interpolation meets itself exactly.
    static func latticeValue(_ ix: Int, _ iy: Int, periodX: Int, periodY: Int, seed: UInt64) -> Float {
        let px = max(1, periodX), py = max(1, periodY)
        let wx = UInt64(((ix % px) + px) % px)
        let wy = UInt64(((iy % py) + py) % py)
        var h = seed &+ 0x9E3779B97F4A7C15
        h = (h ^ wx) &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 27) ^ wy) &* 0x94D049BB133111EB
        h ^= h >> 31
        return Float(h >> 40) / Float(1 << 24)
    }

    static func tileableNoise(_ x: Float, _ y: Float, period: Int, seed: UInt64) -> Float {
        tileableNoise2(x, y, periodX: period, periodY: period, seed: seed)
    }

    static func tileableNoise2(_ x: Float, _ y: Float, periodX: Int, periodY: Int, seed: UInt64) -> Float {
        let x0 = Int(floorf(x)), y0 = Int(floorf(y))
        let fx = x - floorf(x), fy = y - floorf(y)
        let u = fx * fx * (3 - 2 * fx)
        let v = fy * fy * (3 - 2 * fy)
        let aa = latticeValue(x0, y0, periodX: periodX, periodY: periodY, seed: seed)
        let ba = latticeValue(x0 + 1, y0, periodX: periodX, periodY: periodY, seed: seed)
        let ab = latticeValue(x0, y0 + 1, periodX: periodX, periodY: periodY, seed: seed)
        let bb = latticeValue(x0 + 1, y0 + 1, periodX: periodX, periodY: periodY, seed: seed)
        return mix(mix(aa, ba, u), mix(ab, bb, u), v)
    }
}

/// Where a surface's texture sits in the real room.
///
/// Two jobs. It gates resolution — a surface needs enough texels per metre of wall
/// or floor to survive being looked at. And it converts between the slope the map
/// is baked at and the physical depth that implies, so a surface can be checked
/// for plausibility: tatami rush stands about a millimetre proud, plaster tooth a
/// fifth of that, and anything claiming a centimetre is wrong.
struct SurfaceRelief {
    /// The largest dimension of the surface in metres, from `RoomLayout`.
    var surfaceMetres: Float
    /// How many times the texture repeats across that dimension.
    var tile: Float
    /// Texels across one repeat.
    var mapSize: Int

    /// Metres of surface covered by one texel.
    var texelMetres: Float {
        surfaceMetres / max(1e-6, tile * Float(mapSize))
    }

    /// The depth a given slope scale corresponds to, in metres. Derived rather than
    /// authored: depth is the consequence, appearance is the control.
    func reliefMetres(slopeScale: Float) -> Float {
        slopeScale * texelMetres
    }

    /// Texels per metre of real surface. Below about 256 px/m a surface in frame
    /// reads as blurred once the camera is anywhere near it.
    var texelsPerMetre: Float {
        Float(mapSize) * tile / max(1e-6, surfaceMetres)
    }
}
