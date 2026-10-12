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
        .presentationBackground(Palette.sheet)
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
                    Text("\(Text("Plan for today: ").bold().foregroundStyle(Palette.text))\(plan.intent ?? "A session") at \(db.gym(plan.gymId)?.name ?? "the gym"). ")
                        .font(.sans(14)).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.top, 13).padding(.bottom, 40)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                        .overlay(alignment: .bottomTrailing) {
                            LinkButton(title: "Open plan") { router.planSegment = .today; router.closeSheet(then: .plan) }.padding(.trailing, 14)
                        }
                }
                FieldLabel(title: "Gym").padding(.top, 22)
                ChipFlow { ForEach(db.gyms) { g in Chip(label: g.name, on: gymId == g.id, small: true) { gymId = g.id } } }
                FieldLabel(title: "Intent", note: "Optional").padding(.top, 22)
                ChipFlow {
                    ForEach(Vocab.sessionIntents, id: \.self) { i in
                        Chip(label: i, on: intent == i, small: true) { intent = intent == i ? nil : i }
                    }
                }
                if !focus.isEmpty {
                    FieldLabel(title: "Focus from plan").padding(.top, 22)
                    ChipFlow { ForEach(focus, id: \.self) { f in Chip(label: f, on: true, small: true) { focus.removeAll { $0 == f } } } }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Palette.sheet)
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
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Palette.sheet)
        }
        .modifier(SheetChrome(title: "Start session", subtitle: Day.fullDate(store.today)))
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

    var body: some View {
        let db = store.db
        if let session = db.activeSession {
            let gym = db.gym(session.gymId)
            let current = mode ?? initialMode
            VStack(spacing: 0) {
                SquareSegment(options: [(LogMode.gym, "Gym"), (.board, "Board")], selection: Binding(get: { current }, set: { mode = $0 }))
                    .padding(.horizontal, 16).padding(.bottom, 8)
                switch current {
                case .gym:
                    if gym?.isRanked == true { TallyLogView(session: session, gym: gym!, path: $path) }
                    else { GymLogView(session: session, gym: gym, path: $path) }
                case .board:
                    BoardLogView(session: session, path: $path)
                }
            }
            .background(Palette.sheet)
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
                            HStack(spacing: 5) {
                                Text(gym?.shortName ?? "Gym")
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                            }
                            .font(.system(size: 15, weight: .semibold))
                        }
                        .accessibilityLabel("Switch gym, now \(gym?.name ?? "none")")
                    }
                }
            }
        } else {
            StartSessionView(onStarted: {})
        }
    }

    func subtitle(session: Session, gym: Gym?, mode: LogMode) -> String {
        let place = mode == .board ? "Board" : gym?.isRanked == true ? "\(gym?.shortName ?? "Camp5"), pink to black" : "\(gym?.shortName ?? "No gym"), 1 to \(gym?.maxGrade ?? 15)"
        return place
    }
}

/// Load rules tripped by the current style selection.
func trippedRules(_ db: Database, styles: [String], today: String) -> [Metrics.LoadRuleUsage] {
    Metrics.loadRuleUsage(db.loadRules.filter { $0.maxPerWeek != nil }, climbs: db.climbs, weekStart: Day.weekStart(today))
        .filter { u in
            (u.blocked || u.nearing) && styles.contains(db.loadRules.first { $0.id == u.ruleId }?.styleOrType ?? "")
        }
}

/// The live timer under the sheet title.
struct LiveTimerLine: View {
    var session: Session
    var body: some View {
        if let start = session.startedAt {
            HStack(spacing: 6) {
                Text("Live")
                Text(timerInterval: start...Date.distantFuture, countsDown: false).font(.num(12)).monospacedDigit()
            }
            .font(.sans(12)).foregroundStyle(Palette.secondary)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A small section label above a block of controls.
struct FieldLabel: View {
    var title: String
    var note: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.sans(15, .semibold)).foregroundStyle(Palette.text)
            Spacer()
            if let note { Text(note).font(.sans(13)).foregroundStyle(Palette.secondary) }
        }
        .padding(.bottom, 10)
    }
}

/// Styles, Not sent and Where — reset after every save.
struct OptionalBlock: View {
    @Binding var styles: [String]
    @Binding var notSent: Bool
    @Binding var location: String
    var styleList = Vocab.climbStyles
    var showWhere = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldLabel(title: "Style")
            ChipFlow {
                ForEach(styleList, id: \.self) { s in
                    Chip(label: s, on: styles.contains(s), small: true) {
                        if styles.contains(s) { styles.removeAll { $0 == s } } else { styles.append(s) }
                    }
                }
            }
            NotSentRow(notSent: $notSent).padding(.top, 16)
            if showWhere { TextFieldRow(label: "Where", placeholder: "Cave, right of the arête", text: $location).padding(.top, 10) }
        }
    }
}

