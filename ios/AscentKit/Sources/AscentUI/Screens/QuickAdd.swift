import SwiftUI
import AscentCore

/// 1.3 / 1.4 — the selector behind the + (glass sheet, 2 × 3 tiles, hero filled with the accent).
struct QuickAddSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent

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
            HStack(spacing: 10) {
                if live != nil { Circle().fill(accent.color).frame(width: 7, height: 7) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(headTitle(db, live)).font(.sans(15, .semibold)).foregroundStyle(Palette.ink)
                    Text(headSub(db, live, today)).font(.mono(10.5)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer()
                GlassIconButton(systemName: "xmark", label: "Close") { dismiss() }
            }
            .padding(.horizontal, 22).padding(.top, 16).padding(.bottom, 10)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(tiles(db, live: live, today: today)) { t in TileView(tile: t) }
            }
            .padding(.horizontal, 16)
            Spacer(minLength: 0)
        }
        .presentationDetents([.height(452)])
        .presentationDragIndicator(.hidden)
    }

    func headTitle(_ db: Database, _ live: Session?) -> String {
        guard let live else { return "Quick add" }
        return "\(db.gym(live.gymId)?.name ?? "Session") · \(live.startedAt.map { Day.elapsedLabel(from: $0) } ?? "0m")"
    }

    func headSub(_ db: Database, _ live: Session?, _ today: String) -> String {
        if let live {
            let sends = Metrics.sessionSends(db.climbs, sessionId: live.id)
            return "\(sends.count) SENDS · HIGH \(LiveSummary.high(sends, db: db)) · \(sends.filter(Metrics.isFlash).count) FLASHED"
        }
        if let plan = db.plannedSession(on: today) {
            return "NO SESSION · PLAN: \((plan.intent ?? "SESSION").uppercased()) AT \((db.gym(plan.gymId)?.name ?? "").uppercased())"
        }
        return "NO SESSION"
    }

    func tiles(_ db: Database, live: Session?, today: String) -> [Tile] {
        let injury = db.activeInjuries.first
        let lastPain = injury.flatMap { i in db.painEntries.filter { $0.injuryId == i.id }.max { $0.date < $1.date } }
        let painSub = injury.map { "\(shortInjury($0.name).replacingOccurrences(of: " finger", with: "").uppercased()) · LAST \(lastPain.map { "\($0.level)" } ?? "—")/10" } ?? "LOG PAIN"
        let due = dueToday(db, today)
        let pain = Tile(icon: "waveform.path.ecg", title: "Pain check-in", sub: painSub, warn: injury != nil) { go(.painCheckIn) }
        let rehab = Tile(icon: "checkmark.circle", title: "Rehab done", sub: due > 0 ? "\(due) DUE TODAY" : "ALL DONE TODAY", warn: due > 0) { go(.rehabToday) }

        if let live {
            let gym = db.gym(live.gymId)
            let lastBoard = db.climbs.last { $0.boardId != nil }
            return [
                Tile(icon: "figure.climbing", title: "Gym send",
                     sub: gym?.isRanked == true ? "\(gym?.shortName.uppercased() ?? "") · TAGS" : "\(gym?.shortName.uppercased() ?? "") · 1–\(gym?.maxGrade ?? 15)",
                     hero: true) { go(.logging(start: false, step: .log(.gym))) },
                Tile(icon: "square.grid.3x3", title: "Board send",
                     sub: lastBoard.map { "\(db.board($0.boardId)?.code == "KB" ? "KILTER" : "TENSION") \($0.angle ?? 40)°" } ?? "V1–V10") {
                    go(.logging(start: false, step: .log(.board)))
                },
                pain, rehab,
                Tile(icon: "flag.checkered", title: "End & rate", sub: "FINISH SESSION") { go(.logging(start: false, step: .review)) },
                Tile(icon: "list.bullet.clipboard", title: "Plan", sub: "TOMORROW") { planTab() },
            ]
        }
        let plan = db.plannedSession(on: today)
        return [
            Tile(icon: "play.fill", title: "Start session",
                 sub: plan.map { "\((db.gym($0.gymId)?.shortName ?? "").uppercased()) · \(($0.intent ?? "").uppercased())" } ?? "PICK A GYM",
                 hero: true) { go(.logging(start: true, step: .log(.gym))) },
            Tile(icon: "figure.climbing", title: "Gym send", sub: "STARTS A SESSION") { go(.logging(start: true, step: .log(.gym))) },
            Tile(icon: "square.grid.3x3", title: "Board send", sub: "STARTS A SESSION") { go(.logging(start: true, step: .log(.board))) },
            Tile(icon: "list.bullet.clipboard", title: "Plan today", sub: Taper.seasonLine(db, today: today)) { planTab() },
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
                Image(systemName: tile.icon).font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tile.hero ? accent.onAccent : tile.warn ? Palette.warn : Palette.ink)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tile.hero ? accent.onAccent.opacity(0.18) : Palette.track))
                Spacer(minLength: 6)
                Text(tile.title).font(.sans(15, .semibold)).foregroundStyle(tile.hero ? accent.onAccent : Palette.ink)
                Text(tile.sub).font(.mono(10)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(tile.hero ? accent.onAccent.opacity(0.8) : tile.warn ? Palette.warn : Palette.muted)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .topLeading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tile.hero ? accent.color : Palette.card.opacity(0.72)))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tile.title), \(tile.sub.lowercased())")
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
                            .font(.sans(13)).foregroundStyle(Palette.muted).padding(.bottom, 14)
                    }
                    if !db.watchingInjuries.isEmpty {
                        Text(db.activeInjuries.isEmpty ? "Watching" : "Also watching").micro().padding(.top, 4).padding(.bottom, 10)
                        ForEach(db.watchingInjuries) { w in
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    if expanded.contains(w.id) { expanded.remove(w.id) } else { expanded.insert(w.id) }
                                } label: {
                                    HStack(spacing: 10) {
                                        RoundedRectangle(cornerRadius: 3).fill(Palette.watch).frame(width: 11, height: 11)
                                        Text(shortName(w.name)).font(.sans(13.5, .medium)).foregroundStyle(Palette.ink)
                                        Spacer()
                                        Text("\(levels[w.id].map(String.init) ?? "—") /10 \(expanded.contains(w.id) ? "▾" : "▸")")
                                            .font(.mono(11)).foregroundStyle(Palette.muted)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                if expanded.contains(w.id) { PainRow(selected: levels[w.id]) { levels[w.id] = $0 } }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Palette.card).overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
                            .padding(.bottom, 6)
                        }
                    }
                    LinkButton(title: "+ New pain") { router.sheet = .newInjury }.padding(.top, 8)
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .background(Palette.paper)
            .safeAreaInset(edge: .bottom) {
                Button("Save check-in") { save() }.buttonStyle(PrimaryButtonStyle()).disabled(levels.isEmpty)
                    .padding(.horizontal, 16).padding(.vertical, 12).background(Palette.paper)
            }
            .modifier(SheetChrome(title: "Pain check-in", subtitle: Day.plan(store.today)))
        }
        .presentationDetents([.height(520), .large])
        .presentationBackground(Palette.paper)
    }

    func injuryBlock(_ inj: Injury, db: Database) -> some View {
        let entries = db.painEntries.filter { $0.injuryId == inj.id }.sorted { $0.date < $1.date }
        let last = entries.last
        let prev = entries.dropLast().last
        let rule = db.loadRules.first { $0.injuryId == inj.id }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(shortName(inj.name, full: true)).font(.sans(15, .semibold))
                Spacer()
                Text("LAST \(last.map { "\($0.level)" } ?? "—")/10").font(.mono(10.5)).foregroundStyle(Palette.warn)
            }
            PainRow(selected: levels[inj.id], last: last?.level) { levels[inj.id] = $0 }.padding(.top, 10).padding(.bottom, 6)
            if let last, let prev {
                let d = last.level - prev.level
                let w = Day.weekday(prev.date)
                Text("\(d < 0 ? "▼ \(-d)" : d > 0 ? "▲ \(d)" : "— LEVEL") SINCE \(w)\(rule != nil ? " · RULES LIFT AT 1/10" : "")")
                    .font(.mono(10.5)).foregroundStyle(Palette.muted)
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
                        Text("No exercises yet. Add them in Body.").font(.sans(13)).foregroundStyle(Palette.muted)
                    }
                    ForEach(exercises) { e in
                        RehabRow(exercise: e) { done in
                            router.show(Toast(title: e.name, detail: done ? "done" : "unticked"))
                        }
                    }
                    if !exercises.isEmpty {
                        AdherenceStrip(done: adh.done).padding(.top, 8)
                        Text("Saves as you tap.")
                            .font(.sans(12)).foregroundStyle(Palette.muted).padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .background(Palette.paper)
            .modifier(SheetChrome(title: "Rehab today",
                                  subtitle: [injury.map { shortInjury($0.name).uppercased() }, week.map { "WK \($0)" }, "\(adh.streak)-DAY STREAK"]
                                    .compactMap { $0 }.joined(separator: " · ")))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .toastOverlay(inSheet: true)
        }
        .presentationDetents([.height(500), .large])
        .presentationBackground(Palette.paper)
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
