import Foundation
import AVFoundation

/// Every sound in the game is synthesised at runtime — no audio files to ship.
/// Cat vocalisations are built from a pitch contour plus a couple of formants,
/// which is enough to land somewhere between "meow" and "mrrp".
final class CatVoice {

    static let shared = CatVoice()

    private let engine = AVAudioEngine()
    private let voicePlayer = AVAudioPlayerNode()
    private let purrPlayer = AVAudioPlayerNode()
    private let ambiencePlayer = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let sampleRate: Float = 44_100

    private var started = false
    private var purrLooping = false
    private var ambienceLooping = false
    private var lastPlay: [String: TimeInterval] = [:]

    /// Player-facing mute switch.
    var muted: Bool = false {
        didSet { engine.mainMixerNode.outputVolume = muted ? 0 : 1 }
    }

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio is a nice-to-have; the game keeps working without it.
        }

        engine.attach(voicePlayer)
        engine.attach(purrPlayer)
        engine.attach(ambiencePlayer)
        engine.connect(voicePlayer, to: engine.mainMixerNode, format: format)
        engine.connect(purrPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(ambiencePlayer, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            voicePlayer.play()
            purrPlayer.play()
            ambiencePlayer.play()
            purrPlayer.volume = 0
            ambiencePlayer.volume = 0
        } catch {
            started = false
        }
    }

    func stop() {
        guard started else { return }
        engine.pause()
    }

    func resume() {
        guard started else { start(); return }
        if !engine.isRunning { try? engine.start() }
    }

    // MARK: - Public API

    func play(_ event: CatEvent, personality: CatPersonality? = nil) {
        guard started, !muted else { return }
        let voicePitch: Float = 1.0 + ((personality?.vocality ?? 0.5) - 0.5) * 0.20

        switch event {
        case .meow(let pitch):
            schedule(meow(pitch: pitch * voicePitch, length: 0.72), key: "meow", minGap: 0.35, volume: 0.55)
        case .trill:
            schedule(trill(pitch: voicePitch), key: "trill", minGap: 0.4, volume: 0.5)
        case .chirp:
            schedule(chirp(pitch: voicePitch), key: "chirp", minGap: 0.25, volume: 0.45)
        case .hiss:
            schedule(hiss(), key: "hiss", minGap: 0.6, volume: 0.6)
        case .yowl:
            schedule(meow(pitch: 0.78 * voicePitch, length: 1.35, vibrato: 7.5, growl: 0.35),
                     key: "yowl", minGap: 0.8, volume: 0.7)
        case .crunch:
            schedule(crunch(), key: "crunch", minGap: 0.10, volume: 0.30)
        case .lap:
            schedule(lap(), key: "lap", minGap: 0.12, volume: 0.26)
        case .scratchSound:
            schedule(scratch(), key: "scratch", minGap: 0.20, volume: 0.34)
        case .thud:
            schedule(thud(), key: "thud", minGap: 0.15, volume: 0.42)
        case .bell:
            schedule(bell(), key: "bell", minGap: 0.08, volume: 0.30)
        case .startled:
            schedule(hiss(short: true), key: "startle", minGap: 0.5, volume: 0.4)
        case .teacupKnocked:
            schedule(bell(), key: "cup", minGap: 0.3, volume: 0.5)
            schedule(thud(), key: "cupthud", minGap: 0.3, volume: 0.4)
        case .purrStart:
            startPurr()
        case .purrStop:
            setPurr(level: 0)
        case .activityChanged, .overstimulated:
            break
        }
    }

    /// Purr volume follows the cat's contentment continuously.
    func setPurr(level: Float) {
        guard started else { return }
        if level > 0.02 { startPurr() }
        purrPlayer.volume = clamp(level) * 0.55
    }

    func setAmbience(fountainOn: Bool, level: Float) {
        guard started else { return }
        if fountainOn && !ambienceLooping {
            ambienceLooping = true
            if let buf = ambienceBuffer() {
                ambiencePlayer.scheduleBuffer(buf, at: nil, options: [.loops], completionHandler: nil)
            }
        }
        ambiencePlayer.volume = fountainOn ? clamp(level) * 0.12 : 0
    }

    private func startPurr() {
        guard started, !purrLooping else { return }
        purrLooping = true
        if let buf = purrBuffer() {
            purrPlayer.scheduleBuffer(buf, at: nil, options: [.loops], completionHandler: nil)
        }
    }

    private func schedule(_ buffer: AVAudioPCMBuffer?, key: String, minGap: TimeInterval, volume: Float) {
        guard let buffer else { return }
        let now = Date().timeIntervalSinceReferenceDate
        if let last = lastPlay[key], now - last < minGap { return }
        lastPlay[key] = now
        voicePlayer.volume = volume
        voicePlayer.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
    }

    // MARK: - Synthesis helpers

    private func makeBuffer(seconds: Float, _ fill: (UnsafeMutablePointer<Float>, Int) -> Void) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(max(64, sampleRate * seconds))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        guard let data = buffer.floatChannelData?[0] else { return nil }
        fill(data, Int(frames))
        return buffer
    }

    /// A meow: pitch rises then falls, with two formants and a soft attack.
    private func meow(pitch: Float, length: Float, vibrato: Float = 4.5, growl: Float = 0) -> AVAudioPCMBuffer? {
        let base = 480 * pitch
        var phase: Float = 0
        var f1Phase: Float = 0
        var f2Phase: Float = 0
        var rng = SeededGenerator(seed: UInt64(Date().timeIntervalSince1970 * 1000) | 1)
        let noiseSeed = rng.float()

        return makeBuffer(seconds: length) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                let dt = 1 / self.sampleRate

                // Pitch contour: up on the "me", down on the "ow".
                let contour = 1 + 0.30 * sinf(t * .pi) - 0.22 * t
                let vib = 1 + 0.035 * sinf(t * length * vibrato * 2 * .pi)
                let f0 = base * contour * vib

                phase += f0 * dt
                f1Phase += f0 * 2.1 * dt
                f2Phase += f0 * 3.4 * dt

                // Mouth opening sweeps the formant balance from "ee" to "ow".
                let open = sinf(clamp(t * 1.15) * .pi)
                var s = sinf(phase * 2 * .pi) * 0.55
                s += sinf(f1Phase * 2 * .pi) * 0.30 * (0.35 + 0.65 * open)
                s += sinf(f2Phase * 2 * .pi) * 0.16 * (1 - open * 0.6)

                // Growl / rasp for yowls.
                if growl > 0 {
                    s *= 1 - growl * 0.5 * (0.5 + 0.5 * sinf(t * length * 32 * 2 * .pi))
                }

                // Breath noise.
                let nz = (sinf((Float(i) * 12.9898 + noiseSeed * 78.233)) * 43758.5453).truncatingRemainder(dividingBy: 1)
                s += (nz - 0.5) * 0.05 * open

                // Envelope.
                let attack = smoothstep(0, 0.06, t)
                let release = 1 - smoothstep(0.62, 1.0, t)
                data[i] = s * attack * release * 0.8
            }
        }
    }

    /// The rolled "brrp?" greeting.
    private func trill(pitch: Float) -> AVAudioPCMBuffer? {
        let base = 430 * pitch
        var phase: Float = 0
        return makeBuffer(seconds: 0.55) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                let dt = 1 / self.sampleRate
                let f0 = base * (1 + 0.35 * t)
                phase += f0 * dt
                // Fast amplitude roll is what makes it a trill.
                let roll = 0.5 + 0.5 * sinf(t * 0.55 * 30 * 2 * .pi)
                var s = sinf(phase * 2 * .pi) * 0.6 + sinf(phase * 4 * .pi) * 0.22
                s *= 0.35 + 0.65 * roll
                let env = smoothstep(0, 0.08, t) * (1 - smoothstep(0.7, 1, t))
                data[i] = s * env * 0.7
            }
        }
    }

    /// The stuttering chatter aimed at birds.
    private func chirp(pitch: Float) -> AVAudioPCMBuffer? {
        let base = 900 * pitch
        var phase: Float = 0
        return makeBuffer(seconds: 0.42) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                let dt = 1 / self.sampleRate
                phase += base * (1 + 0.5 * sinf(t * 14)) * dt
                let gate: Float = sinf(t * 0.42 * 22 * 2 * .pi) > 0.1 ? 1 : 0.05
                let env = (1 - smoothstep(0.55, 1, t)) * smoothstep(0, 0.03, t)
                data[i] = sinf(phase * 2 * .pi) * gate * env * 0.45
            }
        }
    }

    private func hiss(short: Bool = false) -> AVAudioPCMBuffer? {
        var lp: Float = 0
        var hp: Float = 0
        var seed: UInt64 = 0x2545F4914F6CDD1D
        return makeBuffer(seconds: short ? 0.28 : 0.75) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let white = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
                // Band-pass the noise so it sits where a real hiss sits.
                lp += (white - lp) * 0.55
                hp = lp - hp * 0.02
                let env = smoothstep(0, 0.05, t) * (1 - smoothstep(0.55, 1, t))
                data[i] = hp * env * 0.55
            }
        }
    }

    private func purrBuffer() -> AVAudioPCMBuffer? {
        // One second of loopable purr: 26 Hz pulses with a rough, resonant body.
        var phase: Float = 0
        var seed: UInt64 = 99
        return makeBuffer(seconds: 1.0) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                let dt = 1 / self.sampleRate
                phase += 26 * dt
                let pulse = powf(max(0, sinf(phase * 2 * .pi)), 0.4)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let white = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
                var s = pulse * (0.55 * sinf(t * 120 * 2 * .pi) + 0.30 * white)
                s += 0.25 * pulse * sinf(t * 62 * 2 * .pi)
                data[i] = s * 0.5
            }
        }
    }

    private func crunch() -> AVAudioPCMBuffer? {
        var seed: UInt64 = UInt64(Date().timeIntervalSince1970) | 3
        return makeBuffer(seconds: 0.14) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let white = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
                let env = expf(-t * 22) * (1 - smoothstep(0.85, 1, t))
                data[i] = white * env * 0.6
            }
        }
    }

    private func lap() -> AVAudioPCMBuffer? {
        var seed: UInt64 = 4242
        return makeBuffer(seconds: 0.12) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let white = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
                let click = expf(-t * 45)
                let wet = sinf(t * 700 * 2 * .pi) * expf(-t * 18)
                data[i] = (white * 0.35 * click + wet * 0.4) * 0.7
            }
        }
    }

    private func scratch() -> AVAudioPCMBuffer? {
        var seed: UInt64 = 777
        var lp: Float = 0
        return makeBuffer(seconds: 0.32) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let white = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
                lp += (white - lp) * 0.30
                let rasp = 0.5 + 0.5 * sinf(t * 0.32 * 18 * 2 * .pi)
                let env = smoothstep(0, 0.04, t) * (1 - smoothstep(0.7, 1, t))
                data[i] = lp * rasp * env * 0.6
            }
        }
    }

    private func thud() -> AVAudioPCMBuffer? {
        var seed: UInt64 = 31337
        return makeBuffer(seconds: 0.26) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let white = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
                let body = sinf(t * 68 * 2 * .pi * (1 - t * 0.4)) * expf(-t * 16)
                data[i] = (body * 0.8 + white * 0.15 * expf(-t * 60)) * 0.8
            }
        }
    }

    private func bell() -> AVAudioPCMBuffer? {
        return makeBuffer(seconds: 0.55) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                var s: Float = 0
                for (k, f) in [(1.0, 2100.0), (0.5, 3170.0), (0.28, 4260.0)] as [(Float, Float)] {
                    s += k * sinf(t * 0.55 * f * 2 * .pi) * expf(-t * (7 + f * 0.0015))
                }
                data[i] = s * 0.22
            }
        }
    }

    /// A quiet trickle so the fountain feels alive.
    private func ambienceBuffer() -> AVAudioPCMBuffer? {
        var seed: UInt64 = 2024
        var lp: Float = 0
        return makeBuffer(seconds: 2.0) { data, n in
            for i in 0..<n {
                let t = Float(i) / Float(n)
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let white = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max)
                lp += (white - lp) * 0.10
                // Fade both ends so the loop point is inaudible.
                let fade = smoothstep(0, 0.02, t) * (1 - smoothstep(0.98, 1, t))
                data[i] = lp * fade * 0.5
            }
        }
    }
}
