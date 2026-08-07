import Foundation

// MARK: - Enumerations

enum CatBreed: String, Codable, CaseIterable, Identifiable {
    case domesticShorthair, domesticLonghair, maineCoon, siamese, persian, bengal
    case russianBlue, sphynx, ragdoll, scottishFold, abyssinian, norwegianForest
    case bombay, britishShorthair, orientalShorthair, turkishVan, munchkin, calicoMoggy

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .domesticShorthair: return "Domestic Shorthair"
        case .domesticLonghair: return "Domestic Longhair"
        case .maineCoon: return "Maine Coon"
        case .siamese: return "Siamese"
        case .persian: return "Persian"
        case .bengal: return "Bengal"
        case .russianBlue: return "Russian Blue"
        case .sphynx: return "Sphynx"
        case .ragdoll: return "Ragdoll"
        case .scottishFold: return "Scottish Fold"
        case .abyssinian: return "Abyssinian"
        case .norwegianForest: return "Norwegian Forest"
        case .bombay: return "Bombay"
        case .britishShorthair: return "British Shorthair"
        case .orientalShorthair: return "Oriental Shorthair"
        case .turkishVan: return "Turkish Van"
        case .munchkin: return "Munchkin"
        case .calicoMoggy: return "Calico Moggy"
        }
    }

    var blurb: String {
        switch self {
        case .domesticShorthair: return "The everycat. Sturdy, sleek, endlessly variable."
        case .domesticLonghair: return "A soft cloud with opinions."
        case .maineCoon: return "Enormous, shaggy, and improbably gentle."
        case .siamese: return "Slender, vocal, and deeply invested in your business."
        case .persian: return "Flat-faced, luxurious, professionally unbothered."
        case .bengal: return "Rosetted, athletic, and always plotting."
        case .russianBlue: return "Plush blue-grey coat, quiet and watchful."
        case .sphynx: return "Warm suede skin, zero chill, maximum affection."
        case .ragdoll: return "Goes limp when held. Blue eyes, softer heart."
        case .scottishFold: return "Folded ears, round face, sits like a person."
        case .abyssinian: return "Ticked coat that glows. Never stops exploring."
        case .norwegianForest: return "Built for snow. Climbs everything."
        case .bombay: return "A tiny panther with copper eyes."
        case .britishShorthair: return "Round, dense, and dignified."
        case .orientalShorthair: return "All ears and elegance."
        case .turkishVan: return "White with coloured cap and tail. Loves water."
        case .munchkin: return "Short legs, full speed."
        case .calicoMoggy: return "Three colours, three moods."
        }
    }
}

enum CoatPattern: String, Codable, CaseIterable, Identifiable {
    case solid, mackerelTabby, classicTabby, spottedTabby, tickedTabby, rosetted
    case colorpoint, mink, tuxedo, bicolor, vanBicolor, calico, tortoiseshell, torbie
    case smoke, shaded, sable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .solid: return "Solid"
        case .mackerelTabby: return "Mackerel Tabby"
        case .classicTabby: return "Classic Tabby"
        case .spottedTabby: return "Spotted Tabby"
        case .tickedTabby: return "Ticked Tabby"
        case .rosetted: return "Rosetted"
        case .colorpoint: return "Colourpoint"
        case .mink: return "Mink"
        case .tuxedo: return "Tuxedo"
        case .bicolor: return "Bicolour"
        case .vanBicolor: return "Van Bicolour"
        case .calico: return "Calico"
        case .tortoiseshell: return "Tortoiseshell"
        case .torbie: return "Torbie"
        case .smoke: return "Smoke"
        case .shaded: return "Shaded"
        case .sable: return "Sable"
        }
    }
}

enum EyeShape: String, Codable, CaseIterable, Identifiable {
    case almond, round, oval, oriental, hooded
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum PupilShape: String, Codable, CaseIterable, Identifiable {
    case slit, round, oval
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum EarShape: String, Codable, CaseIterable, Identifiable {
    case standard, tall, wide, folded, curled, lynxTipped
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .lynxTipped: return "Lynx Tipped"
        default: return rawValue.capitalized
        }
    }
}

enum TailShape: String, Codable, CaseIterable, Identifiable {
    case long, plumed, bobbed, kinked, curled, whip
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BodyType: String, Codable, CaseIterable, Identifiable {
    case cobby, semiCobby, foreign, oriental, substantial
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .semiCobby: return "Semi-Cobby"
        default: return rawValue.capitalized
        }
    }
}

enum LifeStage: String, Codable, CaseIterable, Identifiable {
    case kitten, adolescent, adult, senior
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    /// Overall body scale multiplier.
    var scale: Float {
        switch self {
        case .kitten: return 0.62
        case .adolescent: return 0.82
        case .adult: return 1.0
        case .senior: return 0.97
        }
    }
}

enum CollarStyle: String, Codable, CaseIterable, Identifiable {
    case none, leather, ribbon, bandana, bell, charm
    var id: String { rawValue }
    var displayName: String { rawValue == "none" ? "None" : rawValue.capitalized }
}

// MARK: - Appearance

/// Every knob the player can turn. All unit-range values are 0...1 unless noted.
struct CatAppearance: Codable, Equatable {

    // Identity
    var breed: CatBreed = .domesticShorthair
    var lifeStage: LifeStage = .adult

    // Coat colours
    var baseCoat: RGBColor = RGBColor(hex: 0x8A6A4A)
    var markingColor: RGBColor = RGBColor(hex: 0x3A2A1E)
    var bellyColor: RGBColor = RGBColor(hex: 0xD9C6AC)
    var pointColor: RGBColor = RGBColor(hex: 0x4A3628)
    var whitePatchColor: RGBColor = RGBColor(hex: 0xF4EFE6)

