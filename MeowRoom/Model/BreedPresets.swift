import Foundation

/// Breed presets are a *starting point*: they seed every slider, and the player is
/// free to move any of them afterwards.
enum BreedPresets {

    static func appearance(for breed: CatBreed, seed: UInt64 = 20260807) -> CatAppearance {
        var a = CatAppearance()
        a.breed = breed
        a.seed = seed

        switch breed {
        case .domesticShorthair:
            a.baseCoat = RGBColor(hex: 0x8C6E4E)
            a.markingColor = RGBColor(hex: 0x3B2A1D)
            a.bellyColor = RGBColor(hex: 0xD6C3A6)
            a.pattern = .mackerelTabby
            a.furLength = 0.20; a.furFluff = 0.22; a.furGloss = 0.40
            a.bodyType = .semiCobby
            a.eyeColor = RGBColor(hex: 0xB9A03A)

        case .domesticLonghair:
            a.baseCoat = RGBColor(hex: 0x6E5B48)
            a.markingColor = RGBColor(hex: 0x2E2318)
            a.bellyColor = RGBColor(hex: 0xE3D5BE)
            a.pattern = .classicTabby
            a.furLength = 0.72; a.furFluff = 0.70; a.tailFluff = 0.70; a.cheekFluff = 0.6
            a.earTufts = 0.5; a.toeTufts = 0.5
            a.bodyType = .semiCobby
            a.eyeColor = RGBColor(hex: 0x8FA34A)

        case .maineCoon:
            a.baseCoat = RGBColor(hex: 0x7A6046)
            a.markingColor = RGBColor(hex: 0x2C2016)
            a.bellyColor = RGBColor(hex: 0xE6D9C2)
            a.pattern = .classicTabby
            a.furLength = 0.85; a.furFluff = 0.80; a.furCoarseness = 0.6
            a.tailShape = .plumed; a.tailFluff = 0.85; a.tailLength = 0.75
            a.earShape = .lynxTipped; a.earTufts = 0.85; a.earLength = 0.68
            a.cheekFluff = 0.75; a.toeTufts = 0.7
            a.bodyType = .substantial; a.bodyLength = 0.80; a.bodyGirth = 0.70
            a.legLength = 0.6; a.legThickness = 0.65; a.pawSize = 0.72
            a.eyeColor = RGBColor(hex: 0x9C8B2E)
            a.headWidth = 0.62; a.muzzleLength = 0.6

        case .siamese:
            a.baseCoat = RGBColor(hex: 0xE7DCC6)
            a.pointColor = RGBColor(hex: 0x4A3126)
            a.markingColor = RGBColor(hex: 0x4A3126)
            a.bellyColor = RGBColor(hex: 0xF2E9D6)
            a.pattern = .colorpoint
            a.furLength = 0.12; a.furFluff = 0.10; a.furGloss = 0.65
            a.bodyType = .oriental; a.bodyLength = 0.72; a.bodyGirth = 0.28
            a.legLength = 0.70; a.legThickness = 0.30
            a.earShape = .tall; a.earLength = 0.78; a.earWidth = 0.60
            a.eyeShape = .oriental; a.eyeTilt = 0.75
            a.eyeColor = RGBColor(hex: 0x4FA6D6); a.eyeColorRight = RGBColor(hex: 0x4FA6D6)
            a.muzzleLength = 0.70; a.headWidth = 0.34; a.headRoundness = 0.25
            a.tailShape = .whip; a.tailLength = 0.80; a.tailThickness = 0.25
            a.noseColor = RGBColor(hex: 0x5B4136); a.pawPadColor = RGBColor(hex: 0x5B4136)

        case .persian:
            a.baseCoat = RGBColor(hex: 0xE2D3B8)
            a.markingColor = RGBColor(hex: 0xBCA684)
            a.bellyColor = RGBColor(hex: 0xF0E7D5)
            a.pattern = .shaded
            a.furLength = 0.95; a.furFluff = 0.92; a.furDensity = 0.85; a.furCoarseness = 0.15
            a.cheekFluff = 0.85; a.tailFluff = 0.85; a.tailShape = .plumed; a.tailLength = 0.42
            a.bodyType = .cobby; a.bodyLength = 0.35; a.bodyGirth = 0.72
            a.legLength = 0.28; a.legThickness = 0.60
            a.muzzleLength = 0.06; a.muzzleWidth = 0.70; a.headWidth = 0.72; a.headRoundness = 0.90
            a.earShape = .wide; a.earLength = 0.22; a.earWidth = 0.55
            a.eyeShape = .round; a.eyeSize = 0.72
            a.eyeColor = RGBColor(hex: 0xC97E2E)
            a.noseColor = RGBColor(hex: 0xC98B84)

        case .bengal:
            a.baseCoat = RGBColor(hex: 0xC08B45)
            a.markingColor = RGBColor(hex: 0x2B1E12)
            a.bellyColor = RGBColor(hex: 0xEBD6B2)
            a.pattern = .rosetted
            a.patternContrast = 0.92; a.patternScale = 0.62
            a.furLength = 0.10; a.furGloss = 0.85; a.furDensity = 0.7
            a.bodyType = .foreign; a.bodyLength = 0.70; a.bodyGirth = 0.48
            a.legLength = 0.66; a.legThickness = 0.55
            a.eyeColor = RGBColor(hex: 0x5FA24A)
            a.tailRingCount = 0.7
            a.muzzleLength = 0.58

        case .russianBlue:
            a.baseCoat = RGBColor(hex: 0x76808C)
            a.markingColor = RGBColor(hex: 0x5E6874)
            a.bellyColor = RGBColor(hex: 0x8F98A3)
            a.pattern = .solid
            a.furLength = 0.34; a.furDensity = 0.95; a.furGloss = 0.55; a.furFluff = 0.42
            a.bodyType = .foreign; a.bodyLength = 0.60; a.bodyGirth = 0.40
            a.legLength = 0.62
            a.eyeColor = RGBColor(hex: 0x63A05C); a.eyeShape = .oval
            a.noseColor = RGBColor(hex: 0x6E6068); a.pawPadColor = RGBColor(hex: 0x8A6C74)
            a.earShape = .tall; a.earLength = 0.65

        case .sphynx:
            a.baseCoat = RGBColor(hex: 0xD6A891)
            a.markingColor = RGBColor(hex: 0xB98A74)
            a.bellyColor = RGBColor(hex: 0xE0B9A4)
            a.pattern = .solid
            a.hairless = true
            a.furLength = 0; a.furFluff = 0; a.furGloss = 0.25; a.whiskerLength = 0.08
            a.bodyType = .foreign; a.bodyLength = 0.62; a.bodyGirth = 0.42
            a.earShape = .wide; a.earLength = 0.85; a.earWidth = 0.85; a.earTufts = 0
            a.eyeShape = .oriental; a.eyeSize = 0.62
            a.eyeColor = RGBColor(hex: 0xB78A3E)
            a.tailShape = .whip; a.tailFluff = 0; a.tailThickness = 0.22
            a.legLength = 0.62; a.toeTufts = 0

        case .ragdoll:
            a.baseCoat = RGBColor(hex: 0xEDE2CE)
            a.pointColor = RGBColor(hex: 0x6B5346)
            a.markingColor = RGBColor(hex: 0x6B5346)
            a.bellyColor = RGBColor(hex: 0xF6EFE2)
            a.pattern = .colorpoint
            a.whiteSpotting = 0.35
            a.furLength = 0.70; a.furFluff = 0.72; a.furDensity = 0.6
            a.tailShape = .plumed; a.tailFluff = 0.75; a.tailLength = 0.7
            a.bodyType = .substantial; a.bodyLength = 0.72; a.bodyGirth = 0.62
            a.eyeShape = .oval; a.eyeSize = 0.62
            a.eyeColor = RGBColor(hex: 0x5C9AD6); a.eyeColorRight = RGBColor(hex: 0x5C9AD6)
            a.cheekFluff = 0.6
            a.noseColor = RGBColor(hex: 0xC79A90)

        case .scottishFold:
            a.baseCoat = RGBColor(hex: 0x9A9AA0)
            a.markingColor = RGBColor(hex: 0x6C6C74)
            a.bellyColor = RGBColor(hex: 0xC2C2C8)
            a.pattern = .classicTabby
            a.patternContrast = 0.45
            a.earShape = .folded; a.earFold = 0.85; a.earLength = 0.28; a.earWidth = 0.55
            a.headRoundness = 0.85; a.headWidth = 0.66; a.muzzleLength = 0.32
            a.eyeShape = .round; a.eyeSize = 0.70
            a.bodyType = .cobby; a.bodyGirth = 0.62; a.legLength = 0.38
            a.furLength = 0.32
            a.eyeColor = RGBColor(hex: 0xC08A34)

        case .abyssinian:
            a.baseCoat = RGBColor(hex: 0xB07A44)
            a.markingColor = RGBColor(hex: 0x53381F)
            a.bellyColor = RGBColor(hex: 0xD6A26A)
            a.pattern = .tickedTabby
            a.tickingAmount = 0.9; a.patternContrast = 0.55
            a.furLength = 0.12; a.furGloss = 0.75
            a.bodyType = .foreign; a.bodyLength = 0.66; a.bodyGirth = 0.36
            a.legLength = 0.72; a.legThickness = 0.32
            a.earShape = .tall; a.earLength = 0.82; a.earWidth = 0.7
            a.eyeShape = .almond; a.eyeTilt = 0.6
            a.eyeColor = RGBColor(hex: 0xA8802A)
            a.tailShape = .whip; a.tailLength = 0.72

        case .norwegianForest:
            a.baseCoat = RGBColor(hex: 0x8B7358)
            a.markingColor = RGBColor(hex: 0x33261A)
            a.bellyColor = RGBColor(hex: 0xEFE4CC)
            a.pattern = .mackerelTabby
            a.whiteSpotting = 0.30
            a.furLength = 0.88; a.furFluff = 0.82; a.furCoarseness = 0.7; a.furDensity = 0.85
            a.cheekFluff = 0.8; a.earTufts = 0.75; a.toeTufts = 0.7
            a.tailShape = .plumed; a.tailFluff = 0.88; a.tailLength = 0.78
            a.bodyType = .substantial; a.bodyLength = 0.72; a.bodyGirth = 0.66
            a.legLength = 0.66; a.legThickness = 0.62; a.pawSize = 0.68
            a.eyeColor = RGBColor(hex: 0x76A24A)

        case .bombay:
            a.baseCoat = RGBColor(hex: 0x14100F)
            a.markingColor = RGBColor(hex: 0x0C0909)
            a.bellyColor = RGBColor(hex: 0x1A1514)
            a.pointColor = RGBColor(hex: 0x0C0909)
            a.pattern = .solid
            a.furLength = 0.10; a.furGloss = 0.92; a.furDensity = 0.8
            a.bodyType = .semiCobby; a.bodyGirth = 0.55
            a.eyeColor = RGBColor(hex: 0xD08A1E); a.eyeColorRight = RGBColor(hex: 0xD08A1E)
            a.eyeShape = .round; a.eyeSize = 0.62; a.eyeBrightness = 0.7
            a.noseColor = RGBColor(hex: 0x1A1414); a.pawPadColor = RGBColor(hex: 0x1A1414)
            a.whiskerColor = RGBColor(hex: 0x2A2422)

        case .britishShorthair:
            a.baseCoat = RGBColor(hex: 0x8792A0)
            a.markingColor = RGBColor(hex: 0x6C7683)
            a.bellyColor = RGBColor(hex: 0x9DA7B3)
            a.pattern = .solid
            a.furLength = 0.38; a.furDensity = 0.95; a.furFluff = 0.5; a.furCoarseness = 0.35
            a.bodyType = .cobby; a.bodyGirth = 0.78; a.bodyLength = 0.42; a.chonk = 0.55
            a.legLength = 0.34; a.legThickness = 0.68; a.pawSize = 0.62
            a.headRoundness = 0.88; a.headWidth = 0.78; a.cheekFluff = 0.7; a.muzzleLength = 0.28
            a.earShape = .wide; a.earLength = 0.26
            a.eyeShape = .round; a.eyeSize = 0.72
            a.eyeColor = RGBColor(hex: 0xC97F26)
            a.tailLength = 0.42; a.tailThickness = 0.65

        case .orientalShorthair:
            a.baseCoat = RGBColor(hex: 0x2E2A2A)
            a.markingColor = RGBColor(hex: 0x1C1919)
            a.bellyColor = RGBColor(hex: 0x3A3535)
            a.pattern = .solid
            a.furLength = 0.08; a.furGloss = 0.8
            a.bodyType = .oriental; a.bodyLength = 0.82; a.bodyGirth = 0.20
            a.legLength = 0.82; a.legThickness = 0.22
            a.earShape = .tall; a.earLength = 0.95; a.earWidth = 0.90
            a.eyeShape = .oriental; a.eyeTilt = 0.85
            a.eyeColor = RGBColor(hex: 0x74B24A)
            a.muzzleLength = 0.82; a.headWidth = 0.24; a.headRoundness = 0.15
            a.tailShape = .whip; a.tailLength = 0.9; a.tailThickness = 0.18

        case .turkishVan:
            a.baseCoat = RGBColor(hex: 0xF3EDE1)
            a.markingColor = RGBColor(hex: 0xC06A3C)
            a.pointColor = RGBColor(hex: 0xC06A3C)
            a.bellyColor = RGBColor(hex: 0xF8F4EA)
            a.pattern = .vanBicolor
            a.whiteSpotting = 0.85
            a.furLength = 0.6; a.furFluff = 0.6
            a.tailShape = .plumed; a.tailFluff = 0.7; a.tailLength = 0.7
            a.bodyType = .foreign; a.bodyLength = 0.7; a.legLength = 0.65
            a.eyeColor = RGBColor(hex: 0xB79A2E); a.eyeColorRight = RGBColor(hex: 0x63A8D4)
            a.heterochromia = true
            a.noseColor = RGBColor(hex: 0xE0A79E)

        case .munchkin:
            a.baseCoat = RGBColor(hex: 0xA48A6A)
            a.markingColor = RGBColor(hex: 0x4A3423)
            a.bellyColor = RGBColor(hex: 0xE0CFB4)
            a.pattern = .spottedTabby
            a.legLength = 0.06; a.legThickness = 0.55
            a.bodyType = .semiCobby; a.bodyLength = 0.6; a.bodyGirth = 0.55
            a.furLength = 0.35; a.furFluff = 0.35
            a.eyeShape = .round; a.eyeSize = 0.65
            a.eyeColor = RGBColor(hex: 0xB99A34)

        case .calicoMoggy:
            a.baseCoat = RGBColor(hex: 0xF2ECE0)
            a.markingColor = RGBColor(hex: 0x2A2018)
            a.pointColor = RGBColor(hex: 0xC0762F)
            a.bellyColor = RGBColor(hex: 0xF8F4EA)
            a.pattern = .calico
            a.whiteSpotting = 0.55; a.patternIrregularity = 0.85; a.patternContrast = 0.9
            a.furLength = 0.30; a.furFluff = 0.35
            a.bodyType = .semiCobby
            a.eyeColor = RGBColor(hex: 0xB08A2E)
            a.noseColor = RGBColor(hex: 0xE0A79E)
        }

        if !a.heterochromia {
            a.eyeColorRight = a.eyeColor
        }
        return a
    }

