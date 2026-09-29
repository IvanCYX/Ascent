import SwiftUI
import AscentCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// sRGB colour with the maths the accent rules need (DESIGN §4, §7).
nonisolated public struct RGB: Hashable, Sendable {
    public var r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
    }

    public var hex: String {
        String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    static func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }

    /// WCAG relative luminance
    public var luminance: Double { 0.2126 * Self.lin(r) + 0.7152 * Self.lin(g) + 0.0722 * Self.lin(b) }

    public func contrast(with other: RGB) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    /// CIE L*a*b* (D65)
    var lab: (l: Double, a: Double, b: Double) {
        let R = Self.lin(r), G = Self.lin(g), B = Self.lin(b)
        var x = (R * 0.4124 + G * 0.3576 + B * 0.1805) / 0.95047
        var y = R * 0.2126 + G * 0.7152 + B * 0.0722
        var z = (R * 0.0193 + G * 0.1192 + B * 0.9505) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16 / 116 }
        x = f(x); y = f(y); z = f(z)
        return (116 * y - 16, 500 * (x - y), 200 * (y - z))
    }

    /// CIEDE2000 colour difference.
    public func deltaE2000(_ other: RGB) -> Double {
        let (l1, a1, b1) = lab, (l2, a2, b2) = other.lab
        let rad = Double.pi / 180
        let c1 = hypot(a1, b1), c2 = hypot(a2, b2)
        let cBar = (c1 + c2) / 2
        let g = 0.5 * (1 - sqrt(pow(cBar, 7) / (pow(cBar, 7) + pow(25, 7))))
        let a1p = (1 + g) * a1, a2p = (1 + g) * a2
        let c1p = hypot(a1p, b1), c2p = hypot(a2p, b2)
        func hue(_ b: Double, _ a: Double) -> Double {
            if a == 0 && b == 0 { return 0 }
            let h = atan2(b, a) / rad
            return h >= 0 ? h : h + 360
        }
        let h1p = hue(b1, a1p), h2p = hue(b2, a2p)
        let dLp = l2 - l1, dCp = c2p - c1p
        var dhp = 0.0
        if c1p * c2p != 0 {
            dhp = h2p - h1p
            if dhp > 180 { dhp -= 360 } else if dhp < -180 { dhp += 360 }
        }
        let dHp = 2 * sqrt(c1p * c2p) * sin(dhp / 2 * rad)
        let lBarp = (l1 + l2) / 2, cBarp = (c1p + c2p) / 2
        var hBarp = h1p + h2p
        if c1p * c2p != 0 {
            if abs(h1p - h2p) > 180 { hBarp += h1p + h2p < 360 ? 360 : -360 }
            hBarp /= 2
        }
        let t = 1 - 0.17 * cos((hBarp - 30) * rad) + 0.24 * cos(2 * hBarp * rad)
            + 0.32 * cos((3 * hBarp + 6) * rad) - 0.2 * cos((4 * hBarp - 63) * rad)
        let dTheta = 30 * exp(-pow((hBarp - 275) / 25, 2))
        let rc = 2 * sqrt(pow(cBarp, 7) / (pow(cBarp, 7) + pow(25, 7)))
        let sl = 1 + 0.015 * pow(lBarp - 50, 2) / sqrt(20 + pow(lBarp - 50, 2))
        let sc = 1 + 0.045 * cBarp, sh = 1 + 0.015 * cBarp * t
        let rt = -sin(2 * dTheta * rad) * rc
        return sqrt(pow(dLp / sl, 2) + pow(dCp / sc, 2) + pow(dHp / sh, 2) + rt * (dCp / sc) * (dHp / sh))
    }
}

nonisolated extension Color {
    /// A colour that follows the current appearance (light/dark), in apps and widgets.
    public static func dynamic(light: RGB, dark: RGB, lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
        #if canImport(UIKit)
        Color(UIColor { t in
            let c = t.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: t.userInterfaceStyle == .dark ? darkAlpha : lightAlpha)
        })
        #else
        Color(NSColor(name: nil) { a in
            let dark_ = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = dark_ ? dark : light
            return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: dark_ ? darkAlpha : lightAlpha)
        })
        #endif
    }

    public init(hex: String) {
        self = (RGB(hex: hex) ?? RGB(0, 0, 0)).color
    }
}

