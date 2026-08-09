import Foundation
import SceneKit

enum CatEvent {
    case meow(pitch: Float)
    case trill
    case chirp
    case purrStart
    case purrStop
    case hiss
    case yowl
    case crunch
    case lap
    case scratchSound
    case thud
    case bell
    case startled
    case activityChanged(CatActivity)
    case overstimulated
    case teacupKnocked
}

enum PetZone: String {
    case head, cheek, chin, back, belly, tail, paw

    /// How much the cat enjoys being touched here. Negative = actively dislikes.
    var baseAffinity: Float {
        switch self {
        case .head: return 1.0
        case .cheek: return 1.0
        case .chin: return 1.1
        case .back: return 0.8
        case .belly: return -0.35
        case .tail: return -0.2
        case .paw: return -0.5
        }
    }

    /// Multiplier on how fast overstimulation builds.
    var stimulationRate: Float {
        switch self {
        case .head, .cheek, .chin: return 0.7
        case .back: return 1.0
        case .belly: return 2.6
        case .tail: return 2.2
        case .paw: return 2.4
        }
    }
}

/// Read-only view of the cat used by the renderer and the HUD.
struct CatMotion {
    var position = SIMD3<Float>(x: 0, y: 0, z: -0.6)
    var yaw: Float = 0
    var pose: CatPose = .sitting
    var speed: Float = 0
    var lookTarget: SIMD3<Float>? = nil
    var lookWeight: Float = 0
    var tailAgitation: Float = 0
    var earPin: Float = 0
    var eyeOpen: Float = 1
    var purr: Float = 0
    var jumpHeight: Float = 0
    var crouchAmount: Float = 0
    var breathRate: Float = 1
}

final class CatBrain {

    // Configuration
    var personality: CatPersonality
    var appearance: CatAppearance

    // World state
    var needs: CatNeeds
    var room: RoomState
    var bond: Float

    // Motion
    private(set) var motion = CatMotion()
    private(set) var activity: CatActivity = .loafFloor
    private(set) var isTraveling = false

    // Player interaction
    private(set) var isBeingPet = false
    private(set) var petStimulation: Float = 0
    private(set) var isOverstimulated = false
    private var overstimulationTimer: Float = 0
    private var petZone: PetZone = .head
    private var petIntensity: Float = 0
    private var attentionTimer: Float = 0
    private var recallTimer: Float = 0

    var wandActive = false
    var wandTip = SIMD3<Float>(x: 0, y: 0.4, z: 0.4)
    private var wandExcitement: Float = 0
    private var pounceCooldown: Float = 0

    var treatPosition: SIMD3<Float>? = nil

    var onEvent: ((CatEvent) -> Void)?

    // Internals
    private var rng: SeededGenerator
    private var noise: ValueNoise
    private var spot = CatSpot(position: SIMD3<Float>(x: 0, y: 0, z: -0.6))
    private var performRemaining: Float = 4
    private var reevaluateIn: Float = 2
    private var recentActivities: [CatActivity: Float] = [:]
    private var jumpTimer: Float = -1
    private var jumpDuration: Float = 0.52
    private var jumpFromY: Float = 0
    private var jumpToY: Float = 0
    private var vocalCooldown: Float = 4
    private var blinkTimer: Float = 3
    private var blinkPhase: Float = -1
    private var elapsedTotal: Float = 0
    private var sky: SkyState = WorldClock.sky()
    /// How long the current activity has been running (including travel).
    private var activityElapsed: Float = 0
    /// Per-activity preference jitter. Held steady for a while so the cat commits
    /// to a choice instead of dithering between two near-equal options every tick.
    private var scoreJitter: [CatActivity: Float] = [:]
    private var jitterAge: Float = 99

    /// Player-visible caption for the HUD.
    var statusCaption: String {
        if isOverstimulated { return "had quite enough, thank you" }
        if isBeingPet { return "getting pets" }
        if isTraveling { return "on the way to " + activity.caption }
        return activity.caption
    }

