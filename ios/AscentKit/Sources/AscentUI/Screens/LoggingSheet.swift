import SwiftUI
import AscentCore

/// Web `/log`, `/board`, `/review` as one sheet with its own stack (DESIGN §3, 2.1–2.7).
struct LoggingSheet: View {
    @Environment(AscentStore.self) private var store
    var start: Bool
    var step: LogStep
    /// Reviewing a finished session from History.
    var reviewSessionId: String?

    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let id = reviewSessionId {
                    ReviewView(sessionId: id, path: $path)
                } else if store.db.activeSession == nil && (start || step != .review) {
                    StartSessionView(onStarted: {})
                } else {
                    switch step {
                    case .log(let mode): LogView(initialMode: mode, path: $path)
                    case .review: ReviewView(sessionId: nil, path: $path)
                    }
                }
            }
            .navigationDestination(for: LogStep.self) { s in
                switch s {
                case .log(let mode): LogView(initialMode: mode, path: $path)
                case .review: ReviewView(sessionId: nil, path: $path)
                }
            }
            .navigationDestination(for: SavedRoute.self) { r in
                SavedView(sessionId: r.sessionId, editing: reviewSessionId != nil, path: $path)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Palette.paper)
    }
}

struct SavedRoute: Hashable { var sessionId: String }

/// Close button + title with a mono subtitle, shared by every step.
struct SheetChrome: ViewModifier {
    @Environment(Router.self) private var router
    var title: String
    var subtitle: String

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationSubtitle(subtitle)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Not `dismiss`: on a step pushed inside the sheet that would only pop back.
                    Button { router.closeSheet() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
    }
}

/* ── 2.1 Start session ──────────────────────────────────────────────────── */

struct StartSessionView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var onStarted: () -> Void
    @State private var gymId = ""
    @State private var intent: String?
    @State private var focus: [String] = []
    @State private var loaded = false

    var body: some View {
        let db = store.db
        let plan = db.plannedSession(on: store.today)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let plan {
                    Text("\(Text("Plan for today · ").bold().foregroundStyle(Palette.ink))\(plan.intent ?? "A session") at \(db.gym(plan.gymId)?.name ?? "the gym"). ")
                        .font(.sans(13)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .background(Palette.card).overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
                        .overlay(alignment: .bottomTrailing) {
                            LinkButton(title: "Open plan") { router.planSegment = .today; router.closeSheet(then: .plan) }.padding(.trailing, 14)
                        }
                }
                Text("Gym").micro().padding(.top, 22).padding(.bottom, 10)
                ChipFlow { ForEach(db.gyms) { g in Chip(label: g.name, on: gymId == g.id, small: true) { gymId = g.id } } }
                Text("Intent — optional").micro().padding(.top, 22).padding(.bottom, 10)
                ChipFlow {
                    ForEach(Vocab.sessionIntents, id: \.self) { i in
                        Chip(label: i, on: intent == i, small: true) { intent = intent == i ? nil : i }
                    }
                }
                if !focus.isEmpty {
                    Text("Focus from plan").micro().padding(.top, 22).padding(.bottom, 10)
                    ChipFlow { ForEach(focus, id: \.self) { f in Chip(label: f, on: true, small: true) { focus.removeAll { $0 == f } } } }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Palette.paper)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                Button("Start session") {
                    let fromPlan = plan != nil && plan?.gymId == gymId ? plan?.id : nil
                    store.startSession(gymId: gymId, intent: intent, focusStyles: focus.isEmpty ? nil : focus,
                                       plannedBlocks: fromPlan == nil ? nil : plan?.plannedBlocks, fromPlanId: fromPlan)
                    onStarted()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(gymId.isEmpty)
                Text("Starts the clock and opens Log a send.").font(.sans(12)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Palette.paper)
        }
        .modifier(SheetChrome(title: "Start session", subtitle: Day.plan(store.today)))
        .onAppear {
            guard !loaded else { return }
            loaded = true
            gymId = plan?.gymId ?? db.gyms.first?.id ?? ""
            intent = plan?.intent
            focus = plan?.focusStyles ?? []
        }
    }
}

