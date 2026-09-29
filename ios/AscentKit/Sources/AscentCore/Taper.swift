import Foundation

/// Season phases around a competition (DESIGN §3.4). Everything here is derived; nothing is stored.
public enum Phase: String, Sendable, Hashable {
    case build = "BUILD"
    case peak = "PEAK"
    case taper = "TAPER"
    case compWeek = "COMP WK"
    case comp = "COMP"

    public var isTaper: Bool { self == .taper || self == .compWeek }
}

public enum Taper {
    /// Phase of `day` relative to one comp, or nil once the comp is over.
    /// Weeks are Mon–Sun; the comp week is the one containing the comp's first day.
    public static func phase(of comp: Competition, on day: String) -> Phase? {
        if day > comp.lastDay { return nil }
        if day >= comp.date { return .comp }
        let offset = Day.between(Day.weekStart(comp.date), Day.weekStart(day)) / 7
        switch comp.effectivePriority {
        case .a:
            switch offset {
            case 0: return .compWeek
            case -1: return .taper
            case -2: return .peak
            default: return .build
            }
        case .b:
            return offset == 0 ? .taper : .build
        case .c:
            return .build
        }
    }

    public static func volumeFactor(_ phase: Phase?, priority: CompPriority) -> Double {
        switch (phase, priority) {
        case (.peak, .a): 0.9
        case (.taper, _): 0.7
        case (.compWeek, _): 0.5
        default: 1
        }
    }

    /// The A or B comp that governs `day`: the first one that has not finished by then.
    /// When a C comp sits inside an A comp's taper, the A plan wins.
    public static func governingComp(_ comps: [Competition], on day: String) -> Competition? {
        comps.filter { $0.effectivePriority != .c && $0.lastDay >= day }.min { $0.date < $1.date }
    }

    public struct DayPhase: Sendable, Hashable {
        public var phase: Phase
        public var comp: Competition
        public var factor: Double
    }

    public static func dayPhase(_ comps: [Competition], on day: String) -> DayPhase? {
        guard let comp = governingComp(comps, on: day), let p = phase(of: comp, on: day) else { return nil }
        return DayPhase(phase: p, comp: comp, factor: volumeFactor(p, priority: comp.effectivePriority))
    }

    /* ── Season subtitle (Plan tab) ──────────────────────────────────── */

    /// "BUILD · 6 WK TO KL OPEN", "TAPER · WK 1 OF 2 · 12 DAYS TO KL OPEN", or the block phase when no A/B comp is within 8 weeks.
    public static func seasonLine(_ db: Database, today: String) -> String {
        if let dp = dayPhase(db.competitions, on: today), Day.between(today, dp.comp.date) <= 56 {
            let days = Day.between(today, dp.comp.date)
            let name = dp.comp.shortName
            switch dp.phase {
            case .taper, .compWeek:
                let total = dp.comp.effectivePriority == .a ? 2 : 1
                let wk = dp.phase == .compWeek && total == 2 ? 2 : 1
                return "\(dp.phase.rawValue) · WK \(wk) OF \(total) · \(days) DAY\(days == 1 ? "" : "S") TO \(name)"
            case .comp:
                return "COMP DAY · \(name)"
            default:
                return "\(dp.phase.rawValue) · \(Metrics.weeksOut(today: today, compDate: dp.comp.date)) WK TO \(name)"
            }
        }
        let start = db.settings.blockStart ?? Day.weekStart(today)
        let wk = min(db.settings.blockWeeks, max(1, Day.weeksBetween(start, today) + 1))
        return "WK \(wk) OF \(db.settings.blockWeeks) · \(db.settings.blockPhase)"
    }

    /* ── 8-week averages ─────────────────────────────────────────────── */

    public struct Averages: Sendable, Hashable {
        public var sessionsPerWeek: Double
        public var minutesPerWeek: Int
        public var hardSendsPerWeek: Double
    }

    public static func averages(_ db: Database, today: String) -> Averages {
        let from = Day.add(Day.weekStart(today), -56)
        let to = Day.add(Day.weekStart(today), -1)
        let done = db.sessions.filter { $0.status == .done && $0.date >= from && $0.date <= to }
        let minutes = done.reduce(0) { $0 + ($1.durationMin ?? plannedMinutes($1)) }
        let hard = Metrics.volumeAtHard(Metrics.climbsInRange(db.climbs, from: from, to: to))
        return Averages(sessionsPerWeek: Double(done.count) / 8, minutesPerWeek: Int((Double(minutes) / 8).rounded()),
                        hardSendsPerWeek: Double(hard) / 8)
    }

