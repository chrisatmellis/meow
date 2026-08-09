import Foundation
import RealityKit

/// The pose the animator is blending toward. Every field is smoothed, so switching
/// pose never snaps — the cat flows from a loaf into a stretch into a walk.
struct PoseState {
    var bodyHeight: Float = 1.0      // fraction of standing height
    var bodyPitch: Float = 0         // + = nose down
    var bodyRoll: Float = 0
    var neckPitch: Float = 0
    var headPitch: Float = 0
    var headYaw: Float = 0
    var headRoll: Float = 0
    var frontFoot = SIMD3<Float>.zero  // offset from the rest stance, in body space
    var hindFoot = SIMD3<Float>.zero
    var tuckFront: Float = 0         // front legs folding under the chest
    var tuckHind: Float = 0          // hind legs folding under the haunches
    var tailBasePitch: Float = 0
    var tailCurl: Float = 0
    var tailSide: Float = 0
    var earPitch: Float = 0
    var jawOpen: Float = 0
    var frontPawLift: Float = 0      // for kneading / batting
    /// The torso is one rigid mesh, so squashing it along the spine is how a loaf
    /// gets its compact silhouette and a stretch gets its long one.
    var torsoLength: Float = 1
    var torsoHeight: Float = 1

    mutating func blend(toward t: PoseState, rate: Float, dt: Float) {
        bodyHeight = approach(bodyHeight, t.bodyHeight, rate: rate, dt: dt)
        bodyPitch = approach(bodyPitch, t.bodyPitch, rate: rate, dt: dt)
        bodyRoll = approach(bodyRoll, t.bodyRoll, rate: rate, dt: dt)
        neckPitch = approach(neckPitch, t.neckPitch, rate: rate, dt: dt)
        headPitch = approach(headPitch, t.headPitch, rate: rate, dt: dt)
        headYaw = approach(headYaw, t.headYaw, rate: rate, dt: dt)
        headRoll = approach(headRoll, t.headRoll, rate: rate, dt: dt)
        frontFoot = frontFoot.lerped(to: t.frontFoot, 1 - expf(-rate * dt))
        hindFoot = hindFoot.lerped(to: t.hindFoot, 1 - expf(-rate * dt))
        tuckFront = approach(tuckFront, t.tuckFront, rate: rate, dt: dt)
        tuckHind = approach(tuckHind, t.tuckHind, rate: rate, dt: dt)
        tailBasePitch = approach(tailBasePitch, t.tailBasePitch, rate: rate, dt: dt)
        tailCurl = approach(tailCurl, t.tailCurl, rate: rate, dt: dt)
        tailSide = approach(tailSide, t.tailSide, rate: rate, dt: dt)
        earPitch = approach(earPitch, t.earPitch, rate: rate, dt: dt)
        jawOpen = approach(jawOpen, t.jawOpen, rate: rate * 2, dt: dt)
        frontPawLift = approach(frontPawLift, t.frontPawLift, rate: rate, dt: dt)
        torsoLength = approach(torsoLength, t.torsoLength, rate: rate, dt: dt)
        torsoHeight = approach(torsoHeight, t.torsoHeight, rate: rate, dt: dt)
    }
}

final class CatAnimator {
    let rig: CatRig

    private var pose = PoseState()
    private var clock: Float = 0
    private var gait: Float = 0
    private var noise: ValueNoise
    private var lastMeowTime: Float = -10
    private var purrPhase: Float = 0
    private var breathPhase: Float = 0
    private var tailFlickImpulse: Float = 0
    private var earTwitch: Float = 0
    private var earTwitchTimer: Float = 2

    init(rig: CatRig) {
        self.rig = rig
        self.noise = ValueNoise(seed: rig.appearance.seed &+ 1234)
    }

    /// Called when the cat vocalises so the jaw actually moves.
    func triggerMeow() { lastMeowTime = clock }

