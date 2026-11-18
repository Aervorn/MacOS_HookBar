import SwiftUI

/// Un message dans la liste : replié (titre + aperçu) ou déplié (contenu complet).
struct MessageRow: View {
    let message: StoredMessage

    @Environment(AppStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        let isRead = store.isRead(message)
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(barColor)
                .frame(width: 3)

            AsyncImage(url: message.avatarURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Circle().fill(.quaternary)
            }
            .frame(width: 22, height: 22)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(markdown(message.headline))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(expanded ? nil : 1)

                if expanded {
                    MessageDetail(message: message)
                } else if !message.preview.isEmpty {
                    Text(markdown(message.preview))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    if !message.authorName.isEmpty {
                        Text(verbatim: message.authorName)
                        Text(verbatim: "·")
                    }
                    Text(RelativeTime.string(for: message.date))
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.snappy) {
                    if isRead { store.markUnread(message) } else { store.markRead(message, keepVisible: false) }
                }
            } label: {
                Image(systemName: isRead ? "arrow.uturn.backward.circle" : "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(isRead ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.markRead))
                    .frame(width: 28, height: 28)
                    .scaleEffect(hovering && !isRead ? 1.1 : 1)
            }
            .buttonStyle(.borderless)
            // Coche visible au survol du message seulement (comme Gitify) ; la place reste réservée
            // pour garder l'alignement. Un message lu à l'instant garde son bouton « non lu ».
            .opacity(hovering || isRead ? 1 : 0)
            .allowsHitTesting(hovering || isRead)
            .help(isRead ? Text("Marquer comme non lu") : Text("Marquer comme lu"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .opacity(isRead ? 0.5 : 1)
        .background(hovering ? Color.primary.opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            withAnimation(.snappy) { expanded.toggle() }
            if preferences.markReadOnClick, !isRead {
                store.markRead(message, keepVisible: true)
            }
        }
    }

    private var barColor: Color {
        guard let rgb = message.accentColor else { return Color.secondary.opacity(0.25) }
        return Color(rgb: rgb)
    }
}

/// Contenu complet d'un message déplié : texte, embeds (champs, liens, images) et pièces jointes.
private struct MessageDetail: View {
    let message: StoredMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let headlineFromContent = message.embeds.allSatisfy { ($0.title ?? "").isEmpty }
            let text = headlineFromContent
                ? message.content.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().joined(separator: "\n")
                : message.content
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(markdown(text))
                    .font(.system(size: 12))
                    .textSelection(.enabled)
            }

            ForEach(Array(message.embeds.enumerated()), id: \.offset) { index, embed in
                EmbedView(embed: embed, showTitle: !(index == 0 && !headlineFromContent))
            }

            ForEach(message.attachments, id: \.url) { attachment in
                if let url = URL(string: attachment.url) {
                    Link(destination: url) {
                        Label(attachment.filename, systemImage: "paperclip")
                            .font(.system(size: 12))
                    }
                }
            }

            if let link = message.link(appScheme: DiscordLink.appInstalled) {
                Link(destination: link) {
                    Label("Ouvrir dans Discord", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12))
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct EmbedView: View {
    let embed: Embed
    let showTitle: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let author = embed.authorName, !author.isEmpty {
                Text(verbatim: author)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            if showTitle, let title = embed.title, !title.isEmpty {
                if let urlString = embed.url, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Text(markdown(title)).font(.system(size: 12, weight: .semibold))
                    }
                } else {
                    Text(markdown(title)).font(.system(size: 12, weight: .semibold))
                }
            }
            if let description = embed.description, !description.isEmpty {
                Text(markdown(description))
                    .font(.system(size: 12))
                    .textSelection(.enabled)
            }
            if !embed.fields.isEmpty {
                FieldsGrid(fields: embed.fields)
            }
            if let image = embed.imageURL ?? embed.thumbnailURL, let url = URL(string: image) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(.quaternary).frame(height: 80)
                }
                .frame(maxWidth: 280, maxHeight: 180, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if let footer = embed.footer, !footer.isEmpty {
                Text(verbatim: footer)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Champs d'un embed : ceux marqués « inline » côte à côte, les autres sur toute la largeur.
private struct FieldsGrid: View {
    let fields: [EmbedField]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, field in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(markdown(field.name))
                                .font(.system(size: 11, weight: .semibold))
                            Text(markdown(field.value))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    /// Jusqu'à trois champs « inline » par ligne, comme dans Discord.
    private var rows: [[EmbedField]] {
        var rows: [[EmbedField]] = []
        var current: [EmbedField] = []
        for field in fields {
            if field.inline {
                current.append(field)
                if current.count == 3 { rows.append(current); current = [] }
            } else {
                if !current.isEmpty { rows.append(current); current = [] }
                rows.append([field])
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - Outils

/// Markdown de Discord (gras, italique, code, liens) ; texte brut si l'analyse échoue.
func markdown(_ text: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                          failurePolicy: .returnPartiallyParsedIfPossible)
    return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
}

enum RelativeTime {
    static func string(for date: Date) -> String {
        if Date().timeIntervalSince(date) < 60 { return String(localized: "à l'instant") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

enum DiscordLink {
    /// Vrai si l'app Discord est installée : les liens s'ouvrent alors dedans.
    static let appInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hnc.Discord") != nil
}

extension Color {
    /// Vert vif des boutons « Marquer comme lu ».
    static let markRead = Color(.sRGB, red: 0.15, green: 0.90, blue: 0.40)

    /// Couleur Discord (entier 0xRRGGBB).
    init(rgb: Int) {
        self.init(.sRGB,
                  red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
