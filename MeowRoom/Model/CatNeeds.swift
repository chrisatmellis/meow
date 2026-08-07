import Foundation

/// All values are *satisfaction* levels: 1 = fully satisfied, 0 = desperate.
struct CatNeeds: Codable, Equatable {
    var fullness: Float = 0.75      // food
    var hydration: Float = 0.8      // water
    var rest: Float = 0.7           // energy
    var bladder: Float = 0.85       // 0 = needs the litter box urgently
    var social: Float = 0.6         // attention from the player
    var play: Float = 0.6           // stimulation from toys
    var cleanliness: Float = 0.8    // grooming
    var curiosity: Float = 0.6      // wants to look at the window / explore

    /// Base drain per hour for each need, before personality scaling.
    struct DrainRates {
        static let fullness: Float = 0.115
        static let hydration: Float = 0.135
        static let rest: Float = 0.135
        static let bladder: Float = 0.095
        static let social: Float = 0.155
        static let play: Float = 0.175
        static let cleanliness: Float = 0.070
        static let curiosity: Float = 0.145
    }

    mutating func decay(hours: Float, personality p: CatPersonality, awakeFactor: Float) {
        func d(_ v: inout Float, _ rate: Float, _ mult: Float) {
            v = clamp(v - rate * hours * mult)
        }
        d(&fullness, DrainRates.fullness, p.hungerDrain)
        d(&hydration, DrainRates.hydration, 0.8 + 0.5 * p.appetite)
        d(&rest, DrainRates.rest, (0.35 + 0.65 * p.energy + 1.0 * p.sleepiness) * awakeFactor)
        d(&bladder, DrainRates.bladder, 0.7 + 0.7 * p.appetite)
        d(&social, DrainRates.social, p.socialDrain)
        d(&play, DrainRates.play, p.playDrain)
        d(&cleanliness, DrainRates.cleanliness, 0.7 + 0.8 * (1 - p.independence))
        d(&curiosity, DrainRates.curiosity, 0.6 + 1.0 * p.curiosity)
    }

    var lowest: (name: String, value: Float) {
        let all: [(String, Float)] = [
            ("hungry", fullness), ("thirsty", hydration), ("sleepy", rest),
            ("restless", bladder), ("lonely", social), ("bored", play),
            ("scruffy", cleanliness), ("curious", curiosity)
        ]
        guard let worst = all.min(by: { $0.1 < $1.1 }) else { return (name: "fine", value: 1) }
        return (name: worst.0, value: worst.1)
    }

    /// Overall wellbeing shown in the HUD.
    var mood: Float {
        let vals = [fullness, hydration, rest, bladder, social, play, cleanliness, curiosity]
        let mean = vals.reduce(0, +) / Float(vals.count)
        let worst = vals.min() ?? 1
        return clamp(mean * 0.6 + worst * 0.4)
    }

    var moodLabel: String {
        let m = mood
        switch m {
        case ..<0.25: return "Miserable"
        case ..<0.45: return "Grumpy"
        case ..<0.62: return "Okay"
        case ..<0.80: return "Content"
        default: return "Blissful"
        }
    }
}