    func update(dt: Float, motion: CatMotion) {
        clock += dt

        // ---- Root placement --------------------------------------------
        rig.root.position = motion.position
        rig.root.eulerAngles = SIMD3<Float>(x: 0, y: motion.yaw, z: 0)

        // ---- Pose blending ---------------------------------------------
        var target = CatAnimator.targets(for: motion.pose, appearance: rig.appearance)
        target.bodyHeight -= motion.crouchAmount * 0.28
        if clock - lastMeowTime < 0.55 {
            target.jawOpen = 0.7 * (1 - (clock - lastMeowTime) / 0.55)
        }
        let blendRate: Float = motion.pose.isLocomotion ? 9 : 5
        pose.blend(toward: target, rate: blendRate, dt: dt)

        // ---- Gait -------------------------------------------------------
        let strideLength = strideFor(motion.pose, appearance: rig.appearance)
        if motion.speed > 0.02 && strideLength > 0 {
            gait += dt * motion.speed / strideLength
            gait = gait.truncatingRemainder(dividingBy: 1)
        }

        // ---- Breathing & purring ---------------------------------------
        breathPhase += dt * motion.breathRate * 1.15
        let breath = sinf(breathPhase * 2 * .pi) * 0.5 + 0.5
        purrPhase += dt * 26
        let purrJitter = motion.purr > 0.02 ? sinf(purrPhase * 2 * .pi) * 0.0012 * motion.purr : 0

        // ---- Body -------------------------------------------------------
        let bodyY = rig.bodyHeight * pose.bodyHeight
        let bob = motion.speed > 0.02 ? sinf(gait * 4 * .pi) * 0.006 * min(1, motion.speed) : 0
        rig.body.position = SIMD3<Float>(x: 0,
                                       y: bodyY + bob + purrJitter + motion.jumpHeight * 0.05,
                                       z: 0)
        let sway = motion.speed > 0.02 ? sinf(gait * 2 * .pi) * 0.05 * min(1, motion.speed) : 0
        rig.spine.eulerAngles = SIMD3<Float>(x: pose.bodyPitch + breath * 0.008,
                                           y: sway * 0.35,
                                           z: pose.bodyRoll + sway)

        // Torso length, by moving the chest rather than scaling it. A loaf is a
        // cat with its shoulders drawn back toward its hips, and moving the joint
        // takes the neck and head along with it while leaving them their own size
        // — where a scale on the chest would run down the skeleton and inflate
        // the skull.
        rig.chestNode.position = SIMD3<Float>(x: rig.chestRest.x,
                                              y: rig.chestRest.y * pose.torsoHeight,
                                              z: rig.chestRest.z * pose.torsoLength)

        // ---- Legs -------------------------------------------------------
        solveLegs(dt: dt, motion: motion, bodyY: bodyY, strideLength: strideLength)

        // ---- Neck & head -------------------------------------------------
        updateHead(dt: dt, motion: motion, breath: breath)

        // ---- Tail ---------------------------------------------------------
        updateTail(dt: dt, motion: motion)

        // ---- Ears ---------------------------------------------------------
        updateEars(dt: dt, motion: motion)

        // ---- Eyes ----------------------------------------------------------
        updateEyes(motion: motion)

        // ---- Jaw ------------------------------------------------------------
        rig.jaw.eulerAngles = SIMD3<Float>(x: pose.jawOpen * deg(26), y: 0, z: 0)

        // ---- Whisker idle ------------------------------------------------
        let whiskerTwitch = noise.value(clock * 0.9, 5.5) * 0.06
        for (i, pad) in rig.whiskerRoots.enumerated() {
            let s: Float = i == 0 ? -1 : 1
            pad.eulerAngles = SIMD3<Float>(x: whiskerTwitch, y: s * motion.purr * 0.05, z: 0)
        }
    }

    // MARK: - Legs

