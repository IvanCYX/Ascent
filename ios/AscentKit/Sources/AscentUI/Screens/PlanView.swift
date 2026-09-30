import SwiftUI
import AscentCore

/// Plan tab root: `Today | Season` (DESIGN §3.2–3.4).
struct PlanView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SquareSegment(options: [(Router.PlanSegment.today, "Today"), (.season, "Season")], selection: $router.planSegment)
                    .padding(.horizontal, 16).padding(.bottom, 16)
                switch router.planSegment {
                case .today: PlanDayEditor(date: store.today)
                case .season: SeasonView()
                }
            }
        }
        .background(Palette.paper)
        .navigationTitle("Plan")
        .navigationSubtitle(Taper.seasonLine(store.db, today: store.today))
        .largeTitle()
        .toolbar {
            if router.planSegment == .season {
                ToolbarItem(placement: .trailing) {
                    Button("Add comp") { router.sheet = .compEditor(compId: nil, date: nil) }
                }
            }
        }
    }
}

/// A future day from the Season calendar.
struct PlanDayScreen: View {
    @Environment(AscentStore.self) private var store
    var date: String

    var body: some View {
        ScrollView { PlanDayEditor(date: date).padding(.top, 8) }
            .background(Palette.paper)
            .navigationTitle(Day.long(date))
            .inlineTitle()
    }
}

