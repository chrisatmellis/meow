import Foundation
import SceneKit

/// Body poses the animator knows how to build. Activities pick one.
enum CatPose {
    case standing
    case walking
    case trotting
    case running
    case sitting
    case loaf              // paws tucked, upright head
    case lyingSide
    case curled            // deep sleep
    case crouch
    case stretching
    case grooming
    case eating
    case drinking
    case litterCrouch
    case playCrouch        // butt-wiggle before a pounce
    case pounce
    case rearUp            // batting at the wand
    case kneading
    case scratchingPost
    case sittingTall       // alert, watching something

    var isSleep: Bool { self == .curled || self == .lyingSide }
    var isLocomotion: Bool { self == .walking || self == .trotting || self == .running }
}

/// A place in the room the cat can occupy, plus how it gets there.
struct CatSpot {
    var position: SIMD3<Float>
    var surfaceHeight: Float = 0
    var facing: Float? = nil          // desired yaw once arrived
    var needsJump: Bool = false
}

enum CatActivity: String, CaseIterable, Codable {
    case sleepFuton, sleepCatBed, sleepTreeTop, sleepSunPatch, napWindowSill
    case loafFloor, loafTable, perchTree
    case eat, drink, litter
    case groom, stretch, knead
    case scratchPost, playMouse, playBall, batTeacup
    case windowWatch, chirpAtBirds
    case wander, sitAndStare, greetPlayer, receivePets, chaseWand, eatTreat
    case zoomies, hide, followPlayer

    var pose: CatPose {
        switch self {
        case .sleepFuton, .sleepCatBed, .sleepTreeTop: return .curled
        case .sleepSunPatch: return .lyingSide
        case .napWindowSill: return .loaf
        case .loafFloor, .loafTable: return .loaf
        case .perchTree: return .sittingTall
        case .eat: return .eating
        case .drink: return .drinking
        case .litter: return .litterCrouch
        case .groom: return .grooming
        case .stretch: return .stretching
        case .knead: return .kneading
        case .scratchPost: return .scratchingPost
        case .playMouse, .playBall: return .playCrouch
        case .batTeacup: return .rearUp
        case .windowWatch, .chirpAtBirds: return .sittingTall
        case .wander: return .walking
        case .sitAndStare: return .sitting
        case .greetPlayer: return .sittingTall
        case .receivePets: return .sitting
        case .chaseWand: return .playCrouch
        case .eatTreat: return .eating
        case .zoomies: return .running
        case .hide: return .crouch
        case .followPlayer: return .sitting
        }
    }

    /// How long the cat sticks with this, in seconds (min, max).
    var duration: (Float, Float) {
        switch self {
        case .sleepFuton, .sleepCatBed, .sleepTreeTop, .sleepSunPatch: return (1500, 5400)
        case .napWindowSill: return (600, 2400)
        case .loafFloor, .loafTable: return (60, 240)
        case .perchTree: return (40, 150)
        case .eat: return (18, 40)
        case .drink: return (10, 24)
        case .litter: return (14, 26)
        case .groom: return (18, 55)
        case .stretch: return (3.5, 6)
        case .knead: return (12, 30)
        case .scratchPost: return (8, 18)
        case .playMouse, .playBall: return (20, 55)
        case .batTeacup: return (5, 11)
        case .windowWatch: return (45, 200)
        case .chirpAtBirds: return (6, 14)
        case .wander: return (4, 12)
        case .sitAndStare: return (12, 45)
        case .greetPlayer: return (6, 16)
        case .receivePets: return (4, 30)
        case .chaseWand: return (10, 40)
        case .eatTreat: return (4, 8)
        case .zoomies: return (5, 12)
        case .hide: return (25, 90)
        case .followPlayer: return (10, 30)
        }
    }

