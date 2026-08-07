import Foundation
import UserNotifications

/// The app can't run in the background, so when it goes away we project the cat's
/// needs forward and schedule the moments worth interrupting the player for.
enum NotificationScheduler {

    private static let categoryID = "meow.cat"

    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    static func authorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    /// Rebuilds the whole schedule. Call on backgrounding.
    static func reschedule(save: GameSave) {
        cancelAll()
        guard save.notificationsEnabled else { return }

        let center = UNUserNotificationCenter.current()
        let name = save.profile.name
        let p = save.profile.personality
        var planned: [(delay: TimeInterval, title: String, body: String)] = []

        // --- Need-driven alerts: when will each need cross its nag threshold?
        func hoursUntil(_ current: Float, threshold: Float, ratePerHour: Float) -> Float? {
            guard ratePerHour > 0.0001, current > threshold else { return current <= threshold ? 0.35 : nil }
            return (current - threshold) / ratePerHour
        }

        let needs = save.needs
        let candidates: [(Float?, String, String)] = [
            (hoursUntil(needs.social, threshold: 0.28,
                        ratePerHour: CatNeeds.DrainRates.social * p.socialDrain),
             "\(name) misses you",
             "The room is quiet. \(name) keeps looking at the door."),

            (hoursUntil(needs.play, threshold: 0.25,
                        ratePerHour: CatNeeds.DrainRates.play * p.playDrain),
             "\(name) wants to play",
             "The wand toy has been located and is being stared at."),

            (hoursUntil(needs.fullness, threshold: 0.30,
                        ratePerHour: CatNeeds.DrainRates.fullness * p.hungerDrain),
             "\(name) is eating",
             save.room.feederFood > 0.2
                ? "The feeder just went off. Crunching commences."
                : "The feeder is empty and \(name) has noticed."),

            (hoursUntil(needs.hydration, threshold: 0.30,
                        ratePerHour: CatNeeds.DrainRates.hydration * (0.8 + 0.5 * p.appetite)),
             "\(name) is at the fountain",
             "Drinking with great ceremony, as always."),

            (hoursUntil(needs.rest, threshold: 0.30,
                        ratePerHour: CatNeeds.DrainRates.rest * (0.5 + 1.1 * p.energy)),
             "\(name) found a sun patch",
             "Fully asleep. Devastatingly cute. You are missing it."),

            (hoursUntil(needs.bladder, threshold: 0.22,
                        ratePerHour: CatNeeds.DrainRates.bladder * (0.7 + 0.7 * p.appetite)),
             "Litter box duty",
             "\(name) has made a deposit. The box could use a scoop."),
        ]

        for (hours, title, body) in candidates {
            guard let h = hours, h.isFinite else { continue }
            let delay = TimeInterval(max(0.35, h) * 3600)
            if delay < 60 * 20 { continue }        // don't nag the moment they leave
            if delay > 60 * 60 * 24 * 7 { continue }
            planned.append((delay, title, body))
        }

        // --- Consumables.
        if save.room.feederFood < 0.25 {
            planned.append((60 * 90, "The feeder is low", "\(name) will run out of kibble soon."))
        }
        if save.room.fountainWater < 0.25 {
            planned.append((60 * 100, "The fountain is low", "Time for a refill."))
        }

        // --- A couple of flavour pings so opening the app is rewarded.
        let flavour: [(TimeInterval, String, String)] = [
            (60 * 60 * 5, "\(name) did something", "It involved the teacup. That is all we can say."),
            (60 * 60 * 11, "Zoomies detected", "\(name) is doing laps of the tatami at speed."),
            (60 * 60 * 26, "\(name) is on the window sill", "Chirping at something in the garden."),
        ]
        planned.append(contentsOf: flavour.map { (delay: $0.0, title: $0.1, body: $0.2) })

        // Keep the schedule tidy: soonest first, at most 12, spaced at least 45 minutes apart.
        planned.sort { $0.delay < $1.delay }
        var lastDelay: TimeInterval = -.infinity
        var count = 0
        for item in planned {
            guard count < 12 else { break }
            var delay = item.delay
            if delay - lastDelay < 60 * 45 { delay = lastDelay + 60 * 45 }
            guard delay > 60 else { continue }
            lastDelay = delay
            count += 1

            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            content.categoryIdentifier = categoryID

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(identifier: "meow-\(count)-\(Int(delay))",
                                                content: content, trigger: trigger)
            center.add(request, withCompletionHandler: nil)
        }
    }
}