/// Web `3d` session plan, for today (Start session) or any other day (Save plan). Taper-aware (§3.3).
struct PlanDayEditor: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var date: String

    @State private var loadedFor: String?
    @State private var gymId = ""
    @State private var intent = "Max strength"
    @State private var focus: [String] = []
    @State private var blocks: [PlanBlock] = []
    @State private var savedTemplate = false
    @State private var savedPlan = false

    var body: some View {
        let db = store.db
        let isToday = date == store.today
        let existing = db.plannedSession(on: date)
        let usage = Metrics.loadRuleUsage(db.loadRules.filter { $0.maxPerWeek != nil }, climbs: db.climbs, weekStart: Day.weekStart(date))
        let blocked = blockedStyles(db, usage)
        let dp = Taper.dayPhase(db.competitions, on: date)
        let tapering = (dp?.phase.isTaper ?? false) && db.settings.taperOverrideDay != date
        let weak = weakStyles(db)
        let injuryDrop = injuryDroppedStyle(db, dp: dp)
        let suggested = Array(stableSort(Vocab.climbStyles) { weak.contains($0) && !weak.contains($1) }
            .filter { $0 != injuryDrop }.prefix(5))
        let activeBlockedFocus = focus.filter { blocked[$0] != nil }
        let rehab = rehabBlock(db)
        let allBlocks = rehab.map { blocks + [$0] } ?? blocks
        let scaled = tapering ? Taper.scale(allBlocks, factor: dp!.factor) : nil
        let shown = scaled?.blocks ?? allBlocks
        let total = shown.reduce(0) { $0 + $1.durationMin }
        let gym = db.gym(gymId)

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(Day.plan(date)) · \(gym?.name ?? "No gym")").micro()
                Text("\(intent.capitalized) Day")
                    .font(.serif(27, relativeTo: .title)).foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.bottom, 16)

            if tapering, let dp, let scaled {
                TaperCard(dp: dp, scaled: scaled, db: db, date: date).padding(.horizontal, 16).padding(.bottom, 4)
            }

            if !tapering {
                Band {
                    Text("Gym").micro().padding(.bottom, 12)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(db.gyms) { g in Chip(label: g.name, on: g.id == gymId, small: true) { gymId = g.id } }
                        }
                    }
                    .scrollClipDisabled()
                }
            }

            Band(top: !tapering) {
                Text("Session type").micro().padding(.bottom, 12)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
                    ForEach(Vocab.sessionIntents, id: \.self) { i in
                        let struck = tapering && Vocab.highCostIntents.contains(i)
                        Button { applyIntent(i, db: db) } label: {
                            Text(i).font(.sans(13, i == intent ? .semibold : .medium))
                                .strikethrough(struck)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(struck ? Palette.faint : i == intent ? Palette.paper : Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .padding(.horizontal, 6)
                                .background(i == intent ? Palette.ink : Palette.card)
                                .overlay(Rectangle().strokeBorder(i == intent ? Palette.ink : Palette.ruleChip, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(struck)
                        .accessibilityAddTraits(i == intent ? .isSelected : [])
                    }
                }
                if tapering {
                    Insight(label: nil, text: "Max strength and power endurance are off until the comp.")
                }
            }

            Band {
                SectionHead("Focus", note: "WEAKEST FIRST")
                ChipFlow(spacing: 7) {
                    ForEach(suggested, id: \.self) { s in
                        Chip(label: s, on: focus.contains(s), blocked: blocked[s] != nil) {
                            if focus.contains(s) { focus.removeAll { $0 == s } } else { focus.append(s) }
                        }
                    }
                }
                if let (style, info) = blocked.sorted(by: { $0.key < $1.key }).first {
                    let alt = suggested.first { blocked[$0] == nil && weak.contains($0) }
                    WarnPanel(lead: "\(style) off",
                              text: "\(info.usage.used)/\(info.usage.cap ?? 0) this week for \(shortInjury(info.injury)). \(alt.map { "Try \($0.lowercased())." } ?? "Pick another style.")")
                        .padding(.top, 15)
                }
                if !activeBlockedFocus.isEmpty {
                    Text("REMOVE \(activeBlockedFocus.joined(separator: ", ").uppercased()) TO START")
                        .font(.mono(10)).foregroundStyle(Palette.warn).padding(.top, 8)
                }
            }

            Band {
                SectionHead("Blocks", note: scaled.map { "\($0.minutes) MIN · WAS \($0.originalMinutes)" } ?? "\(total) MIN")
                VStack(spacing: 8) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, b in BlockRow(block: b, tapering: tapering) }
                }
                HStack(spacing: 8) {
                    if tapering {
                        Button("Use full plan") { store.setTaperOverride(date) }.buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button(savedTemplate ? "Saved" : "Save template") {
                            persist(existing: existing, blocks: allBlocks)
                            store.saveTemplate(intent, blocks: blocks)
                            savedTemplate = true
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    if isToday {
                        Button("Start session") { start(existing: existing, blocks: shown) }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!activeBlockedFocus.isEmpty || db.activeSession != nil)
                    } else {
                        Button(savedPlan ? "Plan saved" : "Save plan") {
                            persist(existing: existing, blocks: shown)
                            savedPlan = true
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
                .padding(.top, 16)
                if isToday && db.activeSession != nil {
                    Text("A session is already running.").font(.sans(12)).foregroundStyle(Palette.muted).padding(.top, 8)
                }
                if db.settings.taperOverrideDay == date, dp?.phase.isTaper == true {
                    LinkButton(title: "Use taper plan") { store.setTaperOverride(nil) }.padding(.top, 8)
                }
                if let comp = db.upcomingComps(from: date).first(where: { $0.effectivePriority != .c }) ?? db.nextComp(from: date) {
                    Text(footer(comp, date: date)).micro().padding(.top, 16).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 80)
        }
        .onAppear { load(db) }
        .onChange(of: date) { load(store.db) }
    }

    /* ── State ───────────────────────────────────────────────────────── */

    private func load(_ db: Database) {
        guard loadedFor != date else { return }
        loadedFor = date
        let existing = db.plannedSession(on: date)
        gymId = existing?.gymId ?? db.gyms.first?.id ?? ""
        let start = existing?.intent ?? "Max strength"
        let dp = Taper.dayPhase(db.competitions, on: date)
        let tapering = (dp?.phase.isTaper ?? false) && db.settings.taperOverrideDay != date
        intent = tapering && Vocab.highCostIntents.contains(start) ? "Comp sim" : start
        focus = existing?.focusStyles ?? []
        let stored = existing?.plannedBlocks?.filter { !$0.isRehab }
        blocks = (stored?.isEmpty == false && intent == start) ? stored! : PlanTemplates.blocks(for: intent, in: db)
    }

    private func applyIntent(_ i: String, db: Database) {
        intent = i
        blocks = PlanTemplates.blocks(for: i, in: db)
        savedTemplate = false
    }

    private func persist(existing: Session?, blocks: [PlanBlock]) {
        store.savePlan(id: existing?.id, date: date, gymId: gymId, intent: intent, focusStyles: focus, plannedBlocks: blocks)
    }

    private func start(existing: Session?, blocks: [PlanBlock]) {
        let id = store.savePlan(id: existing?.id, date: date, gymId: gymId, intent: intent, focusStyles: focus, plannedBlocks: blocks)
        store.startSession(gymId: gymId, intent: intent, focusStyles: focus, plannedBlocks: blocks, fromPlanId: id)
        router.sheet = .logging(start: false, step: .log(.gym))
    }

    /* ── Derived ─────────────────────────────────────────────────────── */

    struct BlockInfo { var usage: Metrics.LoadRuleUsage; var injury: String }

    private func blockedStyles(_ db: Database, _ usage: [Metrics.LoadRuleUsage]) -> [String: BlockInfo] {
        var out: [String: BlockInfo] = [:]
        for u in usage where u.blocked {
            guard let rule = db.loadRules.first(where: { $0.id == u.ruleId }) else { continue }
            out[rule.styleOrType] = BlockInfo(usage: u, injury: db.injuries.first { $0.id == rule.injuryId }?.name ?? "an active injury")
        }
        return out
    }

    /// Weak styles feed the focus list.
    private func weakStyles(_ db: Database) -> [String] {
        let w = RangeID.eightWeeks.windows(today: date)
        return Metrics.compReadiness(Metrics.climbsInRange(db.climbs, from: w.from, to: w.to), reviews: db.reviews, today: date)
            .filter(\.warn).map { $0.label == "Crimps" ? "Crimpy" : $0.label }
    }

    /// From PEAK on, a ruled style leaves the comp-sim focus while the injury's pain is above 1/10.
    private func injuryDroppedStyle(_ db: Database, dp: Taper.DayPhase?) -> String? {
        guard let dp, dp.phase == .peak || dp.phase.isTaper, let injury = db.activeInjuries.first else { return nil }
        let pain = db.painEntries.filter { $0.injuryId == injury.id }.max { $0.date < $1.date }?.level ?? 0
        guard pain > 1 else { return nil }
        return db.loadRules.first { $0.injuryId == injury.id && $0.maxPerWeek != nil }?.styleOrType
    }

    /// A rehab block is appended while an injury is active, unless one is already there.
    private func rehabBlock(_ db: Database) -> PlanBlock? {
        guard let injury = db.activeInjuries.first, !blocks.contains(where: \.isRehab) else { return nil }
        let ex = db.rehabExercises.first { $0.injuryId == injury.id }
        return PlanBlock(10, "\(shortInjury(injury.name)) rehab · \(ex?.name.lowercased() ?? "protocol")", target: "rehab", rehab: true)
    }

    private func footer(_ comp: Competition, date: String) -> String {
        var parts = ["NEXT: \(comp.shortName)", "\(Metrics.weeksOut(today: date, compDate: comp.date)) WK"]
        if let t = Taper.taperStart(comp), t > date { parts.append("TAPER \(Day.plan(t))") }
        return parts.joined(separator: " · ")
    }

    private func stableSort(_ xs: [String], by first: (String, String) -> Bool) -> [String] {
        xs.enumerated().sorted { a, b in
            if first(a.element, b.element) { return true }
            if first(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}

struct BlockRow: View {
    var block: PlanBlock
    var tapering = false

    var body: some View {
        HStack(spacing: 14) {
            Text("\(block.durationMin) min").font(.mono(11)).foregroundStyle(block.isEmphasis ? Palette.ink : Palette.muted)
                .frame(width: 48, alignment: .leading)
            Text(block.description).font(.sans(13.5, .medium)).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Text(block.isRehab && tapering ? "rehab · kept" : block.target ?? "")
                .font(.sans(12)).multilineTextAlignment(.trailing)
                .foregroundStyle(block.isRehab ? Palette.warn : block.isEmphasis ? Palette.ink : Palette.muted)
                .frame(maxWidth: 110, alignment: .trailing)
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(Palette.card)
        .overlay(Rectangle().strokeBorder(block.isEmphasis ? Palette.ink : Palette.rule, lineWidth: block.isEmphasis ? 2 : 1))
        .accessibilityElement(children: .combine)
    }
}

/// `TAPER · 70% VOLUME` card (3.3).
struct TaperCard: View {
    var dp: Taper.DayPhase
    var scaled: Taper.ScaledPlan
    var db: Database
    var date: String

    var body: some View {
        let avg = Taper.averages(db, today: date).minutesPerWeek
        let week = Taper.minutesThisWeek(db, today: date)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(dp.phase.rawValue) · \(Int(dp.factor * 100))% VOLUME").micro(Palette.ink)
                Spacer()
                Text("\(dp.comp.shortName) · \(Day.plan(dp.comp.date))").font(.mono(10.5)).foregroundStyle(Palette.muted)
            }
            Text(scaled.explanation).font(.sans(13)).foregroundStyle(Palette.muted).padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
            LoadBar(fill: avg > 0 ? Double(week) / Double(avg) : 0)
            HStack {
                Text("THIS WEEK \(week) MIN")
                Spacer()
                Text("AVG \(avg)")
            }
            .font(.mono(10)).foregroundStyle(Palette.muted).padding(.top, 7)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Palette.card)
        .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: 2))
    }
}
