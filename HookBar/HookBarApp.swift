import SwiftUI

@main
struct HookBarApp: App {
    @State private var preferences: AppPreferences
    @State private var store: AppStore
    @State private var icons = IconStore()
    @State private var updater = AppUpdater()

    init() {
        let preferences = AppPreferences()
        _preferences = State(initialValue: preferences)
        _store = State(initialValue: AppStore(preferences: preferences))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(store)
                .environment(icons)
                .environment(preferences)
                .environment(updater)
        } label: {
            MenuBarLabel()
                .environment(store)
                .environment(preferences)
                // L'icône de la barre de menus existe dès le lancement (la fenêtre, seulement au premier clic)
                .task { start() }
        }
        .menuBarExtraStyle(.window)

        Window("Réglages de HookBar", id: SettingsView.windowID) {
            SettingsView()
                .environment(store)
                .environment(icons)
                .environment(preferences)
                .environment(updater)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Window("À propos de HookBar", id: AboutView.windowID) {
            AboutView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }

    private func start() {
        preferences.appearance.apply()
        NotificationManager.shared.start()
        icons.start()
        store.start()
    }
}

/// Icône de la barre de menus, avec le nombre de messages non lus.
struct MenuBarLabel: View {
    @Environment(AppStore.self) private var store
    @Environment(AppPreferences.self) private var preferences

    var body: some View {
        let count = store.unreadCount
        if count > 0, preferences.colorUnreadCount {
            // Image non « template » : sinon macOS redessine toute l'étiquette en monochrome
            Image(nsImage: MenuBarImage.make(symbol: symbol(count: count),
                                             count: count,
                                             countColor: preferences.unreadCountColor))
                .renderingMode(.original)
        } else {
            HStack(spacing: 3) {
                Image(systemName: symbol(count: count))
                if count > 0 {
                    Text(verbatim: "\(count)")
                }
            }
        }
    }

    private func symbol(count: Int) -> String {
        switch store.connection {
        case .failed, .offline: "bell.slash"
        default: count > 0 ? "bell.badge" : "bell"
        }
    }
}

/// Ouvre une fenêtre de l'app et la passe au premier plan (l'app n'a pas d'icône dans le Dock).
@MainActor
func bringToFront(_ openWindow: OpenWindowAction, id: String) {
    openWindow(id: id)
    NSApp.activate()
    // `activate()` n'est qu'une demande, que macOS peut ignorer : on remonte aussi la fenêtre elle-même.
    Task { @MainActor in
        // La fenêtre n'est pas forcément créée tout de suite : quelques essais rapprochés
        for _ in 0..<10 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            // SwiftUI reprend l'identifiant de la scène dans celui de la fenêtre
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(id) == true }) {
                NSApp.activate()
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
                return
            }
        }
        NSLog("HookBar: fenêtre « \(id) » introuvable, impossible de la passer au premier plan")
    }
}