    init(save: GameSave) {
        self.personality = save.profile.personality
        self.appearance = save.profile.appearance
        self.needs = save.needs
        self.room = save.room
        self.bond = save.bond
        self.rng = SeededGenerator(seed: save.profile.appearance.seed &+ UInt64(Date().timeIntervalSince1970))
        self.noise = ValueNoise(seed: save.profile.appearance.seed)
        self.motion.position = SIMD3<Float>(x: 0.1, y: 0, z: -0.5)
        chooseActivity(force: true)
    }

    // MARK: - Public interaction API

    func call() {
        recallTimer = 0
        let roll = rng.float()
        var chance = personality.recallChance + bond * 0.25 + (needs.social < 0.4 ? 0.2 : 0)
        // A cat that is properly asleep mostly just flicks an ear at you.
        if activity.isSleeping && !isTraveling {
            chance *= 0.30 + 0.35 * needs.rest
        }
        motion.lookTarget = RoomLayout.cameraPosition
        motion.lookWeight = 1
        attentionTimer = 3.5

        if roll < chance && !isOverstimulated {
            if rng.float() < personality.chattiness {
                onEvent?(.trill)
            }
            begin(.greetPlayer)
        } else {
            // Acknowledged. Declined.
            if rng.float() < personality.chattiness * 0.6 && !activity.isSleeping {
                onEvent?(.meow(pitch: rng.float(0.85, 1.15)))
            }
            motion.earPin = 0.25
        }
    }

    func beginPetting(zone: PetZone) {
        guard canBePet else { return }
        petZone = zone
        isBeingPet = true
        attentionTimer = 2
        if !activity.isSleeping {
            begin(.receivePets, keepPosition: true)
        }
    }

    func updatePetting(zone: PetZone, intensity: Float) {
        guard isBeingPet else { return }
        petZone = zone
        petIntensity = clamp(intensity)
    }

    func endPetting() {
        guard isBeingPet else { return }
        isBeingPet = false
        petIntensity = 0
        if motion.purr > 0.05 { onEvent?(.purrStop) }
        motion.purr = 0
    }

    /// True when the cat is within arm's reach of the seated player.
    var canBePet: Bool {
        motion.position.planarDistance(to: RoomLayout.cameraPosition) < 1.60 && !isOverstimulated
    }

    func setWand(active: Bool, tip: SIMD3<Float>) {
        if active && !wandActive { wandExcitement = 0.2 }
        wandActive = active
        wandTip = tip
        if !active && activity == .chaseWand {
            performRemaining = 0.5
        }
    }

    func dropTreat(at position: SIMD3<Float>) {
        treatPosition = RoomLayout.clampToWalkable(position)
        reevaluateIn = 0
    }

    func startle(intensity: Float = 1) {
        let s = intensity * personality.skittishness
        if s > 0.35 {
            onEvent?(.startled)
            motion.earPin = 1
            motion.tailAgitation = min(1, motion.tailAgitation + s)
            if s > 0.7 { begin(.hide) }
        }
    }

    func refillFeeder() { room.feederFood = 1 }
    func refillFountain() { room.fountainWater = 1 }
    func cleanLitter() { room.litterCleanliness = 1 }

    // MARK: - Main tick

    func update(dt rawDt: Float, sky: SkyState) {
        let dt = min(rawDt, 0.1)
        self.sky = sky
        elapsedTotal += dt

        decayNeeds(dt: dt)
        updateConsumables(dt: dt)
        updatePetting(dt: dt)
        updateWand(dt: dt)
        updateTimers(dt: dt)

        if jumpTimer >= 0 {
            updateJump(dt: dt)
        } else if wandActive && activity == .chaseWand {
            // updateWand already drove position, yaw and pose this frame.
            performRemaining -= dt
            if performRemaining <= 0 { chooseActivity(force: true) }
        } else if isTraveling {
            updateTravel(dt: dt)
        } else {
            updatePerform(dt: dt)
        }

        updateLook(dt: dt)
        updateExpressions(dt: dt)
    }

    // MARK: - Needs

