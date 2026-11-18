import AppKit
import Foundation

/// État central de l'app : connexion à Discord, salons, réglages par salon et messages non lus.
@MainActor
@Observable
final class AppStore {
    enum Connection: Equatable {
        case noToken
        case connecting
        case connected
        case offline
        case failed(String)
    }

    private(set) var connection: Connection = .noToken
    private(set) var botName: String?
    private(set) var guilds: [Guild] = []
    private(set) var channels: [String: Channel] = [:]
    private(set) var prefs: [String: ChannelPrefs] = [:]
    /// Messages non lus, du plus récent au plus ancien.
    private(set) var unread: [StoredMessage] = []
    /// Messages marqués comme lus pendant que la fenêtre est ouverte : encore affichés, estompés,
    /// jusqu'à sa fermeture (pour ne pas faire disparaître un message qu'on vient de déplier).
    private(set) var recentlyRead: [StoredMessage] = []

    @ObservationIgnored private var lastSeen: [String: String] = [:]
    /// Point de reprise de chaque salon au moment de la (re)connexion : les messages reçus en direct
    /// juste après ne doivent pas faire sauter ceux manqués pendant la coupure.
    @ObservationIgnored private var resumePoints: [String: String] = [:]
    /// Messages déjà traités pendant cette session (évite les doublons entre direct et rattrapage).
    @ObservationIgnored private var seenIds: Set<String> = []
    @ObservationIgnored private var botId: String?
    @ObservationIgnored private var token: String?
    @ObservationIgnored private let gateway = DiscordGateway()
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var catchUpTask: Task<Void, Never>?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let preferences: AppPreferences

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    // MARK: - Démarrage

    func start() {
        guard !started else { return }
        started = true

        let state = Persistence.load()
        guilds = state.guilds
        channels = Dictionary(state.channels.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        prefs = state.prefs
        lastSeen = state.lastSeen
        unread = state.unread.sorted { Snowflake.value($0.id) > Snowflake.value($1.id) }
        botName = state.botName

        gateway.onState = { [weak self] state in self?.gatewayStateChanged(state) }
        gateway.onEvent = { [weak self] event in self?.handle(event) }

        // Sortie de veille : la connexion est sans doute morte, on la refait tout de suite.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.gateway.reconnectNow() }
        }

        token = Keychain.read(Keychain.Account.botToken)
        if let token {
            gateway.connect(token: token)
        }
    }

    var hasToken: Bool { token != nil }

    /// Enregistre le jeton (trousseau) et se reconnecte avec lui.
    func updateToken(_ newToken: String) {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(trimmed, account: Keychain.Account.botToken)
        token = trimmed.isEmpty ? nil : trimmed
        if let token {
            gateway.connect(token: token)
        } else {
            gateway.stop()
            connection = .noToken
        }
    }

    func refresh() {
        switch connection {
        case .connected: catchUp()
        case .noToken: break
        default:
            if let token { gateway.connect(token: token) }
        }
    }

    private func gatewayStateChanged(_ state: DiscordGateway.State) {
        switch state {
        case .connecting: connection = .connecting
        case .connected: connection = .connected
        case .disconnected: connection = token == nil ? .noToken : .offline
        case .failed(let message): connection = .failed(message)
        }
    }

    // MARK: - Événements du Gateway

    private func handle(_ event: DiscordGateway.Event) {
        switch event {
        case .ready(let ready):
            resumePoints = lastSeen
            botId = ready.user.id
            botName = ready.user.displayName
            scheduleSave()

        case .guildCreate(let payload):
            guard payload.unavailable != true else { return }
            let guild = Guild(id: payload.id, name: payload.name ?? payload.id, iconHash: payload.icon)
            guilds.removeAll { $0.id == guild.id }
            guilds.append(guild)
            if let list = payload.channels {
                // La liste reçue est complète : les salons absents ont été supprimés.
                let received = Set(list.map(\.id))
                for (id, channel) in channels where channel.guildId == guild.id && !received.contains(id) {
                    channels[id] = nil
                }
                let firstRun = prefs.isEmpty
                for item in list { upsert(item.channel(guildId: guild.id), firstRun: firstRun) }
            }
            scheduleSave()
            scheduleCatchUp()

        case .guildDelete(let id):
            guilds.removeAll { $0.id == id }
            scheduleSave()

        case .channelUpsert(let payload):
            guard let guildId = payload.guildId else { return }
            upsert(payload.channel(guildId: guildId), firstRun: false)
            scheduleSave()

        case .channelDelete(let id):
            channels[id] = nil
            unread.removeAll { $0.channelId == id }
            scheduleSave()

        case .messageCreate(let payload):
            ingest(payload.stored(guildId: channels[payload.channelId]?.guildId), live: true)

        case .messageUpdate(let payload):
            if let index = unread.firstIndex(where: { $0.id == payload.id }) {
                unread[index] = payload.update(unread[index])
                scheduleSave()
            }

        case .messageDelete(let payload):
            unread.removeAll { $0.id == payload.id }
            recentlyRead.removeAll { $0.id == payload.id }
            scheduleSave()
        }
    }

