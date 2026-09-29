import SwiftUI
import AscentCore

/// Web Dashboard `2a` (DESIGN §3.1).
struct TodayView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @State private var showReads = true

    var body: some View {
        let db = store.db
        let today = store.today
        let m = DashboardModel(db: db, today: today)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let live = db.activeSession {
                    LiveSessionCard(session: live).padding(.horizontal, 16).padding(.bottom, 14)
                }

                SquareSegment(options: RangeID.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { db.settings.dashboardRange }, set: { store.setDashboardRange($0) }))
                    .padding(.horizontal, 16).padding(.bottom, 14)

                KpiGrid(kpis: m.kpis)

                Band {
                    SectionHead(title: "Send pyramid") { PyramidLegend() }
                    Text("Numbered gyms · offset adjusted").micro().padding(.top, -6).padding(.bottom, 12)
                    PyramidView(rows: m.pyramid)
                    reads(label: "Read:", Metrics.pyramidRead(m.pyramid))
                }

                Band {
                    SectionHead("Camp5 · colour tags", note: "RANKED, NOT NUMBERED")
                    TallyView(bars: m.tally)
                    Insight(label: nil, text: Metrics.camp5Read(m.tally))
                }

                Band {
                    SectionHead("Board grades", note: "TRACKED SEPARATELY")
                    if m.boards.isEmpty {
                        Text("No board sends in this range.").font(.sans(13)).foregroundStyle(Palette.muted)
                    }
                    VStack(spacing: 8) { ForEach(m.boards, id: \.boardId) { BoardCard(b: $0) } }
                }

                if let injury = db.activeInjuries.first {
                    Band { InjuryWatch(injury: injury, db: db, today: today) }
                }

                Band {
                    Button { router.planSegment = .season; router.select(.plan) } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("COMP READINESS\(m.compWeeks.map { " · \($0) WEEKS OUT" } ?? "")").micro(Palette.ink)
                            ReadinessRows(rows: m.readiness)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the season plan")
                }

                Band {
                    SectionHead("Where you send", note: "SEND RATE % · \(m.heat.filter(\.weak).count) GAPS")
                    HeatmapView(rows: m.heat)
                    let weak = m.heat.filter(\.weak)
                    if !weak.isEmpty {
                        Insight(label: nil, text: weak.map { "\($0.style) \($0.comment.replacingOccurrences(of: "gap — ", with: "has "))." }
                            .joined(separator: " "), color: Palette.warn)
                    }
                    reads(label: "Comp prep:", Metrics.heatmapRead(m.heat, compName: m.comp?.name))
                }

                Band(bottomPadding: 8) {
                    SectionHead("Recent sessions", note: "\(db.sessions.filter { $0.status == .done }.count) LOGGED")
                    if m.recent.isEmpty {
                        Text("No sessions in this range.").font(.sans(13)).foregroundStyle(Palette.muted)
                    }
                    ForEach(m.recent) { s in
                        NavigationLink(value: Route.session(s.id)) { LedgerRow(session: s, db: db) }.buttonStyle(.plain)
                    }
                }
            }
        }
        .background(Palette.paper)
        .navigationTitle("Today")
        .navigationSubtitle(Day.weekRangeShort(today))
        .largeTitle()
    }

    @ViewBuilder func reads(label: String, _ text: String) -> some View {
        if showReads {
            Button { withAnimation { showReads = false } } label: { Insight(label: label, text: text) }
                .buttonStyle(.plain)
                .accessibilityHint("Hides the reads")
        } else if label == "Read:" {
            LinkButton(title: "Show reads") { withAnimation { showReads = true } }.padding(.top, 10)
        }
    }
}

/// Everything the dashboard draws for one range, derived from the log.
struct DashboardModel {
    let kpis: [Metrics.Kpi]
    let pyramid: [Metrics.PyramidRow]
    let tally: [Metrics.TagBar]
    let boards: [Metrics.BoardSummary]
    let heat: [Metrics.HeatRow]
    let readiness: [Metrics.ReadinessRow]
    let recent: [Session]
    let comp: Competition?
    let compWeeks: Int?

    init(db: Database, today: String) {
        let range = db.settings.dashboardRange
        let w = range.windows(today: today)
        let cur = Metrics.climbsInRange(db.climbs, from: w.from, to: w.to)
        let prev = Metrics.climbsInRange(db.climbs, from: w.prevFrom, to: w.prevTo)
        let inRange = db.sessions.filter { $0.status == .done && $0.date >= w.from && $0.date <= w.to }
        let weeks = max(1, Day.weeksBetween(w.from, w.to))
        kpis = Metrics.buildKpis(cur: cur, prev: prev, gyms: db.gyms, sessionCount: inRange.count, rangeLabel: range.label.lowercased())
        pyramid = Metrics.sendPyramid(cur)
        tally = Metrics.camp5Tally(cur, tags: db.gyms.first(where: \.isRanked)?.tags ?? Vocab.camp5Tags)
        boards = Metrics.boardSummaries(cur: cur, prev: prev, boards: db.boards, weeks: weeks)
        heat = Metrics.styleGradeMatrix(cur)
        readiness = Metrics.compReadiness(cur, reviews: db.reviews, today: today)
        recent = Array(inRange.sorted { $0.date > $1.date }.prefix(5))
        comp = db.upcomingComps(from: today).first { $0.effectivePriority != .c } ?? db.nextComp(from: today)
        compWeeks = comp.map { Metrics.weeksOut(today: today, compDate: $0.date) }
    }
}