    private func decayNeeds(dt: Float) {
        let hours = dt / 3600
        let awakeFactor: Float = activity.isSleeping ? 0.35 : 1.0
        needs.decay(hours: hours, personality: personality, awakeFactor: awakeFactor)

        // Sleeping restores rest instead of draining it.
        for (key, rate) in activity.restores where !isTraveling {
            needs[key] = needs[key] + rate * dt
        }
        if isBeingPet {
            needs.social = clamp(needs.social + 0.018 * dt * (0.5 + petZone.baseAffinity * 0.5))
        }
        if wandActive && activity == .chaseWand {
            needs.play = clamp(needs.play + 0.006 * dt)
        }
    }

    private func updateConsumables(dt: Float) {
        // Rates are tuned so a full hopper lasts about a week and the fountain
        // about five days — the care loop should be a habit, not a chore.
        if activity == .eat && !isTraveling {
            room.feederFood = clamp(room.feederFood - 0.0010 * dt)
        }
        if activity == .drink && !isTraveling {
            room.fountainWater = clamp(room.fountainWater - 0.0011 * dt)
        }
        if activity == .litter && !isTraveling {
            room.litterCleanliness = clamp(room.litterCleanliness - 0.0075 * dt)
        }
        if room.fountainOn {
            room.fountainWater = clamp(room.fountainWater - 0.0000008 * dt)
        }
    }

    // MARK: - Petting & overstimulation

    private func updatePetting(dt: Float) {
        if isOverstimulated {
            overstimulationTimer -= dt
            if overstimulationTimer <= 0 {
                isOverstimulated = false
                petStimulation = 0
                motion.earPin = 0
            }
            return
        }

        guard isBeingPet else {
            petStimulation = max(0, petStimulation - dt * 0.9)
            return
        }

        if !canBePet {
            endPetting()
            return
        }

        let affinity = petZone.baseAffinity + personality.cuddliness * 0.35
        let build = petZone.stimulationRate * (0.55 + petIntensity) * dt
        petStimulation += build / max(1, personality.overstimulationSeconds) * 8

        if affinity > 0.35 {
            let target = clamp(0.35 + affinity * 0.5) * (1 - petStimulation * 0.5)
            if motion.purr < 0.05 && target > 0.2 { onEvent?(.purrStart) }
            motion.purr = approach(motion.purr, max(0, target), rate: 1.4, dt: dt)
            bond = clamp(bond + 0.004 * dt)
        } else {
            motion.purr = approach(motion.purr, 0, rate: 2.5, dt: dt)
            motion.tailAgitation = clamp(motion.tailAgitation + dt * 0.35)
        }

        // Tail flicks and ear pinning telegraph the incoming bite.
        motion.tailAgitation = clamp(motion.tailAgitation + (petStimulation - 0.5) * dt * 0.6)
        motion.earPin = clamp(petStimulation - 0.35)

        if petStimulation >= 1 {
            triggerOverstimulation()
        }
    }

    private func triggerOverstimulation() {
        isOverstimulated = true
        overstimulationTimer = 7
        isBeingPet = false
        petIntensity = 0
        motion.purr = 0
        motion.earPin = 1
        motion.tailAgitation = 1
        bond = clamp(bond - 0.02)
        needs.social = clamp(needs.social - 0.05)
        onEvent?(.purrStop)
        onEvent?(rng.float() < 0.5 ? .hiss : .yowl)
        onEvent?(.overstimulated)
        // Storm off.
        begin(.wander)
        spot = CatSpot(position: RoomLayout.clampToWalkable(
            SIMD3<Float>(x: motion.position.x + rng.float(-1.4, 1.4),
                       y: 0,
                       z: -1.2 + rng.float(-0.3, 0.3))))
        isTraveling = true
    }

    // MARK: - Wand

