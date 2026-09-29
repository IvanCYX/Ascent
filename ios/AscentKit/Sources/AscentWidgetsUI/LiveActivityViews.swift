#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit
import AscentCore
import AscentUI

/// The session Live Activity (DESIGN §2, frames 1.7–1.9).
/// Buttons are links into the app (`ascent://log`, `ascent://review`), which is what `openAppWhenRun` intents would do.
public struct LiveSessionActivity: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveSessionAttributes.self) { context in
            LockScreenLiveView(state: context.state, stale: context.isStale)
                .activityBackgroundTint(Palette.paper)
                .activitySystemActionForegroundColor(Palette.ink)
                .environment(\.accent, SharedAccent.current)
        } dynamicIsland: { context in
            let s = context.state
            let accent = SharedAccent.current
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("LIVE · \(s.gymName.uppercased())", systemImage: "hand.raised.fingers.spread.fill")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(accent.color)
                        if let intent = s.intent { Text(intent).font(.system(size: 13)).opacity(0.7) }
                    }
                    .privacySensitive(s.privacyLock)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 5) {
                        Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false)
                            .font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(accent.color)
                            .multilineTextAlignment(.trailing)
                        Text("since \(Day.timeOfDay(s.startedAt))").font(.system(size: 12)).opacity(0.6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 14) {
                        HStack(spacing: 22) {
                            stat("\(s.sends)", "sends")
                            stat(s.high, "high").privacySensitive(s.privacyLock)
                            stat("\(s.flashed)", "flashed").privacySensitive(s.privacyLock)
                            Spacer()
                        }
                        LiveButtons(accent: accent)
                    }
                    .padding(.top, 6)
                }
            } compactLeading: {
                HStack(spacing: 5) {
                    Image(systemName: "hand.raised.fingers.spread.fill").foregroundStyle(accent.color)
                    Text(s.high).font(.system(size: 15, weight: .bold)).privacySensitive(s.privacyLock)
                }
            } compactTrailing: {
                Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(accent.color)
                    .frame(maxWidth: 64)
            } minimal: {
                Text(timerInterval: s.startedAt...Date.distantFuture, countsDown: false)
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(accent.color)
            }
            .widgetURL(URL(string: "ascent://log"))
            .keylineTint(accent.color)
        }
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).font(.system(size: 22, weight: .bold))
            Text(l).font(.system(size: 11, weight: .medium)).opacity(0.6)
        }
    }
}

struct LiveButtons: View {
    var accent: AccentTheme
    var body: some View {
        HStack(spacing: 8) {
            Link(destination: URL(string: "ascent://log")!) {
                Text("Log a send").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(accent.color))
            }
            Link(destination: URL(string: "ascent://review")!) {
                Text("End & rate").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 44).background(Capsule().fill(Palette.ink.opacity(0.12)))
            }
        }
    }
}

/// 1.9 — the paper card on the Lock Screen.
struct LockScreenLiveView: View {
    @Environment(\.accent) private var accent
    var state: LiveSessionState
    var stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(accent.color).frame(width: 6, height: 6)
                Text(stale ? "STILL CLIMBING?" : "LIVE · \(state.gymName.uppercased())\(state.intent.map { " · \($0.uppercased())" } ?? "")")
                    .font(.mono(10.5)).tracking(1.2).foregroundStyle(Palette.muted)
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
        .foregroundStyle(Palette.ink)
        .padding(16)
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(.serif(20))
            Text(l.uppercased()).font(.mono(9)).foregroundStyle(Palette.muted)
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
