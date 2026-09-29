import SwiftUI
import CoreText

/// Newsreader (serif), Archivo (sans) and IBM Plex Mono, bundled under the OFL (DESIGN §7).
public enum AscentFonts {
    nonisolated(unsafe) private static var registered = false

    /// Registers the bundled fonts for this process. Call once from the app and from the widget extension.
    public static func register() {
        guard !registered else { return }
        registered = true
        for name in ["Newsreader", "Newsreader-Italic", "Archivo", "IBMPlexMono-Regular", "IBMPlexMono-Medium", "IBMPlexMono-SemiBold"] {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension Font {
    /// Newsreader — titles, numerals, section heads.
    public static func serif(_ size: CGFloat, relativeTo style: TextStyle = .title3, italic: Bool = false) -> Font {
        let f = Font.custom("Newsreader", size: size, relativeTo: style)
        return italic ? f.italic() : f
    }

    /// Archivo — body, chips, buttons.
    public static func sans(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: TextStyle = .subheadline) -> Font {
        .custom("Archivo", size: size, relativeTo: style).weight(weight)
    }

    /// IBM Plex Mono — micro labels, data, timers.
    public static func mono(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: TextStyle = .caption) -> Font {
        let name = switch weight {
        case .medium: "IBMPlexMono-Medium"
        case .semibold, .bold, .heavy, .black: "IBMPlexMono-SemiBold"
        default: "IBMPlexMono-Regular"
        }
        return .custom(name, size: size, relativeTo: style)
    }
}

extension View {
    /// Mono caps, +12 % tracking — the "micro" label.
    public func micro(_ color: Color = Palette.muted, size: CGFloat = 10.5) -> some View {
        font(.mono(size, relativeTo: .caption2)).tracking(size * 0.12).textCase(.uppercase).foregroundStyle(color)
    }

    /// Mono caps note on the right of a section head.
    public func note(_ color: Color = Palette.muted) -> some View {
        font(.mono(10, relativeTo: .caption2)).tracking(0.8).textCase(.uppercase).foregroundStyle(color)
    }
}
