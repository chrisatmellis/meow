import SwiftUI

enum CreatorTab: String, CaseIterable, Identifiable {
    case breed, coat, pattern, fur, eyes, ears, head, body, tail, extras, personality, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .breed: return "Breed"
        case .coat: return "Colour"
        case .pattern: return "Pattern"
        case .fur: return "Fur"
        case .eyes: return "Eyes"
        case .ears: return "Ears"
        case .head: return "Face"
        case .body: return "Body"
        case .tail: return "Tail"
        case .extras: return "Collar"
        case .personality: return "Personality"
        case .name: return "Name"
        }
    }
}

struct CharacterCreatorView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var preview = CatPreviewController(
        appearance: BreedPresets.appearance(for: .domesticShorthair))

    @State private var appearance = BreedPresets.appearance(for: .domesticShorthair)
    @State private var personality = CatPersonality()
    @State private var archetype: PersonalityArchetype = .balanced
    @State private var name: String = ""
    @State private var tab: CreatorTab = .breed
    @State private var loaded = false

    private var isEditing: Bool { model.controller != nil }

    var body: some View {
        VStack(spacing: 0) {
            previewPane
            tabStrip
            ScrollView {
                VStack(spacing: 14) {
                    content
                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .overlay(alignment: .bottom) { footer }
        .background(
            LinearGradient(colors: [Color(red: 0.07, green: 0.07, blue: 0.09),
                                    Color(red: 0.03, green: 0.03, blue: 0.045)],
                           startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
        )
        .onAppear {
            guard !loaded else { return }
            loaded = true
            appearance = model.save.profile.appearance
            personality = model.save.profile.personality
            archetype = model.save.profile.archetype
            name = model.save.profile.name
            preview.request(appearance: appearance)
        }
    }

    // MARK: - Preview

    private var previewPane: some View {
        ZStack(alignment: .topTrailing) {
            CatPreviewView(appearance: appearance, controller: preview)
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipped()

            HStack(spacing: 8) {
                Button {
                    randomise()
                } label: {
                    Label("Surprise me", systemImage: "dice.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(14)

            VStack {
                Spacer()
                Text("tap the cat to change pose")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 6)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 300)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CreatorTab.allCases) { t in
                    let selected = t == tab
                    Text(t.title)
                        .font(.caption.weight(selected ? .semibold : .regular))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(selected ? Color.accentColor.opacity(0.35)
                                                   : Color.white.opacity(0.07)))
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { tab = t } }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .breed: breedTab
        case .coat: coatTab
        case .pattern: patternTab
        case .fur: furTab
        case .eyes: eyesTab
        case .ears: earsTab
        case .head: headTab
        case .body: bodyTab
        case .tail: tailTab
        case .extras: extrasTab
        case .personality: personalityTab
        case .name: nameTab
        }
    }

    private var breedTab: some View {
        SectionCard(title: "Pick a starting point") {
            Text("A breed sets every slider. Change anything you like afterwards — nothing is locked.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(CatBreed.allCases) { breed in
                    let selected = breed == appearance.breed
                    Button {
                        applyBreed(breed)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(breed.displayName)
                                .font(.caption.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Text(breed.blurb)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.06)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            ChipPicker(title: "Age", options: LifeStage.allCases,
                       label: { $0.displayName }, selection: $appearance.lifeStage)
        }
    }

    private var coatTab: some View {
        VStack(spacing: 14) {
            SectionCard(title: "Coat colours") {
                ColorRow(title: "Base coat", color: $appearance.baseCoat, presets: ColorPalettes.coat)
                ColorRow(title: "Markings", color: $appearance.markingColor, presets: ColorPalettes.coat)
                ColorRow(title: "Belly & chest", color: $appearance.bellyColor, presets: ColorPalettes.coat)
                ColorRow(title: "Points / second colour", color: $appearance.pointColor, presets: ColorPalettes.coat)
                ColorRow(title: "White patches", color: $appearance.whitePatchColor, presets: ColorPalettes.coat)
            }
            SectionCard(title: "Skin") {
                ColorRow(title: "Nose leather", color: $appearance.noseColor, presets: ColorPalettes.skin)
                ColorRow(title: "Paw pads", color: $appearance.pawPadColor, presets: ColorPalettes.skin)
                ColorRow(title: "Inner ears", color: $appearance.innerEarColor, presets: ColorPalettes.skin)
            }
        }
    }

    private var patternTab: some View {
        SectionCard(title: "Pattern") {
            ChipPicker(title: "Style", options: CoatPattern.allCases,
                       label: { $0.displayName }, selection: $appearance.pattern)
            SliderRow(title: "Contrast", value: $appearance.patternContrast,
                      caption: "How boldly the markings read against the base coat")
            SliderRow(title: "Scale", value: $appearance.patternScale,
                      caption: "Fine pinstripes through to broad blotches")
            SliderRow(title: "Irregularity", value: $appearance.patternIrregularity)
            SliderRow(title: "Coverage", value: $appearance.patternCoverage)
            SliderRow(title: "White spotting", value: $appearance.whiteSpotting,
                      caption: "Socks, bib and blaze")
            SliderRow(title: "Ticking", value: $appearance.tickingAmount,
                      caption: "Banding along each individual hair")
            SliderRow(title: "Pale undercoat", value: $appearance.undercoatLightness)
            SliderRow(title: "Tail rings", value: $appearance.tailRingCount)
        }
    }

    private var furTab: some View {
        SectionCard(title: "Fur") {
            Toggle("Hairless", isOn: $appearance.hairless)
                .font(.subheadline)
            SliderRow(title: "Length", value: $appearance.furLength)
            SliderRow(title: "Fluff", value: $appearance.furFluff,
                      caption: "Ruff, britches and general floof")
            SliderRow(title: "Density", value: $appearance.furDensity)
            SliderRow(title: "Gloss", value: $appearance.furGloss)
            SliderRow(title: "Coarseness", value: $appearance.furCoarseness)
            SliderRow(title: "Toe tufts", value: $appearance.toeTufts)
        }
    }

    private var eyesTab: some View {
        VStack(spacing: 14) {
            SectionCard(title: "Eye colour") {
                ColorRow(title: appearance.heterochromia ? "Left eye" : "Both eyes",
                         color: $appearance.eyeColor, presets: ColorPalettes.eyes)
                Toggle("Heterochromia (odd eyes)", isOn: $appearance.heterochromia)
                    .font(.subheadline)
                if appearance.heterochromia {
                    ColorRow(title: "Right eye", color: $appearance.eyeColorRight, presets: ColorPalettes.eyes)
                }
                SliderRow(title: "Brightness", value: $appearance.eyeBrightness,
                          caption: "How much the eyes catch the light")
                SliderRow(title: "Sclera tint", value: $appearance.scleraTint)
            }
            SectionCard(title: "Eye shape") {
                ChipPicker(title: "Shape", options: EyeShape.allCases,
                           label: { $0.displayName }, selection: $appearance.eyeShape)
                ChipPicker(title: "Pupil", options: PupilShape.allCases,
                           label: { $0.displayName }, selection: $appearance.pupilShape)
                SliderRow(title: "Size", value: $appearance.eyeSize)
                SliderRow(title: "Spacing", value: $appearance.eyeSpacing)
                SliderRow(title: "Tilt", value: $appearance.eyeTilt)
            }
        }
    }

    private var earsTab: some View {
        SectionCard(title: "Ears") {
            ChipPicker(title: "Shape", options: EarShape.allCases,
                       label: { $0.displayName }, selection: $appearance.earShape)
            SliderRow(title: "Length", value: $appearance.earLength)
            SliderRow(title: "Width", value: $appearance.earWidth)
            SliderRow(title: "Set / tilt", value: $appearance.earTilt)
            SliderRow(title: "Fold", value: $appearance.earFold,
                      caption: "Scottish-fold style crimp")
            SliderRow(title: "Tufts & furnishings", value: $appearance.earTufts)
        }
    }

    private var headTab: some View {
        VStack(spacing: 14) {
            SectionCard(title: "Head & muzzle") {
                SliderRow(title: "Head width", value: $appearance.headWidth)
                SliderRow(title: "Roundness", value: $appearance.headRoundness)
                SliderRow(title: "Muzzle length", value: $appearance.muzzleLength,
                          caption: "From flat-faced Persian to long Oriental")
                SliderRow(title: "Muzzle width", value: $appearance.muzzleWidth)
                SliderRow(title: "Cheek floof", value: $appearance.cheekFluff)
                SliderRow(title: "Chin", value: $appearance.chinSize)
                SliderRow(title: "Nose size", value: $appearance.noseSize)
            }
            SectionCard(title: "Whiskers") {
                SliderRow(title: "Length", value: $appearance.whiskerLength)
                SliderRow(title: "Thickness", value: $appearance.whiskerThickness)
                SliderRow(title: "Brow whiskers", value: $appearance.eyebrowWhiskers)
                ColorRow(title: "Colour", color: $appearance.whiskerColor,
                         presets: [0xF2ECE2, 0xE0D6C4, 0x9A9080, 0x2A2422])
            }
        }
    }

    private var bodyTab: some View {
        SectionCard(title: "Body") {
            ChipPicker(title: "Build", options: BodyType.allCases,
                       label: { $0.displayName }, selection: $appearance.bodyType)
            SliderRow(title: "Length", value: $appearance.bodyLength)
            SliderRow(title: "Girth", value: $appearance.bodyGirth)
            SliderRow(title: "Chest depth", value: $appearance.chestDepth)
            SliderRow(title: "Weight", value: $appearance.chonk,
                      caption: "Svelte through to magnificently round")
            SliderRow(title: "Neck thickness", value: $appearance.neckThickness)
            SliderRow(title: "Leg length", value: $appearance.legLength)
            SliderRow(title: "Leg thickness", value: $appearance.legThickness)
            SliderRow(title: "Paw size", value: $appearance.pawSize)
        }
    }

    private var tailTab: some View {
        SectionCard(title: "Tail") {
            ChipPicker(title: "Shape", options: TailShape.allCases,
                       label: { $0.displayName }, selection: $appearance.tailShape)
            SliderRow(title: "Length", value: $appearance.tailLength)
            SliderRow(title: "Thickness", value: $appearance.tailThickness)
            SliderRow(title: "Fluff", value: $appearance.tailFluff)
            SliderRow(title: "Kink", value: $appearance.tailKink)
        }
    }

    private var extrasTab: some View {
        SectionCard(title: "Collar") {
            ChipPicker(title: "Style", options: CollarStyle.allCases,
                       label: { $0.displayName }, selection: $appearance.collarStyle)
            if appearance.collarStyle != .none {
                ColorRow(title: "Colour", color: $appearance.collarColor, presets: ColorPalettes.collar)
                Toggle("Bell", isOn: $appearance.collarHasBell)
                    .font(.subheadline)
                if appearance.collarHasBell {
                    ColorRow(title: "Bell colour", color: $appearance.bellColor,
                             presets: [0xE0B441, 0xC0C4CC, 0xB5763C])
                }
            }
        }
    }

    private var personalityTab: some View {
        VStack(spacing: 14) {
            SectionCard(title: "Temperament") {
                Text("Personality drives what your cat chooses to do all day, how readily it comes when called, and how long it tolerates being petted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(PersonalityArchetype.allCases) { a in
                        let selected = a == archetype
                        Button {
                            archetype = a
                            personality = CatPersonality.archetype(a)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(a.displayName).font(.caption.weight(.semibold))
                                Text(a.blurb).font(.caption2).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading).lineLimit(3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            SectionCard(title: "Fine tuning") {
                SliderRow(title: "Playfulness", value: $personality.playfulness)
                SliderRow(title: "Affection", value: $personality.affection)
                SliderRow(title: "Independence", value: $personality.independence)
                SliderRow(title: "Curiosity", value: $personality.curiosity)
                SliderRow(title: "Energy", value: $personality.energy)
                SliderRow(title: "Vocality", value: $personality.vocality,
                          caption: "How much your cat has to say about things")
                SliderRow(title: "Skittishness", value: $personality.skittishness)
            }
            SectionCard(title: "Fine tuning, continued") {
                SliderRow(title: "Appetite", value: $personality.appetite)
                SliderRow(title: "Cuddliness", value: $personality.cuddliness)
                SliderRow(title: "Mischief", value: $personality.mischief)
                SliderRow(title: "Patience", value: $personality.patience,
                          caption: "How long petting lasts before overstimulation")
                SliderRow(title: "Sleepiness", value: $personality.sleepiness)
                SliderRow(title: "Clinginess", value: $personality.clinginess)
                SliderRow(title: "Confidence", value: $personality.confidence)
            }
        }
    }

    private var nameTab: some View {
        SectionCard(title: "Name") {
            TextField("Name your cat", text: $name)
                .textFieldStyle(.roundedBorder)
                .font(.body)
            Text("You can rename later from settings.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Suggestions").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Mochi", "Yuzu", "Kuro", "Sora", "Anzu", "Tofu", "Hoshi", "Mugi", "Nori", "Ponzu"], id: \.self) { n in
                            Text(n)
                                .font(.caption)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Capsule().fill(Color.white.opacity(0.08)))
                                .onTapGesture { name = n }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if let idx = CreatorTab.allCases.firstIndex(of: tab), idx > 0 {
                Button {
                    withAnimation { tab = CreatorTab.allCases[idx - 1] }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 46, height: 46)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            if let idx = CreatorTab.allCases.firstIndex(of: tab), idx < CreatorTab.allCases.count - 1 {
                Button {
                    withAnimation { tab = CreatorTab.allCases[idx + 1] }
                } label: {
                    Text("Next: \(CreatorTab.allCases[idx + 1].title)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button {
                finish()
            } label: {
                Text(isEditing ? "Save" : "Adopt")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: tab == .name ? .infinity : 96)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .allowsHitTesting(false),
            alignment: .bottom
        )
    }

    // MARK: - Actions

    private func applyBreed(_ breed: CatBreed) {
        var next = BreedPresets.appearance(for: breed, seed: appearance.seed)
        next.lifeStage = appearance.lifeStage
        next.collarStyle = appearance.collarStyle
        next.collarColor = appearance.collarColor
        next.collarHasBell = appearance.collarHasBell
        next.bellColor = appearance.bellColor
        appearance = next
        personality = BreedPresets.personality(for: breed)
        archetype = .balanced
    }

    private func randomise() {
        var g = SeededGenerator(seed: UInt64.random(in: 1...UInt64.max))
        let breed = CatBreed.allCases.randomElement() ?? .domesticShorthair
        var a = BreedPresets.appearance(for: breed, seed: UInt64.random(in: 1...UInt64.max))

        a.pattern = CoatPattern.allCases.randomElement() ?? a.pattern
        a.baseCoat = RGBColor(hex: ColorPalettes.coat.randomElement() ?? 0x8C6E4E)
        a.markingColor = RGBColor(hex: ColorPalettes.coat.randomElement() ?? 0x3B2A1D)
        a.eyeColor = RGBColor(hex: ColorPalettes.eyes.randomElement() ?? 0xC8A93A)
        a.heterochromia = g.float() < 0.12
        a.eyeColorRight = a.heterochromia
            ? RGBColor(hex: ColorPalettes.eyes.randomElement() ?? 0x4FA6D6)
            : a.eyeColor
        a.furLength = g.float()
        a.furFluff = g.float()
        a.patternContrast = g.float(0.3, 1)
        a.patternScale = g.float()
        a.whiteSpotting = g.float() < 0.5 ? 0 : g.float(0, 0.8)
        a.earLength = g.float()
        a.earTufts = g.float()
        a.eyeSize = g.float(0.25, 1)
        a.bodyLength = g.float()
        a.bodyGirth = g.float()
        a.chonk = g.float(0, 0.8)
        a.legLength = g.float()
        a.tailLength = g.float(0.2, 1)
        a.tailFluff = g.float()
        a.tailShape = TailShape.allCases.randomElement() ?? .long
        a.eyeShape = EyeShape.allCases.randomElement() ?? .almond
        a.earShape = EarShape.allCases.randomElement() ?? .standard

        appearance = a
        archetype = PersonalityArchetype.allCases.randomElement() ?? .balanced
        personality = CatPersonality.archetype(archetype)
    }

    private func finish() {
        var final = appearance
        if !final.heterochromia { final.eyeColorRight = final.eyeColor }
        if final.hairless { final.furLength = 0; final.furFluff = 0 }
        let chosenName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if isEditing {
            model.applyEdits(appearance: final, personality: personality,
                             archetype: archetype, name: chosenName)
        } else {
            model.finishCreation(appearance: final, personality: personality,
                                 archetype: archetype, name: chosenName)
        }
    }
}
