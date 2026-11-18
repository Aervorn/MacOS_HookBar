import Foundation

/// Appels à l'API REST de Discord : seulement pour rattraper les messages manqués.
struct DiscordREST {
    enum Failure: Error {
        case http(Int)
    }

    let token: String
    private static let base = URL(string: "https://discord.com/api/v10")!

    /// Messages d'un salon postés après `after`, du plus ancien au plus récent (100 au maximum).
    func messages(channelId: String, after: String) async throws -> [MessagePayload] {
        var components = URLComponents(url: Self.base.appendingPathComponent("channels/\(channelId)/messages"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "after", value: after),
            URLQueryItem(name: "limit", value: "100"),
        ]
        let data = try await get(components.url!)
        let messages = try JSONDecoder.discord.decode([MessagePayload].self, from: data)
        return messages.sorted { Snowflake.value($0.id) < Snowflake.value($1.id) }
    }

    private func get(_ url: URL, retry: Bool = true) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bot \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("HookBar (https://github.com/Aervorn, 0.1)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 429, retry {
            // Limite de débit : Discord indique combien de secondes attendre
            struct RateLimit: Decodable { let retryAfter: Double }
            let wait = (try? JSONDecoder.discord.decode(RateLimit.self, from: data).retryAfter) ?? 1
            try await Task.sleep(nanoseconds: UInt64(min(wait, 10) * 1_000_000_000))
            return try await get(url, retry: false)
        }
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        return data
    }
}
