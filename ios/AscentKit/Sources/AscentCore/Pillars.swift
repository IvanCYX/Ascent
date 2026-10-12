import Foundation

/* ── r3: the three pillars on Today (DESIGN §4) ─────────────────────────────── */

/// Your normal grade on each scale. Load weighs every climb against the one for its scale.
public struct NormalGrades: Sendable, Hashable {
    /// The numbered-gym spine (Batuu reference, 1–15)
    public var numbered: Int?
    /// A Camp5 tag id
    public var tag: String?
    /// The V-scale, for boards
    public var v: Int?

    public init(numbered: Int? = nil, tag: String? = nil, v: Int? = nil) {
        self.numbered = numbered; self.tag = tag; self.v = v
    }
}

public enum Load {
    /// One Camp5 tag spans about three V grades, so a step between tags counts as 2.5 grade steps.
    public static let camp5StepGrades = 2.5
    public static let lightBelow = 0.8
    public static let spikeAbove = 1.3
    /// Days of history the baseline needs (the 4 weeks before the last 7 days).
    public static let baselineDays = 28

    /* ── Normal grades ───────────────────────────────────────────────── */

    /// The median sent grade per scale over the last 28 days, rounded.
    public static func suggestedNormals(_ db: Database, today: String) -> NormalGrades {
        let from = Day.add(today, -27)
        let sends = Metrics.climbsInRange(db.climbs, from: from, to: today).filter(Metrics.isSend)
        func median(_ xs: [Double]) -> Double? {
            guard !xs.isEmpty else { return nil }
            let s = xs.sorted()
            return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        let numbered = median(sends.filter(Metrics.isNumeric).map { Metrics.adjustedGrade($0, gyms: db.gyms) })
        let tagIndex = median(sends.filter(Metrics.isTag).compactMap { c in c.tagId.flatMap { Vocab.camp5Tags.firstIndex(of: $0) }.map(Double.init) })
        let v = median(sends.filter(Metrics.isBoard).map { Double($0.grade) })
        return NormalGrades(numbered: numbered.map { Int($0.rounded()) },
                            tag: tagIndex.map { Vocab.camp5Tags[min(Vocab.camp5Tags.count - 1, Int($0.rounded()))] },
                            v: v.map { Int($0.rounded()) })
    }

    /// The user's choice per scale, else the suggestion.
    public static func normals(_ db: Database, today: String) -> NormalGrades {
        let s = db.settings
        let suggested = suggestedNormals(db, today: today)
        return NormalGrades(numbered: s.normalNumbered ?? suggested.numbered,
                            tag: s.normalTag ?? suggested.tag,
                            v: s.normalV ?? suggested.v)
    }

    /* ── Per climb ───────────────────────────────────────────────────── */

    /// Grade steps above (or below, negative) your normal on the climb's own scale; nil when that scale has no normal.
    public static func stepsAboveNormal(_ c: Climb, gyms: [Gym], normals: NormalGrades) -> Double? {
        switch c.gradeKind {
        case .number:
            guard let n = normals.numbered else { return nil }
            return Metrics.adjustedGrade(c, gyms: gyms) - Double(n)
        case .tag:
            guard let t = normals.tag, let ni = Vocab.camp5Tags.firstIndex(of: t),
                  let tag = c.tagId, let ci = Vocab.camp5Tags.firstIndex(of: tag) else { return nil }
            return Double(ci - ni) * camp5StepGrades
        case .v:
            guard let n = normals.v else { return nil }
            return Double(c.grade - n)
        }
    }

    /// `attempts × 2^((grade − normal) / 2)`. Not-sent attempts count too.
    public static func climbLoad(_ c: Climb, gyms: [Gym], normals: NormalGrades) -> Double {
        guard let steps = stepsAboveNormal(c, gyms: gyms, normals: normals) else { return 0 }
        return Double(max(1, c.attempts)) * pow(2, steps / 2)
    }

    static func total(_ climbs: [Climb], _ db: Database, _ normals: NormalGrades) -> Double {
        climbs.reduce(0) { $0 + climbLoad($1, gyms: db.gyms, normals: normals) }
    }

    /* ── The window: last 7 days against the 4 weeks before ──────────── */

    public enum Band: Sendable, Hashable { case building, light, inRange, spiking }

    public struct Window: Sendable, Hashable {
        /// Load over the last 7 days, today included
        public var acute: Double
        /// Average 7-day load over the 28 days before that; nil while building
        public var baseline: Double?
        /// acute ÷ baseline
        public var ratio: Double?
        /// Full weeks of history inside the baseline window, 0–4
        public var weeksOfBaseline: Int
        public var band: Band
    }

    public static func window(_ db: Database, today: String) -> Window {
        let normals = normals(db, today: today)
        let acuteFrom = Day.add(today, -6)
        let baseTo = Day.add(today, -7)
        let baseFrom = Day.add(today, -7 - baselineDays + 1)
        let acute = total(Metrics.climbsInRange(db.climbs, from: acuteFrom, to: today), db, normals)
        let firstDay = db.climbs.first?.day ?? today
        let covered = max(0, min(baselineDays, Day.between(max(firstDay, baseFrom), baseTo) + 1))
        let weeks = covered / 7
        guard covered >= baselineDays else {
            return Window(acute: acute, baseline: nil, ratio: nil, weeksOfBaseline: weeks, band: .building)
        }
        let baseline = total(Metrics.climbsInRange(db.climbs, from: baseFrom, to: baseTo), db, normals) / 4
        guard baseline > 0 else { return Window(acute: acute, baseline: 0, ratio: nil, weeksOfBaseline: 4, band: .building) }
        let ratio = acute / baseline
        let band: Band = ratio > spikeAbove ? .spiking : ratio < lightBelow ? .light : .inRange
        return Window(acute: acute, baseline: baseline, ratio: ratio, weeksOfBaseline: 4, band: band)
    }

    public struct DayLoad: Sendable, Hashable {
        public var day: String
        public var load: Double
        public var isToday: Bool
    }

    /// One bar per day for the last `days` days, oldest first.
    public static func daily(_ db: Database, today: String, days: Int = 7) -> [DayLoad] {
        let normals = normals(db, today: today)
        return (0..<days).reversed().map { back in
            let d = Day.add(today, -back)
            return DayLoad(day: d, load: total(db.climbs.filter { $0.day == d }, db, normals), isToday: back == 0)
        }
    }

    public struct WeekLoad: Sendable, Hashable {
        /// The last day of the 7-day block
        public var end: String
        public var load: Double
        /// The block's own 4-week baseline, when there was enough history
        public var baseline: Double?
        public var spiking: Bool
        public var isCurrent: Bool
    }

    /// Rolling 7-day blocks ending today, today − 7, … oldest first.
    public static func weekly(_ db: Database, today: String, weeks: Int = 8) -> [WeekLoad] {
        let normals = normals(db, today: today)
        let firstDay = db.climbs.first?.day ?? today
        return (0..<weeks).reversed().map { back in
            let end = Day.add(today, -7 * back)
            let load = total(Metrics.climbsInRange(db.climbs, from: Day.add(end, -6), to: end), db, normals)
            let baseFrom = Day.add(end, -7 - baselineDays + 1), baseTo = Day.add(end, -7)
            let baseline: Double? = firstDay <= baseFrom
                ? total(Metrics.climbsInRange(db.climbs, from: baseFrom, to: baseTo), db, normals) / 4 : nil
            let spiking = baseline.map { $0 > 0 && load / $0 > spikeAbove } ?? false
            return WeekLoad(end: end, load: load, baseline: baseline, spiking: spiking, isCurrent: back == 0)
        }
    }

    public struct SessionLoad: Sendable, Hashable, Identifiable {
        public var id: String { sessionId }
        public var sessionId: String
        public var date: String
        public var sends: Int
        public var attempts: Int
        public var load: Double
    }

    /// Sessions inside the last 7 days with their share, newest first.
    public static func sessions(_ db: Database, today: String) -> [SessionLoad] {
        let normals = normals(db, today: today)
        let climbs = Metrics.climbsInRange(db.climbs, from: Day.add(today, -6), to: today)
        return Dictionary(grouping: climbs, by: \.sessionId).map { id, cs in
            SessionLoad(sessionId: id, date: db.session(id)?.date ?? cs[0].day, sends: cs.filter(Metrics.isSend).count,
                        attempts: cs.reduce(0) { $0 + max(1, $1.attempts) }, load: total(cs, db, normals))
        }
        .sorted { ($0.date, $0.sessionId) > ($1.date, $1.sessionId) }
    }
}

/* ── Progress and Body ─────────────────────────────────────────────────────── */

public enum Pillars {
    public struct Progress: Sendable, Hashable {
        /// Top numbered grade sent in the range
        public var top: Int?
        /// top − the previous range's top
        public var delta: Int?
        public var hardSends: Int
        public var previousHardSends: Int
        /// hard ÷ previous; nil when the previous range had none
        public var ratio: Double?
    }

