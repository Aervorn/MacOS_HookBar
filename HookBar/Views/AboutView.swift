import AppKit
import SwiftUI

/// Fenêtre « À propos de HookBar », dans le même style que celles de Vestora et Flux.
struct AboutView: View {
    static let windowID = "about"
    static let repositoryURL = URL(string: "https://github.com/Aervorn/MacOS_HookBar")!
    static let discordDocsURL = URL(string: "https://discord.com/developers/docs")!
    static let selfhstURL = URL(string: "https://selfh.st/icons")!
    static let sparkleURL = URL(string: "https://sparkle-project.org")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .padding(.top, 8)

            Text(verbatim: "HookBar")
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 6)
            Text(verbatim: version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Text("Les messages de tes salons Discord dans la barre de menus de macOS, sans ouvrir Discord.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Divider().padding(.vertical, 16)

            VStack(spacing: 6) {
                Text("Créé par Aervorn, avec l'aide de Claude.")
                HStack(spacing: 4) {
                    Text("Messages :")
                    Link(destination: Self.discordDocsURL) { Text(verbatim: "API Discord") }
                    Text(verbatim: "·")
                    Text("Icônes :")
                    Link(destination: Self.selfhstURL) { Text(verbatim: "selfh.st") }
                    Text(verbatim: "(CC BY 4.0)")
                }
                HStack(spacing: 4) {
                    Text("Mises à jour :")
                    Link(destination: Self.sparkleURL) { Text(verbatim: "Sparkle") }
                    Text(verbatim: "(MIT)")
                }
                Text("HookBar n'est ni affilié à Discord, ni approuvé par Discord.")
                    .padding(.top, 4)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Link(destination: Self.repositoryURL) {
                Label("Code source sur GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .font(.callout)
            .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .padding(.top, 12)
        .frame(width: 360)
    }
}
