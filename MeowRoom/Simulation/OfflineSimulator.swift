import Foundation

/// Fast-forwards the cat while the app is closed so re-opening it feels like
/// walking back into a room that kept living without you.
enum OfflineSimulator {

    struct Result {
        var needs: CatNeeds
        var room: RoomState
        var log: [String]
        var elapsedHours: Float
    }

    static func catchUp(save: GameSave, now: Date = Date()) -> Result {
        let elapsed = Float(max(0, now.timeIntervalSince(save.lastSeen)))
        let hours = min(elapsed / 3600, 72)     // cap so a month away isn't fatal
        var needs = save.needs
        var room = save.room
        var log: [String] = []

        guard hours > 0.05 else {
            return Result(needs: needs, room: room, log: [], elapsedHours: hours)
        }

        let p = save.profile.personality
        var rng = SeededGenerator(seed: save.profile.appearance.seed &+ UInt64(now.timeIntervalSince1970 / 60))

        // Step in 15-minute slices so the cat can "take care of itself" along the way.
        let stepHours: Float = 0.25
        var t: Float = 0
        var slept: Float = 0
        var meals = 0
        var drinks = 0
        var litterTrips = 0
        var plays = 0

        while t < hours {
            let sliceDate = save.lastSeen.addingTimeInterval(TimeInterval((t) * 3600))
            let sky = WorldClock.sky(at: sliceDate)
            let asleep = shouldSleep(sky: sky, needs: needs, personality: p, rng: &rng)

            needs.decay(hours: stepHours, personality: p, awakeFactor: asleep ? 0.35 : 1.0)

            if asleep {
                needs.rest = clamp(needs.rest + 0.22 * stepHours)
                slept += stepHours
            } else {
                // Autonomous self-care.
                if needs.fullness < 0.45 && room.feederFood > 0.02 {
                    needs.fullness = clamp(needs.fullness + 0.55)
                    room.feederFood = clamp(room.feederFood - 0.065)
                    meals += 1
                }
                if needs.hydration < 0.5 && room.fountainWater > 0.02 {
                    needs.hydration = clamp(needs.hydration + 0.6)
                    room.fountainWater = clamp(room.fountainWater - 0.02)
                    drinks += 1
                }
                if needs.bladder < 0.3 {
                    needs.bladder = 1
                    room.litterCleanliness = clamp(room.litterCleanliness - 0.14)
                    litterTrips += 1
                }
                if needs.cleanliness < 0.6 {
                    needs.cleanliness = clamp(needs.cleanliness + 0.25)
                }
                if needs.play < 0.4 && rng.float() < 0.35 * p.playfulness {
                    needs.play = clamp(needs.play + 0.18)
                    plays += 1
                }
                if needs.curiosity < 0.4 && sky.daylight > 0.3 {
                    needs.curiosity = clamp(needs.curiosity + 0.22)
                }
            }
            t += stepHours
        }

        // Build the "while you were away" summary.
        if hours >= 0.5 {
            log.append("You were away for \(formatDuration(hours)).")
        }
        if slept > 0.5 { log.append("\(save.profile.name) slept for about \(formatDuration(slept)).") }
        if meals > 0 { log.append("Ate \(meals) time\(meals == 1 ? "" : "s") from the feeder.") }
        if drinks > 0 { log.append("Drank from the fountain \(drinks) time\(drinks == 1 ? "" : "s").") }
        if litterTrips > 0 { log.append("Used the litter box \(litterTrips) time\(litterTrips == 1 ? "" : "s").") }
        if plays > 0 { log.append("Found the toys and played on their own.") }
        if room.feederFood < 0.15 { log.append("The feeder is nearly empty.") }
        if room.fountainWater < 0.15 { log.append("The fountain is running low.") }
        if room.litterCleanliness < 0.35 { log.append("The litter box could use a scoop.") }
        if needs.social < 0.3 { log.append("\(save.profile.name) missed you.") }

        return Result(needs: needs, room: room, log: log, elapsedHours: hours)
    }

    private static func shouldSleep(sky: SkyState, needs: CatNeeds, personality: CatPersonality, rng: inout SeededGenerator) -> Bool {
        let hour = sky.localHour
        let dawnPeak = expf(-powf((hour - 6.0) / 2.2, 2))
        let duskPeak = expf(-powf((hour - 19.5) / 2.4, 2))
        let awakeDrive = clamp(dawnPeak + duskPeak) * (0.4 + personality.energy)
        let sleepDrive = (1 - needs.rest) * 1.4 + personality.sleepiness * 0.6
        return rng.float() < clamp(sleepDrive - awakeDrive + 0.28)
    }

    private static func formatDuration(_ hours: Float) -> String {
        if hours < 1 { return "\(Int(hours * 60)) minutes" }
        if hours < 2 { return "an hour" }
        if hours < 24 { return "\(Int(hours.rounded())) hours" }
        let days = Int((hours / 24).rounded())
        return "\(days) day\(days == 1 ? "" : "s")"
    }
}
