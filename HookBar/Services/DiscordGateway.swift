import Foundation
import Network

/// Connexion temps réel au Gateway de Discord (WebSocket), avec le jeton du bot.
///
/// Discord envoie un « Hello » avec l'intervalle de battement de cœur ; l'app s'identifie,
/// puis reçoit les événements (serveurs, salons, messages). En cas de coupure, elle se
/// reconnecte avec une attente croissante ; l'app rattrape ensuite les messages manqués par l'API REST.
/// Sans réseau, ou après plusieurs échecs de suite, elle se déclare injoignable.
@MainActor
final class DiscordGateway {
    enum Event {
        case ready(ReadyPayload)
        case guildCreate(GuildPayload)
        case guildDelete(String)
        case channelUpsert(ChannelPayload)
        case channelDelete(String)
        case messageCreate(MessagePayload)
        case messageUpdate(MessagePayload)
        case messageDelete(DeletedMessagePayload)
    }

    enum State: Equatable {
        case disconnected
        case connecting
        case connected
        /// Pas de réseau, ou Discord ne répond pas (les essais continuent dès que possible)
        case unreachable
        case failed(String)
    }

    /// GUILDS (1 << 0), GUILD_MESSAGES (1 << 9), MESSAGE_CONTENT (1 << 15)
    static let intents = (1 << 0) | (1 << 9) | (1 << 15)
    private static let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json")!
    /// Nombre d'échecs de suite à partir duquel Discord est considéré comme injoignable.
    private static let failuresBeforeUnreachable = 3
    /// Durée maximale d'une tentative : sans « READY » dans ce délai, elle est abandonnée.
    private static let connectTimeout: UInt64 = 10_000_000_000

    var onEvent: ((Event) -> Void)?
    var onState: ((State) -> Void)?