    private func solveLegs(dt: Float, motion: CatMotion, bodyY: Float, strideLength: Float) {
        let phases = phaseOffsets(for: motion.pose)
        let moving = motion.speed > 0.03
        let lift = min(0.045, 0.018 + motion.speed * 0.020)
        let stride = min(strideLength * 0.5, 0.02 + motion.speed * 0.055)

        for (i, leg) in rig.legs.enumerated() {
            // Where the hip sits at rest, not where the spine's pitch has
            // currently carried it: a foot on the floor stays on the floor while
            // the body leans over it, and the IK below is what absorbs the
            // difference.
            let hipInBody = leg.restHip
            let baseOffset = leg.isFront ? pose.frontFoot : pose.hindFoot

            var footX = hipInBody.x + baseOffset.x * leg.side
            var footY = -bodyY + baseOffset.y
            var footZ = hipInBody.z + baseOffset.z + (leg.isFront ? 0.012 : -0.008)

            // Folding the legs under the body for loafing, curling and sitting. Front
            // and hind fold independently: a sitting cat has its haunches down and its
            // forelegs straight.
            let tuck = leg.isFront ? pose.tuckFront : pose.tuckHind
            if tuck > 0.01 {
                let tuckY = mix(footY, -bodyY * 0.30, tuck)
                let tuckZ = mix(footZ, hipInBody.z + (leg.isFront ? 0.032 : -0.020), tuck)
                let tuckX = mix(footX, hipInBody.x * 0.70, tuck)
                footX = tuckX; footY = tuckY; footZ = tuckZ
            }

            if moving {
                let p = (gait + phases[i]).truncatingRemainder(dividingBy: 1)
                // Stance sweeps back, swing arcs forward.
                if p < 0.6 {
                    let s = p / 0.6
                    footZ += mix(stride, -stride, s)
                } else {
                    let s = (p - 0.6) / 0.4
                    footZ += mix(-stride, stride, s)
                    footY += sinf(s * .pi) * lift
                }
            }

            if leg.isFront && pose.frontPawLift > 0.01 {
                let alt: Float = leg.side < 0 ? 0 : .pi
                footY += pose.frontPawLift * (0.5 + 0.5 * sinf(clock * 5 + alt)) * 0.055
                footZ += pose.frontPawLift * 0.02
            }

            let ankleTargetBody = SIMD3<Float>(x: footX, y: footY + leg.pawLength * 0.55, z: footZ)
            // Solved in the hip's parent's space, which is the space the hip's own
            // rotation is expressed in. Anywhere else and the answer is right for
            // a body that is not leaning.
            let parent = leg.hip.parent ?? rig.body
            solveTwoBone(leg, ankleTarget: parent.convert(position: ankleTargetBody, from: rig.body))
        }
    }

    /// Analytic two-bone IK in the leg's sagittal plane.
    private func solveTwoBone(_ leg: LegRig, ankleTarget: SIMD3<Float>) {
        let hip = leg.hip.position
        let dy = ankleTarget.y - hip.y
        let dz = ankleTarget.z - hip.z
        let u = leg.upperLength
        let l = leg.lowerLength

        var d = sqrtf(dy * dy + dz * dz)
        d = min(max(d, abs(u - l) + 0.004), u + l - 0.004)

        let thetaAim = atan2f(-dz, -dy)
        let cosA = clamp((u * u + d * d - l * l) / (2 * u * d), -1, 1)
        let alpha = acosf(cosA)
        let cosK = clamp((u * u + l * l - d * d) / (2 * u * l), -1, 1)
        let interior = acosf(cosK)

        // Where each bone has to end up pointing, as a pitch off straight down.
        let upperAim = thetaAim + leg.bendSign * alpha
        let kneeBend = -leg.bendSign * (.pi - interior)
        let lowerAim = upperAim + kneeBend

        // Turned into joint rotations by subtracting where the bone already
        // points. Without that the solver is right about the direction and wrong
        // about the angle by however far the modelled bone rests from vertical —
        // which is most of a right angle on a foreleg.
        leg.hip.eulerAngles = SIMD3<Float>(x: upperAim - leg.restUpper, y: 0, z: 0)
        leg.knee.eulerAngles = SIMD3<Float>(x: kneeBend - (leg.restLower - leg.restUpper), y: 0, z: 0)
        // Keep the paw roughly flat on the floor.
        leg.ankle.eulerAngles = SIMD3<Float>(x: -lowerAim * 0.92 - (leg.restPaw - leg.restLower),
                                             y: 0, z: 0)
    }

    private func phaseOffsets(for pose: CatPose) -> [Float] {
        // Order is [front-left, front-right, hind-left, hind-right].
        switch pose {
        case .running, .pounce:
            return [0.00, 0.08, 0.52, 0.60]     // bound
        case .trotting:
            return [0.00, 0.50, 0.50, 0.00]     // diagonal pairs
        default:
            return [0.00, 0.50, 0.75, 0.25]     // lateral-sequence walk
        }
    }

    private func strideFor(_ pose: CatPose, appearance a: CatAppearance) -> Float {
        switch pose {
        case .running: return 0.42 * a.scale
        case .trotting: return 0.30 * a.scale
        default: return 0.22 * a.scale
        }
    }

    // MARK: - Head

