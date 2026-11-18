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

    var body: some View {
        let count = store.unreadCount
        HStack(spacing: 3) {
            Image(systemName: symbol(count: count))
            if count > 0 {
                Text(verbatim: "\(count)")
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
}