struct NotSentRow: View {
    @Environment(\.accent) private var accent
    @Binding var notSent: Bool
    var body: some View {
        Toggle(isOn: $notSent) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Not sent").font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                Text("Log attempts without a send").font(.sans(12)).foregroundStyle(Palette.secondary)
            }
        }
        .tint(accent.color)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.raised))
    }
}

/// The pinned bottom bar: `[ − n + ]  label / hint  ……  [ Send ]` (DESIGN §3.5).
struct AttemptBar: View {
    @Binding var attempts: Int
    var notSent: Bool
    /// nil = no button (the Camp5 tally logs from each row)
    var sendTitle: String?
    var canSend = true
    var hint: String?
    var send: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                StepButton(systemName: "minus", label: "One fewer attempt", size: 40, fill: .clear, disabled: attempts <= 1) {
                    attempts = max(1, attempts - 1)
                }
                Text("\(attempts)").font(.num(22)).foregroundStyle(Palette.text).frame(minWidth: 28)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(attempts) attempt\(attempts == 1 ? "" : "s")")
                StepButton(systemName: "plus", label: "One more attempt", size: 40, fill: .clear) {
                    attempts = min(99, attempts + 1)
                }
            }
            .padding(.horizontal, 2)
            .background(Capsule().fill(Palette.raised))
            VStack(alignment: .leading, spacing: 1) {
                Text(Vocab.attemptsLabel(attempts, sent: !notSent)).font(.sans(16, .bold)).foregroundStyle(Palette.text)
                    .contentTransition(.opacity)
                Text(hint ?? (notSent ? "No send logged" : attempts == 1 ? "First go" : "Attempts until sent"))
                    .font(.sans(12)).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let sendTitle {
                Button(sendTitle, action: send)
                    .buttonStyle(PrimaryButtonStyle(height: 50))
                    .frame(width: 100)
                    .disabled(!canSend)
            }
        }
        .padding(.leading, 8).padding(.trailing, sendTitle == nil ? 16 : 8)
        .frame(minHeight: 70)
        .background(Capsule().fill(Palette.surface).shadow(color: .black.opacity(0.18), radius: 16, y: -2))
        .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
        .animation(.snappy(duration: 0.2), value: attempts)
        .animation(.snappy(duration: 0.2), value: notSent)
        .sensoryFeedback(.selection, trigger: attempts)
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
    @State private var attempts = 1
    @State private var notSent = false
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
                LiveTimerLine(session: session).frame(maxWidth: .infinity).padding(.bottom, 14)
                HStack(alignment: .firstTextBaseline) {
                    Text("Grade").font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                    Spacer()
                    if maxGrade > 10 { LinkButton(title: showAll ? "Top 10 only" : "Show 1 to \(maxGrade)", color: Palette.secondary) { showAll.toggle() } }
                }
                .padding(.bottom, 6)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(lowest...maxGrade, id: \.self) { g in
                        GradeCell(label: "\(g)", on: grade == g) { grade = grade == g ? nil : g }
                    }
                }
                .padding(.bottom, 20)

                FieldLabel(title: "Colour", note: "Optional")
                HoldStrip(selection: $colour).padding(.bottom, 20)

                if let t = tripped.first {
                    WarnPanel(lead: "\(t.headline)", text: "\(t.used) of \(t.cap ?? 0) this week\(t.blocked ? ". Limit reached." : ". 1 left.")")
                        .padding(.bottom, 14)
                }

                OptionalBlock(styles: $styles, notSent: $notSent, location: $location)
            }
            .padding(.horizontal, 16)

            SessionRows(climbs: climbs, sends: sends, gymOnly: true, path: $path)
                .padding(.top, 8)
                .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            AttemptBar(attempts: $attempts, notSent: notSent, sendTitle: notSent ? "Log" : "Send", canSend: grade != nil) { save() }
        }
        .sensoryFeedback(.success, trigger: sentCount)
        .onChange(of: session.gymId) { grade = nil; colour = nil }
    }

    func save() {
        guard let grade, let gym else { return }
        let tick = Vocab.tickType(attempts: attempts, sent: !notSent)
        let label = Vocab.attemptsLabel(attempts, sent: !notSent)
        let id = store.addClimb(Climb(sessionId: session.id, gymId: gym.id, gradeKind: .number, grade: grade, holdColour: colour,
                                      styles: styles, location: location.trimmingCharacters(in: .whitespaces).isEmpty ? nil : location,
                                      tickType: tick, attempts: attempts))
        router.show(Toast(title: "Logged \(grade)", detail: label, undo: { [store] in store.deleteClimb(id) }))
        sentCount += 1
        // every climb starts as a first go
        self.grade = nil
        colour = nil
        styles = []
        location = ""
        attempts = 1
        notSent = false
    }
}