    private var token = ""
    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var networkAvailable = true
    /// Change à chaque nouvelle connexion : les tâches d'une ancienne connexion s'arrêtent d'elles-mêmes.
    private var generation = 0
    private var sequence: Int?
    private var heartbeatAcknowledged = true
    private var attempts = 0
    private var stopped = true

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status != .unsatisfied
            MainActor.assumeIsolated { self?.networkChanged(available: available) }
        }
        // File principale : les changements arrivent dans l'ordre, sur le MainActor
        pathMonitor.start(queue: .main)
    }

    func connect(token: String) {
        tearDown()
        self.token = token
        stopped = false
        attempts = 0
        open()
    }

    func stop() {
        stopped = true
        tearDown()
        onState?(.disconnected)
    }

    /// Reconnexion immédiate (bouton Actualiser, sortie de veille).
    func reconnectNow() {
        guard !stopped, !token.isEmpty else { return }
        tearDown()
        attempts = 0
        open()
    }

    private func tearDown() {
        generation += 1
        heartbeatTask?.cancel()
        receiveTask?.cancel()
        reconnectTask?.cancel()
        timeoutTask?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func open() {
        // Sans réseau, inutile d'essayer : `networkChanged` relancera la connexion
        guard networkAvailable else {
            onState?(.unreachable)
            return
        }
        generation += 1
        let current = generation
        sequence = nil
        // Les essais automatiques qui suivent plusieurs échecs restent affichés « hors ligne »
        if attempts < Self.failuresBeforeUnreachable { onState?(.connecting) }
        let task = URLSession.shared.webSocketTask(with: Self.url)
        // GUILD_CREATE contient tous les salons du serveur : plus que la limite par défaut (1 Mo).
        task.maximumMessageSize = 16 * 1024 * 1024
        self.task = task
        task.resume()
        receiveTask = Task { [weak self] in
            await self?.receive(from: task, generation: current)
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.connectTimeout)
            guard let self, !Task.isCancelled, current == self.generation else { return }
            self.scheduleReconnect(after: 2)
        }
    }

    private func receive(from task: URLSessionWebSocketTask, generation current: Int) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                guard current == generation else { return }
                switch message {
                case .string(let text): handle(Data(text.utf8), generation: current)
                case .data(let data): handle(data, generation: current)
                @unknown default: break
                }
            } catch {
                guard current == generation, !stopped else { return }
                let reason = task.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                handleClose(code: task.closeCode.rawValue, reason: reason)
                return
            }
        }
    }

    private func handle(_ data: Data, generation current: Int) {
        guard let frame = try? JSONDecoder.discord.decode(GatewayFrame.self, from: data) else { return }
        if let s = frame.s { sequence = s }
        switch frame.op {
        case 10: // Hello
            guard let hello = try? JSONDecoder.discord.decode(GatewayEnvelope<HelloPayload>.self, from: data) else { return }
            startHeartbeat(milliseconds: hello.d.heartbeatInterval, generation: current)
            identify()
        case 11: // Heartbeat ACK
            heartbeatAcknowledged = true
        case 1: // Heartbeat demandé par Discord
            sendHeartbeat()
        case 7: // Reconnect
            scheduleReconnect(after: 1)
        case 9: // Invalid Session
            scheduleReconnect(after: 3)
        case 0:
            dispatch(type: frame.t ?? "", data: data)
        default:
            break
        }
    }

    private func dispatch(type: String, data: Data) {
        let decoder = JSONDecoder.discord
        func decode<T: Decodable>(_: T.Type) -> T? {
            try? decoder.decode(GatewayEnvelope<T>.self, from: data).d
        }
        switch type {
        case "READY":
            guard let ready = decode(ReadyPayload.self) else { return }
            attempts = 0
            timeoutTask?.cancel()
            onState?(.connected)
            onEvent?(.ready(ready))
        case "GUILD_CREATE", "GUILD_UPDATE":
            if let guild = decode(GuildPayload.self) { onEvent?(.guildCreate(guild)) }
        case "GUILD_DELETE":
            if let guild = decode(GuildPayload.self) { onEvent?(.guildDelete(guild.id)) }
        case "CHANNEL_CREATE", "CHANNEL_UPDATE":
            if let channel = decode(ChannelPayload.self) { onEvent?(.channelUpsert(channel)) }
        case "CHANNEL_DELETE":
            if let channel = decode(ChannelPayload.self) { onEvent?(.channelDelete(channel.id)) }
        case "MESSAGE_CREATE":
            if let message = decode(MessagePayload.self) { onEvent?(.messageCreate(message)) }
        case "MESSAGE_UPDATE":
            if let message = decode(MessagePayload.self) { onEvent?(.messageUpdate(message)) }
        case "MESSAGE_DELETE":
            if let message = decode(DeletedMessagePayload.self) { onEvent?(.messageDelete(message)) }
        default:
            break
        }
    }

    // MARK: - Envoi

    private func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func identify() {
        send([
            "op": 2,
            "d": [
                "token": token,
                "intents": Self.intents,
                "properties": ["os": "macos", "browser": "HookBar", "device": "HookBar"],
            ] as [String: Any],
        ])
    }

    private func sendHeartbeat() {
        send(["op": 1, "d": sequence.map { $0 as Any } ?? NSNull()])
    }

    private func startHeartbeat(milliseconds: Int, generation current: Int) {
        heartbeatTask?.cancel()
        heartbeatAcknowledged = true
        let interval = UInt64(milliseconds) * 1_000_000
        heartbeatTask = Task { [weak self] in
            // Premier battement après un délai aléatoire, comme le demande Discord
            try? await Task.sleep(nanoseconds: UInt64(Double(interval) * Double.random(in: 0.1...1)))
            while !Task.isCancelled {
                guard let self, current == self.generation else { return }
                if !self.heartbeatAcknowledged {
                    // Pas de réponse au battement précédent : connexion morte
                    self.scheduleReconnect(after: 1)
                    return
                }
                self.heartbeatAcknowledged = false
                self.sendHeartbeat()
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    // MARK: - Coupures

    /// Réseau perdu : on s'arrête tout de suite. Réseau revenu : on se reconnecte sans attendre.
    private func networkChanged(available: Bool) {
        guard available != networkAvailable else { return }
        networkAvailable = available
        guard !stopped else { return }
        if available {
            attempts = 0
            open()
        } else {
            tearDown()
            onState?(.unreachable)
        }
    }

    private func handleClose(code: Int, reason: String) {
        if code == 4004 || reason.localizedCaseInsensitiveContains("authentication") {
            stopped = true
            tearDown()
            onState?(.failed(String(localized: "Discord a refusé le jeton du bot. Vérifie-le dans les Réglages.")))
            return
        }
        if code == 4014 || reason.localizedCaseInsensitiveContains("disallowed intent") {
            stopped = true
            tearDown()
            onState?(.failed(String(localized: "Active « Message Content Intent » dans l'onglet Bot du portail développeur Discord.")))
            return
        }
        scheduleReconnect(after: 2)
    }

    private func scheduleReconnect(after seconds: Double) {
        tearDown()
        guard !stopped else { return }
        attempts += 1
        let delay = min(60, seconds * pow(2, Double(max(0, attempts - 1))))
        onState?(attempts < Self.failuresBeforeUnreachable ? .connecting : .unreachable)
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled, !self.stopped else { return }
            self.open()
        }
    }
}
