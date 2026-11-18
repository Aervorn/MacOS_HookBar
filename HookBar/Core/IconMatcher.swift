import Foundation

/// Choix d'icône d'un salon, enregistré dans les préférences.
enum ChannelIcon: Codable, Hashable, Sendable {
    /// Détection automatique d'après le nom du salon.
    case auto
    /// Icône du catalogue selfh.st (sa « référence », ex. `proxmox`).
    case selfhst(String)
    /// Symbole SF.
    case symbol(String)
    /// Première lettre du nom du salon.
    case letter
}

/// Associe un nom de salon à une icône du catalogue selfh.st.
///
/// Ordre : alias connus, nom exact, début de nom (ex. `adguard` → `adguard-home`),
/// faute de frappe proche (ex. `proxmmox` → `proxmox`), puis symbole générique ou lettre.
enum IconMatcher {
    enum Match: Hashable, Sendable {
        case selfhst(String)
        case symbol(String)
        case letter(String)
    }

    /// Noms de salon courants qui ne ressemblent pas à la référence de leur icône.
    static let aliases: [String: String] = [
        "nut": "network-ups-tools",
        "ups": "network-ups-tools",
        "onduleur": "network-ups-tools",
        "forkwatch": "github",
        "pve": "proxmox",
        "pbs": "proxmox",
        "ha": "home-assistant",
        "hass": "home-assistant",
        "homeassistant": "home-assistant",
        "npm": "nginx-proxy-manager",
        "adguard": "adguard-home",
        "pihole": "pi-hole",
        "dsm": "synology",
        "nas": "synology",
        "kuma": "uptime-kuma",
        "unifi": "ubiquiti-unifi",
        "ubiquiti": "ubiquiti-unifi",
        "uptime": "uptime-kuma",
    ]

    /// Symboles pour les salons génériques, sans application associée.
    static let symbols: [String: String] = [
        "security": "lock.shield",
        "securite": "lock.shield",
        "secu": "lock.shield",
        "alerts": "exclamationmark.triangle",
        "alertes": "exclamationmark.triangle",
        "alerte": "exclamationmark.triangle",
        "backup": "externaldrive",
        "backups": "externaldrive",
        "sauvegarde": "externaldrive",
        "sauvegardes": "externaldrive",
        "logs": "doc.text",
        "general": "number",
        "updates": "arrow.triangle.2.circlepath",
        "maj": "arrow.triangle.2.circlepath",
        "monitoring": "waveform.path.ecg",
        "network": "network",
        "reseau": "network",
        "power": "bolt",
        "energie": "bolt",
        "meteo": "cloud.sun",
        "weather": "cloud.sun",
    ]

    /// Minuscules, sans accents, lettres et chiffres seulement.
    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func trimmingTrailingDigits(_ text: String) -> String {
        var result = text
        while let last = result.last, last.isNumber { result.removeLast() }
        return result.isEmpty ? text : result
    }

    static func letter(for name: String) -> String {
        let first = name.first { $0.isLetter || $0.isNumber }
        return first.map { String($0).uppercased() } ?? "#"
    }

    static func match(channelName: String, references: [String]) -> Match {
        let key = normalize(channelName)
        let base = trimmingTrailingDigits(key)
        let available = Set(references)

        for candidate in [key, base] {
            if let alias = aliases[candidate], available.contains(alias) {
                return .selfhst(alias)
            }
        }

        // Référence normalisée → référence (la plus courte en cas d'égalité)
        var byNormalized: [String: String] = [:]
        for reference in references {
            let normalized = normalize(reference)
            if let existing = byNormalized[normalized], existing.count <= reference.count { continue }
            byNormalized[normalized] = reference
        }

        for candidate in [key, base] where !candidate.isEmpty {
            if let reference = byNormalized[candidate] { return .selfhst(reference) }
        }

        if base.count >= 4 {
            let prefixed = byNormalized.filter { $0.key.hasPrefix(base) }
            if let best = prefixed.min(by: { ($0.key.count, $0.key) < ($1.key.count, $1.key) }) {
                return .selfhst(best.value)
            }
        }

        if base.count >= 5 {
            let tolerance = base.count >= 7 ? 2 : 1
            var best: (distance: Int, normalized: String, reference: String)?
            for (normalized, reference) in byNormalized where abs(normalized.count - base.count) <= tolerance {
                let distance = levenshtein(base, normalized, limit: tolerance)
                guard distance <= tolerance else { continue }
                if best == nil || (distance, normalized) < (best!.distance, best!.normalized) {
                    best = (distance, normalized, reference)
                }
            }
            if let best { return .selfhst(best.reference) }
        }

        // Noms en plusieurs mots (ex. « synology-dsm ») : un mot qui correspond à une icône
        let words = channelName
            .split { !($0.isLetter || $0.isNumber) }
            .map { trimmingTrailingDigits(normalize(String($0))) }
            .filter { $0.count >= 3 }
        if words.count > 1 {
            for word in words {
                if let alias = aliases[word], available.contains(alias) { return .selfhst(alias) }
                if let reference = byNormalized[word] { return .selfhst(reference) }
            }
        }

        for candidate in [key, base] + words {
            if let symbol = symbols[candidate] { return .symbol(symbol) }
        }
        return .letter(letter(for: channelName))
    }

    /// Distance d'édition, arrêtée dès qu'elle dépasse `limit`.
    static func levenshtein(_ a: String, _ b: String, limit: Int = .max) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMinimum = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowMinimum = min(rowMinimum, current[j])
            }
            if rowMinimum > limit { return rowMinimum }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