    /// Needs restored per second while performing.
    var restores: [NeedKey: Float] {
        switch self {
        // Rest is restored slowly: a full night is hours of sleep, not minutes.
        case .sleepFuton, .sleepCatBed, .sleepTreeTop, .sleepSunPatch:
            return [.rest: 0.000062, .cleanliness: 0.000004]
        case .napWindowSill:
            return [.rest: 0.000044, .curiosity: 0.0003]
        case .loafFloor, .loafTable:
            return [.rest: 0.000020]
        case .perchTree:
            return [.curiosity: 0.0012, .rest: 0.000008]
        case .eat:
            return [.fullness: 0.030]
        case .drink:
            return [.hydration: 0.045]
        case .litter:
            return [.bladder: 0.060, .cleanliness: -0.004]
        case .groom:
            return [.cleanliness: 0.014]
        case .stretch:
            return [.rest: 0.0002]
        case .knead:
            return [.social: 0.006, .rest: 0.00003]
        case .scratchPost:
            return [.play: 0.008, .cleanliness: 0.002]
        case .playMouse, .playBall:
            return [.play: 0.011, .curiosity: 0.004]
        case .batTeacup:
            return [.play: 0.014, .curiosity: 0.010]
        case .windowWatch:
            return [.curiosity: 0.0035]
        case .chirpAtBirds:
            return [.curiosity: 0.010, .play: 0.003]
        case .wander:
            return [.curiosity: 0.0012]
        case .sitAndStare:
            return [.social: 0.0022, .curiosity: 0.0006]
        case .greetPlayer:
            return [.social: 0.008]
        case .receivePets:
            return [.social: 0.020, .cleanliness: 0.003]
        case .chaseWand:
            return [.play: 0.024, .social: 0.008, .curiosity: 0.006]
        case .eatTreat:
            return [.fullness: 0.020, .social: 0.010]
        case .zoomies:
            return [.play: 0.014, .rest: -0.0006]
        case .hide:
            return [.rest: 0.00002]
        case .followPlayer:
            return [.social: 0.010]
        }
    }

    var isSleeping: Bool {
        switch self {
        case .sleepFuton, .sleepCatBed, .sleepTreeTop, .sleepSunPatch, .napWindowSill: return true
        default: return false
        }
    }

    /// Human-readable status for the HUD and the "while you were away" log.
    var caption: String {
        switch self {
        case .sleepFuton: return "curled up on the futon"
        case .sleepCatBed: return "asleep in the cat bed"
        case .sleepTreeTop: return "asleep on top of the cat tree"
        case .sleepSunPatch: return "sprawled in a sun patch"
        case .napWindowSill: return "dozing on the window sill"
        case .loafFloor: return "loafing on the tatami"
        case .loafTable: return "loafing on the table, illegally"
        case .perchTree: return "surveying the room from the cat tree"
        case .eat: return "eating"
        case .drink: return "drinking from the fountain"
        case .litter: return "using the litter box"
        case .groom: return "grooming"
        case .stretch: return "stretching"
        case .knead: return "making biscuits"
        case .scratchPost: return "scratching the post"
        case .playMouse: return "wrestling the toy mouse"
        case .playBall: return "batting the ball around"
        case .batTeacup: return "eyeing the teacup"
        case .windowWatch: return "watching the garden"
        case .chirpAtBirds: return "chirping at birds"
        case .wander: return "wandering around"
        case .sitAndStare: return "staring at you"
        case .greetPlayer: return "coming to say hello"
        case .receivePets: return "getting pets"
        case .chaseWand: return "chasing the wand"
        case .eatTreat: return "eating a treat"
        case .zoomies: return "having the zoomies"
        case .hide: return "hiding under the table"
        case .followPlayer: return "sitting with you"
        }
    }

