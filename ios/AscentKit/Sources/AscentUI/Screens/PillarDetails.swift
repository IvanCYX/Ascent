import SwiftUI
import AscentCore

/* ── Load detail (DESIGN §3.2) ──────────────────────────────────────────── */

struct LoadDetailView: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.accent) private var accent

    var body: some View {
        let db = store.db
        let today = store.today
        let w = Load.window(db, today: today)
        let weeks = Load.weekly(db, today: today)
        let sessions = Load.sessions(db, today: today)
        let normals = Load.normals(db, today: today)
        let spiking = w.band == .spiking

        ScrollView {
            VStack(spacing: 12) {
                VStack(spacing: 16) {
                    ZStack {
                        PillarRing(progress: w.band == .building ? Double(w.weeksOfBaseline) / 4 : w.ratio ?? 0,
                                   color: spiking ? Palette.caution : accent.color, lineWidth: 14, cutout: Palette.ground,
                                   dashed: w.band == .building)
                        VStack(spacing: 6) {
                            if w.band == .building {
                                Text("\(w.weeksOfBaseline)/4").font(.num(48, relativeTo: .largeTitle))
                                Text("weeks of baseline").font(.sans(13)).foregroundStyle(Palette.secondary)
                            } else {
                                Text("\(Int(((w.ratio ?? 0) * 100).rounded()))%").font(.num(48, relativeTo: .largeTitle))
                                    .contentTransition(.numericText())
                                Text("of your usual week").font(.sans(13)).foregroundStyle(spiking ? Palette.cautionText : Palette.secondary)
                            }
                        }
                        .foregroundStyle(Palette.text)
                    }
                    .frame(width: 196, height: 196)
                    .accessibilityElement(children: .combine)
                    Text(w.band == .building ? "Load needs 4 weeks of history before it can compare."
                                             : "Last 7 days against your 4-week average")
                        .font(.sans(15)).foregroundStyle(Palette.text).multilineTextAlignment(.center)
                }
                .padding(.top, 8).padding(.bottom, 6)

                if let ratio = w.ratio { RangeCard(ratio: ratio) }

                Card {
                    SectionHead("Weekly load", note: "8 weeks")
                    WeeklyBars(weeks: weeks, baseline: w.baseline)
                }

                Card(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("What counted").font(.sans(17, .semibold)).foregroundStyle(Palette.text).padding(.bottom, 4)
                        if sessions.isEmpty {
                            Text("No climbs in the last 7 days.").font(.sans(14)).foregroundStyle(Palette.secondary).padding(.vertical, 12)
                        }
                        ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                            NavigationLink(value: Route.session(s.sessionId)) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(place(db, s.sessionId)), \(Self.inline(Day.relative(s.date, today: today)))")
                                            .font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                                        Text("\(s.sends) send\(s.sends == 1 ? "" : "s"), \(s.attempts) attempts").font(.sans(13)).foregroundStyle(Palette.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(s.load.rounded()))").font(.num(17)).foregroundStyle(Palette.text)
                                }
                                .padding(.vertical, 12)
                                .overlay(alignment: .bottom) { if i < sessions.count - 1 { Hairline() } }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                }

                NavigationLink(value: Route.normalGrade) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your normal grade").font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                            Text(NormalGradeView.summary(normals)).font(.sans(13)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.tertiary)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Palette.surface))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.bottom, 96)
        }
        .background(Palette.ground)
        .navigationTitle("Load")
        .inlineTitle()
    }

    /// "Today" → "today" mid-sentence; weekday names keep their capital.
    static func inline(_ day: String) -> String {
        ["Today", "Tomorrow", "Yesterday"].contains(day) ? day.lowercased() : day
    }

    func place(_ db: Database, _ sessionId: String) -> String {
        let s = db.session(sessionId)
        if let gym = db.gym(s?.gymId) { return gym.name }
        let board = db.climbs.first { $0.sessionId == sessionId && $0.boardId != nil }
        return board.flatMap { c in db.board(c.boardId).map { "\($0.name) \(c.angle ?? 40)°" } } ?? "Session"
    }
}

/// Light (under 80 %), in range, and the amber zone over 130 %, with a marker.
struct RangeCard: View {
    @Environment(\.accent) private var accent
    var ratio: Double
    /// The bar spans 0–150 %.
    let span = 1.5