struct GradeCell: View {
    @Environment(\.accent) private var accent
    var label: String
    var on: Bool
    var height: CGFloat = 54
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label).font(.num(19, relativeTo: .title3))
                .foregroundStyle(on ? accent.onAccent : Palette.text)
                .frame(maxWidth: .infinity, minHeight: height)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? accent.color : Palette.raised))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityLabel("Grade \(label)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The 9 hold colours as dots; tap again to clear.
struct HoldStrip: View {
    @Environment(\.accent) private var accent
    @Binding var selection: String?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Vocab.holdColours, id: \.id) { c in
                let on = selection == c.id
                Button { selection = on ? nil : c.id } label: {
                    Circle().fill(Color(hex: c.hex))
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(Palette.hairlineStrong, lineWidth: Palette.needsHairline(c.id) ? 1 : 0))
                        .padding(3)
                        .overlay(Circle().strokeBorder(accent.color, lineWidth: on ? 2 : 0))
                        .frame(maxWidth: .infinity, minHeight: 44)
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

/// "This session" rows, the latest first, plus End and rate.
struct SessionRows: View {
    @Environment(AscentStore.self) private var store
    var climbs: [Climb]
    var sends: [Climb]
    var gymOnly = false
    @Binding var path: NavigationPath

    var body: some View {
        let shown = gymOnly ? climbs.filter { $0.gradeKind != .v } : climbs
        Band {
            SectionHead("This session", note: "\(sends.count) send\(sends.count == 1 ? "" : "s"), high \(LiveSummary.high(sends, db: store.db)), \(sends.filter(Metrics.isFlash).count) flashed")
            if shown.isEmpty { Text("Nothing logged yet.").font(.sans(14)).foregroundStyle(Palette.secondary) }
            ForEach(Array(shown.prefix(8).enumerated()), id: \.element.id) { i, c in
                ClimbRow(climb: c)
                    .overlay(alignment: .bottom) { if i < min(8, shown.count) - 1 { Hairline() } }
                    .swipeToDelete { store.deleteClimb(c.id) }
            }
            Button("End and rate") { path.append(LogStep.review) }
                .buttonStyle(SecondaryButtonStyle(height: 46))
                .padding(.top, 14)
        }
    }
}

/// `1d` — Camp5 tally. No numbers anywhere.
struct TallyLogView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accent) private var accent
    var session: Session
    var gym: Gym
    @Binding var path: NavigationPath
    @State private var attempts = 1
    @State private var notSent = false
    @State private var styles: [String] = []
    @State private var location = ""
    @State private var added = 0

    var body: some View {
        let climbs = store.db.climbs.filter { $0.sessionId == session.id }.sorted { $0.createdAt > $1.createdAt }
        let tags = gym.tags ?? Vocab.camp5Tags
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                LiveTimerLine(session: session).frame(maxWidth: .infinity).padding(.bottom, 6)
                ForEach(Array(tags.enumerated()), id: \.element) { i, tag in
                    let count = climbs.filter { $0.tagId == tag && Metrics.isSend($0) }.count
                    HStack(spacing: 12) {
                        Swatch(colour: tag, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Vocab.colourLabel(tag)).font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                            Text("About \(Vocab.camp5Ranges[tag] ?? "")\(i == 0 ? ", easiest" : i == tags.count - 1 ? ", hardest" : "")")
                                .font(.sans(12)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Text("\(count)").font(.num(18)).foregroundStyle(count > 0 ? Palette.text : Palette.tertiary)
                            .contentTransition(.numericText())
                        Button { add(tag, ordinal: i + 1) } label: {
                            Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                                .foregroundStyle(count > 0 ? accent.onAccent : Palette.text)
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(count > 0 ? accent.color : Palette.raised))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Log a \(Vocab.colourLabel(tag)) tag, \(Vocab.attemptsLabel(attempts, sent: !notSent))")
                    }
                    .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                }
                if let t = trippedRules(store.db, styles: styles, today: store.today).first {
                    WarnPanel(lead: "\(t.headline)", text: "\(t.used) of \(t.cap ?? 0) this week\(t.blocked ? ". Limit reached." : ". 1 left.")")
                        .padding(.top, 6)
                }
                OptionalBlock(styles: $styles, notSent: $notSent, location: $location).padding(.top, 14)
            }
            .padding(.horizontal, 16)
            SessionRows(climbs: climbs, sends: climbs.filter(Metrics.isSend), gymOnly: true, path: $path).padding(.top, 8).padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) {
            AttemptBar(attempts: $attempts, notSent: notSent, sendTitle: nil, hint: "Then tap + on a tag")
        }
        .sensoryFeedback(.success, trigger: added)
    }

    func add(_ tag: String, ordinal: Int) {
        let label = Vocab.attemptsLabel(attempts, sent: !notSent)
        let id = store.addClimb(Climb(sessionId: session.id, gymId: gym.id, gradeKind: .tag, grade: ordinal, tagId: tag, holdColour: tag,
                                      styles: styles, location: location.isEmpty ? nil : location,
                                      tickType: Vocab.tickType(attempts: attempts, sent: !notSent), attempts: attempts))
        router.show(Toast(title: "Logged \(Vocab.colourLabel(tag).lowercased())", detail: label, undo: { [store] in store.deleteClimb(id) }))
        added += 1
        attempts = 1
        notSent = false
    }
}