/* ── 2.2–2.5 Log a send / Tally / Board ─────────────────────────────────── */

struct LogView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var initialMode: LogMode
    @Binding var path: NavigationPath
    @State private var mode: LogMode?
    @State private var tick = Date.now

    var body: some View {
        let db = store.db
        if let session = db.activeSession {
            let gym = db.gym(session.gymId)
            let current = mode ?? initialMode
            VStack(spacing: 0) {
                SquareSegment(options: [(LogMode.gym, "Gym"), (.board, "Board")], selection: Binding(get: { current }, set: { mode = $0 }))
                    .padding(.horizontal, 16).padding(.bottom, 12)
                switch current {
                case .gym:
                    if gym?.isRanked == true { TallyLogView(session: session, gym: gym!, path: $path) }
                    else { GymLogView(session: session, gym: gym, path: $path) }
                case .board:
                    BoardLogView(session: session, path: $path)
                }
            }
            .background(Palette.paper)
            .modifier(SheetChrome(title: current == .board ? "Board session" : gym?.isRanked == true ? "Tally" : "Log a send",
                                  subtitle: subtitle(session: session, gym: gym, mode: current)))
            .toolbar {
                if current == .gym {
                    ToolbarItem(placement: .confirmationAction) {
                        Menu {
                            ForEach(db.gyms) { g in
                                Button { store.setActiveGym(session.id, gymId: g.id) } label: {
                                    if g.id == gym?.id { Label(g.name, systemImage: "checkmark") } else { Text(g.name) }
                                }
                            }
                        } label: {
                            Text("\(gym?.shortName ?? "Gym") ▾").font(.system(size: 14, weight: .semibold))
                        }
                        .accessibilityLabel("Switch gym, now \(gym?.name ?? "none")")
                    }
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    tick = .now
                }
            }
        } else {
            StartSessionView(onStarted: {})
        }
    }

    func subtitle(session: Session, gym: Gym?, mode: LogMode) -> String {
        let elapsed = session.startedAt.map { Day.elapsedLabel(from: $0, now: tick) } ?? "0m"
        if mode == .board { return "\(gym?.name ?? "Board") · \(elapsed)".uppercased() }
        let scale = gym?.isRanked == true ? "YELLOW → BLACK" : "1–\(gym?.maxGrade ?? 15)"
        return "\(gym?.name ?? "No gym") · \(scale) · \(elapsed)".uppercased()
    }
}

/// Load rules tripped by the current style selection.
func trippedRules(_ db: Database, styles: [String], today: String) -> [Metrics.LoadRuleUsage] {
    Metrics.loadRuleUsage(db.loadRules.filter { $0.maxPerWeek != nil }, climbs: db.climbs, weekStart: Day.weekStart(today))
        .filter { u in
            (u.blocked || u.nearing) && styles.contains(db.loadRules.first { $0.id == u.ruleId }?.styleOrType ?? "")
        }
}

/// Optional fields, kept from the last climb.
struct OptionalBlock: View {
    @Binding var tickType: TickType
    @Binding var styles: [String]
    @Binding var location: String
    var styleList = Vocab.climbStyles
    var showWhere = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Optional — kept from last climb").micro()
                Spacer()
                LinkButton(title: "Clear") { tickType = .flash; styles = []; location = "" }
            }
            .padding(.bottom, 6)
            ChipFlow {
                ForEach(Vocab.tickTypes, id: \.id) { t in Chip(label: t.label, on: tickType == t.id, small: true) { tickType = t.id } }
            }
            .padding(.bottom, 8)
            ChipFlow {
                ForEach(styleList, id: \.self) { s in
                    Chip(label: s, on: styles.contains(s), small: true) {
                        if styles.contains(s) { styles.removeAll { $0 == s } } else { styles.append(s) }
                    }
                }
            }
            .padding(.bottom, 10)
            if showWhere { TextFieldRow(label: "WHERE", placeholder: "cave, right of the arête", text: $location) }
        }
    }
}

