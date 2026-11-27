import AppKit
import Foundation
import ServiceManagement

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var label: LocalizedStringResource {
        switch self {
        case .system: "Suivre le système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, fr, en

    var id: Self { self }

    var label: LocalizedStringResource {
        switch self {
        case .system: "Langue du système"
        case .fr: "Français"
        case .en: "English"
        }
    }

    /// La langue de l'interface est lue au lancement (clé AppleLanguages propre à l'app).
    func apply() {
        let defaults = UserDefaults.standard
        switch self {
        case .system: defaults.removeObject(forKey: "AppleLanguages")
        case .fr, .en: defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

/// Préférences de l'app, enregistrées dans UserDefaults.
@MainActor
@Observable
final class AppPreferences {
    private enum Key {
        static let appearance = "appearance"
        static let language = "language"
        static let markReadOnClick = "markReadOnClick"
        static let autoFollowNewChannels = "autoFollowNewChannels"
        static let colorUnreadCount = "colorUnreadCount"
        static let unreadCountColor = "unreadCountColor"
    }

    private let defaults = UserDefaults.standard

    var appearance: AppearanceMode {
        didSet {
            defaults.set(appearance.rawValue, forKey: Key.appearance)
            appearance.apply()
        }
    }

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: Key.language)
            language.apply()
        }
    }

    /// Cliquer sur un message le marque aussi comme lu (sinon, seulement le bouton ✓).
    var markReadOnClick: Bool {
        didSet { defaults.set(markReadOnClick, forKey: Key.markReadOnClick) }
    }

    /// Les salons créés plus tard sur le serveur sont suivis d'office.
    var autoFollowNewChannels: Bool {
        didSet { defaults.set(autoFollowNewChannels, forKey: Key.autoFollowNewChannels) }
    }

    /// Affiche en couleur le nombre de non-lus dans la barre de menus.
    var colorUnreadCount: Bool {
        didSet { defaults.set(colorUnreadCount, forKey: Key.colorUnreadCount) }
    }

    /// Couleur de ce nombre (entier 0xRRGGBB).
    var unreadCountColor: Int {
        didSet { defaults.set(unreadCountColor, forKey: Key.unreadCountColor) }
    }

    /// Rouge système d'Apple, lisible sur une barre de menus claire ou sombre.
    static let defaultUnreadCountColor = 0xFF453A

    /// Langue choisie au lancement : sert à savoir s'il faut relancer l'app.
    let launchLanguage: AppLanguage

    init() {
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        let language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .system
        self.language = language
        launchLanguage = language
        markReadOnClick = defaults.bool(forKey: Key.markReadOnClick)
        autoFollowNewChannels = defaults.object(forKey: Key.autoFollowNewChannels) as? Bool ?? true
        colorUnreadCount = defaults.object(forKey: Key.colorUnreadCount) as? Bool ?? true
        unreadCountColor = defaults.object(forKey: Key.unreadCountColor) as? Int ?? Self.defaultUnreadCountColor
    }

    // MARK: - Ouverture à la connexion

    var launchAtLogin: Bool {
        get {
            _ = launchAtLoginRevision
            return SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("HookBar: ouverture à la connexion impossible : \(error)")
            }
            launchAtLoginRevision += 1
        }
    }

    /// Force les vues à relire `launchAtLogin`, qui n'est pas une propriété stockée.
    private(set) var launchAtLoginRevision = 0

    // MARK: - Relance

    /// Relance l'app (nouvelle langue).
    func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
