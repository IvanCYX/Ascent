#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
import AscentCore
import AscentUI

/// The session Live Activity (DESIGN §2, frames 1.7–1.9).
/// Buttons are links into the app (`ascent://log`, `ascent://end`), which is what `openAppWhenRun` intents would do.
public struct LiveSessionActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSessionAttributes.self) { context in
            LockScreenLiveView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Palette.surface)
                .activitySystemActionForegroundColor(Palette.text)
                .environment(\.accent, SharedAccent.current)
        } dynamicIsland: { context in
            let s = context.state
            let accent = SharedAccent.current
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Live · \(s.gymName)", systemImage: "hand.raised.fingers.spread.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent.color)
                        if let intent = s.intent { Text(intent).font(.system(size: 13)).opacity(0.7) }
                    }
                    .privacySensitive(s.privacyLock)
                    .island()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false)
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(accent.color)
                        .multilineTextAlignment(.trailing).lineLimit(1).minimumScaleFactor(0.6)
                        .island()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // The expanded island is capped at about 160 pt, so this stays tight.
                    VStack(spacing: 10) {
                        HStack(spacing: 22) {
                            stat("\(s.sends)", "sends")
                            stat(s.high, "high").privacySensitive(s.privacyLock)
                            stat("\(s.flashed)", "flashed").privacySensitive(s.privacyLock)
                            Spacer()
                        }
                        LiveButtons(accent: accent, height: 36)
                    }
                    .island()
                }
            } compactLeading: {
                HStack(spacing: 5) {
                    Image(systemName: "hand.raised.fingers.spread.fill").foregroundStyle(accent.color)
                    Text(s.high).font(.system(size: 15, weight: .bold)).privacySensitive(s.privacyLock)
                }
                .island()
            } compactTrailing: {
                Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(accent.color)
                    .frame(maxWidth: 64)
                    .island()
            } minimal: {
                Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(accent.color)
                    .island()
            }
            .widgetURL(URL(string: "ascent://log"))
            .keylineTint(accent.resolved(dark: true).color)
        }
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.system(size: 20, weight: .bold))
            Text(l).font(.system(size: 11, weight: .medium)).opacity(0.6)
        }
    }
}

private extension View {
    /// The island is always black, so resolve the accent and text tokens as dark whatever the system appearance.
    func island() -> some View { environment(\.colorScheme, .dark) }
}

struct LiveButtons: View {
    var accent: AccentTheme
    var height: CGFloat = 44
    var body: some View {
        HStack(spacing: 8) {
            Link(destination: URL(string: "ascent://log")!) {
                Text("Log a send").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent.onAccent)
                    .frame(maxWidth: .infinity, minHeight: height).background(Capsule().fill(accent.color))
            }
            Link(destination: URL(string: "ascent://end")!) {
                Text("End session").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, minHeight: height).background(Capsule().fill(Palette.text.opacity(0.12)))
            }
        }
    }
}

/// The Lock Screen card (DESIGN §8).
struct LockScreenLiveView: View {
    @Environment(\.accent) private var accent
    var state: LiveSessionState
    var stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(accent.color).frame(width: 6, height: 6)
                Text(stale ? "Still climbing?" : "Live · \(state.gymName)\(state.intent.map { " · \($0)" } ?? "")")
                    .font(.sans(12, .semibold)).foregroundStyle(Palette.secondary)
                    .privacySensitive(state.privacyLock)
            }
            HStack(alignment: .lastTextBaseline) {
                Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
                    .font(.serif(28)).monospacedDigit().foregroundStyle(accent.color)
                Spacer()
                HStack(spacing: 16) {
                    stat("\(state.sends)", "sends")
                    stat(state.high, "high").privacySensitive(state.privacyLock)
                    stat("\(state.flashed)", "flashed").privacySensitive(state.privacyLock)
                }
            }
            LiveButtons(accent: accent)
        }
        .foregroundStyle(Palette.text)
        .padding(16)
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.serif(20))
            Text(l).font(.sans(11)).foregroundStyle(Palette.secondary)
        }
    }
}
#endif

import AscentCore
import AscentUI

/// The accent as the app last saved it.
nonisolated public enum SharedAccent {
    public static var current: AccentTheme { AccentTheme(hex: AppGroup.defaults.string(forKey: SharedKey.accentHex) ?? "") }
    public static var privacyLock: Bool { AppGroup.defaults.bool(forKey: SharedKey.privacyLock) }
}
