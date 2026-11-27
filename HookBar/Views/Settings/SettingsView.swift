import SwiftUI

/// Fenêtre des Réglages : bot, salons suivis, comportement et apparence.
struct SettingsView: View {
    static let windowID = "settings"
    static let developerPortalURL = URL(string: "https://discord.com/developers/applications")!

    @Environment(AppStore.self) private var store
    @Environment(IconStore.self) private var icons
    @Environment(AppPreferences.self) private var preferences
    @Environment(AppUpdater.self) private var updater

    @State private var token = ""
    @State private var pickingIcon: Channel?

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            botSection

            if store.guilds.isEmpty {
                Section("Salons") {
                    Text("Les salons de ton serveur apparaîtront ici une fois le bot connecté.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(store.guilds) { guild in
                    channelsSection(guild)
                }
            }

            Section("Comportement") {
                Toggle("Marquer comme lu en cliquant sur un message", isOn: $preferences.markReadOnClick)
                Toggle("Suivre automatiquement les nouveaux salons", isOn: $preferences.autoFollowNewChannels)
                Toggle("Ouvrir HookBar à l'ouverture de session", isOn: $preferences.launchAtLogin)
            }

            Section("Apparence") {
                Picker("Thème", selection: $preferences.appearance) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Picker("Langue", selection: $preferences.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                Toggle("Nombre de non-lus en couleur dans la barre de menus", isOn: $preferences.colorUnreadCount)
                if preferences.colorUnreadCount {
                    ColorPicker("Couleur du nombre", selection: unreadColorBinding, supportsOpacity: false)
                    if preferences.unreadCountColor != AppPreferences.defaultUnreadCountColor {
                        Button("Revenir à la couleur par défaut") {
                            preferences.unreadCountColor = AppPreferences.defaultUnreadCountColor
                        }
                    }
                }
                if preferences.language != preferences.launchLanguage {
                    HStack {
                        Text("La nouvelle langue s'appliquera au prochain lancement.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Relancer") { preferences.relaunch() }
                    }
                }
            }

            Section("Mises à jour") {
                LabeledContent("Version installée") {
                    Text(verbatim: updater.currentVersion)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if updater.isEnabled {
                    Toggle("Rechercher automatiquement chaque jour", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    Button("Rechercher les mises à jour…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                } else {
                    Text("Les mises à jour automatiques sont désactivées dans les versions de développement.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Données") {
                HStack {
                    Button("Tout marquer comme lu") { store.markAllRead() }
                        .disabled(store.unreadCount == 0)
                    Button("Vider le cache des icônes") { icons.clearCache() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 660)
        .sheet(item: $pickingIcon) { channel in
            IconPicker(channel: channel)
                .environment(store)
                .environment(icons)
        }
        .onAppear {
            token = Keychain.read(Keychain.Account.botToken) ?? ""
        }
    }

    // MARK: - Apparence

    /// Le sélecteur travaille avec une `Color`, la préférence est un entier 0xRRGGBB.
    private var unreadColorBinding: Binding<Color> {
        Binding(
            get: { Color(rgb: preferences.unreadCountColor) },
            set: { color in
                guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                // Bornage : un écran à large gamut peut donner des composantes hors de 0…1
                func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
                preferences.unreadCountColor = byte(srgb.redComponent) << 16
                    | byte(srgb.greenComponent) << 8
                    | byte(srgb.blueComponent)
            }
        )
    }

    // MARK: - Bot

    private var botSection: some View {
        Section {
            SecureField("Jeton du bot", text: $token, prompt: Text("Colle le jeton de ton bot"))
                .onSubmit { store.updateToken(token) }
            HStack {
                connectionStatus
                Spacer()
                Button("Enregistrer et se connecter") { store.updateToken(token) }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty && !store.hasToken)
            }
        } header: {
            Text("Bot Discord")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Le jeton reste dans le trousseau de ton Mac. Dans l'onglet Bot du portail développeur, active « Message Content Intent » et invite le bot sur ton serveur.")
                Link("Ouvrir le portail développeur Discord", destination: Self.developerPortalURL)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        switch store.connection {
        case .connected:
            Label {
                if let name = store.botName {
                    Text("Connecté : \(name)")
                } else {
                    Text("Connecté")
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .connecting:
            Label("Connexion…", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        case .offline:
            Label("Déconnecté", systemImage: "wifi.slash")
                .foregroundStyle(.secondary)
        case .noToken:
            Label("Aucun jeton", systemImage: "key")
                .foregroundStyle(.secondary)
        case .failed(let message):
            Label {
                Text(verbatim: message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
        }
    }

    // MARK: - Salons

    private func channelsSection(_ guild: Guild) -> some View {
        Section {
            ForEach(store.textChannels(guildId: guild.id)) { group in
                if let category = group.category {
                    Text(verbatim: category.name.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(group.channels) { channel in
                    channelRow(channel)
                }
            }
        } header: {
            HStack {
                Text(verbatim: guild.name)
                Spacer()
                Text("Bannière")
                    .frame(width: 60)
                Text("Suivi")
                    .frame(width: 44)
            }
        } footer: {
            Text("Clique sur une icône pour la changer. Les bannières macOS ne concernent que les salons cochés.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func channelRow(_ channel: Channel) -> some View {
        let prefs = store.prefs[channel.id] ?? .new
        return HStack(spacing: 10) {
            Button {
                pickingIcon = channel
            } label: {
                ChannelIconView(channelId: channel.id, channelName: channel.name, size: 22)
            }
            .buttonStyle(.plain)
            .help(Text("Changer l'icône"))

            Text(verbatim: "#\(channel.name)")
                .foregroundStyle(prefs.followed ? .primary : .secondary)
            Spacer()

            Toggle(isOn: Binding(get: { prefs.banner },
                                 set: { store.setBanner($0, channelId: channel.id) })) {
                Image(systemName: prefs.banner ? "bell.fill" : "bell.slash")
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .disabled(!prefs.followed)
            .frame(width: 60)
            .help(Text("Bannière macOS pour chaque nouveau message"))

            Toggle("Suivi", isOn: Binding(get: { prefs.followed },
                                          set: { store.setFollowed($0, channelId: channel.id) }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .frame(width: 44)
        }
    }
}
