import Foundation

/// The relief behind every surface in the room.
///
/// Each entry here is the *physical* counterpart of a `TextureFactory` generator:
/// where that one paints what a surface looks like, this one describes its shape.
/// They are deliberately built from the same structure — the tatami field has the
/// same rush cords and binding threads the albedo draws, the wood grain runs
/// the same way — so the relief lands on the features rather than beside them.
///
/// **Not derived from the albedo.** Reading heights back out of the colour texture
/// would emboss the fake shading we are trying to replace: tabby stripes and the
/// spine gradient are dark, and they are also completely flat. A cat would come out
/// with grooves cut along its stripes. Generating in parallel costs one more pass
/// and gets it right.
///
/// Pure Foundation, so the whole library is exercised headlessly.
enum SurfaceMaps {

    /// A height field plus everything needed to bake it correctly for one surface.
    struct Spec {
        var field: HeightField
        var relief: SurfaceRelief
        /// How strongly the surface should read, as the RMS angle its normals lean
        /// away from flat.
        ///
        /// This is the control, rather than a depth in millimetres, because depth
        /// on its own does not predict appearance — it has to be read against the
        /// width of the features carrying it. Authoring depths directly produced
        /// wood at 0.5° and rope at 30° in the same pass: one invisible, the other
        /// a cliff. Angles are what the eye actually responds to, and unlike depths
        /// they can be measured back off the baked map and held there.
        ///
        /// Roughly: paper and planed wood 2–4°, plaster and fine weave 6–8°, rush
        /// matting and cloth 8–10°, fur 6–14° with length, rope and gravel 16–20°.
        var tiltDegrees: Float
        /// Mid-point roughness for the material.
        var roughnessBase: Float
        /// How far roughness swings with relief. Positive makes the raised parts
        /// smoother — the polished tops of a weave. Negative makes the peaks rough,
        /// which is what plaster tooth and unfinished rope actually do.
        var roughnessVariation: Float
        var occlusionRadius: Int = 6
        var occlusionStrength: Float = 1
        /// Peak-to-trough depth this material really has, in millimetres.
        ///
        /// Not a control — a bound. Tilt says how strong the surface should look;
        /// this says what it is allowed to be. The two pull against each other,
        /// and the pull is informative: the first pass asked plaster for 6° and got
        /// 5.6 mm of relief, which is not a smooth wall, it is stucco. That means
        /// the *features* were too broad, not that the angle was wrong. Tightening
        /// the field until both hold is what keeps this honest rather than merely
        /// vivid.
        var plausibleMillimetres: ClosedRange<Float> = 0.02...6

        /// Solved from the field, so reworking a field's structure never silently
        /// changes how strong its surface looks.
        var slopeScale: Float { field.slopeScale(forRMSTilt: tiltDegrees) }

        /// The physical depth that implies. Reported and sanity-checked, not authored.
        var reliefMetres: Float { relief.reliefMetres(slopeScale: slopeScale) }
    }

    // MARK: - Floor

