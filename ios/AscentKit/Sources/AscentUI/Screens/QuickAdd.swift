import SwiftUI
import AscentCore

/// 1.3 / 1.4 — the selector behind the + (2 × 3 tiles, hero filled with the accent, sized to its content).
struct QuickAddSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    @State private var height: CGFloat = 470

    struct Tile: Identifiable {
        var id: String { title }
        var icon: String
        var title: String
        var sub: String
        var warn = false
        var hero = false
        var action: () -> Void
    }

    var body: some View {
        let db = store.db
        let today = store.today
        let live = db.activeSession
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if live != nil { Circle().fill(accent.color).frame(width: 8, height: 8) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(headTitle(db, live)).font(.sans(17, .semibold)).foregroundStyle(Palette.text)
                    Text(headSub(db, live, today)).font(.sans(13)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Spacer()
                GlassIconButton(systemName: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(tiles(db, live: live, today: today)) { t in TileView(tile: t) }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.hidden)
    }

    func headTitle(_ db: Database, _ live: Session?) -> String {
        guard let live else { return "Quick add" }
        return "\(db.gym(live.gymId)?.name ?? "Session"), \(live.startedAt.map { Day.elapsedLabel(from: $0) } ?? "0m")"
    }

    func headSub(_ db: Database, _ live: Session?, _ today: String) -> String {
        if let live {
            let sends = Metrics.sessionSends(db.climbs, sessionId: live.id)
            return "\(sends.count) sends, high \(LiveSummary.high(sends, db: db)), \(sends.filter(Metrics.isFlash).count) flashed"
        }
        if let plan = db.plannedSession(on: today) {
            return "No session. Plan: \(plan.intent ?? "session") at \(db.gym(plan.gymId)?.name ?? "the gym")"
        }
        return "No session running"
    }

    func tiles(_ db: Database, live: Session?, today: String) -> [Tile] {
        let injury = db.activeInjuries.first
        let lastPain = injury.flatMap { i in db.painEntries.filter { $0.injuryId == i.id }.max { $0.date < $1.date } }
        let painSub = injury.map { "\(shortInjury($0.name).replacingOccurrences(of: " finger", with: "")), last \(lastPain.map { "\($0.level)" } ?? "–")/10" } ?? "Log pain"
        let due = dueToday(db, today)
        let pain = Tile(icon: "waveform.path.ecg", title: "Pain check-in", sub: painSub, warn: injury != nil) { go(.painCheckIn) }
        let rehab = Tile(icon: "checkmark.circle", title: "Rehab done", sub: due > 0 ? "\(due) due today" : "All done today", warn: due > 0) { go(.rehabToday) }

        if let live {
            let gym = db.gym(live.gymId)
            let lastBoard = db.climbs.last { $0.boardId != nil }
            return [
                Tile(icon: "figure.climbing", title: "Gym send",
                     sub: "\(gym?.shortName ?? ""), \(gym?.isRanked == true ? "tags" : gym?.gradeSpan ?? "1 to 15")",
                     hero: true) { go(.logging(start: false, step: .log(.gym))) },
                Tile(icon: "square.grid.3x3", title: "Board send",
                     sub: lastBoard.map { "\(db.board($0.boardId)?.code == "KB" ? "Kilter" : "Tension") \($0.angle ?? 40)°" } ?? "V1 to V10") {
                    go(.logging(start: false, step: .log(.board)))
                },
                pain, rehab,
                Tile(icon: "flag.checkered", title: "End session", sub: "Finish and rate") { router.endSession() },
                Tile(icon: "list.bullet.clipboard", title: "Plan", sub: "Tomorrow") { planTab() },
            ]
        }
        let plan = db.plannedSession(on: today)
        return [
            Tile(icon: "play.fill", title: "Start session",
                 sub: plan.map { "\(db.gym($0.gymId)?.shortName ?? ""), \(($0.intent ?? "").lowercased())" } ?? "Pick a gym",
                 hero: true) { go(.logging(start: true, step: .log(.gym))) },
            Tile(icon: "figure.climbing", title: "Gym send", sub: "Starts a session") { go(.logging(start: true, step: .log(.gym))) },
            Tile(icon: "square.grid.3x3", title: "Board send", sub: "Starts a session") { go(.logging(start: true, step: .log(.board))) },
            Tile(icon: "list.bullet.clipboard", title: "Plan today", sub: Taper.seasonText(db, today: today)) { planTab() },
            pain, rehab,
        ]
    }

    func dueToday(_ db: Database, _ today: String) -> Int {
        let ids = Set(db.activeInjuries.map(\.id))
        return db.rehabExercises.filter { ids.contains($0.injuryId) && $0.frequency >= 7 }
            .filter { e in !db.rehabLogs.contains { $0.exerciseId == e.id && $0.date == today && $0.done } }.count
    }

    func go(_ next: SheetRoute) { router.sheet = next }

    func planTab() {
        router.sheet = nil
        router.planSegment = .today
        router.select(.plan)
    }
}

struct TileView: View {
    @Environment(\.accent) private var accent
    var tile: QuickAddSheet.Tile

    var body: some View {
        Button(action: tile.action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: tile.icon).font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tile.hero ? accent.onAccent : tile.warn ? Palette.injury : Palette.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(tile.hero ? accent.onAccent.opacity(0.12) : Palette.text.opacity(0.08)))
                Spacer(minLength: 14)
                Text(tile.title).font(.sans(17, .bold)).foregroundStyle(tile.hero ? accent.onAccent : Palette.text)
                Text(tile.sub).font(.sans(13)).lineLimit(1).minimumScaleFactor(0.75)
                    .foregroundStyle(tile.hero ? accent.onAccent.opacity(0.7) : tile.warn ? Palette.injuryText : Palette.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tile.hero ? accent.color : Palette.tile))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(TilePressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.title), \(tile.sub)")
    }
}

struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/* ── 2.8 Pain check-in ──────────────────────────────────────────────────── */

struct PainCheckInSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var levels: [String: Int] = [:]
    @State private var expanded: Set<String> = []

    var body: some View {
        let db = store.db
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(db.activeInjuries) { inj in injuryBlock(inj, db: db).padding(.bottom, 18) }
                    if db.activeInjuries.isEmpty {
                        Text("No active injuries.")
                            .font(.sans(13)).foregroundStyle(Palette.secondary).padding(.bottom, 14)
                    }
                    if !db.watchingInjuries.isEmpty {
                        FieldLabel(title: db.activeInjuries.isEmpty ? "Watching" : "Also watching").padding(.top, 4)
                        ForEach(db.watchingInjuries) { w in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    if expanded.contains(w.id) { expanded.remove(w.id) } else { expanded.insert(w.id) }
                                } label: {
                                    HStack(spacing: 10) {
                                        Circle().fill(Palette.caution).frame(width: 10, height: 10)
                                        Text(shortName(w.name)).font(.sans(15, .medium)).foregroundStyle(Palette.text)
                                        Spacer()
                                        Text("\(levels[w.id].map(String.init) ?? "–")/10")
                                            .font(.num(13)).foregroundStyle(Palette.secondary)
                                        Image(systemName: expanded.contains(w.id) ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.tertiary)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if expanded.contains(w.id) { PainRow(selected: levels[w.id]) { levels[w.id] = $0 } }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                            .padding(.bottom, 8)
                        }
                    }
                    LinkButton(title: "+ New pain") { router.sheet = .newInjury }.padding(.top, 8)
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .background(Palette.sheet)
            .safeAreaInset(edge: .bottom) {
                Button("Save check-in") { save() }.buttonStyle(PrimaryButtonStyle()).disabled(levels.isEmpty)
                    .padding(.horizontal, 16).padding(.vertical, 12).background(Palette.sheet)
            }
            .modifier(SheetChrome(title: "Pain check-in", subtitle: Day.fullDate(store.today)))
        }
        .presentationDetents([.height(520), .large])
        .presentationBackground(Palette.sheet)
    }

    func injuryBlock(_ inj: Injury, db: Database) -> some View {
        let entries = db.painEntries.filter { $0.injuryId == inj.id }.sorted { $0.date < $1.date }
        let last = entries.last
        let prev = entries.dropLast().last
        let rule = db.loadRules.first { $0.injuryId == inj.id }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(shortName(inj.name, full: true)).font(.sans(16, .semibold)).foregroundStyle(Palette.text)
                Spacer()
                Text("Last \(last.map { "\($0.level)" } ?? "–")/10").font(.sans(13)).foregroundStyle(Palette.injuryText)
            }
            PainRow(selected: levels[inj.id], last: last?.level) { levels[inj.id] = $0 }.padding(.top, 10).padding(.bottom, 6)
            if let last, let prev {
                let d = last.level - prev.level
                let w = Day.weekday(prev.date)
                Text("\(d < 0 ? "Down \(-d)" : d > 0 ? "Up \(d)" : "Level") since \(Day.weekdayShort(prev.date))\(rule != nil ? ". Rules lift at 1/10." : "")")
                    .font(.sans(13)).foregroundStyle(d > 0 ? Palette.cautionText : Palette.secondary)
            }
        }
    }

    func shortName(_ name: String, full: Bool = false) -> String {
        let parts = name.components(separatedBy: " · ")
        guard parts.count == 2 else { return name }
        let tail = parts[1].components(separatedBy: " ").prefix(full ? 2 : 1).joined(separator: " ")
        return "\(full ? parts[0] : shortInjury(name)) · \(tail)"
    }

    func save() {
        for (id, level) in levels { store.addPainEntry(injuryId: id, level: level) }
        router.show(Toast(title: "Pain logged", detail: levels.count == 1 ? "\(levels.values.first!)/10" : "\(levels.count) areas"))
        dismiss()
    }
}

