import Foundation

/// Réglages d'un salon suivi.
struct ChannelPrefs: Codable, Hashable {
    var followed: Bool
    var banner: Bool
    var icon: ChannelIcon

    static let new = ChannelPrefs(followed: true, banner: false, icon: .auto)
}

/// Tout ce que l'app garde entre deux lancements (hors jeton, rangé dans le trousseau).
struct PersistedState: Codable {
    var guilds: [Guild] = []
    var channels: [Channel] = []
    var prefs: [String: ChannelPrefs] = [:]
    /// Dernier message connu de chaque salon : point de reprise après une coupure.
    var lastSeen: [String: String] = [:]
    var unread: [StoredMessage] = []
    var botName: String?
}

/// Fichiers de l'app dans ~/Library/Application Support/HookBar.
enum Persistence {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("HookBar", isDirectory: true)
        // Ancien nom de l'app (Discordify, version de développement) : on reprend ses données.
        let legacy = base.appendingPathComponent("Discordify", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path), FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: folder)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    static var stateURL: URL { folder.appendingPathComponent("state.json") }

    static var iconsFolder: URL {
        let url = folder.appendingPathComponent("Icons", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func load() -> PersistedState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState()
        }
        return state
    }

    static func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }
}