struct GymLogView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var session: Session
    var gym: Gym?
    @Binding var path: NavigationPath

    @State private var grade: Int?
    @State private var colour: String?
    @State private var tickType: TickType = .flash
    @State private var styles: [String] = []
    @State private var location = ""
    @State private var showAll = false
    @State private var sentCount = 0

    var body: some View {
        let db = store.db
        let maxGrade = gym?.maxGrade ?? 15
        let lowest = showAll ? 1 : max(1, maxGrade - 9)
        let climbs = db.climbs.filter { $0.sessionId == session.id }.sorted { $0.createdAt > $1.createdAt }
        let sends = climbs.filter(Metrics.isSend)
        let tripped = trippedRules(db, styles: styles, today: store.today)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("1 · Grade").micro()
                    Spacer()
                    if maxGrade > 10 { LinkButton(title: showAll ? "Top 10 only" : "Show 1–\(maxGrade)") { showAll.toggle() } }
                }
                .padding(.bottom, 6)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5), spacing: 5) {
                    ForEach(lowest...maxGrade, id: \.self) { g in
                        GradeCell(label: "\(g)", on: grade == g) { grade = g }
                    }
                }
                .padding(.bottom, 18)

                Text("2 · Hold colour").micro().padding(.bottom, 10)
                HoldStrip(selection: $colour).padding(.bottom, 18)

                if let t = tripped.first {
                    WarnPanel(lead: "Load flag", text: "\(t.headline) — used \(t.used) of \(t.cap ?? 0) this week\(t.blocked ? ". You are at the cap." : ". One more and you are over.")")
                        .padding(.bottom, 14)
                }

                OptionalBlock(tickType: $tickType, styles: $styles, location: $location)
            }
            .padding(.horizontal, 16)

            SessionRows(climbs: climbs, sends: sends, gymOnly: true)
                .padding(.top, 18)
                .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 6) {
                ConfirmBar(grade: grade, colour: colour) { save() }
                LinkButton(title: "End & rate") { path.append(LogStep.review) }
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            .background(Palette.paper)
        }
        .sensoryFeedback(.success, trigger: sentCount)
        .onChange(of: session.gymId) { grade = nil; colour = nil }
    }

    func save() {
        guard let grade, let colour, let gym else { return }
        let id = store.addClimb(Climb(sessionId: session.id, gymId: gym.id, gradeKind: .number, grade: grade, holdColour: colour,
                                      styles: styles, location: location.trimmingCharacters(in: .whitespaces).isEmpty ? nil : location,
                                      tickType: tickType, attempts: tickType == .flash ? 1 : tickType == .secondGo ? 2 : 3))
        let attempts = tickType == .flash ? "flash" : "\(tickType == .secondGo ? 2 : 3) tries"
        router.show(Toast(title: "Sent", detail: "\(grade) \(Vocab.colourLabel(colour).lowercased()) · \(attempts)",
                          undo: { [store] in store.deleteClimb(id) }))
        sentCount += 1
        self.grade = nil
        self.colour = nil
    }
}