    static func personality(for breed: CatBreed) -> CatPersonality {
        var p = CatPersonality()
        switch breed {
        case .siamese, .orientalShorthair:
            p.vocality = 0.95; p.affection = 0.8; p.independence = 0.2
            p.curiosity = 0.85; p.energy = 0.75; p.clinginess = 0.8
        case .maineCoon, .norwegianForest, .ragdoll:
            p.affection = 0.85; p.patience = 0.85; p.skittishness = 0.2
            p.energy = 0.45; p.cuddliness = 0.9; p.vocality = 0.35
        case .bengal, .abyssinian:
            p.energy = 0.95; p.playfulness = 0.95; p.mischief = 0.85
            p.curiosity = 0.95; p.independence = 0.6; p.sleepiness = 0.25
        case .persian, .britishShorthair:
            p.energy = 0.25; p.sleepiness = 0.8; p.playfulness = 0.3
            p.patience = 0.4; p.independence = 0.6; p.cuddliness = 0.5
        case .russianBlue, .scottishFold:
            p.skittishness = 0.6; p.vocality = 0.2; p.affection = 0.6
            p.independence = 0.55
        case .sphynx, .bombay:
            p.affection = 0.95; p.clinginess = 0.9; p.independence = 0.1
            p.vocality = 0.6; p.cuddliness = 0.95
        default:
            break
        }
        return p
    }
}