    private func updateHead(dt: Float, motion: CatMotion, breath: Float) {
        let neckPitch = pose.neckPitch
        let headPitch = pose.headPitch
        let headYaw = pose.headYaw
        let headRoll = pose.headRoll

        if let targetWorld = motion.lookTarget, motion.lookWeight > 0.01 {
            // Solve in spine space, not neck space: the neck's own rotation must not
            // feed back into the angle we are about to give it.
            let targetInSpine = rig.spine.convert(position: targetWorld, from: nil)
            // The neck's own place in spine space, which is not `neck.position` —
            // that is its offset from whatever bone the model hangs it from, and
            // on a modelled skeleton that is rarely the spine itself.
            let d = targetInSpine - rig.neck.position(relativeTo: rig.spine)
            let flat = sqrtf(d.x * d.x + d.z * d.z)
            if flat > 1e-4 || abs(d.y) > 1e-4 {
                let yaw = min(max(atan2f(d.x, d.z), -deg(78)), deg(78))
                let pitch = min(max(-atan2f(d.y, max(flat, 1e-4)), -deg(48)), deg(52))
                let w = motion.lookWeight
                // Split the turn between neck and head so it reads as one motion.
                rig.neck.eulerAngles = SIMD3<Float>(x: mix(neckPitch, pitch * 0.35, w),
                                                  y: yaw * 0.40 * w,
                                                  z: 0)
                rig.head.eulerAngles = SIMD3<Float>(x: mix(headPitch, pitch * 0.65, w),
                                                  y: mix(headYaw, yaw * 0.60, w),
                                                  z: headRoll)
                return
            }
        }

        // Idle: tiny head drift so the cat never looks frozen.
        let drift = noise.fbm(clock * 0.13, 1.7, octaves: 2)
        let drift2 = noise.fbm(clock * 0.11, 9.3, octaves: 2)
        rig.neck.eulerAngles = SIMD3<Float>(x: neckPitch + breath * 0.010, y: drift * 0.05, z: 0)
        rig.head.eulerAngles = SIMD3<Float>(x: headPitch + drift2 * 0.05,
                                          y: headYaw + drift * 0.10,
                                          z: headRoll)
    }

    // MARK: - Tail

    private func updateTail(dt: Float, motion: CatMotion) {
        guard !rig.tailSegments.isEmpty else { return }
        let n = Float(rig.tailSegments.count)

        tailFlickImpulse = approach(tailFlickImpulse, 0, rate: 1.6, dt: dt)
        if motion.tailAgitation > 0.5 && noise.value(clock * 2.1, 0.5) > 0.55 {
            tailFlickImpulse = motion.tailAgitation
        }

        let agitation = motion.tailAgitation
        let swaySpeed: Float = 1.1 + agitation * 5.0 + motion.speed * 1.6
        let swayAmp: Float = 0.05 + agitation * 0.30 + tailFlickImpulse * 0.28

        // The tail runs backwards, along -Z, so a positive pitch about X lifts it.
        rig.tailPitch.eulerAngles = SIMD3<Float>(x: deg(30) + pose.tailBasePitch,
                                               y: 0,
                                               z: pose.tailSide * 0.4)

        for (i, seg) in rig.tailSegments.enumerated() {
            guard i > 0 else { continue }
            let t = Float(i) / n
            let phase = clock * swaySpeed - t * 2.4
            let side = sinf(phase) * swayAmp * (0.35 + t)
            // Applied per segment, so keep it small: nine segments compound quickly.
            let curlUp = pose.tailCurl * (0.10 + 0.26 * t)
            let droop = (1 - pose.tailCurl) * 0.06 * t
            let wave = noise.value(clock * 0.5 + Float(i), 3.3) * 0.05
            seg.eulerAngles = SIMD3<Float>(x: curlUp * 0.40 - droop + wave * 0.4,
                                         y: side,
                                         z: 0)
        }
    }

    // MARK: - Ears

    private func updateEars(dt: Float, motion: CatMotion) {
        earTwitchTimer -= dt
        if earTwitchTimer <= 0 {
            earTwitchTimer = 1.5 + abs(noise.value(clock, 2.2)) * 6
            earTwitch = 1
        }
        earTwitch = approach(earTwitch, 0, rate: 7, dt: dt)

        let pin = motion.earPin
        let base = pose.earPitch

        // Only what moves. How far apart the ears sit, how far out they splay and
        // how far a fold tips them over are all shape, applied once when the cat
        // is built — repeating any of it here would double it, and a constant
        // pitch on top of a bone that already points where it should is what lays
        // a cat's ears flat for the rest of the game.
        //
        // An ear bone points up, so a negative pitch about X lays it back.
        for (idx, ear) in [rig.earL, rig.earR].enumerated() {
            let side: Float = idx == 0 ? 1 : -1      // +1 is the cat's left
            let twitch = (idx == 0 ? earTwitch : earTwitch * 0.6) * 0.18
            ear.eulerAngles = SIMD3<Float>(x: base - pin * deg(46) + twitch,
                                         y: 0,
                                         z: -side * pin * deg(20))
        }
    }