    /// Woven rush: cords running across the mat, binding threads crossing them.
    /// The cords are the raised part and they are polished by decades of feet, so
    /// roughness dips on the ridges.
    static func tatami() -> Spec {
        let size = 512
        var f = HeightField(size: size, fill: 0)
        // Half as many cords per repeat as the texture used to carry, tiled twice
        // as often — the same 600 cords across the 4.4 m floor, but each one gets
        // 6.8 texels instead of 3.4. At 3.4 the cords were narrower than the
        // gradient kernel and the weave baked out as a suggestion of itself.
        let cords = 75       // matches TextureFactory.tatami
        let threads = 32

        for y in 0..<size {
            // Each cord is a rounded ridge; the gap between them is the shadow line
            // the albedo currently paints and will stop painting.
            let phase = (Float(y) / Float(size) * Float(cords)).truncatingRemainder(dividingBy: 1)
            let ridge = sinf(phase * .pi)
            for x in 0..<size {
                // The binding thread pulls the cord down where it crosses over.
                let cross = (Float(x) / Float(size) * Float(threads)).truncatingRemainder(dividingBy: 1)
                let pinch = powf(sinf(cross * .pi), 6) * 0.35
                f[x, y] = ridge * (1 - pinch)
            }
        }
        // Rush is a natural fibre: no two cords are the same thickness.
        f.addGrain(seed: 12, cells: 75, stretch: 24, amplitude: 0.18, along: 0)
        f.addNoise(seed: 512, cells: 64, octaves: 3, amplitude: 0.05)
        f.normalize()

        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: RoomLayout.halfDepth * 2,
                                          tile: 8, mapSize: size),
                    tiltDegrees: 9,
                    roughnessBase: 0.88, roughnessVariation: 0.16,
                    occlusionRadius: 5, occlusionStrength: 1.2,
                    plausibleMillimetres: 0.6...1.6)
    }

    /// Cloth mat edging — a tight warp, and nothing else.
    static func tatamiBorder() -> Spec {
        let size = 128
        var f = HeightField(size: size, fill: 0)
        // 16 threads across the strip's 3 cm height, so each is about 2 mm and
        // eight texels wide. The first attempt put 64 across 128 texels — two
        // texels per thread, right at Nyquist, where a sine aliases to nearly flat.
        // The measured gradient collapsed, the solver compensated with an enormous
        // slope, and the strip came out claiming 9 mm of relief.
        for y in 0..<size {
            let phase = (Float(y) / Float(size) * 16).truncatingRemainder(dividingBy: 1)
            let ridge = sinf(phase * .pi)
            for x in 0..<size { f[x, y] = ridge }
        }
        f.addNoise(seed: 3, cells: 32, octaves: 2, amplitude: 0.15)
        f.normalize()
        // Measured across the strip's height, not its length. The threads run
        // across a 3 cm edging; the 4.4 m run is the axis with no detail on it, and
        // sizing relief against that axis would overstate the depth by two orders
        // of magnitude. Where a surface is this anisotropic, the finer axis is the
        // one that governs.
        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: 0.03, tile: 1, mapSize: size),
                    tiltDegrees: 5,
                    roughnessBase: 0.82, roughnessVariation: 0.10,
                    plausibleMillimetres: 0.1...0.8)
    }

    // MARK: - Wood

    /// Grain runs down the board, as the albedo draws it. Softwood loses its early
    /// wood first, so the grain lines sit slightly *below* the surface.
    static func wood(grain: Float = 1, tiltDegrees: Float = 2.5, seed: UInt64 = 77) -> Spec {
        let size = 512
        var f = HeightField(size: size, fill: 0)
        f.addGrain(seed: seed, cells: 200, stretch: 14, amplitude: 0.5, along: 1)
        f.addGrain(seed: seed &+ 5, cells: 440, stretch: 20, amplitude: 0.30 * grain, along: 1)
        // Broad cupping across the board — this is what catches a raking sun and
        // tells you the surface is wood rather than a printed panel. Kept small:
        // it is the lowest frequency here, so it dominates the gradient, and every
        // bit of amplitude on it buys depth everywhere without buying detail.
        f.addNoise(seed: seed &+ 11, cells: 6, octaves: 2, amplitude: 0.10)
        f.normalize()
        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: 1.0, tile: 2, mapSize: size),
                    tiltDegrees: tiltDegrees,
                    roughnessBase: 0.60, roughnessVariation: 0.14,
                    plausibleMillimetres: 0.05...0.6)
    }

    /// Planed hinoki: finer, flatter, and tiled long-ways.
    static func hinoki() -> Spec {
        var spec = wood(grain: 0.6, tiltDegrees: 2, seed: 401)
        spec.relief.tile = 3
        spec.roughnessBase = 0.68
        return spec
    }

    // MARK: - Walls

    /// Trowelled plaster. Fine tooth with occasional nibs; the high points are the
    /// coarse ones, so roughness runs the other way here.
    static func plaster() -> Spec {
        let size = 512
        var f = HeightField(size: size, fill: 0)
        // Fine, and only fine. A wall is flat; what makes it read as plaster and
        // not as painted card is tooth at roughly a millimetre, which at this
        // resolution is two texels. Coarser noise here reads as stucco.
        f.addNoise(seed: 5, cells: 128, octaves: 4, amplitude: 0.5)
        // Trowel drag: long shallow sweeps left by the blade.
        f.addGrain(seed: 6, cells: 90, stretch: 9, amplitude: 0.20, along: 0)
        var rng = SeededGenerator(seed: 6)
        for _ in 0..<900 {
            f.addDisc(cx: rng.float(0, Float(size)), cy: rng.float(0, Float(size)),
                      radius: rng.float(1.2, 3), height: rng.float(0.05, 0.20), falloff: 1.6)
        }
        f.normalize()
        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: RoomLayout.ceilingHeight,
                                          tile: 3, mapSize: size),
                    tiltDegrees: 5,
                    roughnessBase: 0.94, roughnessVariation: -0.10,
                    occlusionRadius: 8, occlusionStrength: 0.8,
                    plausibleMillimetres: 0.2...1.5)
    }

    /// Washi: long fibres suspended in a thin sheet. Barely there, but it is what
    /// makes backlit paper read as paper.
    static func shojiPaper() -> Spec {
        let size = 512
        var f = HeightField(size: size, fill: 0)
        var rng = SeededGenerator(seed: 808)
        for _ in 0..<1400 {
            let x = rng.float(0, Float(size)), y = rng.float(0, Float(size))
            let a = rng.float(0, 2 * .pi), len = rng.float(6, 30)
            f.addStroke(x0: x, y0: y, x1: x + cosf(a) * len, y1: y + sinf(a) * len,
                        width: rng.float(1, 1.8), height: rng.float(0.3, 1))
        }
        f.addNoise(seed: 809, cells: 160, octaves: 3, amplitude: 0.25)
        f.normalize()
        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: 1.2, tile: 2, mapSize: size),
                    tiltDegrees: 0.9,
                    roughnessBase: 0.88, roughnessVariation: 0.08,
                    occlusionRadius: 4, occlusionStrength: 0.5,
                    plausibleMillimetres: 0.02...0.30)
    }

    // MARK: - Cloth and fibre

    /// Plain weave: warp over weft, each thread rising where it crosses on top.
    static func fabric(weave: Float = 1, tiltDegrees: Float = 8) -> Spec {
        let size = 256
        var f = HeightField(size: size, fill: 0)
        let threads = max(4, Int(48 * weave))
        for y in 0..<size {
            let v = Float(y) / Float(size) * Float(threads)
            for x in 0..<size {
                let u = Float(x) / Float(size) * Float(threads)
                // Two perpendicular thread runs; whichever is on top at this cell
                // wins, which is what gives a weave its checkerboard glint.
                let warp = sinf(u * 2 * .pi)
                let weft = sinf(v * 2 * .pi)
                let over = sinf(floorf(u) * .pi) + sinf(floorf(v) * .pi)
                f[x, y] = over >= 0 ? warp : weft
            }
        }
        f.addNoise(seed: 91, cells: 32, octaves: 3, amplitude: 0.22)
        f.normalize()
        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: 0.9, tile: 3, mapSize: size),
                    tiltDegrees: tiltDegrees,
                    roughnessBase: 0.92, roughnessVariation: 0.10,
                    occlusionRadius: 4, occlusionStrength: 1.1,
                    plausibleMillimetres: 0.15...1.0)
    }

    /// Quilted cotton over wadding: the weave, plus the broad puff between stitches.
    static func futonCover() -> Spec {
        var spec = fabric(weave: 1.4, tiltDegrees: 9)
        spec.field.addNoise(seed: 404, cells: 4, octaves: 2, amplitude: 0.9)
        spec.field.normalize()
        spec.relief.surfaceMetres = RoomLayout.futonSize.z
        spec.relief.tile = 3
        spec.roughnessBase = 0.95
        spec.occlusionRadius = 10
        spec.plausibleMillimetres = 1.0...5.0
        return spec
    }

    /// Twisted sisal rope wound around the post. Chunky, and the only surface in the
    /// room whose relief is measured in millimetres rather than fractions of one.
    static func sisal() -> Spec {
        let size = 256
        var f = HeightField(size: size, fill: 0)
        let winds = 20
        for y in 0..<size {
            let phase = (Float(y) / Float(size) * Float(winds)).truncatingRemainder(dividingBy: 1)
            // A rope is a cylinder seen side-on: nearly flat on top, falling away fast.
            let round = powf(sinf(phase * .pi), 0.55)
            for x in 0..<size { f[x, y] = round }
        }
        // Fibres spiralling along each wind.
        f.addGrain(seed: 55, cells: 220, stretch: 5, amplitude: 0.18, along: 0)
        var rng = SeededGenerator(seed: 56)
        for _ in 0..<400 {
            let x = rng.float(0, Float(size)), y = rng.float(0, Float(size))
            f.addStroke(x0: x, y0: y, x1: x + rng.float(-9, 9), y1: y + rng.float(-2, 2),
                        width: 1.4, height: rng.float(0.04, 0.12))
        }
        f.normalize()
        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: 0.5, tile: 6, mapSize: size),
                    tiltDegrees: 18,
                    roughnessBase: 0.97, roughnessVariation: -0.06,
                    occlusionRadius: 8, occlusionStrength: 1.4,
                    plausibleMillimetres: 0.6...4.0)
    }

    /// Clumping pellets. Loose granular material, so almost all of the shading is
    /// occlusion between grains rather than the grain shapes themselves.
    static func litterSubstrate() -> Spec {
        let size = 256
        var f = HeightField(size: size, fill: 0)
        var rng = SeededGenerator(seed: 71)
        for _ in 0..<5200 {
            f.addDisc(cx: rng.float(0, Float(size)), cy: rng.float(0, Float(size)),
                      radius: rng.float(1.2, 3.4), height: rng.float(0.4, 1), falloff: 1.4)
        }
        f.normalize()
        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: 0.34, tile: 2, mapSize: size),
                    tiltDegrees: 16,
                    roughnessBase: 1.0, roughnessVariation: 0,
                    occlusionRadius: 5, occlusionStrength: 1.6,
                    plausibleMillimetres: 1.0...4.0)
    }

    // MARK: - Eyes

    /// The iris, which is not flat.
    ///
    /// A real iris is a pleated muscle: radial fibres standing proud of the stroma,
    /// a collarette ridge partway out, and a rim that falls away into the limbus. It
    /// is also, on a cat, the single feature a player looks at most — the game leans
    /// on the look-at solver precisely so that the cat meets your eye.
    ///
    /// Seeded to match `TextureFactory.iris`, which strokes its fibres from
    /// `SeededGenerator(seed: 4242)` at the same radii, so the relief sits on the
    /// fibres that are drawn rather than between them.
    static func iris(size: Int = 256) -> Spec {
        var f = HeightField(size: size, fill: 0.5)
        let c = Float(size) / 2
        let irisR = Float(size) * 0.46

        // Radial fibres. Same count, same seed, same radial extents as the albedo.
        var rng = SeededGenerator(seed: 4242)
        for _ in 0..<420 {
            let ang = rng.float(0, 2 * .pi)
            let r0 = irisR * rng.float(0.18, 0.5)
            let r1 = irisR * rng.float(0.6, 1.0)
            let raised = rng.float() < 0.5
            f.addStroke(x0: c + cosf(ang) * r0, y0: c + sinf(ang) * r0,
                        x1: c + cosf(ang) * r1, y1: c + sinf(ang) * r1,
                        width: rng.float(0.8, 2.4),
                        height: raised ? 0.25 : -0.20)
        }

        // The collarette: the ridge where the pupillary zone meets the ciliary one.
        for i in 0..<720 {
            let ang = Float(i) / 720 * 2 * .pi
            let r = irisR * (0.52 + 0.03 * HeightField.tileableNoise(cosf(ang) * 3, sinf(ang) * 3,
                                                                    period: 16, seed: 99))
            f.addDisc(cx: c + cosf(ang) * r, cy: c + sinf(ang) * r, radius: 3, height: 0.05)
        }

        // And the limbus, where the iris drops away under the cornea.
        for i in 0..<720 {
            let ang = Float(i) / 720 * 2 * .pi
            f.addDisc(cx: c + cosf(ang) * irisR, cy: c + sinf(ang) * irisR, radius: 4, height: -0.06)
        }
        f.normalize()

        return Spec(field: f,
                    // An eye is about 12 mm across and the texture covers it once.
                    relief: SurfaceRelief(surfaceMetres: 0.012, tile: 1, mapSize: size),
                    // Stronger than any room surface. Iris fibres are genuinely deep
                    // relative to how small they are, and this is the one place on
                    // the cat a player looks closely enough to tell.
                    tiltDegrees: 12,
                    // Wet, and the fibres catch the light more than the crypts do.
                    roughnessBase: 0.12, roughnessVariation: 0.08,
                    occlusionRadius: 4, occlusionStrength: 1.2,
                    plausibleMillimetres: 0.02...0.35)
    }

    // MARK: - The cat

    /// Fur, combed by the same field the albedo strokes follow.
    ///
    /// `drawFurDetail` lays each hair at
    /// `noise.value(x * 0.01, y * 0.01) * 0.9 + π/2` using `ValueNoise(seed: a.seed)`.
    /// Reproducing that here — same noise, same seed, same constants — is what puts
    /// the relief on the hairs instead of across them, which is the difference
    /// between fur and a scouring pad.
    static func catCoat(_ a: CatAppearance, size: Int = 512) -> Spec {
        var f = HeightField(size: size, fill: 0)
        let scale = Float(size) / 1024   // the constants below were tuned at 1024

        if a.hairless {
            // Suede skin: fine wrinkles, no hairs.
            var rng = SeededGenerator(seed: a.seed &+ 7)
            for _ in 0..<900 {
                let x = rng.float(0, Float(size)), y = rng.float(0, Float(size))
                f.addStroke(x0: x, y0: y,
                            x1: x + rng.float(-9, 9) * scale, y1: y + rng.float(-4, 4) * scale,
                            width: 1.6, height: -rng.float(0.2, 0.6))
            }
            f.addNoise(seed: a.seed &+ 21, cells: 40, octaves: 4, amplitude: 0.35)
            f.normalize()
            return Spec(field: f,
                        relief: SurfaceRelief(surfaceMetres: 0.55, tile: 1, mapSize: size),
                        tiltDegrees: 2,
                        roughnessBase: 0.45, roughnessVariation: 0.12,
                        occlusionRadius: 6, occlusionStrength: 0.7,
                        // A sphynx's wrinkles are real folds, not surface texture.
                        plausibleMillimetres: 0.05...1.6)
        }

        let comb = ValueNoise(seed: a.seed)
        var rng = SeededGenerator(seed: a.seed &+ 7)
        let hairs = Int(Float(2600 * (0.4 + a.furDensity)) * scale * scale)
        let hairLen = mix(5, 26, a.furLength) * scale
        let width = (0.7 + a.furCoarseness * 1.6) * scale

        for _ in 0..<max(1, hairs) {
            let x = rng.float(0, Float(size)), y = rng.float(0, Float(size))
            // The albedo samples the comb in 1024-space, so scale back into it.
            let ang = comb.value(x / scale * 0.01, y / scale * 0.01) * 0.9 + .pi / 2
            f.addStroke(x0: x, y0: y,
                        x1: x + cosf(ang) * hairLen * 0.35, y1: y + sinf(ang) * hairLen,
                        width: max(0.8, width), height: 1)
        }
        // Clumping — fur separates into locks, more so the longer and coarser it is.
        // Clumping at lock scale, not at body scale. At 16 cells this was 35 mm
        // features, which is the lowest frequency in the field and therefore the
        // one setting its depth — it alone pushed a shorthair coat to 5 mm of
        // implied relief. Locks are more like a centimetre.
        f.addNoise(seed: a.seed &+ 31, cells: 48, octaves: 3,
                   amplitude: Float(hairs) * 0.0004 * (0.4 + a.furLength))
        f.normalize()

        return Spec(field: f,
                    relief: SurfaceRelief(surfaceMetres: 0.55, tile: 1, mapSize: size),
                    // Gentler than it first looks like it should be, on purpose.
                    // One texel of coat covers about a millimetre of cat, so an
                    // individual hair is smaller than a texel and this field is
                    // really describing locks. Bulk fur shape belongs to the mesh
                    // and the fur shells; what the map adds is how light travels
                    // along the lie of the coat. Asked for more, it produced a cat
                    // with a centimetre of implied relief — a shag rug.
                    tiltDegrees: 2.5 + 4.5 * a.furLength,
                    roughnessBase: 0.95 - 0.45 * a.furGloss,
                    roughnessVariation: 0.18 + 0.20 * a.furGloss,
                    occlusionRadius: max(3, Int(10 * scale)),
                    occlusionStrength: 0.6 + 0.5 * a.furDensity,
                    // A shorthair's coat is a couple of millimetres of lock
                    // relief; a Maine Coon's is genuinely most of a centimetre.
                    plausibleMillimetres: 0.2...(2.0 + 9 * a.furLength))
    }
}
