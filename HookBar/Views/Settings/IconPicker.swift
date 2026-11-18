import SwiftUI

/// Choix de l'icône d'un salon : automatique, application selfh.st, symbole ou initiale.
struct IconPicker: View {
    let channel: Channel

    @Environment(AppStore.self) private var store
    @Environment(IconStore.self) private var icons
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    static let symbols = [
        "lock.shield", "exclamationmark.triangle", "server.rack", "externaldrive", "network",
        "bolt", "cpu", "thermometer.medium", "doc.text", "arrow.triangle.2.circlepath",
        "house", "shippingbox", "cloud", "globe", "bell", "number",
    ]

    private var current: ChannelIcon { store.icon(for: channel.id) }

    private var results: [IconStore.Entry] {
        let text = query.isEmpty ? channel.name : query
        var found = icons.search(text)
        // Sans recherche : l'icône trouvée automatiquement en premier
        if query.isEmpty, case .selfhst(let reference) = icons.resolve(.auto, channelName: channel.name),
           let entry = icons.entries.first(where: { $0.reference == reference }) {
            found.removeAll { $0.reference == reference }
            found.insert(entry, at: 0)
        }
        return found
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ChannelIconView(channelId: channel.id, channelName: channel.name, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "#\(channel.name)").font(.headline)
                    Text("Icône du salon").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                choice(.auto) {
                    Label("Automatique", systemImage: "wand.and.stars")
                }
                choice(.letter) {
                    Label("Initiale", systemImage: "textformat")
                }
            }

            TextField("Rechercher une application", text: $query, prompt: Text("Rechercher une application (ex. Proxmox)"))
                .textFieldStyle(.roundedBorder)

            ScrollView {
                if results.isEmpty {
                    (icons.entries.isEmpty ? Text("Chargement du catalogue d'icônes…") : Text("Aucune icône trouvée."))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 8)], spacing: 8) {
                        ForEach(results) { entry in
                            Button {
                                store.setIcon(.selfhst(entry.reference), channelId: channel.id)
                            } label: {
                                VStack(spacing: 4) {
                                    RemoteIcon(reference: entry.reference, size: 32)
                                    Text(verbatim: entry.name)
                                        .font(.caption2)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .frame(width: 74, height: 62)
                                .background(selectionBackground(current == .selfhst(entry.reference)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(height: 220)

            Text("Symboles").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 12), spacing: 6) {
                ForEach(Self.symbols, id: \.self) { symbol in
                    Button {
                        store.setIcon(.symbol(symbol), channelId: channel.id)
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15))
                            .frame(width: 32, height: 32)
                            .background(selectionBackground(current == .symbol(symbol)))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Link("Icônes : selfh.st/icons", destination: URL(string: "https://selfh.st/icons")!)
                    .font(.caption)
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private func choice<Content: View>(_ icon: ChannelIcon, @ViewBuilder label: () -> Content) -> some View {
        Button {
            store.setIcon(icon, channelId: channel.id)
        } label: {
            label()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(selectionBackground(current == icon))
        }
        .buttonStyle(.plain)
    }

    private func selectionBackground(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.2) : Color.clear)
    }
}

/// Icône selfh.st seule (sélecteur).
private struct RemoteIcon: View {
    let reference: String
    let size: CGFloat
    @Environment(IconStore.self) private var icons

    var body: some View {
        Group {
            if let image = icons.image(reference) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: size, height: size)
    }
}
