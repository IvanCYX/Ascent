import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

/// Archivo (bundled under the OFL) drawn at 125 % width for numbers; everything else is SF Pro (DESIGN §7.3).
public enum AscentFonts {
    nonisolated(unsafe) private static var registered = false

    /// Registers the bundled font for this process. Call once from the app and from the widget extension.
    public static func register() {
        guard !registered else { return }
        registered = true
        if let url = Bundle.module.url(forResource: "Archivo", withExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.module.url(forResource: "Archivo", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// 'wght' and 'wdth' as OpenType axis tags.
    static let weightAxis = 0x7767_6874, widthAxis = 0x7764_7468

    /// Archivo at a given weight (100–900) and width (62–125), straight from the variable font's axes.
    static func archivo(size: CGFloat, weight: CGFloat, width: CGFloat) -> CTFont {
        let base = CTFontDescriptorCreateWithNameAndSize("Archivo-SemiBold" as CFString, size)
        let weighted = CTFontDescriptorCreateCopyWithVariation(base, weightAxis as CFNumber, weight)
        let wide = CTFontDescriptorCreateCopyWithVariation(weighted, widthAxis as CFNumber, width)
        return CTFontCreateWithFontDescriptor(wide, size, nil)
    }

    /// Scales a design size with Dynamic Type, like `relativeTo:` does for text styles.
    static func scaled(_ size: CGFloat, relativeTo style: Font.TextStyle) -> CGFloat {
        #if canImport(UIKit)
        UIFontMetrics(forTextStyle: style.uiStyle).scaledValue(for: size)
        #else
        size
        #endif
    }
}

extension Font.TextStyle {
    /// The text style SF Pro uses at a design size, so custom sizes still follow Dynamic Type.
    static func nearest(to size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: .largeTitle
        case 25..<30: .title
        case 21..<25: .title2
        case 18.5..<21: .title3
        case 16.5..<18.5: .body
        case 15.5..<16.5: .callout
        case 14..<15.5: .subheadline
        case 12.5..<14: .footnote
        case 11.5..<12.5: .caption
        default: .caption2
        }
    }

    #if canImport(UIKit)
    var uiStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
    }
    #endif
}

extension Font {
    /// SF Pro at the text style nearest the design size (34 large title, 17 body, 15 subheadline, 13 footnote…).
    public static func sans(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: TextStyle? = nil) -> Font {
        .system(style ?? .nearest(to: size), design: .default, weight: weight)
    }

    /// Archivo bold at 125 % width — every number that matters (DESIGN §7.3).
    public static func num(_ size: CGFloat, _ weight: CGFloat = 700, relativeTo style: TextStyle? = nil) -> Font {
        let s = AscentFonts.scaled(size, relativeTo: style ?? .nearest(to: size))
        return Font(AscentFonts.archivo(size: s, weight: weight, width: 125)).monospacedDigit()
    }

    /// Big numerals, titles' counterpart. Kept for older call sites: now the wide Archivo.
    public static func serif(_ size: CGFloat, relativeTo style: TextStyle = .title3, italic: Bool = false) -> Font {
        num(size, relativeTo: style)
    }

    /// Small data text: SF Pro with tabular digits.
    public static func mono(_ size: CGFloat, _ weight: Weight = .regular, relativeTo style: TextStyle? = nil) -> Font {
        sans(size, weight == .regular ? .medium : weight, relativeTo: style).monospacedDigit()
    }
}

extension View {
    /// A small section label: sentence case, secondary, semibold (r3 drops the mono caps micro label).
    public func micro(_ color: Color = Palette.secondary, size: CGFloat = 13) -> some View {
        font(.sans(size, .semibold)).foregroundStyle(color)
    }

    /// The secondary note on the right of a section head.
    public func note(_ color: Color = Palette.secondary) -> some View {
        font(.sans(13)).foregroundStyle(color)
    }
}
