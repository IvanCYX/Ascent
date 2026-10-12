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

/// r3 tokens (DESIGN §7): near-black neutral greys in dark, warm stone in light. Hold colours stay the only rainbow.
nonisolated public enum Palette {
    public static let groundLight = RGB(hex: "#f5f5f4")!, groundDark = RGB(hex: "#0a0a0a")!
    public static let surfaceLight = RGB(hex: "#ffffff")!, surfaceDark = RGB(hex: "#161616")!
    public static let textLight = RGB(hex: "#0e1013")!, textDark = RGB(hex: "#f2f3f5")!
    public static let injuryLight = RGB(hex: "#c0392b")!, injuryDark = RGB(hex: "#e5594c")!
    public static let cautionLight = RGB(hex: "#b86e00")!, cautionDark = RGB(hex: "#f5a524")!

    /// Screen background
    public static let ground = Color.dynamic(light: groundLight, dark: groundDark)
    /// Cards, widgets, the Live Activity
    public static let surface = Color.dynamic(light: surfaceLight, dark: surfaceDark)
    /// Segments, grade tiles, inputs, insight rows
    public static let raised = Color.dynamic(light: RGB(hex: "#ecebe8")!, dark: RGB(hex: "#1f1f1f")!)
    /// Empty ring and bar tracks
    public static let track = Color.dynamic(light: RGB(hex: "#e7e6e3")!, dark: RGB(hex: "#262626")!)
    /// Quick-add tiles, the toast
    public static let tile = Color.dynamic(light: RGB(hex: "#ecebe8")!, dark: RGB(hex: "#2a2a2a")!)
    /// The log sheet
    public static let sheet = Color.dynamic(light: RGB(hex: "#fafaf9")!, dark: RGB(hex: "#121212")!)
    /// The selected segment
    public static let segment = Color.dynamic(light: RGB(hex: "#ffffff")!, dark: RGB(hex: "#3a3a3a")!)
    public static let text = Color.dynamic(light: textLight, dark: textDark)
    public static let secondary = Color.dynamic(light: RGB(hex: "#5f5e5a")!, dark: RGB(hex: "#a1a1a1")!)
    public static let tertiary = Color.dynamic(light: RGB(hex: "#a3a29c")!, dark: RGB(hex: "#6e6e6e")!)
    /// Row separators inside cards only
    public static let hairline = Color.dynamic(light: textLight, dark: textDark, lightAlpha: 0.07, darkAlpha: 0.07)
    public static let hairlineStrong = Color.dynamic(light: textLight, dark: textDark, lightAlpha: 0.16, darkAlpha: 0.2)
    /// Non-max bars where the accent would be too loud
    public static let worked = Color.dynamic(light: textLight, dark: textDark, lightAlpha: 0.18, darkAlpha: 0.22)
    /// Amber: spiking load, rising pain, worse deltas, readiness under 55, watching injuries
    public static let caution = Color.dynamic(light: cautionLight, dark: cautionDark)
    public static let cautionText = Color.dynamic(light: cautionLight, dark: RGB(hex: "#f5b850")!)
    public static let cautionBg = Color.dynamic(light: cautionLight, dark: cautionDark, lightAlpha: 0.1, darkAlpha: 0.16)
    /// Injury red: anything body or warning
    public static let injury = Color.dynamic(light: injuryLight, dark: injuryDark)
    public static let injuryText = Color.dynamic(light: RGB(hex: "#a8301f")!, dark: RGB(hex: "#f08a80")!)
    public static let injuryBg = Color.dynamic(light: injuryLight, dark: injuryDark, lightAlpha: 0.08, darkAlpha: 0.14)
    public static let injuryBorder = Color.dynamic(light: injuryLight, dark: injuryDark, lightAlpha: 0.4, darkAlpha: 0.5)
    public static let injurySoft = Color.dynamic(light: injuryLight, dark: injuryDark, lightAlpha: 0.3, darkAlpha: 0.35)
    public static let injuryMid = Color.dynamic(light: injuryLight, dark: injuryDark, lightAlpha: 0.6, darkAlpha: 0.6)

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
        if isInk { return dark ? Palette.textDark : Palette.textLight }
        let base = RGB(hex: hex)!
        let paper = dark ? Palette.surfaceDark : Palette.surfaceLight
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

    /// Dark text on a light accent, otherwise white (Ink itself takes the ground colour).
    public var onAccent: Color {
        if isInk { return Palette.ground }
        let l = resolved(dark: false), d = resolved(dark: true)
        return .dynamic(light: l.luminance > 0.42 ? Palette.textLight : RGB(1, 1, 1),
                        dark: d.luminance > 0.42 ? Palette.textLight : RGB(1, 1, 1))
    }

    /// CIEDE2000 against the injury red below 20 → the red footer in Settings.
    public var isNearInjuryRed: Bool {
        guard !isInk, let c = RGB(hex: hex) else { return false }
        return c.deltaE2000(Palette.injuryLight) < 20
    }

    /// CIEDE2000 against the caution amber below 20 → the amber footer in Settings.
    public var isNearCaution: Bool {
        guard !isInk, let c = RGB(hex: hex) else { return false }
        return c.deltaE2000(Palette.cautionLight) < 20 || c.deltaE2000(Palette.cautionDark) < 20
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
