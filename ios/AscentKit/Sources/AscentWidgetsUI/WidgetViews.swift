import SwiftUI
import WidgetKit
import AscentCore
import AscentUI

/// Which widget is drawing. Mirrors `WidgetFamily` so these views also compile on macOS.
public enum AscentWidgetKind: Sendable { case small, medium, large, circular, rectangular, inline }

/// One entry view for every family (DESIGN §6).
/// Locked + Face ID lock on → the limited layout; otherwise full content. `.privacySensitive()` backs it up.
public struct AscentWidgetView: View {
    @Environment(\.redactionReasons) private var redaction
    var kind: AscentWidgetKind
    var summary: WidgetSummary
    var privacyLock: Bool
    var accent: AccentTheme

    public init(kind: AscentWidgetKind, summary: WidgetSummary, privacyLock: Bool, accent: AccentTheme) {
        self.kind = kind; self.summary = summary; self.privacyLock = privacyLock; self.accent = accent
    }

    /// The system renders a privacy-redacted copy for the locked phone; only honour it when the lock is on.
    var locked: Bool { privacyLock && redaction.contains(.privacy) }

    public var body: some View {
        Group {
            switch kind {
            case .small: SmallWidget(s: summary, locked: locked)
            case .medium: MediumWidget(s: summary, locked: locked)
            case .large: LargeWidget(s: summary, locked: locked)
            case .circular: CircularWidget(s: summary, locked: locked)
            case .rectangular: RectangularWidget(s: summary, locked: locked)
            case .inline: InlineWidget(s: summary, locked: locked)
            }
        }
        .environment(\.accent, accent)
        .unredactedUnless(privacyLock)
    }
}

extension View {
    /// Without the lock, nothing is private: show full content even on a locked phone.
    @ViewBuilder func unredactedUnless(_ lock: Bool) -> some View {
        if lock { self } else { unredacted() }
    }
}

/* ── Pieces ─────────────────────────────────────────────────────────────── */

struct WidgetLabel: View {
    var text: String
    var body: some View { Text(text).font(.mono(9.5)).tracking(1).textCase(.uppercase).foregroundStyle(Palette.muted) }
}

struct WeekStrip: View {
    @Environment(\.accent) private var accent
    var days: [Bool]
    var today: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 3) {
                    Rectangle().fill(days[i] ? accent.color : Palette.track)
                        .frame(height: 8)
                        .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: i == today ? 1 : 0))
                        .widgetAccentable()
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.mono(8)).foregroundStyle(Palette.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(days.filter { $0 }.count) session days this week")
    }
}

/// Grey bars where locked content would be.
struct RedactBars: View {
    var widths: [CGFloat]
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, w in
                RoundedRectangle(cornerRadius: 2).fill(Palette.track).frame(maxWidth: w, minHeight: 9, maxHeight: 9)
            }
        }
    }
}

struct MiniPyramid: View {
    @Environment(\.accent) private var accent
    var rows: [Metrics.PyramidRow]
    var counts = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(rows, id: \.grade) { r in
                HStack(spacing: 6) {
                    Text("\(r.grade)").font(.serif(12)).frame(width: 16, alignment: .trailing)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Palette.track)
                            Rectangle().fill(Palette.worked).frame(width: g.size.width * r.width)
                            Rectangle().fill(accent.color).frame(width: g.size.width * r.width * r.flashShare).widgetAccentable()
                        }
                    }
                    .frame(height: 11)
                    if counts { Text("\(r.count)").font(.mono(9.5)).foregroundStyle(Palette.muted).frame(width: 16, alignment: .leading) }
                }
            }
        }
    }
}

/// Re-normalises widths for a slice of the pyramid.
func slice(_ rows: [Metrics.PyramidRow], from top: Int, to bottom: Int) -> [Metrics.PyramidRow] {
    let s = rows.filter { $0.grade <= top && $0.grade >= bottom }
    let m = max(1, s.map(\.count).max() ?? 0)
    return s.map { var r = $0; r.width = Double(r.count) / Double(m); return r }
}

/* ── Home Screen ────────────────────────────────────────────────────────── */