    /// Uses the Progress range (`settings.dashboardRange`).
    public static func progress(_ db: Database, today: String) -> Progress {
        let w = db.settings.dashboardRange.windows(today: today)
        let cur = Metrics.climbsInRange(db.climbs, from: w.from, to: w.to)
        let prev = Metrics.climbsInRange(db.climbs, from: w.prevFrom, to: w.prevTo)
        let top = Metrics.maxGradeSent(cur, gyms: db.gyms).grade
        let prevTop = Metrics.maxGradeSent(prev, gyms: db.gyms).grade
        let hard = Metrics.volumeAtHard(cur), prevHard = Metrics.volumeAtHard(prev)
        return Progress(top: top, delta: top.flatMap { t in prevTop.map { t - $0 } }, hardSends: hard, previousHardSends: prevHard,
                        ratio: prevHard > 0 ? Double(hard) / Double(prevHard) : (hard > 0 ? 1 : nil))
    }

    public enum BodyState: Int, Sendable, Hashable, Comparable {
        case clear = 0, onTrack, caution, warning
        public static func < (a: BodyState, b: BodyState) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Body: Sendable, Hashable {
        public var state: BodyState
        public var injuryName: String?
        /// Latest pain entry for that injury
        public var pain: Int?
        /// Days with rehab done in the last 7
        public var rehabDays: Int
        public var reason: String?
    }

