import SwiftUI

/// Barre de gauche : « Tous », puis les salons qui ont des messages non lus, et en bas les actions.
struct Sidebar: View {
    @Binding var selection: String?

    @Environment(AppStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        VStack(spacing: 2) {
            SidebarButton(isSelected: selection == nil, badge: 0, help: Text("Tous les salons")) {
                selection = nil
            } icon: {
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .medium))
            }

            Divider().padding(.horizontal, 10)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(store.displayedChannels) { channel in
                        SidebarButton(isSelected: selection == channel.id,
                                      badge: store.unreadCount(channelId: channel.id),
                                      help: Text(verbatim: "#\(channel.name)")) {
                            selection = channel.id
                        } icon: {
                            ChannelIconView(channelId: channel.id, channelName: channel.name, size: 22)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            SidebarButton(isSelected: false, badge: 0, help: Text("Actualiser")) {
                store.refresh()
            } icon: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
            }

            Menu {
                Button("Réglages…") { bringToFront(openWindow, id: SettingsView.windowID) }
                    .keyboardShortcut(",")
                Button("À propos de HookBar") { bringToFront(openWindow, id: AboutView.windowID) }
                if updater.isEnabled {
                    Button("Rechercher les mises à jour…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
                Divider()
                Button("Quitter HookBar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 36, height: 32)
            .help(Text("Réglages"))
        }
        .padding(.vertical, 8)
        .frame(width: 54)
        .background(.background.secondary)
    }
}

/// Bouton carré de la barre latérale, avec pastille du nombre de non lus.
private struct SidebarButton<Icon: View>: View {
    let isSelected: Bool
    let badge: Int
    let help: Text
    let action: () -> Void
    @ViewBuilder let icon: () -> Icon

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            icon()
                .frame(width: 36, height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                              : hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear))
                }
                // Marge autour de l'icône : la pastille reste dans le cadre du bouton
                // (la liste défilante coupe tout ce qui dépasse).
                .frame(width: 46, height: 42)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(verbatim: badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 15, minHeight: 15)
                            .background(Color.red, in: Capsule())
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        .onHover { hovering = $0 }
        .help(help)
    }
}
