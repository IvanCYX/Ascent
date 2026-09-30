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
        let months = Dictionary(grouping: sessions, by: { Day.monthKey($0.date) }).sorted { $0.key > $1.key }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                Band(top: false) { ChipTrendPanel(rows: trends, pattern: Metrics.chipPattern(trends)) }
                if isFiltered {
                    HStack {
                        Text(filterLabel(db)).micro(Palette.ink)
                        Spacer()
                        LinkButton(title: "Clear") { gymFilter = nil; intentFilter = nil; ratedOnly = false }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .overlay(alignment: .top) { Hairline() }
                }
                ForEach(months, id: \.key) { month, rows in
                    Band {
                        Text("\(Day.monthName(month + "-01")) \(month.prefix(4))").micro().padding(.bottom, 4)
                        ForEach(rows) { s in
                            NavigationLink(value: Route.session(s.id)) { LedgerRow(session: s, db: db) }.buttonStyle(.plain)
                        }
                    }
                }
                if sessions.isEmpty {
                    Text("No sessions match.").font(.sans(13)).foregroundStyle(Palette.muted).padding(16)
                }
            }
            .padding(.bottom, 80)
        }
        .background(Palette.paper)
        .navigationTitle("History")
        .navigationSubtitle("\(sessions.count) SESSIONS")
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

    func filterLabel(_ db: Database) -> String {
        [db.gym(gymFilter)?.name, intentFilter, ratedOnly ? "rated" : nil].compactMap { $0 }.joined(separator: " · ")
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
                    VStack(alignment: .leading, spacing: 10) {
                        Text([db.gym(s.gymId)?.name, s.intent, duration].compactMap { $0 }.joined(separator: " · ")).micro()
                        Text(Day.long(s.date).components(separatedBy: " ").dropLast().joined(separator: " "))
                            .font(.serif(32, relativeTo: .largeTitle))
                    }
                    .padding(.horizontal, 16).padding(.bottom, 12)

                    KpiGrid(kpis: detailKpis(sends: sends, review: review, avg: avg))

                    if let review {
                        Band {
                            Text("Review").micro().padding(.bottom, 10)
                            ChipFlow {
                                ForEach(review.chips, id: \.self) { c in
                                    Chip(label: c, on: true, small: true, kind: c.contains("/10") ? .pain : .normal) {}
                                        .allowsHitTesting(false)
                                }
                            }
                            if let note = review.note {
                                Text("“\(note)”").font(.serif(16, italic: true)).foregroundStyle(Palette.ink).padding(.top, 14)
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
                    sectionHead("Board climbs", note: Set(boardClimbs.compactMap { db.board($0.boardId)?.name }).sorted().joined(separator: " · "))
                    ForEach(boardClimbs) { c in
                        ClimbRow(climb: c).plainRow(horizontal: 16)
                            .swipeActions { Button("Delete", role: .destructive) { pendingDelete = c } }
                    }
                }
                if let blocks = s.plannedBlocks, !blocks.isEmpty {
                    Band {
                        SectionHead("Plan", note: "\(blocks.reduce(0) { $0 + $1.durationMin }) MIN")
                        Text(blocks.map { $0.description.components(separatedBy: " · ").first ?? $0.description }.joined(separator: " · "))
                            .font(.sans(13)).foregroundStyle(Palette.muted)
                    }
                    .plainRow()
                }
                Band {
                    Button("Delete session", role: .destructive) { confirmSessionDelete = true }
                        .buttonStyle(SecondaryButtonStyle()).foregroundStyle(Palette.warn)
                }
                .plainRow()
                .padding(.bottom, 60)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.paper)
            .environment(\.defaultMinListRowHeight, 0)
            .navigationTitle(Day.plan(s.date).capitalized)
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
            Text("This session was deleted.").font(.sans(14)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
        }
    }

    func detailKpis(sends: [Climb], review: SessionReview?, avg: Double?) -> [Metrics.Kpi] {
        let flashed = sends.filter(Metrics.isFlash).count
        let felt: String = review.map { String(format: "%.1f", $0.overallScore) } ?? "—"
        let avgText: String = avg.map { String(format: "avg %.1f", $0) } ?? ""
        return [
            Metrics.Kpi(label: "SENDS", value: "\(sends.count)", caption: "\(flashed) flashed", delta: "", deltaStrong: false),
            Metrics.Kpi(label: "FELT", value: felt, caption: avgText, delta: "", deltaStrong: false),
        ]
    }

    func sectionHead(_ title: String, note: String?) -> some View {
        SectionHead(title, note: note)
            .padding(.horizontal, 16).padding(.top, 20)
            .overlay(alignment: .top) { Hairline() }
            .plainRow()
    }
}

struct ClimbRow: View {
    var climb: Climb

    var body: some View {
        HStack(spacing: 10) {
            Text(gradeLabel(climb)).font(.serif(16)).frame(width: 30, alignment: .leading)
            if climb.gradeKind != .v { Swatch(colour: climb.holdColour ?? climb.tagId, size: 15) }
            Text(climb.gradeKind == .v ? boardDetail(climb) : climbDetail(climb).ifEmpty(Vocab.colourLabel(climb.tagId)))
                .font(.sans(13)).foregroundStyle(Palette.muted).lineLimit(1)
            Spacer()
            Text(Day.timeOfDay(climb.createdAt)).font(.mono(11)).foregroundStyle(Palette.faint)
        }
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// A List row that looks like paper content: no separators, no insets, paper ground.
    func plainRow(horizontal: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: horizontal, bottom: 0, trailing: horizontal))
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.paper)
    }
}