    /// Where the activity happens.
    func spot(sky: SkyState, rng: inout SeededGenerator) -> CatSpot {
        switch self {
        case .sleepFuton:
            return CatSpot(position: SIMD3<Float>(x: RoomLayout.futonCenter.x + rng.float(-0.22, 0.22),
                                               y: 0,
                                               z: RoomLayout.futonCenter.z + rng.float(-0.45, 0.45)),
                           surfaceHeight: RoomLayout.futonTop,
                           facing: rng.float(-.pi, .pi))
        case .sleepCatBed:
            return CatSpot(position: RoomLayout.catBedCenter,
                           surfaceHeight: RoomLayout.catBedTop,
                           facing: rng.float(-.pi, .pi))
        case .sleepTreeTop, .perchTree:
            return CatSpot(position: RoomLayout.catTreeTopPlatform,
                           surfaceHeight: RoomLayout.catTreeTopPlatform.y,
                           facing: deg(150),
                           needsJump: true)
        case .sleepSunPatch:
            let p = RoomLayout.sunPatchPosition(sky: sky)
            return CatSpot(position: RoomLayout.clampToWalkable(p), facing: rng.float(-.pi, .pi))
        case .napWindowSill, .windowWatch, .chirpAtBirds:
            return CatSpot(position: SIMD3<Float>(x: RoomLayout.windowSill.x + rng.float(-0.5, 0.5),
                                               y: 0,
                                               z: RoomLayout.windowSill.z + 0.10),
                           surfaceHeight: RoomLayout.windowSill.y,
                           facing: .pi,           // facing -Z, out the window
                           needsJump: true)
        case .loafTable, .batTeacup:
            return CatSpot(position: RoomLayout.tableCenter,
                           surfaceHeight: RoomLayout.tableTop,
                           facing: deg(200),
                           needsJump: true)
        case .eat:
            return CatSpot(position: SIMD3<Float>(x: RoomLayout.feederBowl.x - 0.22, y: 0, z: RoomLayout.feederBowl.z),
                           facing: deg(90))
        case .drink:
            return CatSpot(position: SIMD3<Float>(x: RoomLayout.fountainRim.x - 0.22, y: 0, z: RoomLayout.fountainRim.z),
                           facing: deg(90))
        case .litter:
            return CatSpot(position: RoomLayout.litterBoxCenter,
                           surfaceHeight: 0.06,
                           facing: deg(170))
        case .scratchPost:
            return CatSpot(position: RoomLayout.scratchPostSpot, facing: deg(-120))
        case .playMouse:
            return CatSpot(position: RoomLayout.toyMouseSpot, facing: rng.float(-.pi, .pi))
        case .playBall:
            return CatSpot(position: RoomLayout.toyBallSpot, facing: rng.float(-.pi, .pi))
        case .greetPlayer, .receivePets, .followPlayer:
            return CatSpot(position: RoomLayout.playerNearSpot, facing: 0)
        case .sitAndStare:
            return CatSpot(position: RoomLayout.clampToWalkable(
                SIMD3<Float>(x: rng.float(-0.8, 0.8), y: 0, z: rng.float(0.0, 0.7))), facing: 0)
        case .hide:
            return CatSpot(position: SIMD3<Float>(x: RoomLayout.tableCenter.x, y: 0, z: RoomLayout.tableCenter.z),
                           facing: deg(180))
        case .eatTreat:
            return CatSpot(position: RoomLayout.playerLapSpot, facing: 0)
        case .chaseWand, .zoomies, .wander, .groom, .stretch, .knead, .loafFloor:
            return CatSpot(position: RoomLayout.randomFloorPoint(using: &rng), facing: rng.float(-.pi, .pi))
        }
    }
}

enum NeedKey: String, Codable, CaseIterable {
    case fullness, hydration, rest, bladder, social, play, cleanliness, curiosity

    var displayName: String {
        switch self {
        case .fullness: return "Food"
        case .hydration: return "Water"
        case .rest: return "Rest"
        case .bladder: return "Litter"
        case .social: return "Company"
        case .play: return "Play"
        case .cleanliness: return "Grooming"
        case .curiosity: return "Curiosity"
        }
    }

    var symbol: String {
        switch self {
        case .fullness: return "fork.knife"
        case .hydration: return "drop.fill"
        case .rest: return "moon.zzz.fill"
        case .bladder: return "tray.fill"
        case .social: return "heart.fill"
        case .play: return "figure.play"
        case .cleanliness: return "sparkles"
        case .curiosity: return "eye.fill"
        }
    }
}

extension CatNeeds {
    subscript(key: NeedKey) -> Float {
        get {
            switch key {
            case .fullness: return fullness
            case .hydration: return hydration
            case .rest: return rest
            case .bladder: return bladder
            case .social: return social
            case .play: return play
            case .cleanliness: return cleanliness
            case .curiosity: return curiosity
            }
        }
        set {
            let v = clamp(newValue)
            switch key {
            case .fullness: fullness = v
            case .hydration: hydration = v
            case .rest: rest = v
            case .bladder: bladder = v
            case .social: social = v
            case .play: play = v
            case .cleanliness: cleanliness = v
            case .curiosity: curiosity = v
            }
        }
    }
}