    private func updateWand(dt: Float) {
        if wandActive {
            let dist = motion.position.planarDistance(to: wandTip)
            let interest = clamp(personality.playfulness * 0.8 + (1 - needs.play) * 0.6 + personality.energy * 0.3)
            wandExcitement = approach(wandExcitement, interest, rate: 0.8, dt: dt)
            if activity != .chaseWand && wandExcitement > 0.45 && dist < 2.4 && !isOverstimulated {
                begin(.chaseWand)
            }
        } else {
            wandExcitement = approach(wandExcitement, 0, rate: 0.6, dt: dt)
        }

        guard activity == .chaseWand, wandActive else { return }

        pounceCooldown -= dt
        let target = RoomLayout.clampToWalkable(wandTip)
        let dist = motion.position.planarDistance(to: target)

        // Track the wand, crouch when it settles, pounce when it is close.
        spot.position = target
        motion.yaw = approachAngle(motion.yaw, yawTowards(from: motion.position, to: target), rate: 7, dt: dt)

        if dist > 0.30 {
            let sp = min(2.6, 0.9 + dist * 1.4) * appearance.scale
            step(toward: target, speed: sp, dt: dt)
            motion.pose = dist > 1.1 ? .running : .trotting
            motion.speed = sp
            motion.crouchAmount = 0.2
        } else {
            motion.speed = 0
            if wandTip.y > 0.55 {
                motion.pose = .rearUp
                motion.crouchAmount = 0
            } else if pounceCooldown <= 0 {
                motion.pose = .pounce
                pounceCooldown = rng.float(0.9, 2.0)
                if rng.float() < 0.35 { onEvent?(.thud) }
            } else {
                motion.pose = .playCrouch
                motion.crouchAmount = 0.7
            }
        }
        motion.tailAgitation = clamp(0.5 + wandExcitement * 0.5)
        motion.lookTarget = wandTip
        motion.lookWeight = 1
    }

    // MARK: - Movement

    private func step(toward target: SIMD3<Float>, speed: Float, dt: Float) {
        let dx = target.x - motion.position.x
        let dz = target.z - motion.position.z
        let d = sqrtf(dx * dx + dz * dz)
        guard d > 1e-4 else { return }
        let travel = min(d, speed * dt)
        motion.position.x += dx / d * travel
        motion.position.z += dz / d * travel
    }

    private func updateTravel(dt: Float) {
        let target = spot.position

        // Standing on the sill or the cat tree and heading somewhere lower? Hop down first.
        if motion.position.y > spot.surfaceHeight + 0.06 {
            startJump(to: spot.surfaceHeight)
            return
        }

        let dist = motion.position.planarDistance(to: target)

        let urgency = travelUrgency()
        let baseSpeed: Float = urgency > 0.7 ? 1.75 : (urgency > 0.4 ? 1.05 : 0.55)
        let speed = baseSpeed * appearance.scale * (0.75 + 0.5 * personality.energy)

        motion.pose = speed > 1.5 ? .running : (speed > 0.85 ? .trotting : .walking)
        motion.speed = speed
        motion.crouchAmount = 0

        let desiredYaw = yawTowards(from: motion.position, to: target)
        motion.yaw = approachAngle(motion.yaw, desiredYaw, rate: 6, dt: dt)

        step(toward: target, speed: speed, dt: dt)

        let arriveRadius: Float = spot.needsJump ? 0.34 : 0.09
        if dist <= arriveRadius {
            if spot.needsJump && spot.surfaceHeight > 0.12 {
                startJump(to: spot.surfaceHeight)
            } else {
                arrive()
            }
        }
    }

    private func travelUrgency() -> Float {
        switch activity {
        case .litter: return 1 - needs.bladder
        case .eat: return (1 - needs.fullness) * 0.9
        case .drink: return (1 - needs.hydration) * 0.8
        case .chaseWand, .zoomies: return 1
        case .greetPlayer, .eatTreat: return 0.55 + personality.energy * 0.4
        case .hide: return 1
        default: return 0.25 + personality.energy * 0.3
        }
    }

    private func startJump(to height: Float) {
        jumpTimer = 0
        jumpFromY = motion.position.y
        jumpToY = height
        jumpDuration = 0.42 + abs(height - jumpFromY) * 0.28
        motion.pose = .crouch
    }

