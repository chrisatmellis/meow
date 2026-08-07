import Foundation
import SwiftUI

enum AppScreen {
    case creator
    case game
}

/// Top-level state: owns the save file and the live scene controller.
final class AppModel: ObservableObject {

    @Published var screen: AppScreen = .creator
    @Published var save: GameSave
    @Published var awayLog: [String] = []
    @Published var showAwayLog = false

    let viewModel = GameViewModel()
    private(set) var controller: GameSceneController?

    private var autosaveTimer: Timer?

    init() {
        if let loaded = SaveStore.shared.load() {
            var s = loaded
            let result = OfflineSimulator.catchUp(save: s)
            s.needs = result.needs
            s.room = result.room
            s.awayLog = result.log
            self.save = s
            self.awayLog = result.log
            self.screen = .game
            self.showAwayLog = !result.log.isEmpty
        } else {
            var s = GameSave()
            s.profile.appearance = BreedPresets.appearance(for: .domesticShorthair)
            s.profile.personality = BreedPresets.personality(for: .domesticShorthair)
            self.save = s
            self.screen = .creator
        }
        viewModel.catName = save.profile.name
    }

    // MARK: - Lifecycle

    func startGame() {
        save.lastSeen = Date()
        let controller = GameSceneController(save: save)
        controller.viewModel = viewModel
        viewModel.catName = save.profile.name
        self.controller = controller
        CatVoice.shared.start()
        screen = .game
        persist()
        startAutosave()
    }

    func finishCreation(appearance: CatAppearance, personality: CatPersonality,
                        archetype: PersonalityArchetype, name: String) {
        save.profile.appearance = appearance
        save.profile.personality = personality
        save.profile.archetype = archetype
        save.profile.name = name.isEmpty ? "Mochi" : name
        save.profile.adoptedAt = Date()
        save.lastSeen = Date()
        startGame()
        NotificationScheduler.requestAuthorization { [weak self] granted in
            self?.save.notificationsEnabled = granted
            self?.persist()
        }
    }

    /// Re-opens the creator for an existing cat, keeping needs and bond.
    func editCat() {
        screen = .creator
    }

    func applyEdits(appearance: CatAppearance, personality: CatPersonality,
                    archetype: PersonalityArchetype, name: String) {
        save.profile.appearance = appearance
        save.profile.personality = personality
        save.profile.archetype = archetype
        save.profile.name = name.isEmpty ? save.profile.name : name
        viewModel.catName = save.profile.name
        if let controller {
            controller.applyAppearance(appearance, personality: personality)
            screen = .game
            persist()
        } else {
            startGame()
        }
    }

    private func startAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.persist()
        }
    }

    func persist() {
        controller?.writeBack(to: &save)
        save.lastSeen = Date()
        SaveStore.shared.save(save)
    }

    func handleScenePhase(_ active: Bool) {
        if active {
            CatVoice.shared.resume()
            NotificationScheduler.cancelAll()
            catchUpFromBackground()
        } else {
            persist()
            CatVoice.shared.stop()
            NotificationScheduler.reschedule(save: save)
        }
    }

    /// A cold launch runs the catch-up in `init`. Coming back from the background
    /// has to do it too, otherwise an afternoon away leaves the cat exactly as you
    /// left it.
    private func catchUpFromBackground() {
        guard let controller else { return }
        guard Date().timeIntervalSince(save.lastSeen) > 5 * 60 else {
            save.lastSeen = Date()
            return
        }
        controller.writeBack(to: &save)
        let result = OfflineSimulator.catchUp(save: save)
        save.needs = result.needs
        save.room = result.room
        save.awayLog = result.log
        controller.applyCatchUp(needs: result.needs, room: result.room)
        save.lastSeen = Date()
        awayLog = result.log
        showAwayLog = !result.log.isEmpty
        persist()
    }

    func setNotifications(_ enabled: Bool) {
        if enabled {
            NotificationScheduler.requestAuthorization { [weak self] granted in
                self?.save.notificationsEnabled = granted
                self?.persist()
            }
        } else {
            save.notificationsEnabled = false
            NotificationScheduler.cancelAll()
            persist()
        }
    }

    func startOver() {
        SaveStore.shared.wipe()
        NotificationScheduler.cancelAll()
        controller = nil
        var s = GameSave()
        s.profile.appearance = BreedPresets.appearance(for: .domesticShorthair)
        s.profile.personality = BreedPresets.personality(for: .domesticShorthair)
        save = s
        screen = .creator
    }
}
