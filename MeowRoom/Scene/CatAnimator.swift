import Foundation
import SceneKit

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
    var frontFoot = SCNVector3.zero  // offset from the rest stance, in body space
    var hindFoot = SCNVector3.zero
    var tuck: Float = 0              // legs folding under the body
    var tailBasePitch: Float = 0
    var tailCurl: Float = 0
    var tailSide: Float = 0
    var earPitch: Float = 0
    var jawOpen: Float = 0
    var frontPawLift: Float = 0      // for kneading / batting

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
        tuck = approach(tuck, t.tuck, rate: rate, dt: dt)
        tailBasePitch = approach(tailBasePitch, t.tailBasePitch, rate: rate, dt: dt)
        tailCurl = approach(tailCurl, t.tailCurl, rate: rate, dt: dt)
        tailSide = approach(tailSide, t.tailSide, rate: rate, dt: dt)
        earPitch = approach(earPitch, t.earPitch, rate: rate, dt: dt)
        jawOpen = approach(jawOpen, t.jawOpen, rate: rate * 2, dt: dt)
        frontPawLift = approach(frontPawLift, t.frontPawLift, rate: rate, dt: dt)
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
        rig.root.eulerAngles = SCNVector3(x: 0, y: motion.yaw, z: 0)

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
        rig.body.position = SCNVector3(x: 0,
                                       y: bodyY + bob + purrJitter + motion.jumpHeight * 0.05,
                                       z: 0)
        let sway = motion.speed > 0.02 ? sinf(gait * 2 * .pi) * 0.05 * min(1, motion.speed) : 0
        rig.spine.eulerAngles = SCNVector3(x: pose.bodyPitch + breath * 0.008,
                                           y: sway * 0.35,
                                           z: pose.bodyRoll + sway)

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
        rig.jaw.eulerAngles = SCNVector3(x: pose.jawOpen * deg(26), y: 0, z: 0)

        // ---- Whisker idle ------------------------------------------------
        let whiskerTwitch = noise.value(clock * 0.9, 5.5) * 0.06
        for (i, pad) in rig.whiskerRoots.enumerated() {
            let s: Float = i == 0 ? -1 : 1
            pad.eulerAngles = SCNVector3(x: whiskerTwitch, y: s * motion.purr * 0.05, z: 0)
        }
    }

    // MARK: - Legs

    private func solveLegs(dt: Float, motion: CatMotion, bodyY: Float, strideLength: Float) {
        let phases = phaseOffsets(for: motion.pose)
        let moving = motion.speed > 0.03
        let lift = min(0.045, 0.018 + motion.speed * 0.020)
        let stride = min(strideLength * 0.5, 0.02 + motion.speed * 0.055)

        for (i, leg) in rig.legs.enumerated() {
            // Hip position in body space (unaffected by spine pitch/roll).
            let hipInBody = rig.body.convertPosition(leg.hip.position, from: rig.spine)
            let baseOffset = leg.isFront ? pose.frontFoot : pose.hindFoot

            var footX = hipInBody.x + baseOffset.x * leg.side
            var footY = -bodyY + baseOffset.y
            var footZ = hipInBody.z + baseOffset.z + (leg.isFront ? 0.012 : -0.008)

            // Folding the legs under the body for loafing / curling / sitting.
            if pose.tuck > 0.01 {
                let tuckY = mix(footY, -bodyY * 0.28, pose.tuck)
                let tuckZ = mix(footZ, hipInBody.z + (leg.isFront ? 0.030 : -0.018), pose.tuck)
                let tuckX = mix(footX, hipInBody.x * 0.72, pose.tuck)
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

            let ankleTargetBody = SCNVector3(x: footX, y: footY + leg.pawLength * 0.55, z: footZ)
            let ankleTarget = rig.spine.convertPosition(ankleTargetBody, from: rig.body)
            solveTwoBone(leg, ankleTarget: ankleTarget)
        }
    }

    /// Analytic two-bone IK in the leg's sagittal plane.
    private func solveTwoBone(_ leg: LegRig, ankleTarget: SCNVector3) {
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

        let hipAngle = thetaAim + leg.bendSign * alpha
        let kneeAngle = -leg.bendSign * (.pi - interior)

        leg.hip.eulerAngles = SCNVector3(x: hipAngle, y: 0, z: 0)
        leg.knee.eulerAngles = SCNVector3(x: kneeAngle, y: 0, z: 0)
        // Keep the paw roughly flat on the floor.
        leg.ankle.eulerAngles = SCNVector3(x: -(hipAngle + kneeAngle) * 0.92, y: 0, z: 0)
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
            let targetInSpine = rig.spine.convertPosition(targetWorld, from: nil)
            let d = targetInSpine - rig.neck.position
            let flat = sqrtf(d.x * d.x + d.z * d.z)
            if flat > 1e-4 || abs(d.y) > 1e-4 {
                let yaw = min(max(atan2f(d.x, d.z), -deg(78)), deg(78))
                let pitch = min(max(-atan2f(d.y, max(flat, 1e-4)), -deg(48)), deg(52))
                let w = motion.lookWeight
                // Split the turn between neck and head so it reads as one motion.
                rig.neck.eulerAngles = SCNVector3(x: mix(neckPitch, pitch * 0.35, w),
                                                  y: yaw * 0.40 * w,
                                                  z: 0)
                rig.head.eulerAngles = SCNVector3(x: mix(headPitch, pitch * 0.65, w),
                                                  y: mix(headYaw, yaw * 0.60, w),
                                                  z: headRoll)
                return
            }
        }

        // Idle: tiny head drift so the cat never looks frozen.
        let drift = noise.fbm(clock * 0.13, 1.7, octaves: 2)
        let drift2 = noise.fbm(clock * 0.11, 9.3, octaves: 2)
        rig.neck.eulerAngles = SCNVector3(x: neckPitch + breath * 0.010, y: drift * 0.05, z: 0)
        rig.head.eulerAngles = SCNVector3(x: headPitch + drift2 * 0.05,
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

        // Negative X lifts the tail, because tailPitch sits inside the root's 180° yaw.
        rig.tailPitch.eulerAngles = SCNVector3(x: -(deg(30) + pose.tailBasePitch),
                                               y: 0,
                                               z: pose.tailSide * 0.4)

        for (i, seg) in rig.tailSegments.enumerated() {
            guard i > 0 else { continue }
            let t = Float(i) / n
            let phase = clock * swaySpeed - t * 2.4
            let side = sinf(phase) * swayAmp * (0.35 + t)
            let curlUp = pose.tailCurl * (0.30 + 0.75 * t)
            let droop = (1 - pose.tailCurl) * 0.06 * t
            let wave = noise.value(clock * 0.5 + Float(i), 3.3) * 0.05
            seg.eulerAngles = SCNVector3(x: curlUp * 0.42 - droop + wave * 0.4,
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
        let a = rig.appearance
        let tilt = deg(mix(-8, 30, a.earTilt))

        for (idx, ear) in [rig.earL, rig.earR].enumerated() {
            let side: Float = idx == 0 ? -1 : 1
            let twitch = (idx == 0 ? earTwitch : earTwitch * 0.6) * 0.18
            ear.eulerAngles = SCNVector3(x: deg(-72) + base + pin * deg(46) + twitch,
                                         y: side * (deg(24) + pin * deg(28)),
                                         z: side * (tilt + pin * deg(20)))
        }
    }

    // MARK: - Eyes

    private func updateEyes(motion: CatMotion) {
        let closed = 1 - clamp(motion.eyeOpen)
        let upper = deg(-90) + closed * deg(72)
        let lower = deg(90) - closed * deg(58)
        rig.lidUpperL.eulerAngles = SCNVector3(x: upper, y: 0, z: 0)
        rig.lidUpperR.eulerAngles = SCNVector3(x: upper, y: 0, z: 0)
        rig.lidLowerL.eulerAngles = SCNVector3(x: lower, y: 0, z: 0)
        rig.lidLowerR.eulerAngles = SCNVector3(x: lower, y: 0, z: 0)

        // Eyes converge slightly on whatever the cat is watching.
        if let target = motion.lookTarget, motion.lookWeight > 0.2 {
            for (idx, socket) in [rig.eyeL, rig.eyeR].enumerated() {
                let side: Float = idx == 0 ? -1 : 1
                let local = rig.head.convertPosition(target, from: nil)
                let yaw = clamp(atan2f(local.x, max(0.02, local.z)), -0.35, 0.35)
                let pitch = clamp(-atan2f(local.y, max(0.02, local.z)), -0.28, 0.28)
                socket.eulerAngles = SCNVector3(x: pitch * 0.6,
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
            p.bodyPitch = deg(-7)
            p.neckPitch = deg(-8)
            p.tailBasePitch = deg(6)

        case .sitting:
            p.bodyHeight = 0.74
            p.bodyPitch = deg(-22)
            p.neckPitch = deg(16)
            p.hindFoot = SCNVector3(x: 0.008, y: 0.030, z: 0.040)
            p.frontFoot = SCNVector3(x: 0, y: 0, z: 0.020)
            p.tailBasePitch = deg(-24)
            p.tailCurl = 0.55
            p.tailSide = 0.5

        case .sittingTall:
            p.bodyHeight = 0.80
            p.bodyPitch = deg(-30)
            p.neckPitch = deg(22)
            p.headPitch = deg(-6)
            p.hindFoot = SCNVector3(x: 0.008, y: 0.032, z: 0.044)
            p.frontFoot = SCNVector3(x: 0, y: 0, z: 0.026)
            p.tailBasePitch = deg(-28)
            p.tailCurl = 0.65
            p.tailSide = 0.6

        case .loaf:
            p.bodyHeight = 0.34
            p.tuck = 1.0
            p.neckPitch = deg(6)
            p.tailCurl = 0.9
            p.tailSide = 0.8
            p.tailBasePitch = deg(-38)

        case .lyingSide:
            p.bodyHeight = 0.30
            p.bodyRoll = deg(38)
            p.tuck = 0.35
            p.frontFoot = SCNVector3(x: 0.045, y: 0.010, z: 0.055)
            p.hindFoot = SCNVector3(x: 0.050, y: 0.008, z: -0.035)
            p.neckPitch = deg(14)
            p.headRoll = deg(-22)
            p.tailCurl = 0.25
            p.tailSide = 0.9
            p.earPitch = deg(8)

        case .curled:
            p.bodyHeight = 0.30
            p.bodyRoll = deg(22)
            p.tuck = 1.0
            p.neckPitch = deg(42)
            p.headPitch = deg(26)
            p.headYaw = deg(-46)
            p.headRoll = deg(-18)
            p.tailCurl = 1.0
            p.tailSide = 1.0
            p.tailBasePitch = deg(-52)
            p.earPitch = deg(6)

        case .crouch:
            p.bodyHeight = 0.55
            p.tuck = 0.35
            p.neckPitch = deg(6)
            p.tailBasePitch = deg(-30)
            p.tailCurl = 0.2

        case .stretching:
            p.bodyHeight = 0.86
            p.bodyPitch = deg(22)
            p.frontFoot = SCNVector3(x: 0, y: -0.004, z: 0.075)
            p.hindFoot = SCNVector3(x: 0, y: 0, z: -0.045)
            p.neckPitch = deg(-16)
            p.headPitch = deg(-14)
            p.tailBasePitch = deg(46)
            p.jawOpen = 0.35
            p.earPitch = deg(-4)

        case .grooming:
            p.bodyHeight = 0.62
            p.bodyPitch = deg(-14)
            p.tuck = 0.55
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
            p.bodyHeight = 0.50
            p.tuck = 0.55
            p.bodyPitch = deg(-8)
            p.neckPitch = deg(10)
            p.tailBasePitch = deg(58)
            p.tailCurl = 0.1

        case .playCrouch:
            p.bodyHeight = 0.48
            p.bodyPitch = deg(6)
            p.tuck = 0.30
            p.neckPitch = deg(-10)
            p.headPitch = deg(-4)
            p.tailBasePitch = deg(-16)
            p.tailSide = 1.0
            p.earPitch = deg(-6)

        case .pounce:
            p.bodyHeight = 1.12
            p.bodyPitch = deg(-16)
            p.frontFoot = SCNVector3(x: 0.010, y: 0.085, z: 0.075)
            p.hindFoot = SCNVector3(x: 0, y: 0.010, z: -0.030)
            p.neckPitch = deg(-14)
            p.tailBasePitch = deg(24)

        case .rearUp:
            p.bodyHeight = 1.06
            p.bodyPitch = deg(-46)
            p.frontFoot = SCNVector3(x: 0.020, y: 0.135, z: 0.055)
            p.hindFoot = SCNVector3(x: 0, y: 0.004, z: 0.015)
            p.neckPitch = deg(-22)
            p.headPitch = deg(-16)
            p.frontPawLift = 0.8
            p.tailBasePitch = deg(-6)

        case .kneading:
            p.bodyHeight = 0.42
            p.tuck = 0.65
            p.neckPitch = deg(12)
            p.frontPawLift = 1.0
            p.tailCurl = 0.6
            p.tailSide = 0.3

        case .scratchingPost:
            p.bodyHeight = 1.04
            p.bodyPitch = deg(-54)
            p.frontFoot = SCNVector3(x: 0.024, y: 0.150, z: 0.060)
            p.hindFoot = SCNVector3(x: 0, y: 0, z: 0.010)
            p.neckPitch = deg(-18)
            p.frontPawLift = 0.9
            p.tailBasePitch = deg(10)
        }

        // Long, heavy tails hang lower.
        p.tailBasePitch -= a.tailFluff * deg(6)
        return p
    }
}