    private func updateJump(dt: Float) {
        jumpTimer += dt
        let t = clamp(jumpTimer / jumpDuration)
        let base = mix(jumpFromY, jumpToY, smoothstep(0, 1, t))
        let arc = sinf(t * .pi) * (0.16 + abs(jumpToY - jumpFromY) * 0.35)
        motion.position.y = base + arc
        motion.jumpHeight = arc
        motion.pose = t < 0.5 ? .pounce : .crouch
        motion.speed = 0

        // Glide horizontally onto the platform during the jump.
        step(toward: spot.position, speed: 1.6, dt: dt)

        if t >= 1 {
            jumpTimer = -1
            motion.position.y = jumpToY
            motion.jumpHeight = 0
            if rng.float() < 0.25 { onEvent?(.thud) }
            // A hop down may land well short of the destination — keep walking if so.
            let arriveRadius: Float = spot.needsJump ? 0.34 : 0.12
            if motion.position.planarDistance(to: spot.position) <= arriveRadius {
                arrive()
            }
        }
    }

    private func arrive() {
        isTraveling = false
        motion.position.y = spot.surfaceHeight
        motion.speed = 0
        let (lo, hi) = activity.duration
        performRemaining = rng.float(lo, hi)
        if let f = spot.facing { motion.yaw = f }
        motion.pose = activity.pose
        onEvent?(.activityChanged(activity))

        switch activity {
        case .eat: onEvent?(.crunch)
        case .drink: onEvent?(.lap)
        case .scratchPost: onEvent?(.scratchSound)
        case .greetPlayer:
            if rng.float() < personality.chattiness { onEvent?(.trill) }
        case .chirpAtBirds: onEvent?(.chirp)
        default: break
        }
    }

    private func updatePerform(dt: Float) {
        performRemaining -= dt
        motion.speed = 0

        if let f = spot.facing {
            motion.yaw = approachAngle(motion.yaw, f, rate: 3, dt: dt)
        }

        // Micro-behaviours layered on top of the main activity.
        switch activity {
        case .eat:
            if rng.float() < dt * 1.2 { onEvent?(.crunch) }
        case .drink:
            if rng.float() < dt * 1.6 { onEvent?(.lap) }
        case .scratchPost:
            if rng.float() < dt * 1.1 { onEvent?(.scratchSound) }
        case .windowWatch:
            if rng.float() < dt * 0.012 { onEvent?(.chirp) }
        case .batTeacup:
            if rng.float() < dt * 0.08 {
                onEvent?(.teacupKnocked)
                startle(intensity: 0.4)
            }
        case .playMouse, .playBall:
            if rng.float() < dt * 0.4 { motion.pose = .pounce }
            else { motion.pose = .playCrouch }
        case .receivePets:
            if !isBeingPet && !isOverstimulated { performRemaining = min(performRemaining, 2) }
        default:
            break
        }

        if activity.isSleeping {
            motion.purr = approach(motion.purr, personality.cuddliness > 0.6 ? 0.15 : 0, rate: 0.3, dt: dt)
        }

        // A genuinely urgent need overrides the slow re-evaluation cadence.
        if needs.lowest.value < 0.18 { reevaluateIn = min(reevaluateIn, 1.5) }

        reevaluateIn -= dt
        if performRemaining <= 0 || reevaluateIn <= 0 {
            reevaluateIn = reevaluationInterval(for: activity)
            chooseActivity(force: performRemaining <= 0)
        }
    }

    // MARK: - Decision making

