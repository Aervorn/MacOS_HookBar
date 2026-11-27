import AppKit

/// Dessine la cloche et le nombre de non-lus dans une seule image, pour garder le nombre en couleur.
enum MenuBarImage {
    private static let spacing: CGFloat = 3
    private static let height: CGFloat = 18

    static func make(symbol: String, count: Int, countColor rgb: Int) -> NSImage {
        let text = NSAttributedString(string: "\(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize,
                                                    weight: .medium),
            .foregroundColor: color(rgb),
        ])
        let textSize = text.size()
        let bellSize = bell(symbol)?.size ?? .zero
        let size = NSSize(width: ceil(bellSize.width + spacing + textSize.width), height: height)

        let image = NSImage(size: size, flipped: false) { _ in
            // La cloche est colorée ici, au moment du dessin : `labelColor` suit alors
            // l'apparence (claire ou sombre) de l'endroit où l'image est affichée.
            if let bell = bell(symbol) {
                bell.draw(in: NSRect(x: 0, y: (height - bell.size.height) / 2,
                                     width: bell.size.width, height: bell.size.height))
            }
            text.draw(at: NSPoint(x: bellSize.width + spacing, y: (height - textSize.height) / 2))
            return true
        }
        // Pas de cache : l'image est redessinée quand la barre de menus change d'apparence
        image.cacheMode = .never
        image.isTemplate = false
        image.accessibilityDescription = "HookBar : \(count)"
        return image
    }

    private static func bell(_ symbol: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.labelColor, .labelColor]))
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }

    private static func color(_ rgb: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1)
    }
}