struct SmallWidget: View {
    var s: WidgetSummary
    var locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if locked {
                WidgetLabel(text: "This week")
                Text("\(s.sessionsThisWeek)").font(.serif(52)).padding(.top, 8)
                Text(s.sessionsThisWeek == 1 ? "session" : "sessions").font(.sans(12, .medium))
                WeekStrip(days: s.weekStrip, today: s.todayIndex).padding(.top, 10)
                Spacer(minLength: 0)
                Text("\(s.streakWeeks)-WEEK STREAK").font(.mono(10)).foregroundStyle(Palette.muted)
            } else {
                WidgetLabel(text: "This week · top")
                Text(s.topGrade ?? "—").font(.serif(52)).padding(.top, 8).privacySensitive()
                Text([s.topGym, s.topDelta].compactMap { $0 }.joined(separator: " · ").ifEmpty("no numbered sends yet"))
                    .font(.sans(12, .medium)).lineLimit(1).privacySensitive()
                Text("\(s.sessionsThisWeek) SESSIONS · \(s.sendsThisWeek) SENDS").font(.mono(10)).foregroundStyle(Palette.muted).padding(.top, 8)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if s.rehabDue > 0 || s.painNow != nil {
                    HStack {
                        Text(s.rehabDue > 0 ? "REHAB DUE" : "PAIN")
                        Spacer()
                        Text(s.painNow.map { "\($0)/10" } ?? "")
                    }
                    .font(.mono(10, .medium)).foregroundStyle(Palette.warn).privacySensitive()
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct MediumWidget: View {
    var s: WidgetSummary
    var locked: Bool

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                if locked {
                    WidgetLabel(text: "This week")
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(s.sessionsThisWeek)").font(.serif(44))
                        Text("sessions").font(.sans(14)).foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 6)
                } else {
                    WidgetLabel(text: "This week")
                    HStack(spacing: 14) {
                        stat(s.topGrade ?? "—", "TOP \(s.topDelta?.replacingOccurrences(of: " ", with: "") ?? "")")
                        stat(s.flashRate.map { "\($0)%" } ?? "—", "FLASH")
                    }
                    .padding(.top, 8)
                    .privacySensitive()
                }
                Spacer(minLength: 6)
                WeekStrip(days: s.weekStrip, today: s.todayIndex)
                if locked {
                    Text("\(s.streakWeeks)-WEEK STREAK\(s.weeksToComp.map { " · COMP IN \($0) WK" } ?? "")")
                        .font(.mono(9.5)).foregroundStyle(Palette.muted).padding(.top, 8).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            .frame(width: 140, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if locked {
                    Spacer(minLength: 0)
                    RedactBars(widths: [140, 110, 128])
                    Text("Unlock to see grades and the body log").font(.sans(10.5)).foregroundStyle(Palette.muted)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    MiniPyramid(rows: slice(s.pyramid, from: 13, to: 9))
                    if let inj = s.injuryShort {
                        Text("\(inj.uppercased()) \(s.painNow.map { "\($0)/10" } ?? "")\(s.rehabStreak.map { " · \($0)-DAY REHAB" } ?? "")")
                            .font(.mono(10, .medium)).foregroundStyle(Palette.warn).lineLimit(1).minimumScaleFactor(0.7).padding(.top, 4)
                    }
                    Spacer(minLength: 0)
                }
            }
            .privacySensitive()
        }
        .foregroundStyle(Palette.ink)
    }

    func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).font(.serif(38)).lineLimit(1).minimumScaleFactor(0.6)
            Text(l).font(.mono(9)).foregroundStyle(Palette.muted)
        }
    }
}