    private func upsert(_ channel: Channel, firstRun: Bool) {
        channels[channel.id] = channel
        guard channel.isText else { return }
        if prefs[channel.id] == nil {
            // Premier lancement : tous les salons sont suivis ; ensuite, selon le réglage.
            let follow = firstRun || preferences.autoFollowNewChannels
            prefs[channel.id] = ChannelPrefs(followed: follow, banner: false, icon: .auto)
        }
        // Point de départ d'un salon suivi : son dernier message (pas d'historique importé).
        if lastSeen[channel.id] == nil {
            lastSeen[channel.id] = channel.lastMessageId ?? "0"
        }
    }

    // MARK: - Messages

    /// Ajoute un message aux non lus. Renvoie vrai s'il est nouveau.
    @discardableResult
    private func ingest(_ message: StoredMessage, live: Bool) -> Bool {
        guard let channel = channels[message.channelId] else { return false }
        lastSeen[channel.id] = Snowflake.newest(lastSeen[channel.id], message.id)
        channels[channel.id]?.lastMessageId = Snowflake.newest(channel.lastMessageId, message.id)
        guard prefs[channel.id]?.followed == true else { return false }
        guard message.authorId != botId,
              seenIds.insert(message.id).inserted,
              !unread.contains(where: { $0.id == message.id }),
              !recentlyRead.contains(where: { $0.id == message.id }) else { return false }

        let index = unread.firstIndex { Snowflake.value($0.id) < Snowflake.value(message.id) } ?? unread.endIndex
        unread.insert(message, at: index)
        scheduleSave()

        if live, prefs[channel.id]?.banner == true {
            NotificationManager.shared.post(message: message, channelName: channel.name)
        }
        return true
    }

    /// Rattrape les messages arrivés pendant une coupure (veille, réseau, app fermée).
    func catchUp() {
        catchUpTask?.cancel()
        guard let token else { return }
        let targets = channels.values
            .filter { $0.isText && prefs[$0.id]?.followed == true }
            .map { ($0.id, resumePoints[$0.id] ?? lastSeen[$0.id] ?? $0.lastMessageId ?? "0") }
        let rest = DiscordREST(token: token)
        catchUpTask = Task { [weak self] in
            for (channelId, after) in targets {
                guard !Task.isCancelled else { return }
                guard let messages = try? await rest.messages(channelId: channelId, after: after),
                      let self else { continue }
                // Salon rattrapé : la prochaine fois, on partira du dernier message connu.
                self.resumePoints[channelId] = nil
                let guildId = self.channels[channelId]?.guildId
                let added = messages
                    .map { $0.stored(guildId: guildId) }
                    .filter { self.ingest($0, live: false) }
                self.notifyCaughtUp(added, channelId: channelId)
            }
        }
    }

