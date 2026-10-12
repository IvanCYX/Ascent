import SwiftUI
import AscentCore

/// r3 Today (DESIGN §3.1): the three pillars, the live session, the last 7 days, one insight, up next.
struct TodayView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let db = store.db
        let today = store.today

        ScrollView {
            VStack(spacing: 12) {
                PillarsCard(db: db, today: today)
                if let live = db.activeSession { LiveSessionCard(session: live) }
                LastSevenDaysCard(db: db, today: today)
                if let insight = Insights.today(db, today: today) { InsightCard(insight: insight) }
                UpNextCard(db: db, today: today)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96)
        }
        .background(Palette.ground)
        .navigationTitle("Today")
        .navigationSubtitle(Day.fullDate(today))
        .largeTitle()
    }
}

/* ── Pillars ───────────────────────────────────────────────────────────── */

struct PillarsCard: View {
    @Environment(Router.self) private var router
    @Environment(\.accent) private var accent
    @Environment(\.zoomNamespace) private var ns
    @Environment(\.dynamicTypeSize) private var type
    var db: Database
    var today: String

    var body: some View {
        let load = Load.window(db, today: today)
        let progress = Pillars.progress(db, today: today)
        let body = Pillars.body(db, today: today)
        let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 18)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))

        Card(padding: 0) {
            layout {
                NavigationLink(value: Route.load) {
                    PillarColumn(title: "Load", caption: loadCaption(load), captionColor: load.band == .spiking ? Palette.cautionText : Palette.secondary,
                                 progress: load.band == .building ? Double(load.weeksOfBaseline) / 4 : load.ratio ?? 0,
                                 color: load.band == .spiking ? Palette.caution : accent.color, dashed: load.band == .building, delay: 0) {
                        if load.band == .building {
                            Text("\(load.weeksOfBaseline)\(Text("/4").font(.num(14)).foregroundStyle(Palette.secondary))").font(.num(22))
                        } else {
                            Text("\(Int(((load.ratio ?? 0) * 100).rounded()))%").font(.num(22)).contentTransition(.numericText())
                        }
                    }
                }
                .buttonStyle(.plain)
                .zoomSource("load", in: ns)
                .accessibilityLabel(load.band == .building ? "Load, building baseline, \(load.weeksOfBaseline) of 4 weeks"
                                    : "Load, \(Int(((load.ratio ?? 0) * 100).rounded())) percent of your usual week")

                NavigationLink(value: Route.progress) {
                    PillarColumn(title: "Progress", caption: "\(progress.hardSends) hard sends", captionColor: Palette.secondary,
                                 progress: progress.ratio ?? 0, color: accent.color, dashed: false, delay: 0.08) {
                        VStack(spacing: 3) {
                            Text(progress.top.map(String.init) ?? "–").font(.num(26)).contentTransition(.numericText())
                            if let d = progress.delta, d != 0 {
                                DeltaChip(text: d > 0 ? "+\(d)" : "−\(-d)", tone: d > 0 ? .neutral : .caution)
                                    .scaleEffect(0.85)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .zoomSource("progress", in: ns)
                .accessibilityLabel("Progress, top grade \(progress.top.map(String.init) ?? "none"), \(progress.hardSends) hard sends")

                Button { router.select(.body) } label: {
                    PillarColumn(title: "Body", caption: bodyCaption(body), captionColor: bodyColor(body).caption,
                                 progress: body.state == .clear ? 1 : Double(body.rehabDays) / 7,
                                 color: bodyColor(body).ring, dashed: false, delay: 0.16) {
                        if body.state == .clear {
                            Text("Clear").font(.num(16))
                        } else {
                            Text("\(body.pain.map(String.init) ?? "–")\(Text("/10").font(.num(14)).foregroundStyle(Palette.secondary))").font(.num(22))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(body.state == .clear ? "Body, clear" : "Body, pain \(body.pain ?? 0) of 10, \(bodyCaption(body))")
                .accessibilityHint("Opens Body")
            }
            .padding(.vertical, 20).padding(.horizontal, 6)
        }
    }

    func loadCaption(_ w: Load.Window) -> String {
        switch w.band {
        case .building: "Building baseline"
        case .spiking: "Spiking"
        case .light: "Light week"
        case .inRange: "vs usual week"
        }
    }

    func bodyCaption(_ b: Pillars.Body) -> String {
        switch b.state {
        case .clear: "No active injury"
        case .onTrack: "Rehab \(b.rehabDays) of 7"
        case .caution, .warning: b.reason ?? "Rehab \(b.rehabDays) of 7"
        }
    }

    func bodyColor(_ b: Pillars.Body) -> (ring: Color, caption: Color) {
        switch b.state {
        case .warning: (Palette.injury, Palette.injuryText)
        case .caution: (Palette.caution, Palette.cautionText)
        default: (accent.color, Palette.secondary)
        }
    }
}

struct PillarColumn<Center: View>: View {
    var title: String
    var caption: String
    var captionColor: Color
    var progress: Double
    var color: Color
    var dashed: Bool
    var delay: Double
    @ViewBuilder var center: Center

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                PillarRing(progress: progress, color: color, dashed: dashed, delay: delay)
                center.foregroundStyle(Palette.text)
            }
            .frame(width: 96, height: 96)
            VStack(spacing: 2) {
                Text(title).font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                Text(caption).font(.sans(12)).foregroundStyle(captionColor).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/* ── Live session ──────────────────────────────────────────────────────── */

struct LiveSessionCard: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accent) private var accent
    var session: Session

    var body: some View {
        let db = store.db
        let sends = db.climbs.filter { $0.sessionId == session.id }.filter(Metrics.isSend)
        Card {
            HStack {
                HStack(spacing: 8) {
                    Circle().fill(accent.color).frame(width: 8, height: 8)
                        .background(Circle().fill(accent.color.opacity(0.2)).frame(width: 16, height: 16))
                    Text("Live at \(db.gym(session.gymId)?.name ?? "the gym")").font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                }
                Spacer()
                if let intent = session.intent { Text(intent).font(.sans(13)).foregroundStyle(Palette.secondary) }
            }
            if let start = session.startedAt {
                Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    .font(.num(44, relativeTo: .largeTitle)).foregroundStyle(Palette.text)
                    .padding(.top, 10)
                    .accessibilityLabel("Running for \(spokenDuration(from: start))")
            }
            HStack(spacing: 8) {
                stat("\(sends.count)", "sends")
                stat(LiveSummary.high(sends, db: db, sessionGym: session.gymId), "high")
                stat("\(sends.filter(Metrics.isFlash).count)", "flashed")
            }
            .padding(.top, 16)
            Button("Resume") { router.sheet = .logging(start: false, step: .log(.gym)) }
                .buttonStyle(PrimaryButtonStyle(height: 50))
                .padding(.top, 16)
        }
        .accessibilityElement(children: .contain)
    }

    func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.num(20)).foregroundStyle(Palette.text).contentTransition(.numericText())
            Text(label).font(.sans(12)).foregroundStyle(Palette.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

enum LiveSummary {
    /// Top grade in a session; a Camp5 tag stays a tag ("PUR"), never a number.
    static func high(_ sends: [Climb], db: Database, sessionGym: String? = nil) -> String {
        let gymSends = sends.filter { $0.gradeKind != .v }
        let numbered = gymSends.filter { $0.gradeKind == .number }
        let tagged = gymSends.filter { $0.gradeKind == .tag }
        let gymId = sessionGym ?? db.activeSession?.gymId
        if db.gym(gymId)?.isRanked == true, let best = tagged.max(by: { $0.grade < $1.grade }) {
            return Vocab.colourCode(best.tagId)
        }
        if let m = numbered.map(\.grade).max() { return "\(m)" }
        if let best = tagged.max(by: { $0.grade < $1.grade }) { return Vocab.colourCode(best.tagId) }
        if let v = sends.filter({ $0.gradeKind == .v }).map(\.grade).max() { return "V\(v)" }
        return "–"
    }
}

/* ── Last 7 days ───────────────────────────────────────────────────────── */

struct LastSevenDaysCard: View {
    @Environment(\.accent) private var accent
    var db: Database
    var today: String

    var body: some View {
        let days = Load.daily(db, today: today)
        let window = Load.window(db, today: today)
        let average = window.baseline.map { $0 / 7 }
        let top = max(days.map(\.load).max() ?? 0, (average ?? 0) * 1.4, 0.001)
        let sessions = Load.sessions(db, today: today).count
        NavigationLink(value: Route.load) {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    Text("Last 7 days").font(.sans(17, .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    Text("\(sessions) session\(sessions == 1 ? "" : "s")").font(.sans(13)).foregroundStyle(Palette.secondary)
                }
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(days, id: \.day) { d in
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(d.load == 0 ? Palette.track : accent.color.opacity(d.isToday ? 1 : 0.55))
                                .frame(height: d.load == 0 ? 4 : max(8, 96 * d.load / top))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let average, average > 0 {
                        Line().stroke(Palette.text.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .frame(height: 1)
                            .offset(y: -96 * average / top)
                    }
                }
                .frame(height: 96, alignment: .bottom)
                .padding(.top, 16)
                HStack(spacing: 10) {
                    ForEach(days, id: \.day) { d in
                        Text(Day.weekdayShort(d.day).prefix(1))
                            .font(.sans(12, d.isToday ? .semibold : .regular))
                            .foregroundStyle(d.isToday ? Palette.text : Palette.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 7 days, \(sessions) sessions")
        .accessibilityHint("Opens Load")
    }
}

/// A horizontal line for dashed averages.
nonisolated struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: CGPoint(x: rect.minX, y: rect.midY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY)) }
    }
}

/* ── Insight and up next ───────────────────────────────────────────────── */

struct InsightCard: View {
    @Environment(Router.self) private var router
    var insight: Insights.Insight

    var body: some View {
        let content = HStack(spacing: 14) {
            Image(systemName: insight.destination == .progress ? "chart.line.uptrend.xyaxis" : "text.bubble")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                .frame(width: 40, height: 40).background(Circle().fill(Palette.raised))
            VStack(alignment: .leading, spacing: 2) {
                Text(insight.headline).font(.sans(16, .semibold)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                Text(insight.detail).font(.sans(13)).foregroundStyle(Palette.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.surface))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

        switch insight.destination {
        case .progress: NavigationLink(value: Route.progress) { content }.buttonStyle(.plain)
        case .history: Button { router.select(.history) } label: { content }.buttonStyle(.plain)
        }
    }
}

struct UpNextCard: View {
    @Environment(Router.self) private var router
    var db: Database
    var today: String

    var body: some View {
        let plan = db.sessions.filter { $0.status == .planned && $0.date >= today }.min { $0.date < $1.date }
        let blocks = plan?.plannedBlocks ?? []
        let minutes = blocks.reduce(0) { $0 + $1.durationMin }
        let usage = Metrics.loadRuleUsage(db.loadRules.filter { $0.maxPerWeek != nil }, climbs: db.climbs, weekStart: Day.weekStart(today))
        let blocked = usage.first(where: \.blocked)

        Button { router.planSegment = .today; router.select(.plan) } label: {
            Card {
                HStack(alignment: .firstTextBaseline) {
                    Text("Up next").micro()
                    Spacer()
                    if let plan { Text(Day.relative(plan.date, today: today)).font(.sans(13)).foregroundStyle(Palette.secondary) }
                }
                Text(plan.map { "\($0.intent ?? "Session") day" } ?? "Nothing planned")
                    .font(.sans(20, .bold)).foregroundStyle(Palette.text).padding(.top, 6)
                Text(plan == nil ? "Plan your next session" : "\(blocks.count) block\(blocks.count == 1 ? "" : "s"), \(Self.duration(minutes))")
                    .font(.sans(14)).foregroundStyle(Palette.secondary).padding(.top, 2)
                if let blocked {
                    WarnPanel(lead: "\(blocked.headline) off", text: "\(blocked.used) of \(blocked.cap ?? 0) this week").padding(.top, 12)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Plan")
    }

    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) h\(minutes % 60 > 0 ? " \(minutes % 60) min" : "")" : "\(minutes) min"
    }
}

/* ── Zoom from a card into its detail screen ───────────────────────────── */

private struct ZoomNamespaceKey: EnvironmentKey { static let defaultValue: Namespace.ID? = nil }
extension EnvironmentValues {
    var zoomNamespace: Namespace.ID? {
        get { self[ZoomNamespaceKey.self] }
        set { self[ZoomNamespaceKey.self] = newValue }
    }
}

extension View {
    @ViewBuilder func zoomSource(_ id: String, in ns: Namespace.ID?) -> some View {
        if let ns { matchedTransitionSource(id: id, in: ns) } else { self }
    }

    @ViewBuilder func zoomDestination(_ id: String, in ns: Namespace.ID?) -> some View {
        if let ns { zoomTransition(id, in: ns) } else { self }
    }
}