struct GradeCell: View {
    var label: String
    var on: Bool
    var height: CGFloat = 48
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.mono(17, .medium, relativeTo: .body))
                .foregroundStyle(on ? Palette.paper : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(on ? Palette.ink : Palette.card)
                .overlay(Rectangle().strokeBorder(on ? Palette.ink : Palette.ruleChip, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityLabel("Grade \(label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// 9 contiguous hold colours, 40 × 48 pt.
struct HoldStrip: View {
    @Binding var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Vocab.holdColours, id: \.id) { c in
                let on = selection == c.id
                Button { selection = c.id } label: {
                    Rectangle().fill(Color(hex: c.hex))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(Rectangle().strokeBorder(Palette.ruleStrong, lineWidth: Palette.needsHairline(c.id) ? 1 : 0))
                        .overlay(Rectangle().strokeBorder(Palette.paper, lineWidth: on ? 3 : 0).padding(0))
                        .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: on ? 2 : 0).padding(-1))
                        .zIndex(on ? 1 : 0)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(c.label)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct ConfirmBar: View {
    var grade: Int?
    var colour: String?
    var send: () -> Void

    var body: some View {
        let ready = grade != nil && colour != nil
        HStack(spacing: 11) {
            Text(grade.map(String.init) ?? "—").font(.serif(24)).foregroundStyle(ready ? Palette.ink : Palette.faint).frame(minWidth: 26)
            Swatch(colour: colour, size: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(ready ? "Grade \(grade!) · \(Vocab.colourLabel(colour).lowercased())" : "Pick a grade and a colour")
                    .font(.sans(14, .medium)).foregroundStyle(Palette.ink)
                Text(ready ? "tap send to save" : "two taps, then send").font(.mono(10.5)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            Button("Send", action: send).buttonStyle(PrimaryButtonStyle(height: 44)).frame(width: 92).disabled(!ready)
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 10)
        .background(Palette.card)
        .overlay(Rectangle().strokeBorder(ready ? Palette.ink : Palette.rule, lineWidth: 2))
    }
}

/// "This session · N sends" rows.
struct SessionRows: View {
    @Environment(AscentStore.self) private var store
    var climbs: [Climb]
    var sends: [Climb]
    var gymOnly = false

    var body: some View {
        let shown = gymOnly ? climbs.filter { $0.gradeKind != .v } : climbs
        Band {
            SectionHead("This session · \(sends.count) send\(sends.count == 1 ? "" : "s")",
                        note: "HIGH \(LiveSummary.high(sends, db: store.db)) · \(sends.filter(Metrics.isFlash).count) FLASHED", size: 18)
            if shown.isEmpty { Text("Nothing logged yet tonight.").font(.sans(13)).foregroundStyle(Palette.muted) }
            ForEach(shown.prefix(8)) { c in
                ClimbRow(climb: c)
                    .swipeToDelete { store.deleteClimb(c.id) }
            }
            if let last = climbs.first {
                LinkButton(title: "Undo last") { store.deleteClimb(last.id) }.padding(.top, 6)
            }
        }
    }
}

/// `1d` — Camp5 tally. No numbers anywhere.
struct TallyLogView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var session: Session
    var gym: Gym
    @Binding var path: NavigationPath
    @State private var tickType: TickType = .flash
    @State private var styles: [String] = []
    @State private var location = ""
    @State private var added = 0

    var body: some View {
        let climbs = store.db.climbs.filter { $0.sessionId == session.id }.sorted { $0.createdAt > $1.createdAt }
        let tags = gym.tags ?? Vocab.camp5Tags
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(tags.enumerated()), id: \.element) { i, tag in
                    let count = climbs.filter { $0.tagId == tag && Metrics.isSend($0) }.count
                    HStack(spacing: 12) {
                        Swatch(colour: tag, size: 30)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(Vocab.colourLabel(tag)).font(.sans(14, .medium))
                            Text("TAG \(i + 1) OF \(tags.count)\(i == 0 ? " · EASIEST" : i == tags.count - 1 ? " · HARDEST" : "")")
                                .font(.mono(10)).tracking(0.6).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text("\(count)").font(.mono(18)).foregroundStyle(count > 0 ? Palette.ink : Palette.faint)
                        Button { add(tag, ordinal: i + 1) } label: {
                            Text("+").font(.sans(20)).foregroundStyle(count > 0 ? Palette.paper : Palette.ink)
                                .frame(width: 44, height: 44)
                                .background(count > 0 ? Palette.ink : .clear)
                                .overlay(Rectangle().strokeBorder(count > 0 ? Palette.ink : Palette.ruleChip, lineWidth: 1))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log a \(Vocab.colourLabel(tag)) tag")
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 13).padding(.vertical, 8)
                    .background(Palette.card)
                    .overlay(Rectangle().strokeBorder(count > 0 ? Palette.ink : Palette.rule, lineWidth: count > 0 ? 2 : 1))
                }
                Text("Set style, tick type or location below and it sticks to every tag you add. Otherwise it just counts.")
                    .font(.sans(12.5)).foregroundStyle(Palette.muted).padding(.top, 2).padding(.bottom, 14)
                if let t = trippedRules(store.db, styles: styles, today: store.today).first {
                    WarnPanel(lead: "Load flag", text: "\(t.headline) — used \(t.used) of \(t.cap ?? 0) this week\(t.blocked ? ". You are at the cap." : ". One more and you are over.")")
                        .padding(.bottom, 14)
                }
                OptionalBlock(tickType: $tickType, styles: $styles, location: $location)
            }
            .padding(.horizontal, 16)
            SessionRows(climbs: climbs, sends: climbs.filter(Metrics.isSend), gymOnly: true).padding(.top, 18).padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) {
            Button("End & rate") { path.append(LogStep.review) }.buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 16).padding(.vertical, 10).background(Palette.paper)
        }
        .sensoryFeedback(.success, trigger: added)
    }

    func add(_ tag: String, ordinal: Int) {
        let id = store.addClimb(Climb(sessionId: session.id, gymId: gym.id, gradeKind: .tag, grade: ordinal, tagId: tag, holdColour: tag,
                                      styles: styles, location: location.isEmpty ? nil : location, tickType: tickType,
                                      attempts: tickType == .flash ? 1 : 2))
        router.show(Toast(title: "Tallied", detail: Vocab.colourLabel(tag).lowercased(), undo: { [store] in store.deleteClimb(id) }))
        added += 1
    }
}

/// `3b` — board log.
struct BoardLogView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var session: Session
    @Binding var path: NavigationPath
    @State private var boardId = ""
    @State private var angle = 40
    @State private var v: Int?
    @State private var name = ""
    @State private var styles: [String] = []
    @State private var tickType: TickType = .secondGo
    @State private var logged = 0

    var body: some View {
        let db = store.db
        let board = db.board(boardId) ?? db.boards.first
        let bars = Metrics.boardHistogram(db.climbs, boardId: board?.id ?? "", angle: angle)
        let maxV = bars.filter { $0.count > 0 }.last?.v
        let tonight = db.climbs.filter { $0.sessionId == session.id && $0.boardId != nil }.sorted { $0.createdAt > $1.createdAt }
        let tripped = trippedRules(db, styles: styles, today: store.today)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(db.boards) { b in
                        Button {
                            boardId = b.id
                            if !b.angles.contains(angle) { angle = b.angles.first ?? 40 }
                        } label: {
                            Text(b.name).font(.sans(13, b.id == board?.id ? .semibold : .medium))
                                .foregroundStyle(b.id == board?.id ? Palette.paper : Palette.ink)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(b.id == board?.id ? Palette.ink : Palette.card)
                                .overlay(Rectangle().strokeBorder(b.id == board?.id ? Palette.ink : Palette.ruleChip, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
                FieldRow(label: "ANGLE") {
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(board?.angles ?? [], id: \.self) { a in GradeCell(label: "\(a)°", on: a == angle, height: 36) { angle = a }.frame(width: 52) }
                    }
                }
                .padding(.bottom, 16)
                Text("Grade sent").micro().padding(.bottom, 10)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5), spacing: 5) {
                    ForEach(1...10, id: \.self) { g in GradeCell(label: "V\(g)", on: v == g) { v = g } }
                }
                .padding(.bottom, 14)
                TextFieldRow(label: "CLIMB", placeholder: "shrimp cocktail", text: $name).padding(.bottom, 10)
                ChipFlow {
                    ForEach(Vocab.boardStyles, id: \.self) { s in
                        Chip(label: s, on: styles.contains(s), small: true) {
                            if styles.contains(s) { styles.removeAll { $0 == s } } else { styles.append(s) }
                        }
                    }
                }
                .padding(.bottom, 8)
                ChipFlow {
                    ForEach(Vocab.tickTypes, id: \.id) { t in Chip(label: t.label, on: tickType == t.id, small: true) { tickType = t.id } }
                }
                .padding(.bottom, 14)
                if let t = tripped.first {
                    WarnPanel(lead: "\(t.headline.components(separatedBy: " ").first ?? "") load flag",
                              text: t.used == t.cap ? "You are at the cap — \(t.used) of \(t.cap ?? 0) this week \(t.condition)."
                                                    : "\(ordinal(t.used + 1)) session this week against a cap of \(t.cap ?? 0). One more and you are over.")
                        .padding(.bottom, 14)
                }
                Button(v == nil ? "Pick a V-grade" : "Log V\(v!) · \(board?.name ?? "") \(angle)°") { save(board) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(v == nil || board == nil)
                ForEach(tonight.prefix(5)) { c in
                    HStack {
                        Text("V\(c.grade)").font(.serif(16)).frame(width: 30, alignment: .leading)
                        Text(boardDetail(c)).font(.sans(13)).foregroundStyle(Palette.muted).lineLimit(1)
                        Spacer()
                        LinkButton(title: "Undo", size: 12) { store.deleteClimb(c.id) }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)

            Band {
                SectionHead("\(board?.name.replacingOccurrences(of: "Board", with: "").trimmingCharacters(in: .whitespaces) ?? "") \(angle)° · all time",
                            note: maxV.map { "MAX V\($0)" } ?? "NO SENDS", noteColor: Palette.ink, size: 18)
                BoardHistogramView(bars: bars)
            }
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) {
            Button("End & rate") { path.append(LogStep.review) }.buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 16).padding(.vertical, 10).background(Palette.paper)
        }
        .sensoryFeedback(.success, trigger: logged)
        .onAppear {
            if boardId.isEmpty {
                let b = db.boards.first
                boardId = b?.id ?? ""
                angle = b?.angles.contains(40) == true ? 40 : b?.angles.first ?? 40
            }
        }
    }

    func save(_ board: Board?) {
        guard let v, let board else { return }
        let attempts = tickType == .flash ? 1 : tickType == .secondGo ? 2 : 4
        let id = store.addClimb(Climb(sessionId: session.id, boardId: board.id, angle: angle, gradeKind: .v, grade: v, styles: styles,
                                      name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name, tickType: tickType, attempts: attempts))
        router.show(Toast(title: "Logged", detail: "V\(v) · \(board.name) \(angle)°", undo: { [store] in store.deleteClimb(id) }))
        logged += 1
        self.v = nil
        name = ""
    }

    func ordinal(_ n: Int) -> String { n == 1 ? "1st" : n == 2 ? "2nd" : n == 3 ? "3rd" : "\(n)th" }
}

/* ── 2.6 Review ─────────────────────────────────────────────────────────── */

struct ReviewView: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.accent) private var accent
    /// nil = the live session, or the most recent finished one
    var sessionId: String?
    @Binding var path: NavigationPath

    @State private var chips: [String] = []
    @State private var score = 6.8
    @State private var note = ""
    @State private var painLevels: [String: Int] = [:]
    @State private var intent: String?
    @State private var newPain = false
    @State private var newPainName = ""
    @State private var newPainPart = Vocab.bodyParts[6].id
    @State private var loadedFor: String?

    var session: Session? {
        let db = store.db
        if let sessionId { return db.session(sessionId) }
        return db.activeSession ?? db.sessions.last { $0.status == .done }
    }

    var body: some View {
        let db = store.db
        if let session {
            let sends = Metrics.sessionSends(db.climbs, sessionId: session.id).count
            let avg = db.reviews.isEmpty ? nil : ((db.reviews.map(\.overallScore).reduce(0, +) / Double(db.reviews.count)) * 10).rounded() / 10
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("How did that feel?").font(.serif(28, relativeTo: .title))
                    Text("Tap what applies. Nothing is required. \(sends) send\(sends == 1 ? "" : "s") logged.")
                        .font(.sans(13)).foregroundStyle(Palette.muted).padding(.top, 8)

                    if session.intent == nil {
                        group("Session type") {
                            ForEach(Vocab.sessionIntents, id: \.self) { i in Chip(label: i, on: intent == i, small: true) { intent = i } }
                        }
                    }
                    ForEach(Vocab.ChipGroup.allCases, id: \.self) { g in
                        group(g.rawValue.capitalized) {
                            ForEach(Vocab.reviewChips[g] ?? [], id: \.self) { c in
                                Chip(label: c, on: chips.contains(c), small: true) {
                                    if chips.contains(c) { chips.removeAll { $0 == c } } else { chips.append(c) }
                                }
                            }
                        }
                    }
                    group("Pain") {
                        Chip(label: "No pain", on: chips.contains("No pain"), small: true) {
                            if chips.contains("No pain") { chips.removeAll { $0 == "No pain" } } else { chips.append("No pain"); painLevels = [:] }
                        }
                        ForEach(painInjuries(db)) { inj in
                            let level = painLevels[inj.id] ?? 0
                            Menu {
                                ForEach(0...10, id: \.self) { n in Button("\(n)/10") { setPain(inj.id, n) } }
                            } label: {
                                Chip(label: "\(shortInjury(inj.name)) · \(level)/10", on: level > 0, small: true, kind: .pain) {}
                                    .allowsHitTesting(false)
                            } primaryAction: {
                                setPain(inj.id, (level + 1) % 11)
                            }
                            .menuIndicator(.hidden)
                            .accessibilityHint("Tap to raise the level, hold to pick one")
                        }
                        Chip(label: "+ new pain", small: true, kind: .dashed) { newPain.toggle() }
                    }
                    if newPain {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("New — goes straight into the body log").micro()
                            TextFieldRow(label: "WHAT", placeholder: "R shoulder · front deltoid", text: $newPainName)
                            ChipFlow { ForEach(Vocab.bodyParts, id: \.id) { p in Chip(label: p.label, on: newPainPart == p.id, small: true) { newPainPart = p.id } } }
                            Button("Add to the log") { addNewPain() }.buttonStyle(PrimaryButtonStyle(height: 44))
                                .disabled(newPainName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(14).background(Palette.card).overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
                        .padding(.top, 10)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Overall session").micro()
                            Spacer()
                            Text(String(format: "%.1f", score)).font(.serif(32)).monospacedDigit()
                        }
                        Slider(value: $score, in: 0...10, step: 0.1).tint(accent.color).padding(.top, 8)
                            .accessibilityLabel("Overall session score")
                            .accessibilityValue(String(format: "%.1f out of 10", score))
                        HStack {
                            Text("ROUGH"); Spacer(); Text(avg.map { String(format: "AVG %.1f", $0) } ?? "NO AVG YET"); Spacer(); Text("BEST")
                        }
                        .font(.mono(10.5)).foregroundStyle(Palette.muted).padding(.top, 10)
                    }
                    .padding(16).background(Palette.card).overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
                    .padding(.top, 18)

                    NoteBox(placeholder: "Anything worth remembering about tonight…", text: $note).padding(.top, 10)
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
            .background(Palette.paper)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(db.review(for: session.id) == nil ? "Save review" : "Update review") { save(session) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16).padding(.vertical, 12).background(Palette.paper)
            }
            .modifier(SheetChrome(title: "", subtitle: [db.gym(session.gymId)?.name, session.intent].compactMap { $0 }.joined(separator: " · ").uppercased()))
            .onAppear { load(session, db: db) }
        } else {
            Text("Nothing to review yet — start a session first.").font(.sans(14)).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper)
                .modifier(SheetChrome(title: "Review", subtitle: ""))
        }
    }

    @ViewBuilder func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        Text(title).micro().padding(.top, 18).padding(.bottom, 9)
        ChipFlow { content() }
    }

    /// One chip per active injury, plus any the user has just added.
    func painInjuries(_ db: Database) -> [Injury] {
        db.injuries.filter { $0.status == .active || painLevels[$0.id] != nil }
    }

    func setPain(_ id: String, _ level: Int) {
        painLevels[id] = level
        chips.removeAll { $0 == "No pain" }
    }

    func load(_ s: Session, db: Database) {
        guard loadedFor != s.id else { return }
        loadedFor = s.id
        let existing = db.review(for: s.id)
        let painNames = Set(db.injuries.map { shortInjury($0.name) })
        chips = existing?.chips.filter { chip in !painNames.contains { chip.hasPrefix("\($0) · ") } } ?? []
        score = existing?.overallScore ?? 6.8
        note = existing?.note ?? ""
        intent = s.intent
        for inj in db.injuries {
            if let chip = existing?.chips.first(where: { $0.hasPrefix("\(shortInjury(inj.name)) · ") }),
               let n = Int(chip.components(separatedBy: "· ").last?.replacingOccurrences(of: "/10", with: "") ?? "") {
                painLevels[inj.id] = n
            }
        }
    }

    func addNewPain() {
        let n = newPainName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let id = store.createInjury(Injury(bodyPart: newPainPart, name: n, onsetDate: store.today, status: .watching))
        painLevels[id] = 3
        newPain = false
        newPainName = ""
    }

    func save(_ s: Session) {
        let db = store.db
        let painChips = painLevels.filter { $0.value > 0 }.sorted { $0.key < $1.key }.compactMap { id, level in
            db.injuries.first { $0.id == id }.map { "\(shortInjury($0.name)) · \(level)/10" }
        }
        store.saveReview(sessionId: s.id, chips: chips + painChips, score: (score * 10).rounded() / 10,
                         note: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : note)
        for (id, level) in painLevels where level > 0 { store.addPainEntry(injuryId: id, level: level, sessionId: s.id, date: s.date) }
        if chips.contains("No pain") {
            for inj in db.activeInjuries { store.addPainEntry(injuryId: inj.id, level: 0, sessionId: s.id, date: s.date) }
        }
        if let intent, intent != s.intent { store.updateSession(s.id) { $0.intent = intent } }
        if s.status == .active { store.endSession(s.id) }
        path.append(SavedRoute(sessionId: s.id))
    }
}