    var body: some View {
        Card {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Rectangle().fill(Palette.text.opacity(0.14)).frame(width: w * Load.lightBelow / span)
                    Rectangle().fill(Palette.text.opacity(0.28)).frame(width: w * (Load.spikeAbove - Load.lightBelow) / span)
                        .offset(x: w * Load.lightBelow / span)
                    Rectangle().fill(Palette.caution.opacity(0.55)).frame(width: w * (span - Load.spikeAbove) / span)
                        .offset(x: w * Load.spikeAbove / span)
                }
                .clipShape(Capsule())
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(accent.color).frame(width: 4, height: 24)
                        .overlay(Capsule().strokeBorder(Palette.surface, lineWidth: 2).padding(-2))
                        .offset(x: w * min(1, ratio / span) - 2)
                }
            }
            .frame(height: 24)
            ZStack(alignment: .leading) {
                Text("Light").frame(maxWidth: .infinity, alignment: .leading)
                GeometryReader { g in
                    Text("100%").fixedSize().position(x: g.size.width / span, y: 8)
                }
                Text("130%+").foregroundStyle(Palette.cautionText).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.sans(12)).foregroundStyle(Palette.secondary)
            .frame(height: 16)
            .padding(.top, 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((ratio * 100).rounded())) percent. Light is under 80, spiking is over 130.")
    }
}

struct WeeklyBars: View {
    @Environment(\.accent) private var accent
    var weeks: [Load.WeekLoad]
    var baseline: Double?

