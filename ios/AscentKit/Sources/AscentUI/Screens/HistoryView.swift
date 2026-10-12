import SwiftUI
import AscentCore

/// Web `1g` + the ledger (DESIGN §3.6).
struct HistoryView: View {
    @Environment(AscentStore.self) private var store
    @State private var gymFilter: String?
    @State private var intentFilter: String?
    @State private var ratedOnly = false

    var body: some View {
        let db = store.db
        let trends = Metrics.chipTrends(db.reviews, sessions: db.sessions)
        let sessions = db.sessions
            .filter { $0.status == .done }
            .filter { gymFilter == nil || $0.gymId == gymFilter }
            .filter { intentFilter == nil || $0.intent == intentFilter }
            .filter { !ratedOnly || db.review(for: $0.id) != nil }
            .sorted { $0.date > $1.date }
        let weeks = Dictionary(grouping: sessions, by: { Day.weekStart($0.date) }).sorted { $0.key > $1.key }
        let live = db.activeSession

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                Band { ChipTrendPanel(rows: trends, pattern: Metrics.chipPattern(trends)) }
                if isFiltered {
                    HStack {
                        Text(filterLabel(db)).micro(Palette.text)
                        Spacer()
                        LinkButton(title: "Clear") { gymFilter = nil; intentFilter = nil; ratedOnly = false }
                    }
                    .padding(.horizontal, 20).padding(.top, 14)
                }
                if let live, !isFiltered {
                    group("Now", [live], db: db)
                }
                ForEach(weeks, id: \.key) { week, rows in
                    group(weekLabel(week), rows, db: db)
                }
                if sessions.isEmpty {
                    Text("No sessions match.").font(.sans(14)).foregroundStyle(Palette.secondary).padding(20)
                }
            }
            .padding(.bottom, 96)
        }
        .background(Palette.ground)
        .navigationTitle("History")
        .navigationSubtitle("\(sessions.count) session\(sessions.count == 1 ? "" : "s")")
        .largeTitle()
        .toolbar {
            ToolbarItem(placement: .trailing) {
                Menu {
                    Picker("Gym", selection: $gymFilter) {
                        Text("All gyms").tag(String?.none)
                        ForEach(db.gyms) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Intent", selection: $intentFilter) {
                        Text("Any intent").tag(String?.none)
                        ForEach(Vocab.sessionIntents, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Toggle("Rated only", isOn: $ratedOnly)
                } label: {
                    Image(systemName: isFiltered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                }
                .accessibilityLabel("Filter sessions")
            }
        }
    }

    var isFiltered: Bool { gymFilter != nil || intentFilter != nil || ratedOnly }

    @ViewBuilder func group(_ label: String, _ rows: [Session], db: Database) -> some View {
        Text(label).micro().padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 6)
        Card(padding: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { i, s in
                NavigationLink(value: Route.session(s.id)) { LedgerRow(session: s, db: db, showDivider: i < rows.count - 1) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.leading, 0)
    }

    func weekLabel(_ start: String) -> String {
        let thisWeek = Day.weekStart(store.today)
        if start == thisWeek { return "This week" }
        if start == Day.add(thisWeek, -7) { return "Last week" }
        return "Week of \(Day.pretty(start))"
    }

    func filterLabel(_ db: Database) -> String {
        [db.gym(gymFilter)?.name, intentFilter, ratedOnly ? "rated" : nil].compactMap { $0 }.joined(separator: ", ")
    }
}

/// 3.7 — one session in full.
struct SessionDetailView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    var sessionId: String
    @State private var pendingDelete: Climb?
    @State private var confirmSessionDelete = false

    var body: some View {
        let db = store.db
        if let s = db.session(sessionId) {
            let climbs = db.climbs.filter { $0.sessionId == s.id }.sorted { $0.createdAt > $1.createdAt }
            let gymClimbs = climbs.filter { $0.gradeKind != .v }
            let boardClimbs = climbs.filter { $0.gradeKind == .v }
            let sends = climbs.filter(Metrics.isSend)
            let review = db.review(for: s.id)
            let avg = db.reviews.isEmpty ? nil : db.reviews.map(\.overallScore).reduce(0, +) / Double(db.reviews.count)
            let duration = s.durationMin.map { $0 >= 60 ? "\($0 / 60)h \($0 % 60)m" : "\($0)m" }

            List {
                Group {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Day.fullDate(s.date)).font(.sans(28, .bold)).foregroundStyle(Palette.text)
                        Text([db.gym(s.gymId)?.name, s.intent, duration].compactMap { $0 }.joined(separator: ", "))
                            .font(.sans(15)).foregroundStyle(Palette.secondary)
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 14)

                    KpiGrid(kpis: detailKpis(sends: sends, review: review, avg: avg)).padding(.horizontal, 16)

                    if let review {
                        Band {
                            SectionHead("Review")
                            ChipFlow {
                                ForEach(review.chips, id: \.self) { c in
                                    Chip(label: c, on: true, small: true, kind: c.contains("/10") ? .pain : .normal) {}
                                        .allowsHitTesting(false)
                                }
                            }
                            if let note = review.note {
                                Text("“\(note)”").font(.sans(15).italic()).foregroundStyle(Palette.text).padding(.top, 14)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .plainRow()

                if !gymClimbs.isEmpty {
                    sectionHead("Gym climbs", note: nil)
                    ForEach(gymClimbs) { c in
                        ClimbRow(climb: c).plainRow(horizontal: 16)
                            .swipeActions { Button("Delete", role: .destructive) { pendingDelete = c } }
                    }
                }
                if !boardClimbs.isEmpty {
                    sectionHead("Board climbs", note: Set(boardClimbs.compactMap { db.board($0.boardId)?.name }).sorted().joined(separator: ", "))
                    ForEach(boardClimbs) { c in
                        ClimbRow(climb: c).plainRow(horizontal: 16)
                            .swipeActions { Button("Delete", role: .destructive) { pendingDelete = c } }
                    }
                }
                if let blocks = s.plannedBlocks, !blocks.isEmpty {
                    Band {
                        SectionHead("Plan", note: "\(blocks.reduce(0) { $0 + $1.durationMin }) min")
                        Text(blocks.map { $0.description.components(separatedBy: " · ").first ?? $0.description }.joined(separator: ", "))
                            .font(.sans(14)).foregroundStyle(Palette.secondary)
                    }
                    .plainRow()
                }
                Band {
                    Button("Delete session", role: .destructive) { confirmSessionDelete = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                .plainRow()
                .padding(.bottom, 60)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.ground)
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle(Day.weekdayShort(s.date) + " " + Day.pretty(s.date))
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .trailing) {
                    Button(review == nil ? "Rate" : "Edit review") { router.sheet = .reviewEdit(sessionId: s.id) }
                }
            }
            .confirmationDialog("Delete this climb?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Delete climb", role: .destructive) { if let c = pendingDelete { store.deleteClimb(c.id) }; pendingDelete = nil }
            } message: {
                Text(pendingDelete.map { "\(gradeLabel($0).ifEmpty(Vocab.colourLabel($0.tagId))) · \($0.gradeKind == .v ? boardDetail($0) : climbDetail($0))" } ?? "")
            }
            .confirmationDialog("Delete this session?", isPresented: $confirmSessionDelete, titleVisibility: .visible) {
                Button("Delete session", role: .destructive) { dismiss(); store.deleteSession(s.id) }
            } message: {
                Text("Its climbs, review and pain entries are deleted too.")
            }
        } else {
            Text("This session was deleted.").font(.sans(14)).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.ground)
        }
    }

    func detailKpis(sends: [Climb], review: SessionReview?, avg: Double?) -> [Metrics.Kpi] {
        let flashed = sends.filter(Metrics.isFlash).count
        let felt: String = review.map { String(format: "%.1f", $0.overallScore) } ?? "—"
        let avgText: String = avg.map { String(format: "avg %.1f", $0) } ?? ""
        return [
            Metrics.Kpi(label: "Sends", value: "\(sends.count)", caption: "\(flashed) flashed", delta: "", deltaStrong: false),
            Metrics.Kpi(label: "Felt", value: felt, caption: avgText.isEmpty ? "" : avgText.replacingOccurrences(of: "avg", with: "Average"), delta: "", deltaStrong: false),
        ]
    }

    func sectionHead(_ title: String, note: String?) -> some View {
        SectionHead(title, note: note)
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, -6)
            .plainRow()
    }
}

struct ClimbRow: View {
    var climb: Climb

    var body: some View {
        HStack(spacing: 10) {
            Text(gradeLabel(climb).ifEmpty(Vocab.colourCode(climb.tagId))).font(.num(15)).foregroundStyle(Palette.text)
                .frame(width: 44, height: 32).background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.raised))
            Swatch(colour: climb.gradeKind == .v ? nil : climb.holdColour ?? climb.tagId, size: 12)
                .opacity(climb.gradeKind == .v || (climb.holdColour ?? climb.tagId) == nil ? 0 : 1)
            Text(climb.gradeKind == .v ? boardDetail(climb) : climbDetail(climb))
                .font(.sans(15)).foregroundStyle(Palette.text).lineLimit(1)
            Spacer()
            Text(Day.timeOfDay(climb.createdAt)).font(.sans(13)).monospacedDigit().foregroundStyle(Palette.secondary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A List row that looks like paper content: no separators, no insets, paper ground.
    func plainRow(horizontal: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: horizontal, bottom: 0, trailing: horizontal))
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.ground)
    }
}