struct LargeWidget: View {
    var s: WidgetSummary
    var locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if locked {
                WidgetLabel(text: "This week")
                HStack(alignment: .bottom, spacing: 18) {
                    Text("\(s.sessionsThisWeek)").font(.serif(56))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("sessions").font(.sans(13, .medium))
                        Text("\(s.streakWeeks)-week streak").font(.sans(13)).foregroundStyle(Palette.muted)
                    }
                    .padding(.bottom, 8)
                }
                .padding(.top, 10)
                WeekStrip(days: s.weekStrip, today: s.todayIndex).padding(.top, 12)
                RedactBars(widths: [300, 240, 280, 200]).padding(.top, 22)
                Spacer(minLength: 0)
                Rectangle().fill(Palette.rule).frame(height: 1)
                HStack {
                    Text(s.weeksToComp.map { "NEXT COMP · \($0) WEEKS OUT" } ?? "NO COMP PLANNED").font(.mono(10)).foregroundStyle(Palette.muted)
                    Spacer()
                    Label("Unlock for details", systemImage: "lock.fill").font(.sans(10.5)).foregroundStyle(Palette.muted)
                }
                .padding(.top, 10)
            } else {
                HStack {
                    WidgetLabel(text: "8 weeks")
                    Spacer()
                    WidgetLabel(text: "\(s.sessionsThisWeek) sessions this week")
                }
                HStack(spacing: 18) {
                    ForEach(Array(s.kpis.prefix(3).enumerated()), id: \.offset) { i, k in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(k.value).font(.serif(32))
                            Text(["TOP", "FLASH 8+", "ATT/SEND"][i]).font(.mono(9)).foregroundStyle(Palette.muted)
                        }
                    }
                }
                .padding(.top, 10)
                MiniPyramid(rows: slice(s.pyramid, from: 13, to: 8), counts: true).padding(.top, 14)
                HStack(alignment: .bottom, spacing: 3) {
                    let maxCount = max(1, s.camp5.map(\.count).max() ?? 0)
                    ForEach(s.camp5, id: \.tagId) { b in
                        Rectangle().fill(b.count > 0 ? Palette.hold(b.tagId) : Palette.worked)
                            .frame(height: b.count > 0 ? max(4, 28 * CGFloat(b.count) / CGFloat(maxCount)) : 2)
                    }
                }
                .frame(height: 30, alignment: .bottom)
                .padding(.top, 12)
                Spacer(minLength: 0)
                Rectangle().fill(Palette.rule).frame(height: 1)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.injuryShort.map { "\($0) · \(s.painNow.map { "\($0)/10" } ?? "—")" } ?? "No active injury").font(.sans(12, .medium))
                        if s.injuryShort != nil {
                            Text("\(s.rehabDue > 0 ? "REHAB DUE" : "REHAB DONE")\(s.rehabStreak.map { " · \($0)-DAY STREAK" } ?? "")")
                                .font(.mono(9.5)).foregroundStyle(Palette.warn)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(s.compName ?? "No comp").font(.sans(12, .medium))
                        Text([s.weeksToComp.map { "\($0) WK" }, s.weakest?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                            .font(.mono(9.5)).foregroundStyle(Palette.muted)
                    }
                }
                .padding(.top, 10)
            }
        }
        .foregroundStyle(Palette.ink)
        .privacySensitive(!locked)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/* ── Lock Screen (monochrome) ───────────────────────────────────────────── */

struct CircularWidget: View {
    var s: WidgetSummary
    var locked: Bool

    var body: some View {
        Gauge(value: Double(min(s.sessionsThisWeek, s.weeklyTarget)), in: 0...Double(max(1, s.weeklyTarget))) {
            Text("Sessions")
        } currentValueLabel: {
            VStack(spacing: 0) {
                Text(locked || s.topGrade == nil ? "\(s.sessionsThisWeek)" : s.topGrade!).font(.system(size: 22, weight: .bold))
                Text(locked || s.topGrade == nil ? "OF \(s.weeklyTarget)" : "TOP").font(.system(size: 8, weight: .semibold)).opacity(0.8)
            }
        }
        .circularCapacityStyle()
        .widgetAccentable()
        .accessibilityLabel("\(s.sessionsThisWeek) of \(s.weeklyTarget) sessions this week")
    }
}

extension View {
    @ViewBuilder func circularCapacityStyle() -> some View {
        #if os(iOS)
        gaugeStyle(.accessoryCircularCapacity)
        #else
        self
        #endif
    }
}

struct RectangularWidget: View {
    var s: WidgetSummary
    var locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if locked {
                Text("ASCENT").font(.system(size: 12, weight: .semibold)).opacity(0.75)
                Text("\(s.sessionsThisWeek) sessions this week").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 6) {
                    Text("\(s.streakWeeks)-wk streak").font(.system(size: 12, weight: .medium)).opacity(0.85)
                    RoundedRectangle(cornerRadius: 2).fill(.primary.opacity(0.3)).frame(width: 52, height: 9)
                }
            } else {
                Text(["ASCENT", s.liveGym?.uppercased() ?? s.topGym?.uppercased()].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12, weight: .semibold)).opacity(0.75)
                Text(s.topGrade.map { "Top \($0) · \(s.sendsThisWeek) sends" } ?? "\(s.sessionsThisWeek) sessions · \(s.sendsThisWeek) sends")
                    .font(.system(size: 15, weight: .semibold))
                if let inj = s.injuryShort {
                    Text("\(s.rehabDue > 0 ? "Rehab due" : "Rehab done") · \(inj) \(s.painNow.map { "\($0)/10" } ?? "")")
                        .font(.system(size: 12, weight: .medium)).opacity(0.85)
                } else {
                    Text("\(s.streakWeeks)-wk streak").font(.system(size: 12, weight: .medium)).opacity(0.85)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive(!locked)
    }
}

struct InlineWidget: View {
    var s: WidgetSummary
    var locked: Bool

    var body: some View {
        if locked || s.topGrade == nil {
            Label("\(s.sessionsThisWeek) sessions this week", systemImage: "figure.climbing")
        } else {
            Label("Top \(s.topGrade!) · \(s.sessionsThisWeek) sessions\(s.rehabDue > 0 ? " · rehab due" : "")", systemImage: "figure.climbing")
                .privacySensitive()
        }
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
