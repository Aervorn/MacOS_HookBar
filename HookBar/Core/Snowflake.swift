import Foundation

/// Identifiants Discord (« snowflakes ») : des entiers 64 bits transmis sous forme de texte.
/// Ils sont croissants dans le temps et contiennent la date de création.
enum Snowflake {
    /// 1er janvier 2015, l'époque de Discord, en millisecondes.
    static let discordEpoch: UInt64 = 1_420_070_400_000

    static func value(_ id: String) -> UInt64 {
        UInt64(id) ?? 0
    }

    /// Date de création de l'objet (message, salon…).
    static func date(_ id: String) -> Date {
        let milliseconds = (value(id) >> 22) + discordEpoch
        return Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
    }

    /// Vrai si `a` est plus récent que `b`.
    static func isNewer(_ a: String, than b: String?) -> Bool {
        guard let b else { return true }
        return value(a) > value(b)
    }

    /// Le plus récent des deux identifiants.
    static func newest(_ a: String?, _ b: String?) -> String? {
        switch (a, b) {
        case let (a?, b?): value(a) >= value(b) ? a : b
        case let (a?, nil): a
        case let (nil, b?): b
        default: nil
        }
    }
}