/* ── 2.9 Rehab today ────────────────────────────────────────────────────── */

struct RehabTodaySheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let db = store.db
        let today = store.today
        let injury = db.activeInjuries.first ?? db.watchingInjuries.first
        let exercises = db.rehabExercises.filter { $0.injuryId == injury?.id }
        let adh = Metrics.rehabAdherence(exercises, logs: db.rehabLogs, today: today)
        let week = injury?.rehabStart.map { max(1, Day.weeksBetween($0, today) + 1) }

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if exercises.isEmpty {
                        Text("No exercises yet. Add them in Body.").font(.sans(13)).foregroundStyle(Palette.secondary)
                    }
                    ForEach(exercises) { e in
                        RehabRow(exercise: e) { done in
                            router.show(Toast(title: e.name, detail: done ? "done" : "unticked"))
                        }
                    }
                    if !exercises.isEmpty {
                        AdherenceStrip(done: adh.done).padding(.top, 8)
                        Text("Saves as you tap.")
                            .font(.sans(12)).foregroundStyle(Palette.secondary).padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .background(Palette.sheet)
            .modifier(SheetChrome(title: "Rehab today",
                                  subtitle: [injury.map { shortInjury($0.name) }, week.map { "week \($0)" }, "\(adh.streak)-day streak"]
                                    .compactMap { $0 }.joined(separator: ", ")))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .toastOverlay(inSheet: true)
        }
        .presentationDetents([.height(500), .large])
        .presentationBackground(Palette.sheet)
    }
}

/* ── Toasts ─────────────────────────────────────────────────────────────── */

struct ToastOverlay: ViewModifier {
    @Environment(Router.self) private var router
    var inSheet: Bool
    var bottom: CGFloat = 12
    /// Sits higher while the tab bar is showing.
    var clearsTabBar = false

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = router.toast, inSheet == (router.sheet != nil) {
                ToastView(toast: toast) { router.toast = nil }
                    .padding(.bottom, bottom + (clearsTabBar && !router.barHidden ? 70 : 0))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
            }
        }
        .animation(.spring(duration: 0.3), value: router.toast)
    }
}

extension View {
    func toastOverlay(inSheet: Bool, bottom: CGFloat = 12, clearsTabBar: Bool = false) -> some View {
        modifier(ToastOverlay(inSheet: inSheet, bottom: bottom, clearsTabBar: clearsTabBar))
    }
}