    private func updateTimers(dt: Float) {
        attentionTimer = max(0, attentionTimer - dt)
        recallTimer += dt
        vocalCooldown -= dt
        activityElapsed += dt

        jitterAge += dt
        if jitterAge > 45 {
            jitterAge = 0
            for candidate in CatActivity.allCases {
                scoreJitter[candidate] = rng.float(-0.45, 0.45)
            }
        }
        for (k, v) in recentActivities {
            let nv = v - dt
            if nv <= 0 { recentActivities.removeValue(forKey: k) } else { recentActivities[k] = nv }
        }
        motion.tailAgitation = approach(motion.tailAgitation, isBeingPet ? motion.tailAgitation : 0, rate: 0.25, dt: dt)
        if !isBeingPet && !isOverstimulated {
            motion.earPin = approach(motion.earPin, 0, rate: 0.8, dt: dt)
        }

        // Spontaneous vocalisation when a need is really low.
        if vocalCooldown <= 0 {
            vocalCooldown = rng.float(90, 300) / max(0.3, personality.chattiness)
            let worst = needs.lowest
            if worst.value < 0.22 && !activity.isSleeping && rng.float() < personality.chattiness {
                onEvent?(.meow(pitch: rng.float(0.85, 1.25)))
            }
        }
    }

    private func begin(_ new: CatActivity, keepPosition: Bool = false) {
        activity = new
        activityElapsed = 0
        switch new {
        case .stretch: recentActivities[new] = 240
        case .zoomies: recentActivities[new] = 1200
        case .scratchPost, .batTeacup: recentActivities[new] = 300
        case .chirpAtBirds: recentActivities[new] = 900
        case .greetPlayer: recentActivities[new] = 900
        case .sitAndStare, .followPlayer: recentActivities[new] = 240
        case .loafTable: recentActivities[new] = 260
        case _ where new.isSleeping: recentActivities[new] = 700
        default: recentActivities[new] = 40
        }
        spot = new.spot(sky: sky, rng: &rng)
        if keepPosition {
            spot.position = motion.position
            spot.facing = yawTowards(from: motion.position, to: RoomLayout.cameraPosition)
            isTraveling = false
            let (lo, hi) = new.duration
            performRemaining = rng.float(lo, hi)
            motion.pose = new.pose
            onEvent?(.activityChanged(new))
            return
        }
        if new == .chaseWand {
            // The wand chase steers itself every frame; it never "travels" to a fixed spot.
            spot.position = RoomLayout.clampToWalkable(wandTip)
            isTraveling = false
            let (lo, hi) = new.duration
            performRemaining = rng.float(lo, hi)
            motion.pose = new.pose
            onEvent?(.activityChanged(new))
            reevaluateIn = reevaluationInterval(for: new)
            return
        }
        if new == .eatTreat, let t = treatPosition {
            spot.position = t
        }
        let dist = motion.position.planarDistance(to: spot.position)
        let heightMismatch = abs(motion.position.y - spot.surfaceHeight) > 0.05
        isTraveling = dist > 0.10 || heightMismatch
        if !isTraveling { arrive() }
        reevaluateIn = reevaluationInterval(for: new)
    }

    /// Long activities are re-considered rarely; short ones often. Without this a
    /// sleeping cat gets poked awake every couple of seconds by scoring noise.
    private func reevaluationInterval(for a: CatActivity) -> Float {
        let (lo, _) = a.duration
        return min(20, max(2.5, lo * 0.12))
    }

    private func chooseActivity(force: Bool) {
        guard !isOverstimulated || force else { return }
        if isBeingPet { return }
        if wandActive && activity == .chaseWand { return }

        var best: CatActivity = .loafFloor
        var bestScore: Float = -999

        for candidate in CatActivity.allCases {
            let s = score(candidate)
            if s > bestScore {
                bestScore = s
                best = candidate
            }
        }

        // Inertia: don't abandon a long activity for a marginal improvement.
        // The jitter is held steady between re-rolls, so this comparison is stable.
        if !force {
            let current = score(activity)
            let threshold: Float = activity.isSleeping ? 0.7 : 0.35
            if bestScore < current + threshold { return }
        }
        if best == activity && !force { return }

        // Cats stretch when they get up from a proper nap — but only after a real
        // one, and never twice in quick succession.
        if activity.isSleeping && best != activity && activityElapsed > 90
            && recentActivities[.stretch] == nil && rng.float() < 0.7 {
            begin(.stretch)
            return
        }
        begin(best)
    }