/* ── 2.7 Saved ──────────────────────────────────────────────────────────── */

struct SavedView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    var sessionId: String
    /// Re-reviewing an old session from History: Done returns there instead of to Today.
    var editing = false
    @Binding var path: NavigationPath

    var body: some View {
        let db = store.db
        let s = db.session(sessionId)
        let review = db.review(for: sessionId)
        let others = db.reviews.filter { $0.sessionId != sessionId }
        let avg = others.isEmpty ? nil : others.map(\.overallScore).reduce(0, +) / Double(others.count)
        let trends = Metrics.chipTrends(db.reviews, sessions: db.sessions)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Saved · \([db.gym(s?.gymId)?.name, s?.intent].compactMap { $0 }.joined(separator: " · "))").micro()
                Text(headline(review?.overallScore, avg)).font(.serif(28, relativeTo: .title)).padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            Band { ChipTrendPanel(rows: trends, pattern: Metrics.chipPattern(trends)) }.padding(.top, 14)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button("Body log") { router.closeSheet(then: .body) }.buttonStyle(SecondaryButtonStyle())
                    Button("Dashboard") { router.closeSheet(then: .today) }.buttonStyle(SecondaryButtonStyle())
                }
                Button("Update review") { path.removeLast() }.buttonStyle(SecondaryButtonStyle(dashed: true))
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Palette.paper)
        .navigationBarBackButtonHiddenIfAvailable()
        .navigationTitle("")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.closeSheet(then: editing ? nil : .today) } } }
        .sensoryFeedback(.success, trigger: true)
    }

    func headline(_ score: Double?, _ avg: Double?) -> String {
        guard let score else { return "Saved" }
        let s = String(format: "%.1f", score)
        guard let avg else { return "\(s), your first rated session" }
        let a = String(format: "%.1f", avg)
        if (score * 10).rounded() == (avg * 10).rounded() { return "\(s), right on your average" }
        return "\(s), \(score > avg ? "above" : "below") your \(a) average"
    }
}

extension View {
    func navigationBarBackButtonHiddenIfAvailable() -> some View { navigationBarBackButtonHidden(true) }
}