    private func scheduleCatchUp() {
        // Plusieurs GUILD_CREATE arrivent à la suite : un seul rattrapage, une fois la liste à jour.
        catchUpTask?.cancel()
        catchUpTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.catchUp()
        }
    }

    private func notifyCaughtUp(_ messages: [StoredMessage], channelId: String) {
        guard let channel = channels[channelId], prefs[channelId]?.banner == true, !messages.isEmpty else { return }
        if messages.count <= 3 {
            for message in messages { NotificationManager.shared.post(message: message, channelName: channel.name) }
        } else {
            NotificationManager.shared.postSummary(count: messages.count, channelId: channelId, channelName: channel.name)
        }
    }

    // MARK: - Lecture

    var unreadCount: Int { unread.count }

    func unreadCount(channelId: String) -> Int {
        unread.reduce(0) { $0 + ($1.channelId == channelId ? 1 : 0) }
    }

    func isRead(_ message: StoredMessage) -> Bool {
        recentlyRead.contains { $0.id == message.id }
    }

    /// Messages affichés pour un salon (non lus et lus à l'instant), du plus récent au plus ancien.
    func displayedMessages(channelId: String?) -> [StoredMessage] {
        (unread + recentlyRead)
            .filter { channelId == nil || $0.channelId == channelId }
            .sorted { Snowflake.value($0.id) > Snowflake.value($1.id) }
    }

    /// Salons à afficher dans la barre latérale, dans l'ordre de Discord.
    var displayedChannels: [Channel] {
        let ids = Set((unread + recentlyRead).map(\.channelId))
        let guildOrder = Dictionary(guilds.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { channels[$0] }.sorted { a, b in
            let ga = guildOrder[a.guildId] ?? 0, gb = guildOrder[b.guildId] ?? 0
            if ga != gb { return ga < gb }
            let ca = channels[a.parentId ?? ""]?.position ?? -1, cb = channels[b.parentId ?? ""]?.position ?? -1
            if ca != cb { return ca < cb }
            return (a.position, a.id) < (b.position, b.id)
        }
    }

    /// Marque un message comme lu. `keepVisible` : il reste affiché, estompé, jusqu'à la fermeture de la fenêtre.
    func markRead(_ message: StoredMessage, keepVisible: Bool) {
        guard let index = unread.firstIndex(where: { $0.id == message.id }) else { return }
        let removed = unread.remove(at: index)
        if keepVisible { recentlyRead.append(removed) }
        NotificationManager.shared.remove(messageIds: [message.id])
        scheduleSave()
    }

    /// Remet un message lu à l'instant dans les non lus.
    func markUnread(_ message: StoredMessage) {
        guard let index = recentlyRead.firstIndex(where: { $0.id == message.id }) else { return }
        let restored = recentlyRead.remove(at: index)
        let position = unread.firstIndex { Snowflake.value($0.id) < Snowflake.value(restored.id) } ?? unread.endIndex
        unread.insert(restored, at: position)
        scheduleSave()
    }

    func markChannelRead(_ channelId: String) {
        let ids = unread.filter { $0.channelId == channelId }.map(\.id)
        unread.removeAll { $0.channelId == channelId }
        recentlyRead.removeAll { $0.channelId == channelId }
        NotificationManager.shared.remove(messageIds: ids)
        scheduleSave()
    }

    func markAllRead() {
        NotificationManager.shared.remove(messageIds: unread.map(\.id))
        unread.removeAll()
        recentlyRead.removeAll()
        scheduleSave()
    }

    /// À la fermeture de la fenêtre : les messages lus disparaissent pour de bon.
    func flushRecentlyRead() {
        guard !recentlyRead.isEmpty else { return }
        recentlyRead.removeAll()
    }

    // MARK: - Réglages des salons

    func setFollowed(_ followed: Bool, channelId: String) {
        var current = prefs[channelId] ?? .new
        current.followed = followed
        prefs[channelId] = current
        if followed {
            // On repart de maintenant, sans importer l'historique du salon.
            lastSeen[channelId] = Snowflake.newest(lastSeen[channelId], channels[channelId]?.lastMessageId) ?? "0"
        } else {
            unread.removeAll { $0.channelId == channelId }
            recentlyRead.removeAll { $0.channelId == channelId }
        }
        scheduleSave()
    }

    func setBanner(_ banner: Bool, channelId: String) {
        var current = prefs[channelId] ?? .new
        current.banner = banner
        prefs[channelId] = current
        if banner { NotificationManager.shared.requestAuthorization() }
        scheduleSave()
    }

    func setIcon(_ icon: ChannelIcon, channelId: String) {
        var current = prefs[channelId] ?? .new
        current.icon = icon
        prefs[channelId] = current
        scheduleSave()
    }

    func icon(for channelId: String) -> ChannelIcon {
        prefs[channelId]?.icon ?? .auto
    }

    struct ChannelGroup: Identifiable {
        let category: Channel?
        let channels: [Channel]
        var id: String { category?.id ?? "" }
    }

    /// Salons textuels d'un serveur, regroupés par catégorie, dans l'ordre de Discord.
    func textChannels(guildId: String) -> [ChannelGroup] {
        let all = channels.values.filter { $0.guildId == guildId }
        let categories = all.filter(\.isCategory).sorted { ($0.position, $0.id) < ($1.position, $1.id) }
        let texts = all.filter(\.isText).sorted { ($0.position, $0.id) < ($1.position, $1.id) }
        var groups: [ChannelGroup] = []
        let loose = texts.filter { $0.parentId == nil || channels[$0.parentId!] == nil }
        if !loose.isEmpty { groups.append(ChannelGroup(category: nil, channels: loose)) }
        for category in categories {
            let children = texts.filter { $0.parentId == category.id }
            if !children.isEmpty { groups.append(ChannelGroup(category: category, channels: children)) }
        }
        return groups
    }

    // MARK: - Enregistrement

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        let state = PersistedState(guilds: guilds, channels: Array(channels.values), prefs: prefs,
                                   lastSeen: lastSeen, unread: unread,
                                   botName: botName)
        Persistence.save(state)
    }
}