    private func score(_ a: CatActivity) -> Float {
        var s: Float = 0

        // Base: how much this activity relieves a deficit.
        for (key, rate) in a.restores where rate > 0 {
            let deficit = 1 - needs[key]
            s += deficit * deficit * rate * 240
        }

        let hour = sky.localHour
        // Crepuscular energy: peaks around dawn and dusk.
        let dawnPeak = expf(-powf((hour - 6.0) / 2.2, 2))
        let duskPeak = expf(-powf((hour - 19.5) / 2.4, 2))
        let crepuscular = clamp(dawnPeak + duskPeak)
        let sleepiness = clamp(1 - crepuscular * 0.9) * (0.5 + personality.sleepiness * 0.8)

        // Sleep pressure is the rest deficit shaped by the circadian curve. A fully
        // rested cat still naps, but not enough to sleep through the whole game.
        let restDeficit = 1 - needs.rest
        let sleepPull = (0.30 + sleepiness * 1.5) * (0.30 + 1.9 * restDeficit)

        switch a {
        case .sleepFuton:
            s += sleepPull * 1.15
        case .sleepCatBed:
            s += sleepPull * 1.00
        case .sleepTreeTop:
            s += sleepPull * 0.85 * (0.4 + personality.confidence)
        case .sleepSunPatch:
            if sky.daylight < 0.25 { return -100 }
            s += sleepPull * 1.25 * clamp(sky.daylight * 1.4)
        case .napWindowSill:
            s += sleepPull * 0.95 * clamp(sky.daylight + 0.2)
        case .perchTree:
            s += personality.curiosity * 1.1 + crepuscular * 0.7
        case .loafFloor:
            s += 0.75
        case .loafTable:
            s += 0.35 + personality.mischief * 1.0
        case .eat:
            if room.feederFood <= 0.02 { return -100 }
            s += (1 - needs.fullness) * 5.5 * personality.appetite + 0.2
        case .drink:
            if room.fountainWater <= 0.02 { return -100 }
            s += (1 - needs.hydration) * 5.0
            if !room.fountainOn { s -= 1.2 }
            s += personality.curiosity * 0.3
        case .litter:
            s += powf(1 - needs.bladder, 2) * 9
            s -= (1 - room.litterCleanliness) * 2.0
        case .groom:
            s += (1 - needs.cleanliness) * 3.4 + 0.55
            if activity == .eat || activity == .litter { s += 1.8 }
        case .stretch:
            return -100          // only reached by waking up from a nap
        case .knead:
            s += personality.cuddliness * 0.9 + (1 - needs.social) * 0.8
        case .scratchPost:
            s += 0.6 + personality.energy * 0.7
        case .playMouse, .playBall:
            s += (1 - needs.play) * 3.4 * personality.playfulness + crepuscular * 1.2
        case .batTeacup:
            s += personality.mischief * 2.0 * (1 - needs.play) + crepuscular * 0.8
            if hour > 2 && hour < 5 { s += personality.mischief * 1.5 }
        case .windowWatch:
            s += (1 - needs.curiosity) * 2.6 * personality.curiosity
            s += sky.daylight * 1.0
        case .chirpAtBirds:
            // Punctuation while already at the window, and rare enough to stay special.
            s += personality.curiosity * 0.7 * sky.daylight
            if activity == .windowWatch || activity == .napWindowSill { s += 0.9 }
        case .wander:
            s += 0.5 + personality.energy * 0.5
        case .sitAndStare:
            s += (1 - needs.social) * 3.0 + personality.affection * 1.1
        case .greetPlayer:
            s += (1 - needs.social) * 4.4 * (0.4 + personality.affection + personality.clinginess) * 0.6
            s += bond * 1.2 + personality.affection * 0.8
            if attentionTimer > 0 { s += 2.5 }
        case .receivePets:
            return isBeingPet ? 50 : -100
        case .chaseWand:
            return wandActive ? (2 + wandExcitement * 6) : -100
        case .eatTreat:
            return treatPosition != nil ? (4 + personality.appetite * 3) : -100
        case .zoomies:
            if needs.rest < 0.30 { return -100 }
            s += (0.4 + crepuscular * 2.4) * personality.energy * (1 - needs.play) * 1.6
        case .hide:
            return -100          // only reached by being startled
        case .followPlayer:
            s += (1 - needs.social) * 3.0 * (0.3 + personality.clinginess) + personality.cuddliness * 0.6
        }

        // Variety: recently performed activities are less attractive.
        if let cooldown = recentActivities[a] {
            s -= min(1.8, cooldown * 0.06)
        }
        // Sleeping cats resist getting up.
        if activity.isSleeping && !a.isSleeping {
            s -= 1.2 * personality.sleepiness
        }
        // Held jitter so two identical days never happen, without causing dithering.
        s += scoreJitter[a] ?? 0
        return s
    }