    // MARK: - Eyes

    private func updateEyes(motion: CatMotion) {
        let closed = 1 - clamp(motion.eyeOpen)
        let upper = deg(-90) + closed * deg(72)
        let lower = deg(90) - closed * deg(58)
        rig.lidUpperL.eulerAngles = SIMD3<Float>(x: upper, y: 0, z: 0)
        rig.lidUpperR.eulerAngles = SIMD3<Float>(x: upper, y: 0, z: 0)
        rig.lidLowerL.eulerAngles = SIMD3<Float>(x: lower, y: 0, z: 0)
        rig.lidLowerR.eulerAngles = SIMD3<Float>(x: lower, y: 0, z: 0)

        // Eyes converge slightly on whatever the cat is watching.
        if let target = motion.lookTarget, motion.lookWeight > 0.2 {
            for (idx, socket) in [rig.eyeL, rig.eyeR].enumerated() {
                let side: Float = idx == 0 ? -1 : 1
                let local = rig.head.convert(position: target, from: nil)
                let yaw = clamp(atan2f(local.x, max(0.02, local.z)), -0.35, 0.35)
                let pitch = clamp(-atan2f(local.y, max(0.02, local.z)), -0.28, 0.28)
                socket.eulerAngles = SIMD3<Float>(x: pitch * 0.6,
                                                y: side * deg(16) + yaw * 0.6,
                                                z: socket.eulerAngles.z)
            }
        }
    }

    // MARK: - Pose table

