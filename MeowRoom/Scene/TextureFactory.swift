import Foundation
import UIKit
import CoreGraphics

/// Every texture in the game is drawn at runtime with Core Graphics.
/// Results are cached because the room is rebuilt whenever the player edits the cat.
enum TextureFactory {

    private struct Entry {
        let image: UIImage
        let bytes: Int
        let pinned: Bool
        var lastUsed: UInt64
    }

    private static var cache: [String: Entry] = [:]
    private static let cacheLock = NSLock()
    private static var clock: UInt64 = 0
    private static var bytesUsed = 0

    /// Budgeted in bytes, not entries.
    ///
    /// This used to be a flat count of 48 that dropped everything at once. That was
    /// wrong in both directions: the static room alone uses about thirty slots, and
    /// the day/night `garden-*` and `env-*` buckets pushed past the limit on their
    /// own, so every few hours the whole cache was wiped and the 1024² coat was
    /// redrawn from scratch — a visible hitch, caused by bookkeeping. Counting
    /// entries also treats a 128² border swatch and a 1024² coat as equally
    /// expensive, when one is 64 KB and the other is 4 MB.
    ///
    /// Now that every surface carries a normal, roughness and occlusion map as well
    /// as its colour, the total is roughly four times what it was, which is why this
    /// had to be fixed before the material work rather than after it.
    static var byteBudget: Int {
        switch RenderQuality.tier {
        case .high: return 160 << 20
        case .medium: return 96 << 20
        case .low: return 48 << 20
        }
    }

    /// - Parameter pinned: for surfaces that exist for the whole session and are
    ///   expensive to rebuild — the room's own materials. Pinned entries are never
    ///   evicted, so a long night of sky transitions cannot cost the floor its maps.
    private static func cached(_ key: String, bytes: Int = 0, pinned: Bool = false,
                               _ make: () -> UIImage) -> UIImage {
        cacheLock.lock()
        clock &+= 1
        if var hit = cache[key] {
            hit.lastUsed = clock
            cache[key] = hit
            cacheLock.unlock()
            return hit.image
        }
        cacheLock.unlock()

        let img = make()

        cacheLock.lock()
        clock &+= 1
        // Re-check: another thread may have made the same texture while we were
        // drawing. Keep whichever is already installed so callers never hold two.
        if let hit = cache[key] { cacheLock.unlock(); return hit.image }
        cache[key] = Entry(image: img, bytes: max(bytes, 4096), pinned: pinned, lastUsed: clock)
        bytesUsed += max(bytes, 4096)
        evictIfNeeded()
        cacheLock.unlock()
        return img
    }

    /// Least-recently-used, skipping pinned entries. Caller holds the lock.
    private static func evictIfNeeded() {
        let budget = byteBudget
        guard bytesUsed > budget else { return }
        let evictable = cache.filter { !$0.value.pinned }.sorted { $0.value.lastUsed < $1.value.lastUsed }
        for (key, entry) in evictable {
            cache.removeValue(forKey: key)
            bytesUsed -= entry.bytes
            if bytesUsed <= budget { return }
        }
    }

    /// Bytes an RGBA8 texture of this edge length occupies.
    static func textureBytes(_ size: Int) -> Int { size * size * 4 }