/// The paper palette, light and dark (DESIGN §7). Ink is the only data colour until the user picks an accent.
nonisolated public enum Palette {
    public static let paperLight = RGB(hex: "#f5f2ea")!, paperDark = RGB(hex: "#12110e")!
    public static let inkLight = RGB(hex: "#17150f")!, inkDark = RGB(hex: "#ece6d8")!
    public static let warnLight = RGB(hex: "#c0392b")!, warnDark = RGB(hex: "#e5594c")!

    public static let paper = Color.dynamic(light: paperLight, dark: paperDark)
    public static let card = Color.dynamic(light: RGB(hex: "#ffffff")!, dark: RGB(hex: "#1d1b17")!)
    public static let ink = Color.dynamic(light: inkLight, dark: inkDark)
    public static let muted = Color.dynamic(light: RGB(hex: "#6f6a5e")!, dark: RGB(hex: "#a39c8c")!)
    public static let faint = Color.dynamic(light: RGB(hex: "#a09a8c")!, dark: RGB(hex: "#6e6859")!)
    public static let rule = Color.dynamic(light: inkLight, dark: inkDark, lightAlpha: 0.12, darkAlpha: 0.12)
    public static let ruleStrong = Color.dynamic(light: inkLight, dark: inkDark, lightAlpha: 0.22, darkAlpha: 0.24)
    public static let ruleChip = Color.dynamic(light: inkLight, dark: inkDark, lightAlpha: 0.16, darkAlpha: 0.18)
    public static let track = Color.dynamic(light: inkLight, dark: inkDark, lightAlpha: 0.06, darkAlpha: 0.07)
    public static let worked = Color.dynamic(light: inkLight, dark: inkDark, lightAlpha: 0.20, darkAlpha: 0.26)
    public static let warn = Color.dynamic(light: warnLight, dark: warnDark)
    public static let warnBg = Color.dynamic(light: warnLight, dark: warnDark, lightAlpha: 0.07, darkAlpha: 0.12)
    public static let warnBorder = Color.dynamic(light: warnLight, dark: warnDark, lightAlpha: 0.40, darkAlpha: 0.50)
    public static let warnSoft = Color.dynamic(light: warnLight, dark: warnDark, lightAlpha: 0.28, darkAlpha: 0.30)
    public static let warnMid = Color.dynamic(light: warnLight, dark: warnDark, lightAlpha: 0.55, darkAlpha: 0.60)
    public static let watch = Color(hex: "#f2c744")
    public static let grouped = Color.dynamic(light: RGB(hex: "#ece8de")!, dark: RGB(hex: "#0d0c0a")!)
    public static let groupedRow = Color.dynamic(light: RGB(hex: "#fbfaf6")!, dark: RGB(hex: "#1d1b17")!)

    public static func hold(_ id: String?) -> Color { Color(hex: Vocab.colourHex(id) ?? "#00000020") }
    public static func needsHairline(_ id: String?) -> Bool { id == "white" || id == "black" }
}

/// The user accent, resolved for both schemes (DESIGN §4).
nonisolated public struct AccentTheme: Hashable, Sendable {
    public static let presets: [(name: String, hex: String)] = [
        ("Ink", ""), ("Moss", "#4a6b3a"), ("Cobalt", "#2c55c7"), ("Ochre", "#b07a12"), ("Plum", "#7a3f73"),
    ]

    /// empty = Ink
    public var hex: String

    public init(hex: String) { self.hex = hex }

    public var isInk: Bool { hex.isEmpty || RGB(hex: hex) == nil }

    public var name: String {
        if isInk { return "Ink" }
        return Self.presets.first { $0.hex.lowercased() == hex.lowercased() }?.name ?? "Custom"
    }

    /// Lift in dark, darken in light, until contrast against paper is at least 3:1.
    public func resolved(dark: Bool) -> RGB {
        if isInk { return dark ? Palette.inkDark : Palette.inkLight }
        let base = RGB(hex: hex)!
        let paper = dark ? Palette.paperDark : Palette.paperLight
        let toward = dark ? RGB(1, 1, 1) : RGB(0, 0, 0)
        var c = base
        var t = 0.0
        while c.contrast(with: paper) < 3 && t < 1 {
            t += 0.04
            c = base.mixed(with: toward, t)
        }
        return c
    }

    public var color: Color {
        .dynamic(light: resolved(dark: false), dark: resolved(dark: true))
    }

    /// ink when the accent is light, otherwise white (Ink itself takes paper, like the web's primary button).
    public var onAccent: Color {
        if isInk { return Palette.paper }
        let l = resolved(dark: false), d = resolved(dark: true)
        return .dynamic(light: l.luminance > 0.42 ? Palette.inkLight : RGB(1, 1, 1),
                        dark: d.luminance > 0.42 ? Palette.inkLight : RGB(1, 1, 1))
    }

    /// CIEDE2000 against the injury red below 20 → the red footer in Settings.
    public var isNearInjuryRed: Bool {
        guard !isInk, let c = RGB(hex: hex) else { return false }
        return c.deltaE2000(Palette.warnLight) < 20
    }
}

private struct AccentKey: EnvironmentKey {
    static let defaultValue = AccentTheme(hex: "")
}

extension EnvironmentValues {
    public var accent: AccentTheme {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
