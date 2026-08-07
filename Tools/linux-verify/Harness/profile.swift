// Behavioural profile: simulates whole days and reports how the cat spends them.
// Run with `meowcheck --profile`.
import Foundation
import SceneKit

func runProfile() {
    let hoursToSim = 24
    let hz: Float = 10

    for archetype in [PersonalityArchetype.balanced, .lapCat, .aloof, .hunter, .chill, .gremlin] {
        var save = GameSave()
        save.profile.appearance = BreedPresets.appearance(for: .domesticShorthair)
        save.profile.personality = CatPersonality.archetype(archetype)
        let brain = CatBrain(save: save)

        var timeIn: [CatActivity: Float] = [:]
        var byHour: [Int: [CatActivity: Float]] = [:]
        var vocalisations = 0
        var byKind: [String: Int] = [:]
        brain.onEvent = { event in
            switch event {
            case .meow: vocalisations += 1; byKind["meow", default: 0] += 1
            case .trill: vocalisations += 1; byKind["trill", default: 0] += 1
            case .chirp: vocalisations += 1; byKind["chirp", default: 0] += 1
            case .yowl: vocalisations += 1; byKind["yowl", default: 0] += 1
            case .hiss: vocalisations += 1; byKind["hiss", default: 0] += 1
            default: break
            }
        }

        // Start at local midnight so the day reads naturally.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 12; comps.hour = 0
        let start = cal.date(from: comps)!

        let steps = Int(Float(hoursToSim) * 3600 * hz)
        var sky = WorldClock.sky(at: start, timeZone: TimeZone(identifier: "UTC")!)
        for step in 0..<steps {
            let elapsed = Double(step) / Double(hz)
            if step % 600 == 0 {
                sky = WorldClock.sky(at: start.addingTimeInterval(elapsed),
                                     timeZone: TimeZone(identifier: "UTC")!)
            }
            brain.update(dt: 1 / hz, sky: sky)
            let hour = Int(elapsed / 3600) % 24
            timeIn[brain.activity, default: 0] += 1 / hz
            byHour[hour, default: [:]][brain.activity, default: 0] += 1 / hz
        }

        let total = Float(hoursToSim) * 3600
        print("\n── \(archetype.displayName) ──────────────────────────────")
        let ranked = timeIn.sorted { $0.value > $1.value }
        for (activity, seconds) in ranked.prefix(10) {
            let pct = seconds / total * 100
            let bar = String(repeating: "█", count: max(1, Int(pct / 2)))
            print(String(format: "  %-16@ %5.1f%%  %@",
                         activity.rawValue as NSString, pct, bar as NSString))
        }
        let sleepPct = ranked.filter { $0.key.isSleeping }.reduce(0) { $0 + $1.value } / total * 100
        let distinct = timeIn.keys.count
        print(String(format: "  asleep %.0f%% · %d distinct activities · %d vocalisations · mood %.2f",
                     sleepPct, distinct, vocalisations, brain.needs.mood))

        let neverDid = Set(CatActivity.allCases).subtracting(timeIn.keys)
            .filter { $0 != .chaseWand && $0 != .receivePets && $0 != .eatTreat }
        print("  voices: " + byKind.sorted { $0.value > $1.value }
                .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        if !neverDid.isEmpty {
            print("  never did: \(neverDid.map(\.rawValue).sorted().joined(separator: ", "))")
        }

        // What is the cat doing at 3am vs 3pm?
        for hour in [3, 9, 15, 21] {
            let top = (byHour[hour] ?? [:]).max { $0.value < $1.value }
            print("   \(String(format: "%02d", hour)):00 → \(top?.key.rawValue ?? "-")")
        }
    }

    // Needs equilibrium over three days: does the cat look after itself?
    print("\n── three-day self-sufficiency ──────────────────────────")
    var save = GameSave()
    save.profile.personality = CatPersonality.archetype(.balanced)
    let brain = CatBrain(save: save)
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    var comps = DateComponents(); comps.year = 2026; comps.month = 5; comps.day = 12
    let start = cal.date(from: comps)!
    var sky = WorldClock.sky(at: start, timeZone: TimeZone(identifier: "UTC")!)
    var worstMood: Float = 1
    for step in 0..<(3 * 24 * 3600 * 10) {
        if step % 600 == 0 {
            sky = WorldClock.sky(at: start.addingTimeInterval(Double(step) / 10),
                                 timeZone: TimeZone(identifier: "UTC")!)
            // The player refills things once a day, as a real owner would.
            if step % (24 * 3600 * 10) == 0 {
                brain.refillFeeder(); brain.refillFountain(); brain.cleanLitter()
            }
        }
        brain.update(dt: 0.1, sky: sky)
        worstMood = min(worstMood, brain.needs.mood)
    }
    print(String(format: "  after 3 days: mood %.2f (worst %.2f), food %.2f, water %.2f, litter %.2f",
                 brain.needs.mood, worstMood, brain.room.feederFood,
                 brain.room.fountainWater, brain.room.litterCleanliness))
    for key in NeedKey.allCases {
        print(String(format: "    %-12@ %.2f", key.rawValue as NSString, brain.needs[key]))
    }

    print("\n── light across the day ────────────────────────────────")
    print("  hour      sun     sky    moon lantern  |    key    EV   screen")
    var dayCal = Calendar(identifier: .gregorian)
    dayCal.timeZone = TimeZone(identifier: "UTC")!
    var lo = Float.infinity, hi = -Float.infinity
    for hour in 0..<24 {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 9; comps.day = 21; comps.hour = hour
        let s = WorldClock.sky(at: dayCal.date(from: comps)!, timeZone: TimeZone(identifier: "UTC")!)
        let b = LightingRig.budget(sky: s, lanternOn: s.wantsLampLight)
        let screen = LightingRig.renderedBrightness(for: b)
        lo = min(lo, screen); hi = max(hi, screen)
        print(String(format: "  %02d:00 %7.0f %7.0f %7.1f %7.0f  | %6.0f %+5.2f %8.0f",
                     hour, b.sun, b.sky, b.moon, b.lantern,
                     b.key, Float(LightingRig.exposureOffset(for: b)), screen))
    }
    print(String(format: "  screen brightness spans %.2f stops across the day", log2(hi / lo)))
}