    // MARK: - Look-at, blinking, breathing

    private func updateLook(dt: Float) {
        var target: SIMD3<Float>? = nil
        var weight: Float = 0

        if isBeingPet || attentionTimer > 0 {
            target = RoomLayout.cameraPosition
            weight = 1
        } else if wandActive && wandExcitement > 0.3 {
            target = wandTip
            weight = 1
        } else if activity == .windowWatch || activity == .chirpAtBirds || activity == .napWindowSill {
            target = SIMD3<Float>(x: RoomLayout.windowCenter.x, y: 1.2, z: -2.4)
            weight = 0.8
        } else if activity == .sitAndStare || activity == .greetPlayer || activity == .followPlayer {
            target = RoomLayout.cameraPosition
            weight = 0.9
        } else if !activity.isSleeping {
            // Idle glancing around.
            let n = noise.fbm(elapsedTotal * 0.11, 3.7, octaves: 2)
            if n > 0.35 {
                target = RoomLayout.cameraPosition
                weight = 0.4
            } else if n < -0.4 {
                target = SIMD3<Float>(x: RoomLayout.windowCenter.x, y: 1.0, z: -2.0)
                weight = 0.4
            }
        }

        motion.lookTarget = target
        motion.lookWeight = approach(motion.lookWeight, weight, rate: 3, dt: dt)
    }

    private func updateExpressions(dt: Float) {
        // Eyes
        let sleeping = activity.isSleeping && !isTraveling
        var targetOpen: Float = sleeping ? 0.02 : 1.0
        if activity == .napWindowSill && !isTraveling { targetOpen = 0.25 }
        if motion.purr > 0.4 && !sleeping { targetOpen = 0.55 }        // slow blink of trust
        if isOverstimulated { targetOpen = 1.0 }

        if !sleeping {
            blinkTimer -= dt
            if blinkTimer <= 0 {
                blinkTimer = rng.float(2.5, 7.5)
                blinkPhase = 0
            }
            if blinkPhase >= 0 {
                blinkPhase += dt / 0.16
                if blinkPhase >= 1 { blinkPhase = -1 }
                else { targetOpen *= abs(cosf(blinkPhase * .pi)) }
            }
        }
        motion.eyeOpen = approach(motion.eyeOpen, targetOpen, rate: 14, dt: dt)

        // Breathing speeds up after exertion.
        let exertion: Float = motion.pose.isLocomotion ? 1 : 0
        motion.breathRate = approach(motion.breathRate, sleeping ? 0.55 : (0.9 + exertion * 0.9), rate: 0.6, dt: dt)

        // Purring while content and near the player.
        if !isBeingPet && !sleeping {
            let content = needs.mood > 0.7 && motion.position.planarDistance(to: RoomLayout.cameraPosition) < 1.9
            motion.purr = approach(motion.purr, content ? 0.35 * personality.affection : 0, rate: 0.5, dt: dt)
        }

        // Eat the treat if we reached it.
        if activity == .eatTreat && !isTraveling && performRemaining < 1 {
            treatPosition = nil
        }
    }

    // MARK: - Persistence

    func writeBack(to save: inout GameSave) {
        save.needs = needs
        save.room = room
        save.bond = bond
        save.lastSeen = Date()
    }
}