struct LiveSessionCard: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var session: Session

    var body: some View {
        let db = store.db
        let climbs = db.climbs.filter { $0.sessionId == session.id }
        let sends = climbs.filter(Metrics.isSend)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                TimelineView(.periodic(from: .now, by: 30)) { ctx in
                    HStack(spacing: 6) {
                        Circle().fill(Palette.ink).frame(width: 6, height: 6)
                        Text("LIVE · \(db.gym(session.gymId)?.name ?? "—") · \(session.startedAt.map { Day.elapsedLabel(from: $0, now: ctx.date) } ?? "0m")")
                            .micro(Palette.ink)
                    }
                }
                Text("\(sends.count) sends · high \(Text(LiveSummary.high(sends, db: db)).foregroundStyle(Palette.ink).bold()) · \(sends.filter(Metrics.isFlash).count) flashed")
                    .font(.sans(13)).foregroundStyle(Palette.muted)
            }
            Spacer()
            Button("Resume") { router.sheet = .logging(start: false, step: .log(.gym)) }
                .buttonStyle(PrimaryButtonStyle(height: 40))
                .frame(width: 96)
        }
        .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 12)
        .background(Palette.card)
        .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: 2))
        .accessibilityElement(children: .contain)
    }
}

enum LiveSummary {
    /// Top grade tonight; a Camp5 tag stays a tag ("PUR"), never a number.
    static func high(_ sends: [Climb], db: Database) -> String {
        let gymSends = sends.filter { $0.gradeKind != .v }
        let numbered = gymSends.filter { $0.gradeKind == .number }
        let tagged = gymSends.filter { $0.gradeKind == .tag }
        if let active = db.activeSession, db.gym(active.gymId)?.isRanked == true, let best = tagged.max(by: { $0.grade < $1.grade }) {
            return Vocab.colourCode(best.tagId)
        }
        if let m = numbered.map(\.grade).max() { return "\(m)" }
        if let best = tagged.max(by: { $0.grade < $1.grade }) { return Vocab.colourCode(best.tagId) }
        if let v = sends.filter({ $0.gradeKind == .v }).map(\.grade).max() { return "V\(v)" }
        return "—"
    }
}

struct InjuryWatch: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var injury: Injury
    var db: Database
    var today: String

    var body: some View {
        let pain = db.painEntries.filter { $0.injuryId == injury.id }.sorted { $0.date < $1.date }.suffix(7)
        let exercises = db.rehabExercises.filter { $0.injuryId == injury.id }
        let adherence = Metrics.rehabAdherence(exercises, logs: db.rehabLogs, today: today)
        let rehabWeek = injury.rehabStart.map { max(1, Day.weeksBetween($0, today) + 1) }
        let usage = Metrics.loadRuleUsage(db.loadRules.filter { $0.maxPerWeek != nil }, climbs: db.climbs, weekStart: Day.weekStart(today))
        let hot = usage.first(where: \.blocked) ?? usage.first(where: \.nearing)

        VStack(alignment: .leading, spacing: 0) {
            SectionHead("Injury watch", note: rehabWeek.map { "REHAB · WK \($0)" }, noteColor: Palette.warn)
            Button { router.select(.body) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(injury.name).font(.sans(14, .medium)).foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted)
                    }
                    if pain.isEmpty {
                        Text("no pain entries yet").font(.sans(12)).foregroundStyle(Palette.muted).padding(.vertical, 12)
                    } else {
                        PainBars(levels: pain.map(\.level)).padding(.top, 12).padding(.bottom, 8)
                    }
                    HStack {
                        Text(pain.isEmpty ? "no pain logged" : "pain \(pain.first!.level)/10 → \(pain.last!.level)/10")
                        Spacer()
                        Text("\(adherence.streak)-day rehab streak")
                    }
                    .font(.mono(11)).foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(Palette.warnBg)
                .overlay(Rectangle().strokeBorder(Palette.warnBorder, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the body log")

            if let hot {
                Text("\(Text("Load flag · ").foregroundStyle(Palette.warn).font(.sans(13, .semibold)))\(hot.headline) \(hot.condition). Used \(hot.used) of \(hot.cap ?? 0) this week\(hot.blocked ? " — swap to slopers?" : ".")")
                    .font(.sans(13)).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Palette.card)
                    .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
                    .padding(.top, 8)
            }
        }
    }
}