    // Pattern
    var pattern: CoatPattern = .mackerelTabby
    var patternContrast: Float = 0.75
    var patternScale: Float = 0.5
    var patternIrregularity: Float = 0.4
    var patternCoverage: Float = 0.7
    var whiteSpotting: Float = 0.15      // socks / bib / blaze amount
    var tickingAmount: Float = 0.35      // per-hair banding
    var undercoatLightness: Float = 0.5  // how pale the belly/chest goes

    // Fur
    var furLength: Float = 0.25
    var furFluff: Float = 0.3            // silhouette softening / ruff
    var furDensity: Float = 0.6
    var furGloss: Float = 0.35
    var furCoarseness: Float = 0.4
    var hairless: Bool = false

    // Eyes
    var eyeColor: RGBColor = RGBColor(hex: 0xC8A93A)
    var eyeColorRight: RGBColor = RGBColor(hex: 0xC8A93A)
    var heterochromia: Bool = false
    var eyeShape: EyeShape = .almond
    var pupilShape: PupilShape = .slit
    var eyeSize: Float = 0.5
    var eyeSpacing: Float = 0.5
    var eyeTilt: Float = 0.5
    var eyeBrightness: Float = 0.5
    var scleraTint: Float = 0.2

    // Ears
    var earShape: EarShape = .standard
    var earLength: Float = 0.5
    var earWidth: Float = 0.5
    var earTilt: Float = 0.5
    var earFold: Float = 0.0
    var earTufts: Float = 0.25
    var innerEarColor: RGBColor = RGBColor(hex: 0xE4A9A0)

    // Head
    var headWidth: Float = 0.5
    var headRoundness: Float = 0.5
    var muzzleLength: Float = 0.5
    var muzzleWidth: Float = 0.5
    var cheekFluff: Float = 0.35
    var chinSize: Float = 0.5
    var noseColor: RGBColor = RGBColor(hex: 0xD98F8A)
    var noseSize: Float = 0.5
    var whiskerLength: Float = 0.5
    var whiskerThickness: Float = 0.5
    var whiskerColor: RGBColor = RGBColor(hex: 0xF2ECE2)
    var eyebrowWhiskers: Float = 0.5

    // Body
    var bodyType: BodyType = .semiCobby
    var bodyLength: Float = 0.5
    var bodyGirth: Float = 0.5
    var chestDepth: Float = 0.5
    var chonk: Float = 0.35              // weight
    var shoulderHeight: Float = 0.5
    var neckThickness: Float = 0.5

    // Legs & paws
    var legLength: Float = 0.5
    var legThickness: Float = 0.5
    var pawSize: Float = 0.5
    var toeTufts: Float = 0.25
    var pawPadColor: RGBColor = RGBColor(hex: 0xC98A84)

    // Tail
    var tailShape: TailShape = .long
    var tailLength: Float = 0.55
    var tailThickness: Float = 0.45
    var tailFluff: Float = 0.35
    var tailKink: Float = 0.0
    var tailRingCount: Float = 0.4

    // Accessory
    var collarStyle: CollarStyle = .none
    var collarColor: RGBColor = RGBColor(hex: 0xB03A48)
    var collarHasBell: Bool = true
    var bellColor: RGBColor = RGBColor(hex: 0xE0B441)

    /// Stable seed used for per-cat procedural detail (fur mottling, freckles).
    var seed: UInt64 = 20260807

    // MARK: Derived measurements (metres, adult reference cat ≈ 46 cm body)

    var scale: Float { lifeStage.scale }

    var bodyTypeGirthBias: Float {
        switch bodyType {
        case .cobby: return 0.14
        case .semiCobby: return 0.06
        case .foreign: return -0.02
        case .oriental: return -0.10
        case .substantial: return 0.18
        }
    }

    var bodyTypeLengthBias: Float {
        switch bodyType {
        case .cobby: return -0.10
        case .semiCobby: return -0.02
        case .foreign: return 0.04
        case .oriental: return 0.12
        case .substantial: return 0.08
        }
    }

    /// Half-length of the torso along its spine, metres.
    var torsoLength: Float {
        (0.20 + 0.11 * (bodyLength + bodyTypeLengthBias)) * scale
    }

    var torsoRadius: Float {
        let base = 0.055 + 0.030 * clamp(bodyGirth + bodyTypeGirthBias) + 0.022 * chonk
        return base * scale * (1 + 0.10 * effectiveFurLength)
    }

    var effectiveFurLength: Float { hairless ? 0 : furLength }

    var effectiveFluff: Float { hairless ? 0 : furFluff }

    var legHeight: Float {
        (0.115 + 0.075 * legLength) * scale
    }

    var headRadius: Float {
        (0.043 + 0.014 * headWidth + 0.006 * headRoundness) * scale
    }

    var tailLengthMeters: Float {
        let base: Float
        switch tailShape {
        case .bobbed: base = 0.08
        case .whip: base = 0.30
        default: base = 0.26
        }
        return (base * (0.6 + 0.8 * tailLength)) * scale
    }

    var tailRadius: Float {
        (0.010 + 0.010 * tailThickness) * scale * (1 + 1.4 * tailFluff * (tailShape == .plumed ? 1.6 : 1.0))
    }

    /// Height of the cat's shoulder above the floor when standing.
    var standingHeight: Float { legHeight + torsoRadius }
}
