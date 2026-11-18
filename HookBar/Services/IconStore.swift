import AppKit
import Foundation

/// Icônes d'applications du catalogue selfh.st (https://selfh.st/icons), mises en cache sur le disque.
@MainActor
@Observable
final class IconStore {
    struct Entry: Decodable, Hashable, Identifiable {
        let name: String
        let reference: String

        var id: String { reference }

        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case reference = "Reference"
        }
    }

    private static let cdn = "https://cdn.jsdelivr.net/gh/selfhst/icons"
    private static let indexMaxAge: TimeInterval = 7 * 24 * 3600

    /// Catalogue complet (environ 3 000 icônes).
    private(set) var entries: [Entry] = []
    private(set) var images: [String: NSImage] = [:]

    @ObservationIgnored private var references: [String] = []
    @ObservationIgnored private var matchCache: [String: IconMatcher.Match] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    @ObservationIgnored private var failed: Set<String> = []

    private var indexURL: URL { Persistence.iconsFolder.appendingPathComponent("index.json") }

    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        if let data = try? Data(contentsOf: indexURL) { apply(indexData: data) }
        let modified = (try? indexURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        if entries.isEmpty || modified.map({ Date().timeIntervalSince($0) > Self.indexMaxAge }) ?? true {
            Task { await refreshIndex() }
        }
    }

    func refreshIndex() async {
        guard let url = URL(string: "\(Self.cdn)/index.json"),
              let data = await Self.fetch(url) else { return }
        if apply(indexData: data) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    @discardableResult
    private func apply(indexData data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode([Entry].self, from: data), !decoded.isEmpty else { return false }
        entries = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        references = decoded.map(\.reference)
        matchCache = [:]
        return true
    }

    /// Icône à afficher pour un salon, selon son réglage.
    func resolve(_ icon: ChannelIcon, channelName: String) -> IconMatcher.Match {
        switch icon {
        case .selfhst(let reference): return .selfhst(reference)
        case .symbol(let name): return .symbol(name)
        case .letter: return .letter(IconMatcher.letter(for: channelName))
        case .auto:
            _ = entries.count // relu quand le catalogue arrive
            if let cached = matchCache[channelName] { return cached }
            let match = IconMatcher.match(channelName: channelName, references: references)
            if !references.isEmpty { matchCache[channelName] = match }
            return match
        }
    }

    /// Image d'une icône selfh.st ; la télécharge si besoin (la vue se met à jour à l'arrivée).
    func image(_ reference: String) -> NSImage? {
        if let image = images[reference] { return image }
        guard !loading.contains(reference), !failed.contains(reference) else { return nil }
        loading.insert(reference)
        Task { await load(reference) }
        return nil
    }

    private func load(_ reference: String) async {
        defer { loading.remove(reference) }
        let file = Persistence.iconsFolder.appendingPathComponent("\(reference).png")
        if let image = NSImage(contentsOf: file) {
            images[reference] = image
            return
        }
        guard let url = URL(string: "\(Self.cdn)/png/\(reference).png"),
              let data = await Self.fetch(url),
              let image = NSImage(data: data) else {
            failed.insert(reference)
            return
        }
        try? data.write(to: file, options: .atomic)
        images[reference] = image
    }

    /// Contenu d'une URL si le serveur répond 200, sinon nil.
    private static func fetch(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200 ? data : nil
        } catch {
            return nil
        }
    }

    /// Icônes dont le nom contient la recherche (pour le sélecteur des Réglages).
    func search(_ query: String, limit: Int = 60) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        let normalized = IconMatcher.normalize(trimmed)
        let matches = entries.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed) || IconMatcher.normalize($0.reference).contains(normalized)
        }
        return Array(matches.prefix(limit))
    }

    func clearCache() {
        images = [:]
        failed = []
        if let files = try? FileManager.default.contentsOfDirectory(at: Persistence.iconsFolder, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "png" {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
