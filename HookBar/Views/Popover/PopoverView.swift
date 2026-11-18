import SwiftUI

/// Fenêtre qui s'ouvre depuis la barre de menus, sur le modèle de Gitify :
/// salons non lus à gauche, messages à droite.
struct PopoverView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    /// Salon sélectionné ; nil = tous les salons.
    @State private var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(selection: $selection)
            Divider()
            VStack(spacing: 0) {
                header
                Divider()
                StatusBanner()
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 470, height: 540)
        .onChange(of: store.displayedChannels.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
        .onDisappear {
            store.flushRecentlyRead()
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 8) {
            if let selection, let channel = store.channels[selection] {
                ChannelIconView(channelId: channel.id, channelName: channel.name, size: 18)
                Text(verbatim: "#\(channel.name)")
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Text("Tous les salons")
                    .font(.headline)
            }
            Spacer()
            let count = selection.map { store.unreadCount(channelId: $0) } ?? store.unreadCount
            // Avec un seul message, sa propre coche suffit
            if count > 1 {
                Button {
                    withAnimation(.snappy) {
                        if let selection { store.markChannelRead(selection) } else { store.markAllRead() }
                    }
                } label: {
                    Label("Tout marquer comme lu", systemImage: "checkmark.circle.fill")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.markRead)
                        // Même cadre que la coche des messages : toutes les coches sur une même colonne
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(selection == nil ? Text("Tout marquer comme lu") : Text("Marquer le salon comme lu"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        if !store.hasToken {
            EmptyStateView(symbol: "key", title: "Connecte ton bot Discord",
                           message: "Ajoute le jeton de ton bot dans les Réglages pour recevoir les messages de tes salons.") {
                Button("Ouvrir les Réglages") { bringToFront(openWindow, id: SettingsView.windowID) }
                    .buttonStyle(.borderedProminent)
            }
        } else if store.displayedMessages(channelId: selection).isEmpty {
            EmptyStateView(symbol: "checkmark.circle", title: "Aucun message non lu",
                           message: "Tout est calme pour l'instant.") { EmptyView() }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if let selection {
                        ForEach(store.displayedMessages(channelId: selection)) { message in
                            MessageRow(message: message)
                            Divider()
                        }
                    } else {
                        ForEach(store.displayedChannels) { channel in
                            Section {
                                ForEach(store.displayedMessages(channelId: channel.id)) { message in
                                    MessageRow(message: message)
                                    Divider()
                                }
                            } header: {
                                ChannelSectionHeader(channel: channel)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// En-tête d'un salon dans la vue « Tous les salons ».
private struct ChannelSectionHeader: View {
    let channel: Channel
    @Environment(AppStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            ChannelIconView(channelId: channel.id, channelName: channel.name, size: 22)
            Text(verbatim: channel.name)
                .font(.subheadline.weight(.semibold))
            let count = store.unreadCount(channelId: channel.id)
            if count > 0 {
                Text(verbatim: "\(count)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
            // Coche du salon seulement si elle apporte quelque chose : plusieurs messages dans le salon,
            // et d'autres salons affichés (sinon la coche du haut fait déjà la même chose).
            if count > 1, store.displayedChannels.count > 1 {
                Button {
                    withAnimation(.snappy) { store.markChannelRead(channel.id) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color.markRead)
                        // Même cadre que la coche des messages : toutes les coches sur une même colonne
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help(Text("Marquer le salon comme lu"))
            }
        }
        .frame(minHeight: 28)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

/// Bandeau en haut de la liste quand la connexion pose problème.
private struct StatusBanner: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        switch store.connection {
        case .failed(let message):
            banner(symbol: "exclamationmark.triangle.fill", text: Text(verbatim: message), retry: true)
        case .offline:
            banner(symbol: "wifi.slash", text: Text("Déconnecté de Discord"), retry: true)
        case .connecting:
            banner(symbol: "arrow.triangle.2.circlepath", text: Text("Connexion à Discord…"), retry: false)
        case .connected, .noToken:
            EmptyView()
        }
    }

    private func banner(symbol: String, text: Text, retry: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            text.lineLimit(2)
            Spacer()
            if retry {
                Button("Réessayer") { store.refresh() }
                    .buttonStyle(.borderless)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.12))
    }
}

/// Message centré quand la liste est vide.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actions()
                .padding(.top, 4)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