    static func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        bytesUsed = 0
        cacheLock.unlock()
    }

    /// Test and diagnostic access to the cache's accounting.
    static var cacheBytes: Int {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return bytesUsed
    }

    static var cacheCount: Int {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache.count
    }

    static func cacheContains(_ key: String) -> Bool {
        cacheLock.lock(); defer { cacheLock.unlock() }
        return cache[key] != nil
    }

    private static func render(_ size: Int, _ body: (CGContext, CGFloat) -> Void) -> UIImage {
        let s = CGFloat(size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: format)
        return renderer.image { ctx in
            body(ctx.cgContext, s)
        }
    }

    private static func renderAlpha(_ size: Int, _ body: (CGContext, CGFloat) -> Void) -> UIImage {
        let s = CGFloat(size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: s, height: s), format: format)
        return renderer.image { ctx in
            body(ctx.cgContext, s)
        }
    }

    // MARK: - Cat coat

    static func catCoat(_ a: CatAppearance) -> UIImage {
        let key = "coat-\(coatKey(a))"
        return cached(key, bytes: textureBytes(1024)) { drawCoat(a, size: 1024) }
    }

    /// Small, cheap version used by the live preview in the character creator.
    static func catCoatPreview(_ a: CatAppearance) -> UIImage {
        let key = "coatP-\(coatKey(a))"
        return cached(key, bytes: textureBytes(512)) { drawCoat(a, size: 512) }
    }

    private static func coatKey(_ a: CatAppearance) -> String {
        var parts: [String] = []
        parts.append(a.pattern.rawValue)
        parts.append(String(format: "%.3f,%.3f,%.3f", a.baseCoat.r, a.baseCoat.g, a.baseCoat.b))
        parts.append(String(format: "%.3f,%.3f,%.3f", a.markingColor.r, a.markingColor.g, a.markingColor.b))
        parts.append(String(format: "%.3f,%.3f,%.3f", a.bellyColor.r, a.bellyColor.g, a.bellyColor.b))
        parts.append(String(format: "%.3f,%.3f,%.3f", a.pointColor.r, a.pointColor.g, a.pointColor.b))
        parts.append(String(format: "%.3f,%.3f,%.3f", a.whitePatchColor.r, a.whitePatchColor.g, a.whitePatchColor.b))
        parts.append(String(format: "%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f",
                            a.patternContrast, a.patternScale, a.patternIrregularity,
                            a.patternCoverage, a.whiteSpotting, a.tickingAmount, a.undercoatLightness))
        parts.append(String(format: "%.2f,%.2f,%.2f", a.furLength, a.furCoarseness, a.furDensity))
        parts.append("\(a.seed)")
        parts.append(a.hairless ? "h" : "f")
        return parts.joined(separator: "|")
    }

    private static func drawCoat(_ a: CatAppearance, size: Int) -> UIImage {
        let noise = ValueNoise(seed: a.seed)
        var rng = SeededGenerator(seed: a.seed &+ 7)

        return render(size) { ctx, s in
            let base = a.hairless ? a.baseCoat.mixed(with: RGBColor(0.85, 0.7, 0.65), 0.25) : a.baseCoat
            ctx.setFillColor(UIColor(base).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

            // --- Belly / undercoat. u = 0.25 is the spine, u = 0.75 is the belly.
            let bellyCenter = s * 0.75
            let bellyWidth = s * CGFloat(0.16 + 0.16 * a.undercoatLightness)
            ctx.saveGState()
            let bellyColors = [UIColor(a.bellyColor, alpha: 0.95).cgColor,
                               UIColor(a.bellyColor, alpha: 0.0).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: bellyColors, locations: [0, 1]) {
                for dir in [-1.0, 1.0] as [CGFloat] {
                    ctx.saveGState()
                    ctx.clip(to: CGRect(x: bellyCenter + (dir < 0 ? -bellyWidth : 0), y: 0,
                                        width: bellyWidth, height: s))
                    ctx.drawLinearGradient(grad,
                                           start: CGPoint(x: bellyCenter, y: 0),
                                           end: CGPoint(x: bellyCenter + dir * bellyWidth, y: 0),
                                           options: [])
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()

            // --- Darker saddle along the spine for depth.
            ctx.saveGState()
            let spineColors = [UIColor(base.darkened(0.22), alpha: 0.55).cgColor,
                               UIColor(base, alpha: 0.0).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: spineColors, locations: [0, 1]) {
                let spineX = s * 0.25
                for dir in [-1.0, 1.0] as [CGFloat] {
                    ctx.saveGState()
                    ctx.clip(to: CGRect(x: spineX + (dir < 0 ? -s * 0.18 : 0), y: 0, width: s * 0.18, height: s))
                    ctx.drawLinearGradient(grad,
                                           start: CGPoint(x: spineX, y: 0),
                                           end: CGPoint(x: spineX + dir * s * 0.18, y: 0),
                                           options: [])
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()

            drawPattern(a, ctx: ctx, s: s, noise: noise, rng: &rng)
            drawWhiteSpotting(a, ctx: ctx, s: s, rng: &rng)
            drawFurDetail(a, ctx: ctx, s: s, noise: noise, rng: &rng)
        }
    }

    private static func drawPattern(_ a: CatAppearance, ctx: CGContext, s: CGFloat,
                                    noise: ValueNoise, rng: inout SeededGenerator) {
        let mark = UIColor(a.markingColor, alpha: CGFloat(0.22 + 0.52 * a.patternContrast))
        let bellyX = s * 0.75

        switch a.pattern {
        case .solid, .sable:
            break

        case .mackerelTabby:
            // A real mackerel tabby has roughly ten to eighteen stripes along the body.
            let count = Int(mix(8, 18, a.patternScale))
            ctx.setFillColor(mark.cgColor)
            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count)
                let y = t * s + CGFloat(noise.value(Float(i) * 1.7, 0.3)) * s * 0.02
                let h = s / CGFloat(count) * CGFloat(mix(0.22, 0.48, a.patternCoverage))
                // Draw the stripe as a wobbling band that thins toward the belly.
                let steps = 48
                ctx.beginPath()
                var first = true
                for k in 0...steps {
                    let u = CGFloat(k) / CGFloat(steps)
                    let x = u * s
                    let bellyFade = 1 - CGFloat(smoothstep(0.10, 0.34, Float(abs(x - bellyX) / s)))
                    let wob = CGFloat(noise.fbm(Float(u) * 6, Float(i) * 2.3, octaves: 2)) * s * 0.012 * CGFloat(1 + a.patternIrregularity)
                    let yy = y + wob - h * 0.5 * (1 - bellyFade * 0.85)
                    if first { ctx.move(to: CGPoint(x: x, y: yy)); first = false }
                    else { ctx.addLine(to: CGPoint(x: x, y: yy)) }
                }
                for k in stride(from: steps, through: 0, by: -1) {
                    let u = CGFloat(k) / CGFloat(steps)
                    let x = u * s
                    let bellyFade = 1 - CGFloat(smoothstep(0.10, 0.34, Float(abs(x - bellyX) / s)))
                    let wob = CGFloat(noise.fbm(Float(u) * 6, Float(i) * 2.3, octaves: 2)) * s * 0.012 * CGFloat(1 + a.patternIrregularity)
                    let yy = y + wob + h * 0.5 * (1 - bellyFade * 0.85)
                    ctx.addLine(to: CGPoint(x: x, y: yy))
                }
                ctx.closePath()
                ctx.fillPath()
            }

        case .classicTabby:
            ctx.setFillColor(mark.cgColor)
            let blotches = Int(mix(5, 11, a.patternScale))
            for i in 0..<blotches {
                let cy = CGFloat(i) / CGFloat(blotches) * s + CGFloat(rng.float(-0.03, 0.03)) * s
                for sideT in [0.05, 0.45] as [CGFloat] {
                    let cx = sideT * s + CGFloat(rng.float(-0.04, 0.04)) * s
                    let r = s * CGFloat(mix(0.05, 0.11, a.patternScale))
                    ctx.saveGState()
                    ctx.setLineWidth(r * 0.42)
                    ctx.setStrokeColor(mark.cgColor)
                    ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r * 1.3, width: r * 2, height: r * 2.6))
                    ctx.strokeEllipse(in: CGRect(x: cx - r * 0.45, y: cy - r * 0.6,
                                                 width: r * 0.9, height: r * 1.2))
                    ctx.restoreGState()
                }
            }
            // Spine stripes.
            ctx.setFillColor(mark.cgColor)
            for k in 0..<3 {
                let x = s * (0.215 + CGFloat(k) * 0.032)
                ctx.fill(CGRect(x: x, y: 0, width: s * 0.014, height: s))
            }

        case .spottedTabby, .rosetted:
            let count = Int(mix(60, 190, a.patternScale) * (0.5 + a.patternCoverage))
            for _ in 0..<count {
                let x = CGFloat(rng.float(0, 1)) * s
                let y = CGFloat(rng.float(0, 1)) * s
                let bellyFade = CGFloat(smoothstep(0.06, 0.28, Float(abs(x - bellyX) / s)))
                if bellyFade < 0.25 { continue }
                let r = s * CGFloat(mix(0.010, 0.030, a.patternScale)) * CGFloat(rng.float(0.6, 1.4))
                let rect = CGRect(x: x - r, y: y - r * 0.75, width: r * 2, height: r * 1.5)
                if a.pattern == .rosetted {
                    ctx.setFillColor(UIColor(a.markingColor.lightened(0.35),
                                             alpha: CGFloat(0.5 * a.patternContrast) * bellyFade).cgColor)
                    ctx.fillEllipse(in: rect.insetBy(dx: r * 0.3, dy: r * 0.22))
                    ctx.setStrokeColor(UIColor(a.markingColor, alpha: CGFloat(0.85 * a.patternContrast) * bellyFade).cgColor)
                    ctx.setLineWidth(r * 0.36)
                    ctx.strokeEllipse(in: rect)
                } else {
                    ctx.setFillColor(UIColor(a.markingColor,
                                             alpha: CGFloat(0.85 * a.patternContrast) * bellyFade).cgColor)
                    ctx.fillEllipse(in: rect)
                }
            }

        case .tickedTabby:
            break   // handled entirely by the per-hair ticking pass

        case .colorpoint, .mink, .smoke, .shaded:
            // Extremities (both ends of every lofted part) go dark.
            let pointStrength: CGFloat = a.pattern == .mink ? 0.65 : (a.pattern == .shaded ? 0.5 : 1.0)
            let colors = [UIColor(a.pointColor, alpha: pointStrength).cgColor,
                          UIColor(a.pointColor, alpha: 0).cgColor] as CFArray
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let span = s * CGFloat(a.pattern == .smoke ? 0.55 : 0.30)
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: 0, width: s, height: span))
                ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: span), options: [])
                ctx.restoreGState()
                ctx.saveGState()
                ctx.clip(to: CGRect(x: 0, y: s - span, width: s, height: span))
                ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s - span), options: [])
                ctx.restoreGState()
            }

        case .tuxedo, .bicolor, .vanBicolor, .calico, .tortoiseshell, .torbie:
            // Irregular colour patches; white spotting is layered on afterwards.
            let patchCount = a.pattern == .tortoiseshell || a.pattern == .torbie ? 90 : 26
            for _ in 0..<patchCount {
                let x = CGFloat(rng.float(0, 1)) * s
                let y = CGFloat(rng.float(0, 1)) * s
                let r = s * CGFloat(rng.float(0.04, 0.16)) * CGFloat(0.6 + a.patternIrregularity)
                let useSecond = rng.float() < 0.5
                let c = useSecond ? a.pointColor : a.markingColor
                ctx.setFillColor(UIColor(c, alpha: CGFloat(rng.float(0.55, 0.95)) * CGFloat(a.patternContrast)).cgColor)
                ctx.saveGState()
                ctx.beginPath()
                let lobes = 7
                for k in 0...lobes {
                    let ang = CGFloat(k) / CGFloat(lobes) * .pi * 2
                    let rr = r * CGFloat(0.6 + 0.8 * abs(noise.value(Float(ang) * 2.2, Float(x) * 0.02)))
                    let px = x + cos(ang) * rr
                    let py = y + sin(ang) * rr * 0.8
                    if k == 0 { ctx.move(to: CGPoint(x: px, y: py)) } else { ctx.addLine(to: CGPoint(x: px, y: py)) }
                }
                ctx.closePath()
                ctx.fillPath()
                ctx.restoreGState()
            }
            if a.pattern == .torbie {
                ctx.setFillColor(UIColor(a.markingColor, alpha: 0.35).cgColor)
                for i in 0..<22 {
                    let y = CGFloat(i) / 22 * s
                    ctx.fill(CGRect(x: 0, y: y, width: s, height: s * 0.012))
                }
            }
        }
    }

    private static func drawWhiteSpotting(_ a: CatAppearance, ctx: CGContext, s: CGFloat, rng: inout SeededGenerator) {
        guard a.whiteSpotting > 0.02 else { return }
        let white = UIColor(a.whitePatchColor, alpha: 1)
        ctx.setFillColor(white.cgColor)

        // Belly and chest are white first, then it creeps up the sides.
        let bellyX = s * 0.75
        let reach = s * CGFloat(0.10 + 0.30 * a.whiteSpotting)
        ctx.saveGState()
        let colors = [white.cgColor, UIColor(a.whitePatchColor, alpha: 0).cgColor] as CFArray
        if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
            for dir in [-1.0, 1.0] as [CGFloat] {
                ctx.saveGState()
                ctx.clip(to: CGRect(x: bellyX + (dir < 0 ? -reach : 0), y: 0, width: reach, height: s))
                ctx.drawLinearGradient(grad, start: CGPoint(x: bellyX, y: 0),
                                       end: CGPoint(x: bellyX + dir * reach, y: 0), options: [])
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()

        // Socks: the far end of each lofted part (paws, tail tip, chin).
        let sockDepth = s * CGFloat(0.05 + 0.22 * a.whiteSpotting)
        ctx.setFillColor(white.cgColor)
        ctx.fill(CGRect(x: 0, y: s - sockDepth, width: s, height: sockDepth))

        if a.pattern == .vanBicolor {
            ctx.fill(CGRect(x: 0, y: s * 0.18, width: s, height: s * 0.62))
        }

        // A few random splashes for character.
        let splashes = Int(a.whiteSpotting * 14)
        for _ in 0..<splashes {
            let x = CGFloat(rng.float(0, 1)) * s
            let y = CGFloat(rng.float(0, 1)) * s
            let r = s * CGFloat(rng.float(0.02, 0.09))
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.8, width: r * 2, height: r * 1.6))
        }
    }

    private static func drawFurDetail(_ a: CatAppearance, ctx: CGContext, s: CGFloat,
                                      noise: ValueNoise, rng: inout SeededGenerator) {
        guard !a.hairless else {
            // Suede-like skin gets fine wrinkles instead of hair.
            ctx.setStrokeColor(UIColor(a.baseCoat.darkened(0.20), alpha: 0.10).cgColor)
            ctx.setLineWidth(1)
            for _ in 0..<900 {
                let x = CGFloat(rng.float(0, 1)) * s
                let y = CGFloat(rng.float(0, 1)) * s
                ctx.move(to: CGPoint(x: x, y: y))
                ctx.addLine(to: CGPoint(x: x + CGFloat(rng.float(-9, 9)), y: y + CGFloat(rng.float(-4, 4))))
            }
            ctx.strokePath()
            return
        }

        // Per-hair ticking: short strokes in a slightly lighter/darker shade.
        let strokes = Int(2600 * (0.4 + a.furDensity))
        let hairLen = CGFloat(mix(5, 26, a.furLength))
        ctx.setLineCap(.round)
        for _ in 0..<strokes {
            let x = CGFloat(rng.float(0, 1)) * s
            let y = CGFloat(rng.float(0, 1)) * s
            let lighten = rng.float() < 0.5
            let amt = CGFloat(0.05 + 0.22 * a.tickingAmount) * CGFloat(rng.float(0.4, 1.2))
            let c = lighten ? a.baseCoat.lightened(Float(amt)) : a.baseCoat.darkened(Float(amt))
            ctx.setStrokeColor(UIColor(c, alpha: CGFloat(0.10 + 0.30 * a.tickingAmount)).cgColor)
            ctx.setLineWidth(CGFloat(0.7 + a.furCoarseness * 1.6))
            let ang = CGFloat(noise.value(Float(x) * 0.01, Float(y) * 0.01)) * 0.9 + .pi / 2
            ctx.move(to: CGPoint(x: x, y: y))
            ctx.addLine(to: CGPoint(x: x + cos(ang) * hairLen * 0.35, y: y + sin(ang) * hairLen))
            ctx.strokePath()
        }

        // Broad mottling so large areas never look flat.
        for _ in 0..<220 {
            let x = CGFloat(rng.float(0, 1)) * s
            let y = CGFloat(rng.float(0, 1)) * s
            let r = s * CGFloat(rng.float(0.02, 0.08))
            let dark = noise.value(Float(x) * 0.004, Float(y) * 0.004) < 0
            ctx.setFillColor(UIColor(dark ? a.baseCoat.darkened(0.10) : a.baseCoat.lightened(0.08),
                                     alpha: 0.10).cgColor)
            ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }
    }

    /// Soft-edged alpha mask used for the long-fur shell layers.
    static func furShellMask(_ a: CatAppearance) -> UIImage {
        let key = "furshell-\(a.seed)-\(Int(a.furDensity * 20))-\(Int(a.furCoarseness * 20))"
        return cached(key, bytes: textureBytes(512)) {
            renderAlpha(512) { ctx, s in
                ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))
                var rng = SeededGenerator(seed: a.seed &+ 991)
                let count = Int(4200 * (0.35 + a.furDensity))
                for _ in 0..<count {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    let r = CGFloat(rng.float(1.2, 3.6)) * CGFloat(0.6 + a.furCoarseness)
                    ctx.setFillColor(UIColor(white: 1, alpha: CGFloat(rng.float(0.25, 0.85))).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
            }
        }
    }

    // MARK: - Eyes

    static func iris(color: RGBColor, pupil: PupilShape, dilation: Float, brightness: Float) -> UIImage {
        let key = String(format: "iris-%.3f,%.3f,%.3f-%@-%.2f-%.2f", color.r, color.g, color.b,
                         pupil.rawValue, dilation, brightness)
        return cached(key, bytes: textureBytes(256)) {
            render(256) { ctx, s in
                let c = CGPoint(x: s / 2, y: s / 2)
                // Sclera ring (barely visible on a cat, but it catches light).
                ctx.setFillColor(UIColor(white: 0.94, alpha: 1).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

                // Iris with radial fibres.
                let irisR = s * 0.46
                ctx.setFillColor(UIColor(color).cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x - irisR, y: c.y - irisR, width: irisR * 2, height: irisR * 2))

                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: c.x - irisR, y: c.y - irisR, width: irisR * 2, height: irisR * 2))
                ctx.clip()
                var rng = SeededGenerator(seed: 4242)
                for _ in 0..<420 {
                    let ang = CGFloat(rng.float(0, .pi * 2))
                    let r0 = irisR * CGFloat(rng.float(0.18, 0.5))
                    let r1 = irisR * CGFloat(rng.float(0.6, 1.0))
                    let light = rng.float() < 0.5
                    let fibre = light ? color.lightened(0.35) : color.darkened(0.30)
                    ctx.setStrokeColor(UIColor(fibre, alpha: CGFloat(rng.float(0.10, 0.45))).cgColor)
                    ctx.setLineWidth(CGFloat(rng.float(0.8, 2.4)))
                    ctx.move(to: CGPoint(x: c.x + cos(ang) * r0, y: c.y + sin(ang) * r0))
                    ctx.addLine(to: CGPoint(x: c.x + cos(ang) * r1, y: c.y + sin(ang) * r1))
                    ctx.strokePath()
                }
                // Darker limbal ring.
                ctx.setStrokeColor(UIColor(color.darkened(0.6), alpha: 0.85).cgColor)
                ctx.setLineWidth(s * 0.055)
                ctx.strokeEllipse(in: CGRect(x: c.x - irisR, y: c.y - irisR, width: irisR * 2, height: irisR * 2))
                // Warm inner glow near the pupil.
                ctx.setFillColor(UIColor(color.lightened(0.25 + 0.3 * brightness), alpha: 0.45).cgColor)
                let g = irisR * 0.55
                ctx.fillEllipse(in: CGRect(x: c.x - g, y: c.y - g, width: g * 2, height: g * 2))
                ctx.restoreGState()

                // Pupil.
                ctx.setFillColor(UIColor(white: 0.02, alpha: 1).cgColor)
                let d = CGFloat(clamp(dilation, 0.05, 1))
                switch pupil {
                case .slit:
                    let w = irisR * (0.10 + 0.72 * d)
                    let h = irisR * (1.55 - 0.35 * d)
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.addEllipse(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                    ctx.fillPath()
                    ctx.restoreGState()
                case .oval:
                    let w = irisR * (0.30 + 0.55 * d)
                    let h = irisR * (0.62 + 0.5 * d)
                    ctx.fillEllipse(in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
                case .round:
                    let r = irisR * (0.28 + 0.6 * d)
                    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }

                // Specular catchlight.
                ctx.setFillColor(UIColor(white: 1, alpha: 0.9).cgColor)
                let hr = s * 0.055
                ctx.fillEllipse(in: CGRect(x: c.x - irisR * 0.42, y: c.y - irisR * 0.48, width: hr * 2, height: hr * 2))
                ctx.setFillColor(UIColor(white: 1, alpha: 0.4).cgColor)
                ctx.fillEllipse(in: CGRect(x: c.x + irisR * 0.20, y: c.y + irisR * 0.28, width: hr, height: hr))
            }
        }
    }

    // MARK: - Room surfaces

    static func tatami() -> UIImage {
        cached("tatami", bytes: textureBytes(512), pinned: true) {
            render(512) { ctx, s in
                let straw = RGBColor(hex: 0xC9B383)
                ctx.setFillColor(UIColor(straw).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                var rng = SeededGenerator(seed: 12)
                // Woven rush: fine horizontal reeds with slight colour drift.
                // 75 per repeat at a tile factor of 8 — the same cord pitch on the
                // floor as 150 at 4, with twice the texels per cord for the relief
                // pass in SurfaceMaps to resolve.
                let reeds = 75
                for i in 0..<reeds {
                    let y = CGFloat(i) / CGFloat(reeds) * s
                    let h = s / CGFloat(reeds)
                    let shade = Float(rng.float(-0.09, 0.09))
                    let c = shade > 0 ? straw.lightened(shade) : straw.darkened(-shade)
                    ctx.setFillColor(UIColor(c).cgColor)
                    ctx.fill(CGRect(x: 0, y: y, width: s, height: h * 1.05))
                }
                // Cross-weave shadow lines.
                ctx.setStrokeColor(UIColor(straw.darkened(0.30), alpha: 0.30).cgColor)
                ctx.setLineWidth(1)
                for i in 0..<32 {
                    let x = CGFloat(i) / 32 * s
                    ctx.move(to: CGPoint(x: x, y: 0))
                    ctx.addLine(to: CGPoint(x: x, y: s))
                }
                ctx.strokePath()
                // Speckled age.
                for _ in 0..<1400 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    ctx.setFillColor(UIColor(straw.darkened(Float(rng.float(0.05, 0.35))), alpha: 0.14).cgColor)
                    ctx.fill(CGRect(x: x, y: y, width: CGFloat(rng.float(1, 4)), height: 1))
                }
            }
        }
    }

    static func tatamiBorder() -> UIImage {
        cached("tatamiBorder", bytes: textureBytes(128), pinned: true) {
            render(128) { ctx, s in
                let cloth = RGBColor(hex: 0x2E3A46)
                ctx.setFillColor(UIColor(cloth).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                ctx.setStrokeColor(UIColor(cloth.lightened(0.35), alpha: 0.5).cgColor)
                ctx.setLineWidth(1.5)
                for i in 0..<10 {
                    let y = CGFloat(i) / 10 * s
                    ctx.move(to: CGPoint(x: 0, y: y))
                    ctx.addLine(to: CGPoint(x: s, y: y))
                }
                ctx.strokePath()
            }
        }
    }

    static func wood(base: RGBColor, grain: Float = 1.0, key: String) -> UIImage {
        cached("wood-\(key)-\(base.hexKey)-\(Int(grain * 100))", bytes: textureBytes(512), pinned: true) {
            render(512) { ctx, s in
                ctx.setFillColor(UIColor(base).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                let noise = ValueNoise(seed: 77)
                var rng = SeededGenerator(seed: 78)
                // Grain lines running vertically.
                for _ in 0..<Int(260 * grain) {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let dark = rng.float() < 0.6
                    let c = dark ? base.darkened(Float(rng.float(0.06, 0.28))) : base.lightened(Float(rng.float(0.04, 0.16)))
                    ctx.setStrokeColor(UIColor(c, alpha: CGFloat(rng.float(0.12, 0.45))).cgColor)
                    ctx.setLineWidth(CGFloat(rng.float(0.6, 3.0)))
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: x, y: 0))
                    var yy: CGFloat = 0
                    while yy < s {
                        yy += s / 24
                        let off = CGFloat(noise.fbm(Float(x) * 0.01, Float(yy) * 0.008, octaves: 3)) * s * 0.03
                        ctx.addLine(to: CGPoint(x: x + off, y: yy))
                    }
                    ctx.strokePath()
                }
                // Occasional knot.
                for _ in 0..<3 {
                    let cx = CGFloat(rng.float(0.1, 0.9)) * s
                    let cy = CGFloat(rng.float(0.1, 0.9)) * s
                    for k in 0..<7 {
                        let r = CGFloat(4 + k * 5)
                        ctx.setStrokeColor(UIColor(base.darkened(0.30), alpha: 0.35 - CGFloat(k) * 0.04).cgColor)
                        ctx.setLineWidth(2)
                        ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r * 1.4, width: r * 2, height: r * 2.8))
                    }
                }
            }
        }
    }

    static func shojiPaper() -> UIImage {
        cached("shoji", bytes: textureBytes(512), pinned: true) {
            render(512) { ctx, s in
                ctx.setFillColor(UIColor(RGBColor(hex: 0xF2EADA)).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                var rng = SeededGenerator(seed: 33)
                // Washi fibres.
                ctx.setLineCap(.round)
                for _ in 0..<1200 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    let len = CGFloat(rng.float(4, 26))
                    let ang = CGFloat(rng.float(0, .pi * 2))
                    ctx.setStrokeColor(UIColor(RGBColor(hex: 0xD8CDB6), alpha: CGFloat(rng.float(0.08, 0.35))).cgColor)
                    ctx.setLineWidth(CGFloat(rng.float(0.5, 1.6)))
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + cos(ang) * len, y: y + sin(ang) * len))
                    ctx.strokePath()
                }
            }
        }
    }

    static func plaster() -> UIImage {
        cached("plaster", bytes: textureBytes(512), pinned: true) {
            render(512) { ctx, s in
                let base = RGBColor(hex: 0xD6CBB6)
                ctx.setFillColor(UIColor(base).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                let noise = ValueNoise(seed: 5)
                var rng = SeededGenerator(seed: 6)
                for _ in 0..<2600 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    let n = noise.fbm(Float(x) * 0.02, Float(y) * 0.02, octaves: 4)
                    let c = n > 0 ? base.lightened(n * 0.10) : base.darkened(-n * 0.14)
                    ctx.setFillColor(UIColor(c, alpha: 0.5).cgColor)
                    let r = CGFloat(rng.float(1, 5))
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
            }
        }
    }

    static func fabric(_ color: RGBColor, key: String, weave: Float = 1) -> UIImage {
        cached("fabric-\(key)-\(color.hexKey)-\(Int(weave * 100))", bytes: textureBytes(256), pinned: true) {
            render(256) { ctx, s in
                ctx.setFillColor(UIColor(color).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                ctx.setStrokeColor(UIColor(color.darkened(0.16), alpha: 0.4).cgColor)
                ctx.setLineWidth(1)
                let n = Int(48 * weave)
                for i in 0..<n {
                    let t = CGFloat(i) / CGFloat(n) * s
                    ctx.move(to: CGPoint(x: t, y: 0)); ctx.addLine(to: CGPoint(x: t, y: s))
                    ctx.move(to: CGPoint(x: 0, y: t)); ctx.addLine(to: CGPoint(x: s, y: t))
                }
                ctx.strokePath()
                var rng = SeededGenerator(seed: 91)
                for _ in 0..<600 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    ctx.setFillColor(UIColor(color.lightened(0.12), alpha: 0.12).cgColor)
                    ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
        }
    }

    /// Indigo shibori-dyed futon cover.
    static func futonCover() -> UIImage {
        cached("futon", bytes: textureBytes(512), pinned: true) {
            render(512) { ctx, s in
                let indigo = RGBColor(hex: 0x2B4B6F)
                ctx.setFillColor(UIColor(indigo).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                var rng = SeededGenerator(seed: 404)
                // Simple asanoha-ish repeating motif.
                ctx.setStrokeColor(UIColor(RGBColor(hex: 0xE8E2D2), alpha: 0.55).cgColor)
                ctx.setLineWidth(1.6)
                let cell = s / 8
                var y: CGFloat = 0
                while y < s + cell {
                    var x: CGFloat = 0
                    while x < s + cell {
                        for k in 0..<6 {
                            let a = CGFloat(k) / 6 * .pi * 2
                            ctx.move(to: CGPoint(x: x, y: y))
                            ctx.addLine(to: CGPoint(x: x + cos(a) * cell * 0.5, y: y + sin(a) * cell * 0.5))
                        }
                        x += cell
                    }
                    y += cell
                }
                ctx.strokePath()
                for _ in 0..<900 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    ctx.setFillColor(UIColor(indigo.lightened(Float(rng.float(0.05, 0.2))), alpha: 0.18).cgColor)
                    ctx.fill(CGRect(x: x, y: y, width: 2, height: 2))
                }
            }
        }
    }

    static func sisal() -> UIImage {
        cached("sisal", bytes: textureBytes(256), pinned: true) {
            render(256) { ctx, s in
                let rope = RGBColor(hex: 0xC2A878)
                ctx.setFillColor(UIColor(rope).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                var rng = SeededGenerator(seed: 55)
                for i in 0..<80 {
                    let y = CGFloat(i) / 80 * s
                    ctx.setFillColor(UIColor(rope.darkened(Float(rng.float(0.02, 0.25))), alpha: 0.6).cgColor)
                    ctx.fill(CGRect(x: 0, y: y, width: s, height: s / 80 * 0.55))
                }
                for _ in 0..<900 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    ctx.setStrokeColor(UIColor(rope.lightened(0.25), alpha: 0.25).cgColor)
                    ctx.setLineWidth(1)
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + CGFloat(rng.float(-6, 6)), y: y + CGFloat(rng.float(-1, 1))))
                    ctx.strokePath()
                }
            }
        }
    }

    static func litterSubstrate() -> UIImage {
        cached("litter", bytes: textureBytes(256), pinned: true) {
            render(256) { ctx, s in
                let g = RGBColor(hex: 0xCFC7B6)
                ctx.setFillColor(UIColor(g).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                var rng = SeededGenerator(seed: 71)
                for _ in 0..<5200 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    let r = CGFloat(rng.float(1, 3.2))
                    let dark = rng.float() < 0.5
                    ctx.setFillColor(UIColor(dark ? g.darkened(Float(rng.float(0.05, 0.25)))
                                             : g.lightened(Float(rng.float(0.02, 0.15))), alpha: 0.8).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                }
            }
        }
    }

    /// Sumi-e style hanging scroll.
    static func inkScroll() -> UIImage {
        cached("scroll", bytes: textureBytes(512), pinned: true) {
            render(512) { ctx, s in
                ctx.setFillColor(UIColor(RGBColor(hex: 0xEDE4D0)).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                // Border silk.
                ctx.setFillColor(UIColor(RGBColor(hex: 0x8A7256)).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s * 0.10))
                ctx.fill(CGRect(x: 0, y: s * 0.90, width: s, height: s * 0.10))

                // A branch with a few blossoms.
                ctx.setStrokeColor(UIColor(white: 0.12, alpha: 0.85).cgColor)
                ctx.setLineWidth(s * 0.012)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: s * 0.18, y: s * 0.80))
                ctx.addCurve(to: CGPoint(x: s * 0.78, y: s * 0.28),
                             control1: CGPoint(x: s * 0.36, y: s * 0.60),
                             control2: CGPoint(x: s * 0.52, y: s * 0.52))
                ctx.strokePath()
                ctx.setLineWidth(s * 0.006)
                for (bx, by) in [(0.36, 0.60), (0.52, 0.46), (0.66, 0.36)] as [(CGFloat, CGFloat)] {
                    ctx.move(to: CGPoint(x: s * bx, y: s * by))
                    ctx.addLine(to: CGPoint(x: s * (bx + 0.10), y: s * (by - 0.14)))
                    ctx.strokePath()
                }
                var rng = SeededGenerator(seed: 808)
                for _ in 0..<14 {
                    let x = CGFloat(rng.float(0.25, 0.82)) * s
                    let y = CGFloat(rng.float(0.24, 0.72)) * s
                    let r = s * CGFloat(rng.float(0.014, 0.026))
                    ctx.setFillColor(UIColor(RGBColor(hex: 0xD98C9E), alpha: 0.85).cgColor)
                    for k in 0..<5 {
                        let a = CGFloat(k) / 5 * .pi * 2
                        ctx.fillEllipse(in: CGRect(x: x + cos(a) * r - r * 0.6, y: y + sin(a) * r - r * 0.6,
                                                   width: r * 1.2, height: r * 1.2))
                    }
                }
                // Red seal.
                ctx.setFillColor(UIColor(RGBColor(hex: 0xB03A34)).cgColor)
                ctx.fill(CGRect(x: s * 0.14, y: s * 0.20, width: s * 0.055, height: s * 0.055))
            }
        }
    }

    // MARK: - Outside the window

    /// Equirectangular-ish backdrop seen through the shoji: a small garden and sky.
    static func gardenBackdrop(sky: SkyState) -> UIImage {
        let bucket = Int(sky.sunElevation * 12)   // quantise so we don't redraw every frame
        return cached("garden-\(bucket)", bytes: textureBytes(512)) {
            render(512) { ctx, s in
                let zenith = sky.skyZenithColor
                let horizon = sky.skyHorizonColor
                let colors = [UIColor(zenith).cgColor, UIColor(horizon).cgColor] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: s * 0.62), options: [])
                }
                var rng = SeededGenerator(seed: 900)

                // Stars at night.
                if sky.sunElevation < -0.12 {
                    let a = CGFloat(smoothstep(-0.12, -0.32, sky.sunElevation))
                    for _ in 0..<220 {
                        let x = CGFloat(rng.float(0, 1)) * s
                        let y = CGFloat(rng.float(0, 0.55)) * s
                        let r = CGFloat(rng.float(0.6, 1.9))
                        ctx.setFillColor(UIColor(white: 1, alpha: a * CGFloat(rng.float(0.2, 0.9))).cgColor)
                        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
                    }
                } else {
                    // Soft clouds.
                    for _ in 0..<26 {
                        let x = CGFloat(rng.float(-0.1, 1.0)) * s
                        let y = CGFloat(rng.float(0.05, 0.42)) * s
                        let w = s * CGFloat(rng.float(0.10, 0.30))
                        let h = w * CGFloat(rng.float(0.16, 0.30))
                        ctx.setFillColor(UIColor(white: 1, alpha: CGFloat(rng.float(0.10, 0.35)) * CGFloat(sky.daylight)).cgColor)
                        ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
                    }
                }

                // Distant fence and a maple, silhouetted at low light.
                let ground = s * 0.62
                let shade = CGFloat(0.25 + 0.75 * CGFloat(sky.daylight))
                ctx.setFillColor(UIColor(RGBColor(0.24, 0.32, 0.18).mixed(with: sky.skyHorizonColor, Float(1 - shade))).cgColor)
                ctx.fill(CGRect(x: 0, y: ground, width: s, height: s - ground))

                ctx.setFillColor(UIColor(RGBColor(0.36, 0.28, 0.20).mixed(with: sky.skyHorizonColor, Float(1 - shade))).cgColor)
                for i in 0..<26 {
                    let x = CGFloat(i) / 26 * s
                    ctx.fill(CGRect(x: x, y: ground - s * 0.10, width: s * 0.022, height: s * 0.10))
                }
                ctx.fill(CGRect(x: 0, y: ground - s * 0.085, width: s, height: s * 0.012))

                // Maple.
                let trunkColor = UIColor(RGBColor(0.22, 0.17, 0.13).mixed(with: sky.skyHorizonColor, Float(1 - shade)))
                ctx.setFillColor(trunkColor.cgColor)
                ctx.fill(CGRect(x: s * 0.70, y: ground - s * 0.30, width: s * 0.028, height: s * 0.30))
                let leafBase = RGBColor(0.55, 0.28, 0.16).mixed(with: sky.skyHorizonColor, Float(1 - shade))
                for _ in 0..<150 {
                    let x = s * 0.715 + CGFloat(rng.float(-0.17, 0.17)) * s
                    let y = ground - s * 0.34 + CGFloat(rng.float(-0.16, 0.10)) * s
                    let r = s * CGFloat(rng.float(0.012, 0.035))
                    ctx.setFillColor(UIColor(leafBase.lightened(Float(rng.float(0, 0.25))), alpha: 0.85).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 1.6))
                }

                // Stone lantern.
                ctx.setFillColor(UIColor(RGBColor(0.45, 0.45, 0.42).mixed(with: sky.skyHorizonColor, Float(1 - shade))).cgColor)
                ctx.fill(CGRect(x: s * 0.20, y: ground - s * 0.10, width: s * 0.05, height: s * 0.10))
                ctx.fill(CGRect(x: s * 0.175, y: ground - s * 0.135, width: s * 0.10, height: s * 0.035))
            }
        }
    }

    /// Spherical environment map used for image-based lighting.
    static func skyEnvironment(sky: SkyState) -> UIImage {
        let bucket = Int(sky.sunElevation * 10)
        return cached("env-\(bucket)", bytes: 256 * 128 * 4) {
            let w = 256, h = 128
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
            return renderer.image { c in
                let ctx = c.cgContext
                let colors = [UIColor(sky.skyZenithColor).cgColor,
                              UIColor(sky.skyHorizonColor).cgColor,
                              UIColor(RGBColor(0.20, 0.17, 0.14).mixed(with: sky.skyHorizonColor, 0.35)).cgColor] as CFArray
                if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors, locations: [0, 0.5, 1]) {
                    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: CGFloat(h)), options: [])
                }
                // A soft bright spot where the sun is, so highlights land believably.
                if sky.sunElevation > -0.15 {
                    let u = CGFloat(sky.sunAzimuth / (2 * .pi)) * CGFloat(w)
                    let v = CGFloat(0.5 - sky.sunElevation / .pi) * CGFloat(h)
                    let r: CGFloat = 26
                    let sunColors = [UIColor(sky.sunColor, alpha: 0.95).cgColor,
                                     UIColor(sky.sunColor, alpha: 0).cgColor] as CFArray
                    if let g2 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: sunColors, locations: [0, 1]) {
                        ctx.drawRadialGradient(g2, startCenter: CGPoint(x: u, y: v), startRadius: 0,
                                               endCenter: CGPoint(x: u, y: v), endRadius: r, options: [])
                    }
                }
            }
        }
    }

    // MARK: - Small props

    static func ceramic(_ color: RGBColor, key: String) -> UIImage {
        cached("ceramic-\(key)-\(color.hexKey)", bytes: textureBytes(256), pinned: true) {
            render(256) { ctx, s in
                ctx.setFillColor(UIColor(color).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                var rng = SeededGenerator(seed: 313)
                ctx.setStrokeColor(UIColor(color.darkened(0.25), alpha: 0.22).cgColor)
                ctx.setLineWidth(1)
                for _ in 0..<40 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    ctx.move(to: CGPoint(x: x, y: y))
                    ctx.addLine(to: CGPoint(x: x + CGFloat(rng.float(-40, 40)), y: y + CGFloat(rng.float(-40, 40))))
                }
                ctx.strokePath()
            }
        }
    }

    static func foliage() -> UIImage {
        cached("foliage", bytes: textureBytes(512), pinned: true) {
            render(256) { ctx, s in
                let leaf = RGBColor(hex: 0x3E6B3A)
                ctx.setFillColor(UIColor(leaf).cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
                var rng = SeededGenerator(seed: 606)
                for _ in 0..<400 {
                    let x = CGFloat(rng.float(0, 1)) * s
                    let y = CGFloat(rng.float(0, 1)) * s
                    let r = CGFloat(rng.float(3, 12))
                    let c = rng.float() < 0.5 ? leaf.lightened(Float(rng.float(0.05, 0.3))) : leaf.darkened(Float(rng.float(0.05, 0.3)))
                    ctx.setFillColor(UIColor(c, alpha: 0.7).cgColor)
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 1.6, height: r))
                }
            }
        }
    }

    // MARK: - Material maps

    /// The non-colour channels for one surface.
    struct MapSet {
        var normal: UIImage?
        var roughness: UIImage?
        var occlusion: UIImage?
    }

    /// Bakes and caches a surface's normal, roughness and occlusion maps.
    ///
    /// The three share one height field, so the field is built at most once even
    /// though each map is cached under its own key and can be evicted on its own.
    ///
    /// - Parameter size: the field's edge length, stated here so the cache can
    ///   budget before anything is built. The harness asserts it against the spec
    ///   the closure actually returns, so it cannot drift.
    static func surfaceMaps(_ name: String, size: Int, pinned: Bool = true,
                            _ make: () -> SurfaceMaps.Spec) -> MapSet {
        var built: SurfaceMaps.Spec?
        func spec() -> SurfaceMaps.Spec {
            if let b = built { return b }
            let b = make()
            built = b
            return b
        }
        let bytes = textureBytes(size)

        let normal = cached("\(name)#normal", bytes: bytes, pinned: pinned) { () -> UIImage in
            let s = spec()
            let bytes = s.field.normalMap(slopeScale: s.slopeScale)
            return TextureBaker.image(rgba: bytes, size: s.field.size) ?? UIImage()
        }
        let roughness = cached("\(name)#roughness", bytes: bytes, pinned: pinned) { () -> UIImage in
            let s = spec()
            let bytes = s.field.roughnessMap(base: s.roughnessBase, variation: s.roughnessVariation)
            return TextureBaker.image(rgba: bytes, size: s.field.size) ?? UIImage()
        }
        let occlusion = cached("\(name)#occlusion", bytes: bytes, pinned: pinned) { () -> UIImage in
            let s = spec()
            let bytes = s.field.occlusionMap(radius: s.occlusionRadius, strength: s.occlusionStrength)
            return TextureBaker.image(rgba: bytes, size: s.field.size) ?? UIImage()
        }
        return MapSet(normal: normal, roughness: roughness, occlusion: occlusion)
    }

    static func tatamiMaps() -> MapSet {
        surfaceMaps("tatami", size: 512) { SurfaceMaps.tatami() }
    }

    static func tatamiBorderMaps() -> MapSet {
        surfaceMaps("tatamiBorder", size: 128) { SurfaceMaps.tatamiBorder() }
    }

    static func woodMaps(key: String) -> MapSet {
        surfaceMaps("wood-\(key)", size: 512) {
            key == "hinoki" ? SurfaceMaps.hinoki() : SurfaceMaps.wood()
        }
    }

    static func plasterMaps() -> MapSet {
        surfaceMaps("plaster", size: 512) { SurfaceMaps.plaster() }
    }

    static func shojiMaps() -> MapSet {
        surfaceMaps("shoji", size: 512) { SurfaceMaps.shojiPaper() }
    }

    static func fabricMaps(key: String) -> MapSet {
        surfaceMaps("fabric-\(key)", size: 256) { SurfaceMaps.fabric() }
    }

    static func futonMaps() -> MapSet {
        surfaceMaps("futon", size: 256) { SurfaceMaps.futonCover() }
    }

    static func sisalMaps() -> MapSet {
        surfaceMaps("sisal", size: 256) { SurfaceMaps.sisal() }
    }

    static func litterMaps() -> MapSet {
        surfaceMaps("litter", size: 256) { SurfaceMaps.litterSubstrate() }
    }

    /// The coat's maps follow the cat, so they are not pinned — a player who keeps
    /// editing their cat would otherwise pin every intermediate coat for the session.
    static func catCoatMaps(_ a: CatAppearance, preview: Bool = false) -> MapSet {
        let size = preview ? 256 : 512
        return surfaceMaps("coat-\(coatKey(a))-\(size)", size: size, pinned: false) {
            SurfaceMaps.catCoat(a, size: size)
        }
    }
}
