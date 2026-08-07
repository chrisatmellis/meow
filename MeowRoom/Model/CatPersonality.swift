import Foundation

/// Behavioural weights. Everything is 0...1 and every trait is player-editable.
struct CatPersonality: Codable, Equatable {
    var playfulness: Float = 0.6
    var affection: Float = 0.6
    var independence: Float = 0.45
    var curiosity: Float = 0.6
    var energy: Float = 0.55
    var vocality: Float = 0.45
    var skittishness: Float = 0.35
    var appetite: Float = 0.5
    var cuddliness: Float = 0.6
    var mischief: Float = 0.45
    var patience: Float = 0.55      // how long petting is tolerated
    var sleepiness: Float = 0.55
    var clinginess: Float = 0.45
    var confidence: Float = 0.55

    /// Seconds of continuous petting before the cat becomes overstimulated.
    var overstimulationSeconds: Float { 3.0 + 12.0 * patience + 4.0 * cuddliness }

    /// How likely the cat is to come when called, 0...1.
    var recallChance: Float {
        clamp(0.20 + 0.55 * affection + 0.30 * clinginess - 0.40 * independence - 0.20 * skittishness)
    }

    /// Multiplier applied to how quickly the play need drains.
    var playDrain: Float { 0.5 + 1.4 * playfulness * (0.4 + 0.9 * energy) }

    var sleepDrain: Float { 0.6 + 1.0 * (1 - energy) + 0.6 * sleepiness }

    var hungerDrain: Float { 0.6 + 0.9 * appetite }

    var socialDrain: Float { 0.4 + 1.3 * clinginess + 0.6 * affection - 0.5 * independence }

    /// Chance per vocal opportunity that the cat actually says something.
    var chattiness: Float { clamp(0.12 + 0.8 * vocality) }

    static func archetype(_ a: PersonalityArchetype) -> CatPersonality {
        var p = CatPersonality()
        switch a {
        case .lapCat:
            p.affection = 0.95; p.cuddliness = 0.95; p.clinginess = 0.8
            p.patience = 0.9; p.independence = 0.15; p.energy = 0.35; p.sleepiness = 0.7
        case .velcro:
            p.clinginess = 1.0; p.affection = 0.9; p.vocality = 0.8
            p.independence = 0.05; p.skittishness = 0.25; p.energy = 0.55
        case .aloof:
            p.independence = 0.95; p.affection = 0.3; p.clinginess = 0.1
            p.patience = 0.3; p.vocality = 0.2; p.confidence = 0.8
        case .hunter:
            p.playfulness = 0.95; p.energy = 0.9; p.curiosity = 0.9
            p.mischief = 0.7; p.sleepiness = 0.3; p.appetite = 0.7
        case .goofball:
            p.playfulness = 0.9; p.mischief = 0.95; p.curiosity = 0.85
            p.confidence = 0.8; p.energy = 0.8; p.patience = 0.6
        case .scaredy:
            p.skittishness = 0.95; p.confidence = 0.1; p.independence = 0.6
            p.affection = 0.5; p.patience = 0.25; p.vocality = 0.3
        case .chill:
            p.energy = 0.25; p.sleepiness = 0.9; p.patience = 0.85
            p.playfulness = 0.35; p.skittishness = 0.15; p.affection = 0.65
        case .gremlin:
            p.mischief = 1.0; p.energy = 0.95; p.playfulness = 0.85
            p.patience = 0.2; p.vocality = 0.7; p.appetite = 0.85; p.sleepiness = 0.25
        case .balanced:
            break
        }
        return p
    }
}

enum PersonalityArchetype: String, CaseIterable, Identifiable, Codable {
    case balanced, lapCat, velcro, aloof, hunter, goofball, scaredy, chill, gremlin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .lapCat: return "Lap Cat"
        case .velcro: return "Velcro Cat"
        case .aloof: return "Aloof"
        case .hunter: return "Hunter"
        case .goofball: return "Goofball"
        case .scaredy: return "Scaredy Cat"
        case .chill: return "Chill"
        case .gremlin: return "Chaos Gremlin"
        }
    }

    var blurb: String {
        switch self {
        case .balanced: return "A bit of everything."
        case .lapCat: return "Will find you. Will sit on you."
        case .velcro: return "Follows you into every room, including this one."
        case .aloof: return "Loves you. Refuses to prove it."
        case .hunter: return "The wand toy is prey and prey must die."
        case .goofball: return "Falls off things on purpose."
        case .scaredy: return "Startles at the fountain. Every time."
        case .chill: return "Sleeps 19 hours. Regrets nothing."
        case .gremlin: return "Knocks the teacup off the table at 3am."
        }
    }
}
