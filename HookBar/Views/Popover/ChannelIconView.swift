import SwiftUI

/// Icône d'un salon : icône d'application selfh.st, symbole ou initiale.
struct ChannelIconView: View {
    let channelId: String
    let channelName: String
    var size: CGFloat = 22
    /// Réglage à afficher à la place de celui du salon (aperçu dans le sélecteur).
    var override: ChannelIcon?

    @Environment(AppStore.self) private var store
    @Environment(IconStore.self) private var icons

    var body: some View {
        let match = icons.resolve(override ?? store.icon(for: channelId), channelName: channelName)
        content(match)
            .frame(width: size, height: size)
    }

    @ViewBuilder
    private func content(_ match: IconMatcher.Match) -> some View {
        switch match {
        case .selfhst(let reference):
            if let image = icons.image(reference) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                LetterIcon(letter: IconMatcher.letter(for: channelName), size: size)
            }
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.62, weight: .medium))
                .foregroundStyle(.secondary)
        case .letter(let letter):
            LetterIcon(letter: letter, size: size)
        }
    }
}

/// Initiale dans un cercle (salon sans icône).
struct LetterIcon: View {
    let letter: String
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(.quaternary)
            .overlay {
                Text(verbatim: letter)
                    .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
    }
}
