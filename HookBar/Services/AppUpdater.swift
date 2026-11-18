import AppKit
import Combine
import Foundation
import Observation
import Sparkle

/// Mises à jour par Sparkle, comme pour Vestora et Flux.
///
/// Le flux des versions (`appcast.xml`, à la racine du dépôt) est indiqué par `SUFeedURL` ;
/// chaque DMG est signé avec la clé EdDSA dont la partie publique est `SUPublicEDKey`
/// (voir scripts/make-dmg.sh). Une mise à jour mal signée est refusée.
///
/// Désactivé en Debug : un build lancé depuis Xcode ne doit pas se remplacer par la version publiée.
@MainActor
@Observable
final class AppUpdater {
    private(set) var canCheckForUpdates = false

    var automaticallyChecksForUpdates: Bool {
        didSet {
            guard automaticallyChecksForUpdates != oldValue else { return }
            controller?.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var cancellable: AnyCancellable?

    static var isEnabledByDefault: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    var isEnabled: Bool { controller != nil }

    init(enabled: Bool? = nil) {
        let enabled = enabled ?? Self.isEnabledByDefault
        let controller = enabled
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            : nil
        self.controller = controller
        automaticallyChecksForUpdates = controller?.updater.automaticallyChecksForUpdates ?? false
        cancellable = controller?.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                MainActor.assumeIsolated { self?.canCheckForUpdates = value }
            }
    }

    var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var lastCheck: Date? { controller?.updater.lastUpdateCheckDate }

    /// HookBar n'a pas d'icône dans le Dock : on la passe au premier plan pour que la fenêtre de Sparkle se voie.
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}
