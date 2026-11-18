import Foundation
import Security

/// Stockage du jeton du bot dans le trousseau macOS.
///
/// Avec la signature locale (« Sign to Run Locally »), macOS peut redemander l'autorisation
/// d'accès au trousseau après une recompilation : il suffit de cliquer sur « Toujours autoriser ».
enum Keychain {
    private static let service = "io.github.aervorn.hookbar"

    enum Account {
        static let botToken = "discord-bot-token"
    }

    /// Ancien nom de l'app (Discordify, version de développement).
    private static let legacyService = "io.github.aervorn.discordify"

    static func read(_ account: String) -> String? {
        if let value = read(account, service: service) { return value }
        // Jeton enregistré sous l'ancien nom : on le reprend sous le nouveau.
        guard let legacy = read(account, service: legacyService) else { return nil }
        save(legacy, account: account)
        return legacy
    }

    private static func read(_ account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)
        return value?.isEmpty == true ? nil : value
    }

    /// Enregistre la valeur, ou l'efface si elle est vide.
    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        delete(account)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
        ]
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
