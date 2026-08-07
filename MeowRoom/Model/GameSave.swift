import Foundation

struct CatProfile: Codable, Equatable {
    var name: String = "Mochi"
    var appearance: CatAppearance = .init()
    var personality: CatPersonality = .init()
    var archetype: PersonalityArchetype = .balanced
    var adoptedAt: Date = Date()

    var ageDays: Int { max(0, Int(Date().timeIntervalSince(adoptedAt) / 86_400)) }
}

/// Things in the room the cat uses and the player maintains.
struct RoomState: Codable, Equatable {
    var feederFood: Float = 1.0      // 1 = full hopper
    var fountainWater: Float = 1.0
    var fountainOn: Bool = true
    var litterCleanliness: Float = 1.0
    var lanternOn: Bool = false
    var lanternAuto: Bool = true
    var treatsOnFloor: Int = 0
}

struct GameSave: Codable, Equatable {
    var version: Int = 1
    var profile = CatProfile()
    var needs = CatNeeds()
    var room = RoomState()
    var bond: Float = 0.1            // grows with good interactions
    var lastSeen: Date = Date()
    var totalPets: Int = 0
    var totalPlaySessions: Int = 0
    var notificationsEnabled: Bool = false
    /// Short log of what the cat did while the app was closed.
    var awayLog: [String] = []
}

/// JSON-on-disk persistence. Small enough that we just rewrite the whole file.
final class SaveStore {
    static let shared = SaveStore()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "meow.savestore")

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        fileURL = dir.appendingPathComponent("meowroom-save.json")
    }

    func load() -> GameSave? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GameSave.self, from: data)
    }

    func save(_ save: GameSave) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(save) else { return }
        let url = fileURL
        queue.async {
            try? data.write(to: url, options: .atomic)
        }
    }

    func wipe() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