    var body: some View {
        let top = max(weeks.map(\.load).max() ?? 0, (baseline ?? 0) * 1.3, 0.001)
        VStack(spacing: 8) {
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(weeks, id: \.end) { wk in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(wk.load == 0 ? Palette.track : wk.spiking ? Palette.caution.opacity(0.85) : accent.color.opacity(wk.isCurrent ? 1 : 0.45))
                            .frame(height: wk.load == 0 ? 4 : max(8, 120 * wk.load / top))
                            .frame(maxWidth: .infinity)
                    }
                }
                if let baseline, baseline > 0 {
                    Line().stroke(Palette.text.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .frame(height: 1).offset(y: -120 * baseline / top)
                }
            }
            .frame(height: 120, alignment: .bottom)
            HStack(spacing: 10) {
                ForEach(weeks, id: \.end) { wk in
                    Text(wk.isCurrent ? "Now" : "\(Day.isoWeek(wk.end).week)")
                        .font(.sans(11, wk.isCurrent ? .semibold : .regular))
                        .foregroundStyle(wk.spiking ? Palette.cautionText : wk.isCurrent ? Palette.text : Palette.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly load for the last 8 weeks")
    }
}

/* ── Progress detail (DESIGN §3.3) ─────────────────────────────────────── */

struct ProgressDetailView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let db = store.db
        let today = store.today
        let range = db.settings.dashboardRange
        let w = range.windows(today: today)
        let cur = Metrics.climbsInRange(db.climbs, from: w.from, to: w.to)
        let prev = Metrics.climbsInRange(db.climbs, from: w.prevFrom, to: w.prevTo)
        let weeks = max(1, Day.weeksBetween(w.from, w.to))
        let pyramid = Metrics.sendPyramid(cur)
        let tally = Metrics.camp5Tally(cur, tags: db.gyms.first(where: \.isRanked)?.tags ?? Vocab.camp5Tags)
        let boards = Metrics.boardSummaries(cur: cur, prev: prev, boards: db.boards, weeks: weeks)
        let heat = Metrics.styleGradeMatrix(cur)
        let readiness = Metrics.compReadiness(cur, reviews: db.reviews, today: today)
        let comp = db.upcomingComps(from: today).first { $0.effectivePriority != .c } ?? db.nextComp(from: today)

        ScrollView {
            VStack(spacing: 12) {
                SquareSegment(options: RangeID.allCases.map { ($0, $0.label) },
                              selection: Binding(get: { range }, set: { store.setDashboardRange($0) }))

                StatGrid(stats: Self.stats(cur: cur, prev: prev, db: db, sessions: db.sessions.filter { $0.status == .done && $0.date >= w.from && $0.date <= w.to }.count))

                Card {
                    SectionHead(title: "Send pyramid") { PyramidLegend() }
                    PyramidView(rows: pyramid)
                    Insight(label: nil, text: Metrics.pyramidRead(pyramid))
                }

                Card {
                    SectionHead("Camp5 colours", note: Self.nextTag(tally).map { "Next up: \(Vocab.colourLabel($0))" })
                    TallyView(bars: tally)
                }

                Card(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Boards").font(.sans(17, .semibold)).foregroundStyle(Palette.text).padding(.bottom, 4)
                        if boards.isEmpty { Text("No board sends.").font(.sans(14)).foregroundStyle(Palette.secondary).padding(.vertical, 10) }
                        ForEach(Array(boards.enumerated()), id: \.element.boardId) { i, b in
                            BoardCard(b: b).overlay(alignment: .bottom) { if i < boards.count - 1 { Hairline() } }
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 14)
                }

                Card {
                    SectionHead("Where you send", note: "Send %")
                    HeatmapView(rows: heat)
                }

                Button { router.planSegment = .season; router.select(.plan) } label: {
                    Card {
                        SectionHead("Comp readiness", note: comp.map { "\(Metrics.weeksOut(today: today, compDate: $0.date)) weeks out" })
                        ReadinessRows(rows: readiness)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the season plan")
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 96)
        }
        .background(Palette.ground)
        .navigationTitle("Progress")
        .inlineTitle()
    }

    /// The first tag above your hardest sent one that you haven't sent yet.
    static func nextTag(_ bars: [Metrics.TagBar]) -> String? {
        guard let hardest = bars.last(where: { $0.count > 0 }) else { return nil }
        return bars.first { $0.ordinal > hardest.ordinal && $0.count == 0 }?.tagId
    }

    static func stats(cur: [Climb], prev: [Climb], db: Database, sessions: Int) -> [Stat] {
        func signed(_ d: Double, digits: Int = 0) -> String {
            let v = digits == 0 ? String(Int(abs(d).rounded())) : String(format: "%.\(digits)f", abs(d))
            return d > 0 ? "+\(v)" : d < 0 ? "−\(v)" : "Flat"
        }
        let top = Metrics.maxGradeSent(cur, gyms: db.gyms), prevTop = Metrics.maxGradeSent(prev, gyms: db.gyms)
        let flash = Metrics.flashRate(cur), prevFlash = Metrics.flashRate(prev)
        let tries = Metrics.attemptsPerSend(cur), prevTries = Metrics.attemptsPerSend(prev)
        let hard = Metrics.volumeAtHard(cur), prevHard = Metrics.volumeAtHard(prev)
        var out: [Stat] = []
        let topDelta = top.grade.flatMap { t in prevTop.grade.map { Double(t - $0) } }
        out.append(Stat(label: "Top grade", value: top.grade.map(String.init) ?? "–",
                        chip: topDelta.map { signed($0) }, chipTone: (topDelta ?? 0) < 0 ? .caution : (topDelta == 0 ? .quiet : .neutral),
                        caption: top.grade == nil ? nil : "\(top.gymName), \(Day.pretty(top.date))"))
        let flashDelta = flash.flatMap { f in prevFlash.map { f - $0 } }
        out.append(Stat(label: "Flash rate", value: flash.map { "\(Int($0.rounded()))%" } ?? "–",
                        chip: flashDelta.map { signed($0) }, chipTone: (flashDelta ?? 0) < 0 ? .caution : (flashDelta.map { abs($0) < 0.5 } ?? true ? .quiet : .neutral),
                        caption: "Grade \(Metrics.flashRateThreshold) and up"))
        // fewer tries per send is better
        let triesDelta = tries.flatMap { t in prevTries.map { t - $0 } }
        out.append(Stat(label: "Tries per send", value: tries.map { Metrics.fixed1($0) } ?? "–",
                        chip: triesDelta.map { signed($0, digits: 1) }, chipTone: (triesDelta ?? 0) > 0.05 ? .caution : (triesDelta.map { abs($0) < 0.05 } ?? true ? .quiet : .neutral),
                        caption: "Grade \(Metrics.hardGradeThreshold) and up"))
        out.append(Stat(label: "Hard sends", value: "\(hard)", chip: signed(Double(hard - prevHard)),
                        chipTone: hard < prevHard ? .caution : hard == prevHard ? .quiet : .neutral,
                        caption: sessions > 0 ? "\(Metrics.fixed1(Double(hard) / Double(sessions))) per session" : nil))
        return out
    }
}

/* ── Settings › Your normal grade (DESIGN §3.9) ────────────────────────── */

struct NormalGradeView: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.accent) private var accent

    var body: some View {
        let db = store.db
        let today = store.today
        let suggested = Load.suggestedNormals(db, today: today)
        let current = Load.normals(db, today: today)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Load counts climbs above this more, and below it less.")
                    .font(.sans(15)).foregroundStyle(Palette.secondary).padding(.horizontal, 4).padding(.top, 8)

                Card {
                    header("Numbered gyms", suggested: suggested.numbered.map(String.init), custom: db.settings.normalNumbered != nil) {
                        store.setNormalNumbered(nil)
                    }
                    bigStepper(current.numbered.map(String.init) ?? "–",
                               minus: { store.setNormalNumbered((current.numbered ?? 9) - 1) },
                               plus: { store.setNormalNumbered((current.numbered ?? 9) + 1) },
                               canMinus: (current.numbered ?? 2) > 1, canPlus: (current.numbered ?? 0) < 15)
                }

                Card {
                    header("Camp5 tags", suggested: suggested.tag.map(Vocab.colourLabel), custom: db.settings.normalTag != nil) {
                        store.setNormalTag(nil)
                    }
                    HStack(spacing: 0) {
                        ForEach(Vocab.camp5Tags, id: \.self) { tag in
                            let on = current.tag == tag
                            Button { store.setNormalTag(tag) } label: {
                                Circle().fill(Palette.hold(tag)).frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(Palette.hairlineStrong, lineWidth: Palette.needsHairline(tag) ? 1 : 0))
                                    .padding(3)
                                    .overlay(Circle().strokeBorder(accent.color, lineWidth: on ? 2 : 0))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(Vocab.colourLabel(tag)), \(Vocab.camp5Ranges[tag] ?? "")")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                    .padding(.top, 12)
                    if let tag = current.tag {
                        Text("\(Vocab.colourLabel(tag)), about \(Vocab.camp5Ranges[tag] ?? "")")
                            .font(.sans(13)).foregroundStyle(Palette.secondary).padding(.top, 6)
                    }
                }

                Card {
                    header("Boards", suggested: suggested.v.map { "V\($0)" }, custom: db.settings.normalV != nil) {
                        store.setNormalV(nil)
                    }
                    bigStepper(current.v.map { "V\($0)" } ?? "–",
                               minus: { store.setNormalV((current.v ?? 5) - 1) },
                               plus: { store.setNormalV((current.v ?? 3) + 1) },
                               canMinus: (current.v ?? 1) > 0, canPlus: (current.v ?? 0) < 17)
                }

                Text("Changes apply to all past Load.").font(.sans(13)).foregroundStyle(Palette.secondary).padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.bottom, 96)
        }
        .background(Palette.ground)
        .navigationTitle("Your normal grade")
        .inlineTitle()
        .sensoryFeedback(.selection, trigger: current)
    }

    @ViewBuilder func header(_ title: String, suggested: String?, custom: Bool, reset: @escaping () -> Void) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sans(16, .semibold)).foregroundStyle(Palette.text)
                Text(suggested.map { "Suggested \($0), from the last 4 weeks" } ?? "Not set: no sends in the last 4 weeks")
                    .font(.sans(13)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if custom, suggested != nil { LinkButton(title: "Use suggestion", size: 13, action: reset) }
        }
    }

    func bigStepper(_ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void, canMinus: Bool, canPlus: Bool) -> some View {
        HStack {
            StepButton(systemName: "minus", label: "Lower", size: 44, fill: Palette.raised, disabled: !canMinus, action: minus)
            Spacer()
            Text(value).font(.num(44, relativeTo: .largeTitle)).foregroundStyle(Palette.text).contentTransition(.numericText())
            Spacer()
            StepButton(systemName: "plus", label: "Higher", size: 44, fill: Palette.raised, disabled: !canPlus, action: plus)
        }
        .padding(.top, 14)
        .animation(.snappy, value: value)
    }

    /// "10, Green, V5"
    static func summary(_ n: NormalGrades) -> String {
        [n.numbered.map(String.init), n.tag.map(Vocab.colourLabel), n.v.map { "V\($0)" }].compactMap { $0 }.joined(separator: ", ").ifEmpty("Not set")
    }
}
