import Foundation

// MARK: - Données conservées par l'app

struct Guild: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var iconHash: String?
}

struct Channel: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var guildId: String
    var name: String
    var type: Int
    var position: Int
    var parentId: String?
    var lastMessageId: String?

    /// Salons textuels (0) et d'annonces (5) : les seuls qui reçoivent des messages à suivre.
    var isText: Bool { type == 0 || type == 5 }
    /// Catégorie (4) : sert seulement à regrouper les salons dans les Réglages.
    var isCategory: Bool { type == 4 }
}

struct EmbedField: Codable, Hashable, Sendable {
    var name: String
    var value: String
    var inline: Bool
}

struct Embed: Codable, Hashable, Sendable {
    var title: String?
    var description: String?
    var url: String?
    var color: Int?
    var authorName: String?
    var footer: String?
    var fields: [EmbedField]
    var imageURL: String?
    var thumbnailURL: String?
}

struct Attachment: Codable, Hashable, Sendable {
    var filename: String
    var url: String
}

struct StoredMessage: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var channelId: String
    var guildId: String?
    var authorId: String
    var authorName: String
    var authorAvatar: String?
    var content: String
    var embeds: [Embed]
    var attachments: [Attachment]

    var date: Date { Snowflake.date(id) }

    /// Couleur de la barre : celle du premier embed qui en a une.
    var accentColor: Int? { embeds.first { $0.color != nil }?.color }

    /// Ligne de titre affichée dans la liste.
    var headline: String {
        if let title = embeds.lazy.compactMap(\.title).first(where: { !$0.isEmpty }) { return title }
        if let firstLine = content.split(separator: "\n").first.map(String.init), !firstLine.isEmpty {
            return firstLine
        }
        if let author = embeds.lazy.compactMap(\.authorName).first { return author }
        return attachments.first?.filename ?? ""
    }

    /// Aperçu sous le titre.
    var preview: String {
        let titleFromContent = embeds.allSatisfy { ($0.title ?? "").isEmpty }
        if titleFromContent {
            let rest = content.split(separator: "\n").dropFirst().joined(separator: " ")
            if !rest.isEmpty { return rest }
            return embeds.lazy.compactMap(\.description).first ?? ""
        }
        if let description = embeds.lazy.compactMap(\.description).first(where: { !$0.isEmpty }) {
            return description
        }
        if let field = embeds.first?.fields.first { return "\(field.name) : \(field.value)" }
        return content
    }

    /// Image de profil de l'auteur (bot, webhook ou personne), 64 px.
    var avatarURL: URL? {
        if let authorAvatar {
            return URL(string: "https://cdn.discordapp.com/avatars/\(authorId)/\(authorAvatar).png?size=64")
        }
        return URL(string: "https://cdn.discordapp.com/embed/avatars/0.png")
    }

    /// Lien vers le message dans Discord.
    func link(appScheme: Bool) -> URL? {
        let guild = guildId ?? "@me"
        let path = "/channels/\(guild)/\(channelId)/\(id)"
        return URL(string: appScheme ? "discord://-\(path)" : "https://discord.com\(path)")
    }
}

// MARK: - Réponses de Discord (Gateway et API REST)

struct GatewayFrame: Decodable {
    let op: Int
    let s: Int?
    let t: String?
}

struct GatewayEnvelope<Payload: Decodable>: Decodable {
    let d: Payload
}

struct HelloPayload: Decodable {
    let heartbeatInterval: Int
}

struct UserPayload: Decodable {
    let id: String
    let username: String
    let globalName: String?
    let avatar: String?
    let bot: Bool?

    var displayName: String { globalName ?? username }
}

struct ReadyPayload: Decodable {
    let sessionId: String
    let user: UserPayload
}

struct ChannelPayload: Decodable {
    let id: String
    let type: Int
    let guildId: String?
    let name: String?
    let position: Int?
    let parentId: String?
    let lastMessageId: String?

    func channel(guildId fallback: String) -> Channel {
        Channel(id: id, guildId: guildId ?? fallback, name: name ?? id, type: type,
                position: position ?? 0, parentId: parentId, lastMessageId: lastMessageId)
    }
}

struct GuildPayload: Decodable {
    let id: String
    let name: String?
    let icon: String?
    let unavailable: Bool?
    let channels: [ChannelPayload]?
}

struct DeletedMessagePayload: Decodable {
    let id: String
    let channelId: String
}

struct EmbedPayload: Decodable {
    struct Footer: Decodable { let text: String? }
    struct Author: Decodable { let name: String? }
    struct Media: Decodable { let url: String? }
    struct Field: Decodable {
        let name: String?
        let value: String?
        let inline: Bool?
    }

    let title: String?
    let description: String?
    let url: String?
    let color: Int?
    let footer: Footer?
    let author: Author?
    let fields: [Field]?
    let image: Media?
    let thumbnail: Media?

    var embed: Embed {
        Embed(title: title, description: description, url: url, color: color,
              authorName: author?.name, footer: footer?.text,
              fields: (fields ?? []).map { EmbedField(name: $0.name ?? "", value: $0.value ?? "", inline: $0.inline ?? false) },
              imageURL: image?.url, thumbnailURL: thumbnail?.url)
    }
}

struct AttachmentPayload: Decodable {
    let filename: String?
    let url: String?
}

struct MessagePayload: Decodable {
    let id: String
    let channelId: String
    let guildId: String?
    let author: UserPayload?
    let content: String?
    let embeds: [EmbedPayload]?
    let attachments: [AttachmentPayload]?
    let webhookId: String?

    func stored(guildId fallback: String?) -> StoredMessage {
        StoredMessage(
            id: id, channelId: channelId, guildId: guildId ?? fallback,
            authorId: author?.id ?? webhookId ?? "0",
            authorName: author?.displayName ?? "",
            authorAvatar: author?.avatar,
            content: content ?? "",
            embeds: (embeds ?? []).map(\.embed),
            attachments: (attachments ?? []).compactMap { item in
                guard let url = item.url else { return nil }
                return Attachment(filename: item.filename ?? url, url: url)
            })
    }

    /// Applique une mise à jour partielle (MESSAGE_UPDATE) : seuls les champs présents changent.
    func update(_ message: StoredMessage) -> StoredMessage {
        var updated = message
        if let content { updated.content = content }
        if let embeds { updated.embeds = embeds.map(\.embed) }
        if let attachments {
            updated.attachments = attachments.compactMap { item in
                guard let url = item.url else { return nil }
                return Attachment(filename: item.filename ?? url, url: url)
            }
        }
        return updated
    }
}

extension JSONDecoder {
    /// Décodeur des réponses de Discord (clés en snake_case).
    static let discord: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