/// `3b` — board log.
struct BoardLogView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accent) private var accent
    var session: Session
    @Binding var path: NavigationPath
    @State private var boardId = ""
    @State private var angle = 40
    @State private var v: Int?
    @State private var name = ""
    @State private var styles: [String] = []
    @State private var attempts = 1
    @State private var notSent = false
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
                LiveTimerLine(session: session).frame(maxWidth: .infinity).padding(.bottom, 14)
                HStack(spacing: 8) {
                    ForEach(db.boards) { b in
                        let on = b.id == board?.id
                        Button {
                            boardId = b.id
                            if !b.angles.contains(angle) { angle = b.angles.first ?? 40 }
                        } label: {
                            Text(b.name).font(.sans(14, on ? .semibold : .medium))
                                .foregroundStyle(on ? accent.onAccent : Palette.text)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? accent.color : Palette.raised))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
                FieldRow(label: "Angle") {
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(board?.angles ?? [], id: \.self) { a in GradeCell(label: "\(a)°", on: a == angle, height: 36) { angle = a }.frame(width: 56) }
                    }
                }
                .padding(.bottom, 20)
                FieldLabel(title: "Grade")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                    ForEach(1...10, id: \.self) { g in GradeCell(label: "V\(g)", on: v == g) { v = v == g ? nil : g } }
                }
                .padding(.bottom, 16)
                TextFieldRow(label: "Climb", placeholder: "Shrimp cocktail", text: $name).padding(.bottom, 16)
                if let t = tripped.first {
                    WarnPanel(lead: "\(t.headline)", text: "\(t.used) of \(t.cap ?? 0) this week\(t.used == t.cap ? ". Limit reached." : ".")")
                        .padding(.bottom, 14)
                }
                OptionalBlock(styles: $styles, notSent: $notSent, location: .constant(""), styleList: Vocab.boardStyles, showWhere: false)
            }
            .padding(.horizontal, 16)

            if !tonight.isEmpty {
                Band {
                    SectionHead("Tonight", note: "\(tonight.filter(Metrics.isSend).count) sends")
                    ForEach(Array(tonight.prefix(6).enumerated()), id: \.element.id) { i, c in
                        ClimbRow(climb: c)
                            .overlay(alignment: .bottom) { if i < min(6, tonight.count) - 1 { Hairline() } }
                            .swipeToDelete { store.deleteClimb(c.id) }
                    }
                }
            }

            Band {
                SectionHead("\(board?.name ?? "Board") \(angle)°, all time", note: maxV.map { "Max V\($0)" } ?? "No sends")
                BoardHistogramView(bars: bars)
                Button("End and rate") { path.append(LogStep.review) }
                    .buttonStyle(SecondaryButtonStyle(height: 46))
                    .padding(.top, 14)
            }
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom) {
            AttemptBar(attempts: $attempts, notSent: notSent, sendTitle: notSent ? "Log" : "Send", canSend: v != nil && board != nil) { save(board) }
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
        let label = Vocab.attemptsLabel(attempts, sent: !notSent)
        let id = store.addClimb(Climb(sessionId: session.id, boardId: board.id, angle: angle, gradeKind: .v, grade: v, styles: styles,
                                      name: name.trimmingCharacters(in: .whitespaces).isEmpty ? nil : name,
                                      tickType: Vocab.tickType(attempts: attempts, sent: !notSent), attempts: attempts))
        router.show(Toast(title: "Logged V\(v)", detail: label, undo: { [store] in store.deleteClimb(id) }))
        logged += 1
        self.v = nil
        name = ""
        styles = []
        attempts = 1
        notSent = false
    }
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
                    Text("How did that feel?").font(.sans(28, .bold)).foregroundStyle(Palette.text)
                    Text("\(sends) send\(sends == 1 ? "" : "s"). Tap any that apply.")
                        .font(.sans(15)).foregroundStyle(Palette.secondary).padding(.top, 6)

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
                            .accessibilityHint("Tap to raise, hold to pick")
                        }
                        Chip(label: "+ new pain", small: true, kind: .dashed) { newPain.toggle() }
                    }
                    if newPain {
                        VStack(alignment: .leading, spacing: 10) {
                            FieldLabel(title: "New pain")
                            TextFieldRow(label: "What", placeholder: "R shoulder, front deltoid", text: $newPainName)
                            ChipFlow { ForEach(Vocab.bodyParts, id: \.id) { p in Chip(label: p.label, on: newPainPart == p.id, small: true) { newPainPart = p.id } } }
                            Button("Add") { addNewPain() }.buttonStyle(PrimaryButtonStyle(height: 44))
                                .disabled(newPainName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding(14).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                        .padding(.top, 10)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Overall session").font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                            Spacer()
                            Text(String(format: "%.1f", score)).font(.num(32)).foregroundStyle(Palette.text).contentTransition(.numericText())
                        }
                        Slider(value: $score, in: 0...10, step: 0.1).tint(accent.color).padding(.top, 8)
                            .accessibilityLabel("Overall session score")
                            .accessibilityValue(String(format: "%.1f out of 10", score))
                        HStack {
                            Text("Rough"); Spacer(); Text(avg.map { String(format: "Average %.1f", $0) } ?? "No average yet"); Spacer(); Text("Best")
                        }
                        .font(.sans(12)).foregroundStyle(Palette.secondary).padding(.top, 10)
                    }
                    .padding(16).background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.surface))
                    .padding(.top, 18)

                    NoteBox(placeholder: "Note", text: $note).padding(.top, 10)
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
            .background(Palette.sheet)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button(db.review(for: session.id) == nil ? "Save review" : "Update review") { save(session) }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16).padding(.vertical, 12).background(Palette.sheet)
            }
            .modifier(SheetChrome(title: "", subtitle: [db.gym(session.gymId)?.name, session.intent].compactMap { $0 }.joined(separator: ", ")))
            .onAppear { load(session, db: db) }
        } else {
            Text("No session to review.").font(.sans(14)).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.sheet)
                .modifier(SheetChrome(title: "Review", subtitle: ""))
        }
    }

    @ViewBuilder func group<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        FieldLabel(title: title).padding(.top, 20)
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
                Text("Saved, \([db.gym(s?.gymId)?.name, s?.intent].compactMap { $0 }.joined(separator: ", "))").micro()
                Text(headline(review?.overallScore, avg)).font(.sans(28, .bold)).foregroundStyle(Palette.text).padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            Band { ChipTrendPanel(rows: trends, pattern: Metrics.chipPattern(trends)) }.padding(.top, 14)
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button("Body log") { router.closeSheet(then: .body) }.buttonStyle(SecondaryButtonStyle())
                    Button("Today") { router.closeSheet(then: .today) }.buttonStyle(SecondaryButtonStyle())
                }
                Button("Update review") { path.removeLast() }.buttonStyle(SecondaryButtonStyle(dashed: true))
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(Palette.sheet)
        .navigationBarBackButtonHiddenIfAvailable()
        .navigationTitle("")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { router.closeSheet(then: editing ? nil : .today) } } }
        .sensoryFeedback(.success, trigger: true)
    }

    func headline(_ score: Double?, _ avg: Double?) -> String {
        guard let score else { return "Saved" }
        let s = String(format: "%.1f", score)
        guard let avg else { return "\(s)" }
        let a = String(format: "%.1f", avg)
        if (score * 10).rounded() == (avg * 10).rounded() { return "\(s), your average" }
        return "\(s), average \(a)"
    }
}

extension View {
    func navigationBarBackButtonHiddenIfAvailable() -> some View { navigationBarBackButtonHidden(true) }
}