    static func plannedMinutes(_ s: Session) -> Int { (s.plannedBlocks ?? []).reduce(0) { $0 + $1.durationMin } }

    /// Minutes this Mon–Sun week: done sessions count what they took, planned/live ones what they plan.
    public static func minutesThisWeek(_ db: Database, today: String) -> Int {
        let from = Day.weekStart(today), to = Day.add(from, 6)
        return db.sessions.filter { $0.date >= from && $0.date <= to }
            .reduce(0) { $0 + ($1.status == .done ? ($1.durationMin ?? plannedMinutes($1)) : plannedMinutes($1)) }
    }

    /* ── Weekly target (Lock Screen gauge) ───────────────────────────── */

    /// `round(target × factor)`, never below 2 in TAPER and COMP WK.
    public static func weeklyTarget(_ db: Database, today: String) -> Int {
        let target = db.settings.weeklyTarget
        guard let dp = dayPhase(db.competitions, on: today), dp.phase != .comp else { return target }
        let scaled = Int((Double(target) * dp.factor).rounded())
        return dp.phase.isTaper ? max(2, scaled) : max(1, scaled)
    }

    /* ── Scaling a day's plan ────────────────────────────────────────── */

    public struct ScaledPlan: Sendable, Hashable {
        public var blocks: [PlanBlock]
        public var originalMinutes: Int
        public var minutes: Int
        public var dropped: [PlanBlock]
        public var explanation: String
    }

    /// Every duration × the phase factor, rounded to 5 min. The emphasis block keeps its intensity target and
    /// notes the original. Blocks marked drop-in-taper go. Rehab blocks are never scaled.
    public static func scale(_ blocks: [PlanBlock], factor: Double) -> ScaledPlan {
        var out: [PlanBlock] = []
        var dropped: [PlanBlock] = []
        for b in blocks {
            if b.isRehab { out.append(b); continue }
            if b.isDroppedInTaper { dropped.append(b); continue }
            var s = b
            s.durationMin = max(5, Int((Double(b.durationMin) * factor / 5).rounded()) * 5)
            if b.isEmphasis {
                s.target = [b.target, "was \(b.durationMin) min"].compactMap { $0 }.joined(separator: " · ")
            }
            out.append(s)
        }
        let before = blocks.filter { !$0.isRehab }.reduce(0) { $0 + $1.durationMin }
        let after = out.filter { !$0.isRehab }.reduce(0) { $0 + $1.durationMin }
        var text = "Blocks were shortened from \(before) to \(after) min."
        if !dropped.isEmpty {
            let names = dropped.map { shortBlockName($0.description) }.joined(separator: " and ")
            text += " The \(names) block\(dropped.count == 1 ? " was" : "s were") dropped."
        }
        text += " Keep the intensity: full-effort attempts, long rests."
        return ScaledPlan(blocks: out, originalMinutes: before + rehabMinutes(blocks), minutes: after + rehabMinutes(out),
                          dropped: dropped, explanation: text)
    }

    static func rehabMinutes(_ blocks: [PlanBlock]) -> Int { blocks.filter(\.isRehab).reduce(0) { $0 + $1.durationMin } }

    /// "4×4s on mid-grade boulders" → "4×4s"
    static func shortBlockName(_ d: String) -> String {
        (d.components(separatedBy: " on ").first ?? d).components(separatedBy: " · ").first ?? d
    }

    /* ── Season view — taper plan rows ───────────────────────────────── */

    public struct PlanRow: Sendable, Hashable, Identifiable {
        public var id: String { phase.rawValue + range }
        public var phase: Phase
        public var range: String
        public var lead: String
        public var body: String
        /// fill of the load bar, 0–1; nil = no bar
        public var factor: Double?
        public var isNow: Bool
    }

