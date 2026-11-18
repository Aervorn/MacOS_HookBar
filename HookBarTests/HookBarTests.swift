import Foundation
import Testing

/// Extrait du catalogue selfh.st, suffisant pour les salons du homelab.
private let references = [
    "adguard-home", "adguardian-term", "adguardhome-sync", "docker", "dockge", "github", "github-copilot",
    "home-assistant", "home-assistant-matter-hub", "jdownloader", "ovh", "network-ups-tools", "nutify",
    "peanut", "proxmox", "proxmox-helper-scripts", "synology", "synology-photos", "zed", "crowdsec",
]

@Suite("Icônes des salons")
struct IconMatcherTests {
    private func match(_ name: String) -> IconMatcher.Match {
        IconMatcher.match(channelName: name, references: references)
    }

    @Test func exactNames() {
        #expect(match("docker") == .selfhst("docker"))
        #expect(match("home-assistant") == .selfhst("home-assistant"))
        #expect(match("synology") == .selfhst("synology"))
        #expect(match("ovh") == .selfhst("ovh"))
        #expect(match("zed") == .selfhst("zed"))
    }

    @Test func variants() {
        #expect(match("ad-guard") == .selfhst("adguard-home"))
        #expect(match("jdownloader2") == .selfhst("jdownloader"))
        #expect(match("proxmmox") == .selfhst("proxmox"))
        #expect(match("Synology DSM") == .selfhst("synology"))
    }

    @Test func aliases() {
        #expect(match("nut") == .selfhst("network-ups-tools"))
        #expect(match("forkwatch") == .selfhst("github"))
    }

    @Test func fallbacks() {
        #expect(match("security") == .symbol("lock.shield"))
        #expect(match("sécurité") == .symbol("lock.shield"))
        #expect(match("bricolage") == .letter("B"))
    }

    @Test func emptyCatalogue() {
        #expect(IconMatcher.match(channelName: "docker", references: []) == .letter("D"))
        #expect(IconMatcher.match(channelName: "security", references: []) == .symbol("lock.shield"))
    }

    @Test func levenshtein() {
        #expect(IconMatcher.levenshtein("proxmmox", "proxmox") == 1)
        #expect(IconMatcher.levenshtein("kitten", "sitting") == 3)
    }
}

@Suite("Identifiants Discord")
struct SnowflakeTests {
    @Test func date() {
        // Exemple de la documentation Discord : 175928847299117063 → 2016-04-30 11:18:25.796 UTC
        let date = Snowflake.date("175928847299117063")
        #expect(abs(date.timeIntervalSince1970 - 1_462_015_105.796) < 0.01)
    }

    @Test func ordering() {
        #expect(Snowflake.isNewer("200", than: "100"))
        #expect(!Snowflake.isNewer("100", than: "200"))
        #expect(Snowflake.newest("100", "200") == "200")
        #expect(Snowflake.newest(nil, "5") == "5")
    }
}

@Suite("Messages Discord")
struct MessageDecodingTests {
    @Test func webhookEmbed() throws {
        let json = """
        {"id":"1300000000000000000","channel_id":"42","guild_id":"7","webhook_id":"99",
         "author":{"id":"99","username":"Uptime Kuma","avatar":"abc","bot":true},
         "content":"","embeds":[{"title":"Nextcloud DOWN","description":"Code **502**","color":15158332,
         "fields":[{"name":"Durée","value":"3 min","inline":true}]}],"attachments":[]}
        """
        let payload = try JSONDecoder.discord.decode(MessagePayload.self, from: Data(json.utf8))
        let message = payload.stored(guildId: nil)
        #expect(message.guildId == "7")
        #expect(message.headline == "Nextcloud DOWN")
        #expect(message.preview == "Code **502**")
        #expect(message.accentColor == 15158332)
        #expect(message.embeds.first?.fields.first?.inline == true)
        #expect(message.link(appScheme: false)?.absoluteString == "https://discord.com/channels/7/42/1300000000000000000")
    }

    @Test func plainText() throws {
        let json = """
        {"id":"1","channel_id":"42","author":{"id":"5","username":"forkwatch"},
         "content":"Sauvegarde OK\\n14 forks synchronisés","embeds":[]}
        """
        let message = try JSONDecoder.discord.decode(MessagePayload.self, from: Data(json.utf8)).stored(guildId: "7")
        #expect(message.headline == "Sauvegarde OK")
        #expect(message.preview == "14 forks synchronisés")
    }

    @Test func partialUpdateKeepsContent() throws {
        let original = try JSONDecoder.discord.decode(MessagePayload.self, from: Data("""
        {"id":"1","channel_id":"42","content":"Bonjour","embeds":[]}
        """.utf8)).stored(guildId: "7")
        let update = try JSONDecoder.discord.decode(MessagePayload.self, from: Data("""
        {"id":"1","channel_id":"42","embeds":[{"title":"Aperçu"}]}
        """.utf8))
        let updated = update.update(original)
        #expect(updated.content == "Bonjour")
        #expect(updated.embeds.first?.title == "Aperçu")
    }
}