    /// The worst active injury decides the state; no active injury reads Clear.
    public static func body(_ db: Database, today: String) -> Body {
        let active = db.activeInjuries
        guard !active.isEmpty else { return Body(state: .clear, injuryName: nil, pain: nil, rehabDays: 7, reason: nil) }
        let usage = Metrics.loadRuleUsage(db.loadRules.filter { $0.maxPerWeek != nil }, climbs: db.climbs, weekStart: Day.weekStart(today))
        var worst: Body?
        for inj in active {
            let pain = db.painEntries.filter { $0.injuryId == inj.id }.sorted { $0.date < $1.date }
            let latest = pain.last?.level
            let before = pain.dropLast().last?.level
            let ruleIds = Set(db.loadRules.filter { $0.injuryId == inj.id }.map(\.id))
            let mine = usage.filter { ruleIds.contains($0.ruleId) }
            let exercises = db.rehabExercises.filter { $0.injuryId == inj.id }
            let adherence = Metrics.rehabAdherence(exercises, logs: db.rehabLogs, window: 7, today: today)
            var state = BodyState.onTrack
            var reason: String?
            if let hit = mine.first(where: \.blocked) {
                state = .warning
                reason = "\(hit.headline) \(hit.used) of \(hit.cap ?? 0)"
            } else if let latest, let before, latest > before {
                state = .caution
                reason = "Pain \(before) → \(latest)"
            } else if let near = mine.first(where: \.nearing) {
                state = .caution
                reason = "\(near.headline) \(near.used) of \(near.cap ?? 0)"
            }
            let b = Body(state: state, injuryName: inj.name, pain: latest, rehabDays: adherence.doneDays, reason: reason)
            if worst == nil || b.state > worst!.state { worst = b }
        }
        return worst!
    }
}

/* ── The one insight on Today ──────────────────────────────────────────────── */

public enum Insights {
    public enum Destination: Sendable, Hashable { case progress, history }

    public struct Insight: Sendable, Hashable {
        public var headline: String
        public var detail: String
        public var destination: Destination
    }

    /// The most notable read in the last 8 weeks: a hard grade you send but never flash, then a review pattern,
    /// then the next Camp5 tag.
    public static func today(_ db: Database, today: String) -> Insight? {
        let w = RangeID.eightWeeks.windows(today: today)
        let cur = Metrics.climbsInRange(db.climbs, from: w.from, to: w.to)
        let rows = Metrics.sendPyramid(cur)
        if let row = rows.filter({ $0.count >= 5 && $0.flashed == 0 }).max(by: { $0.grade < $1.grade }) {
            let rate = Metrics.flashRate(cur).map { "Your flash rate is \(Int($0.rounded()))% overall" } ?? "Worth a flash attempt"
            return Insight(headline: "\(row.count) sends at \(row.grade), none flashed", detail: rate, destination: .progress)
        }
        let trends = Metrics.chipTrends(db.reviews, sessions: db.sessions)
        if let pattern = Metrics.chipPattern(trends) {
            // "“Sloppy feet” in 5 of the last 12 sessions. Worth a warm-up block." → headline + detail
            let parts = pattern.components(separatedBy: ". ")
            let detail = parts.count > 1 ? parts[1].trimmingCharacters(in: CharacterSet(charactersIn: ".")) : "From your last 12 reviews"
            return Insight(headline: parts[0], detail: detail, destination: .history)
        }
        let bars = Metrics.camp5Tally(cur)
        if bars.contains(where: { $0.count > 0 }) {
            return Insight(headline: Metrics.camp5Read(bars), detail: "Camp5, last 8 weeks", destination: .progress)
        }
        return nil
    }
}