    public static func planRows(_ db: Database, comp: Competition, today: String, weakest: Metrics.ReadinessRow?) -> [PlanRow] {
        let compWeek = Day.weekStart(comp.date)
        let p = comp.effectivePriority
        let target = db.settings.weeklyTarget
        let avg = averages(db, today: today)
        func range(_ a: String, _ b: String) -> String {
            let sa = Day.short(a), sb = Day.short(b)
            if a.prefix(7) == b.prefix(7) { return "\(Day.dayOfMonth(a))–\(sb)" }
            return "\(sa) – \(sb)"
        }
        func dayName(_ iso: String) -> String {
            let w = Day.weekday(iso)
            return "\(w.prefix(1))\(w.dropFirst().lowercased()) \(Day.pretty(iso))"
        }
        let phaseNow = phase(of: comp, on: today)
        var rows: [PlanRow] = []

        let buildEnd: String
        switch p {
        case .a: buildEnd = Day.add(compWeek, -15)
        case .b: buildEnd = Day.add(compWeek, -1)
        case .c: buildEnd = Day.add(comp.date, -1)
        }
        let buildStart = Day.weekStart(today)
        if buildStart <= buildEnd {
            var body = "\(max(1, target - 1))–\(target) sessions a week at full volume."
            if let w = weakest, w.warn {
                body += " Two \((Metrics.readinessStyle[w.label] ?? w.label).lowercased()) sessions a week close the \(comp.displayName) gap (\(w.label) \(w.score))."
            }
            rows.append(.init(phase: .build, range: range(buildStart, buildEnd), lead: phaseNow == .build ? "Now." : "Build.",
                              body: body, factor: 1, isNow: phaseNow == .build))
        }

        switch p {
        case .a:
            let peak = Day.add(compWeek, -14), taper = Day.add(compWeek, -7)
            rows.append(.init(phase: .peak, range: range(peak, Day.add(peak, 6)), lead: "3 comp sims.",
                              body: "4 min on, 4 min off, no previews. Full intensity. Volume holds at 90%.",
                              factor: 0.9, isNow: phaseNow == .peak))
            let n = max(2, Int((Double(target) * 0.7).rounded()))
            rows.append(.init(phase: .taper, range: range(taper, Day.add(taper, 6)), lead: "\(n) sessions, 75 min max.",
                              body: "Volume 70% (about \(Int(Double(avg.minutesPerWeek) * 0.7)) min). Keep one limit session. Drop the 4×4s and new max-strength blocks.",
                              factor: 0.7, isNow: phaseNow == .taper))
            let m = max(2, Int((Double(target) * 0.5).rounded()))
            rows.append(.init(phase: .compWeek, range: range(compWeek, Day.add(comp.date, -1)), lead: "\(m) short sessions.",
                              body: "Volume 50%. Last hard session \(dayName(Day.add(comp.date, -4))). No limit board after \(Day.weekday(Day.add(comp.date, -6)).prefix(1))\(Day.weekday(Day.add(comp.date, -6)).dropFirst().lowercased()). Rest \(dayName(Day.add(comp.date, -1))).",
                              factor: 0.5, isNow: phaseNow == .compWeek))
        case .b:
            rows.append(.init(phase: .taper, range: range(compWeek, Day.add(comp.date, -1)), lead: "One lighter week.",
                              body: "Volume 70%. Last hard session \(dayName(Day.add(comp.date, -3))). Rest \(dayName(Day.add(comp.date, -1))).",
                              factor: 0.7, isNow: phaseNow == .taper))
        case .c:
            break
        }
        rows.append(.init(phase: .comp, range: comp.endDate.map { range(comp.date, $0) } ?? Day.short(comp.date),
                          lead: "\(comp.name).",
                          body: p == .c ? "Train through. Rest \(dayName(Day.add(comp.date, -1)))." : "Warm-up plan and notes go in the comp detail.",
                          factor: nil, isNow: phaseNow == .comp))
        return rows
    }

    /// Ledger subtitle: "Bukit Jalil · Open · A · full 2-week taper"
    public static func summary(_ comp: Competition, all: [Competition]) -> String {
        let taper: String
        switch comp.effectivePriority {
        case .a: taper = "full 2-week taper"
        case .b: taper = "one lighter week"
        case .c:
            let host = all.first { other in
                guard other.id != comp.id, other.effectivePriority != .c, let ph = phase(of: other, on: comp.date) else { return false }
                return ph.isTaper || ph == .peak
            }
            if let host {
                taper = "inside the \(host.displayName) taper — the A plan wins"
            } else {
                taper = "train through, rest the day before"
            }
        }
        return [comp.location, comp.category, comp.effectivePriority.rawValue, taper]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    /// First day of the taper, or nil for a C comp. "taper starts Mon 26 Oct"
    public static func taperStart(_ comp: Competition) -> String? {
        switch comp.effectivePriority {
        case .a: Day.add(Day.weekStart(comp.date), -7)
        case .b: Day.weekStart(comp.date)
        case .c: nil
        }
    }

    public static func peakStart(_ comp: Competition) -> String? {
        comp.effectivePriority == .a ? Day.add(Day.weekStart(comp.date), -14) : nil
    }
}
