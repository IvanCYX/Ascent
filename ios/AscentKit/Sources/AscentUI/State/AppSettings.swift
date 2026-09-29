import SwiftUI
import AscentCore

public enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum RequireInterval: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0, oneMinute = 60, fifteenMinutes = 900
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fifteenMinutes: "After 15 minutes"
        }
    }
}

/// Device preferences — not part of the log, never exported. Kept in App Group defaults so widgets read them.
@MainActor
@Observable
public final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults
    /// Called when something widgets draw with changes (accent, privacy lock).
    @ObservationIgnored public var onWidgetRelevantChange: (() -> Void)?

    public var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: SharedKey.appearance) }
    }
    public var accentHex: String {
        didSet { defaults.set(accentHex, forKey: SharedKey.accentHex); onWidgetRelevantChange?() }
    }
    public var faceIDLock: Bool {
        didSet { defaults.set(faceIDLock, forKey: SharedKey.privacyLock); onWidgetRelevantChange?() }
    }
    public var requireInterval: RequireInterval {
        didSet { defaults.set(requireInterval.rawValue, forKey: SharedKey.requireInterval) }
    }

    public init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        appearance = Appearance(rawValue: defaults.string(forKey: SharedKey.appearance) ?? "") ?? .system
        accentHex = defaults.string(forKey: SharedKey.accentHex) ?? ""
        faceIDLock = defaults.bool(forKey: SharedKey.privacyLock)
        requireInterval = RequireInterval(rawValue: defaults.integer(forKey: SharedKey.requireInterval)) ?? .immediately
    }

    public var accent: AccentTheme { AccentTheme(hex: accentHex) }
}