    static func targets(for pose: CatPose, appearance a: CatAppearance) -> PoseState {
        var p = PoseState()
        switch pose {
        case .standing:
            p.bodyHeight = 1.0
            p.neckPitch = deg(-18)
            p.headPitch = deg(16)
            p.tailBasePitch = deg(10)

        case .walking:
            p.bodyHeight = 0.98
            p.tailBasePitch = deg(18)
            p.tailCurl = 0.25

        case .trotting:
            p.bodyHeight = 0.97
            p.bodyPitch = deg(-3)
            p.tailBasePitch = deg(24)
            p.tailCurl = 0.30

        case .running:
            p.bodyHeight = 0.92
            p.torsoLength = 1.06
            p.bodyPitch = deg(-7)
            p.neckPitch = deg(-8)
            p.tailBasePitch = deg(6)

        case .sitting:
            p.bodyHeight = 0.72
            p.torsoLength = 0.92
            p.torsoHeight = 1.05
            p.bodyPitch = deg(-26)
            p.neckPitch = deg(-16)
            p.tuckHind = 0.80
            p.hindFoot = SIMD3<Float>(x: 0.006, y: 0.018, z: 0.048)
            p.frontFoot = SIMD3<Float>(x: 0, y: 0, z: -0.012)
            p.tailBasePitch = deg(-24)
            p.tailCurl = 0.55
            p.tailSide = 0.5

        case .sittingTall:
            p.bodyHeight = 0.76
            p.torsoLength = 0.90
            p.torsoHeight = 1.06
            p.bodyPitch = deg(-33)
            p.neckPitch = deg(-24)
            p.headPitch = deg(14)
            p.tuckHind = 0.85
            p.hindFoot = SIMD3<Float>(x: 0.006, y: 0.020, z: 0.054)
            p.frontFoot = SIMD3<Float>(x: 0, y: 0, z: -0.016)
            p.tailBasePitch = deg(-34)
            p.tailCurl = 0.5
            p.tailSide = 0.6

        case .loaf:
            p.bodyHeight = 0.46
            p.torsoLength = 0.80
            p.torsoHeight = 1.14
            p.tuckFront = 1.0
            p.tuckHind = 1.0
            p.neckPitch = deg(-46)
            p.headPitch = deg(32)
            p.tailCurl = 0.9
            p.tailSide = 0.8
            p.tailBasePitch = deg(-38)

        case .lyingSide:
            p.bodyHeight = 0.34
            p.torsoLength = 1.06
            p.torsoHeight = 0.92
            p.bodyRoll = deg(38)
            p.tuckFront = 0.30
            p.tuckHind = 0.35
            p.frontFoot = SIMD3<Float>(x: 0.045, y: 0.010, z: 0.055)
            p.hindFoot = SIMD3<Float>(x: 0.050, y: 0.008, z: -0.035)
            p.neckPitch = deg(14)
            p.headRoll = deg(-22)
            p.tailCurl = 0.25
            p.tailSide = 0.9
            p.earPitch = deg(8)

        case .curled:
            p.bodyHeight = 0.40
            p.torsoLength = 0.72
            p.torsoHeight = 1.18
            p.bodyRoll = deg(22)
            p.tuckFront = 1.0
            p.tuckHind = 1.0
            p.neckPitch = deg(52)
            p.headPitch = deg(26)
            p.headYaw = deg(-46)
            p.headRoll = deg(-18)
            p.tailCurl = 1.0
            p.tailSide = 1.0
            p.tailBasePitch = deg(-52)
            p.earPitch = deg(6)

        case .crouch:
            p.bodyHeight = 0.55
            p.tuckFront = 0.30
            p.tuckHind = 0.40
            p.neckPitch = deg(6)
            p.tailBasePitch = deg(-30)
            p.tailCurl = 0.2

        case .stretching:
            p.bodyHeight = 0.86
            p.torsoLength = 1.14
            p.torsoHeight = 0.92
            p.bodyPitch = deg(22)
            p.frontFoot = SIMD3<Float>(x: 0, y: -0.004, z: 0.075)
            p.hindFoot = SIMD3<Float>(x: 0, y: 0, z: -0.045)
            p.neckPitch = deg(-16)
            p.headPitch = deg(-14)
            p.tailBasePitch = deg(46)
            p.jawOpen = 0.35
            p.earPitch = deg(-4)

        case .grooming:
            p.bodyHeight = 0.66
            p.bodyPitch = deg(-16)
            p.tuckFront = 0.25
            p.tuckHind = 0.75
            p.neckPitch = deg(48)
            p.headPitch = deg(30)
            p.headYaw = deg(28)
            p.jawOpen = 0.22
            p.tailCurl = 0.5
            p.tailSide = 0.4

        case .eating:
            p.bodyHeight = 0.90
            p.neckPitch = deg(52)
            p.headPitch = deg(26)
            p.jawOpen = 0.28
            p.tailBasePitch = deg(-6)

        case .drinking:
            p.bodyHeight = 0.88
            p.neckPitch = deg(58)
            p.headPitch = deg(30)
            p.jawOpen = 0.16
            p.tailBasePitch = deg(-10)

        case .litterCrouch:
            p.bodyHeight = 0.52
            p.tuckFront = 0.30
            p.tuckHind = 0.65
            p.bodyPitch = deg(-8)
            p.neckPitch = deg(10)
            p.tailBasePitch = deg(58)
            p.tailCurl = 0.1

        case .playCrouch:
            p.bodyHeight = 0.48
            p.bodyPitch = deg(6)
            p.tuckFront = 0.35
            p.tuckHind = 0.25
            p.neckPitch = deg(-10)
            p.headPitch = deg(-4)
            p.tailBasePitch = deg(-16)
            p.tailSide = 1.0
            p.earPitch = deg(-6)

        case .pounce:
            p.bodyHeight = 1.12
            p.bodyPitch = deg(-16)
            p.frontFoot = SIMD3<Float>(x: 0.010, y: 0.085, z: 0.075)
            p.hindFoot = SIMD3<Float>(x: 0, y: 0.010, z: -0.030)
            p.neckPitch = deg(-14)
            p.tailBasePitch = deg(24)

        case .rearUp:
            p.bodyHeight = 1.06
            p.bodyPitch = deg(-46)
            p.frontFoot = SIMD3<Float>(x: 0.020, y: 0.135, z: 0.055)
            p.hindFoot = SIMD3<Float>(x: 0, y: 0.004, z: 0.015)
            p.neckPitch = deg(-22)
            p.headPitch = deg(-16)
            p.frontPawLift = 0.8
            p.tailBasePitch = deg(-6)

        case .kneading:
            p.bodyHeight = 0.46
            p.tuckFront = 0.10
            p.tuckHind = 0.80
            p.neckPitch = deg(12)
            p.frontPawLift = 1.0
            p.tailCurl = 0.6
            p.tailSide = 0.3

        case .scratchingPost:
            p.bodyHeight = 1.04
            p.bodyPitch = deg(-54)
            p.frontFoot = SIMD3<Float>(x: 0.024, y: 0.150, z: 0.060)
            p.hindFoot = SIMD3<Float>(x: 0, y: 0, z: 0.010)
            p.neckPitch = deg(-18)
            p.frontPawLift = 0.9
            p.tailBasePitch = deg(10)
        }

        // Long, heavy tails hang lower.
        p.tailBasePitch -= a.tailFluff * deg(6)
        return p
    }
}
