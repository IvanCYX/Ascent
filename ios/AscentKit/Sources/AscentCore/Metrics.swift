import Foundation

/// Every derived number, recomputed from the log — nothing is stored pre-aggregated.
/// A line-for-line port of the web `src/domain/metrics.ts`.
public enum Metrics {
    /* ── Primitives ──────────────────────────────────────────────────── */

    public static func isSend(_ c: Climb) -> Bool { c.tickType != .attempt }
    public static func isFlash(_ c: Climb) -> Bool { c.tickType == .flash }
    public static func isNumeric(_ c: Climb) -> Bool { c.gradeKind == .number }
    public static func isTag(_ c: Climb) -> Bool { c.gradeKind == .tag }
    public static func isBoard(_ c: Climb) -> Bool { c.gradeKind == .v }

    /// Numbered gyms share a 1–15 spine; each gym carries a soft/hard offset.
    public static func adjustedGrade(_ c: Climb, gyms: [Gym]) -> Double {
        Double(c.grade) + (gyms.first { $0.id == c.gymId }?.offset ?? 0)
    }

    public static func climbsInRange(_ climbs: [Climb], from: String, to: String) -> [Climb] {
        climbs.filter { $0.day >= from && $0.day <= to }
    }

    static func mean(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
    static func round1(_ n: Double) -> Double { (n * 10).rounded() / 10 }
    public static func fixed1(_ n: Double) -> String { String(format: "%.1f", round1(n)) }

    /* ── KPIs ────────────────────────────────────────────────────────── */

    public static let flashRateThreshold = 8
    public static let hardGradeThreshold = 10

    public struct MaxGrade: Sendable { public var grade: Int?; public var gymName: String; public var date: String }

    /// Highest grade with ≥1 send in range, on the numbered-gym spine, offset adjusted.
    public static func maxGradeSent(_ climbs: [Climb], gyms: [Gym]) -> MaxGrade {
        let pool = climbs.filter { isNumeric($0) && isSend($0) }
        guard var best = pool.first else { return .init(grade: nil, gymName: "", date: "") }
        var bestAdj = adjustedGrade(best, gyms: gyms)
        for c in pool {
            let adj = adjustedGrade(c, gyms: gyms)
            if adj > bestAdj || (adj == bestAdj && c.createdAt > best.createdAt) {
                best = c
                bestAdj = adj
            }
        }
        return .init(grade: best.grade, gymName: gyms.first { $0.id == best.gymId }?.name ?? "", date: best.day)
    }

    /// Flashed sends ÷ total sends, restricted to grade 8+ on the numbered spine.
    public static func flashRate(_ climbs: [Climb], threshold: Int = flashRateThreshold) -> Double? {
        let sends = climbs.filter { isNumeric($0) && isSend($0) && $0.grade >= threshold }
        guard !sends.isEmpty else { return nil }
        return Double(sends.filter(isFlash).count) / Double(sends.count) * 100
    }

    /// Mean attempts over sends at grade 10+.
    public static func attemptsPerSend(_ climbs: [Climb], threshold: Int = hardGradeThreshold) -> Double? {
        let sends = climbs.filter { isNumeric($0) && isSend($0) && $0.grade >= threshold }
        guard !sends.isEmpty else { return nil }
        return mean(sends.map { Double($0.attempts) })
    }

    /// Count of sends at grade ≥10 in range.
    public static func volumeAtHard(_ climbs: [Climb], threshold: Int = hardGradeThreshold) -> Int {
        climbs.filter { isNumeric($0) && isSend($0) && $0.grade >= threshold }.count
    }

    public struct Kpi: Sendable, Hashable {
        public var label: String
        public var value: String
        public var caption: String
        public var delta: String
        public var deltaStrong: Bool

        public init(label: String, value: String, caption: String, delta: String, deltaStrong: Bool) {
            self.label = label; self.value = value; self.caption = caption; self.delta = delta; self.deltaStrong = deltaStrong
        }
    }

    public static func buildKpis(cur: [Climb], prev: [Climb], gyms: [Gym], sessionCount: Int, rangeLabel: String) -> [Kpi] {
        let max = maxGradeSent(cur, gyms: gyms)
        let maxPrev = maxGradeSent(prev, gyms: gyms)
        let maxDelta: Int? = (max.grade != nil && maxPrev.grade != nil) ? max.grade! - maxPrev.grade! : nil

        let fr = flashRate(cur), frPrev = flashRate(prev)
        let aps = attemptsPerSend(cur), apsPrev = attemptsPerSend(prev)
        let vol = volumeAtHard(cur)

        let maxDeltaText: String = {
            guard let d = maxDelta else { return "— no prior window" }
            if d > 0 { return "▲ +\(d) vs previous \(rangeLabel)" }
            if d < 0 { return "▼ \(d) vs previous \(rangeLabel)" }
            return "— level vs previous \(rangeLabel)"
        }()

        let frDeltaText: String = {
            guard let fr, let frPrev else { return "— no prior window" }
            let diff = Int(abs(fr - frPrev).rounded())
            if diff == 0 { return "— level vs previous" }
            return "\(fr >= frPrev ? "▲ +" : "▼ ")\(diff) pts"
        }()

        let apsDeltaText: String = {
            guard let aps, let apsPrev else { return "— no prior window" }
            if aps < apsPrev { return "▼ \(fixed1(apsPrev)) → \(fixed1(aps)) (better)" }
            if aps > apsPrev { return "▲ \(fixed1(apsPrev)) → \(fixed1(aps))" }
            return "— flat at \(fixed1(aps))"
        }()

        return [
            Kpi(label: "MAX GRADE SENT",
                value: max.grade.map(String.init) ?? "—",
                caption: max.grade == nil ? "no sends in range" : "\(max.gymName) · \(fmtDay(max.date))",
                delta: maxDeltaText,
                deltaStrong: maxDelta != nil && maxDelta != 0),
            Kpi(label: "FLASH RATE",
                value: fr.map { "\(Int($0.rounded()))%" } ?? "—",
                caption: "grade \(flashRateThreshold)+",
                delta: frDeltaText,
                deltaStrong: fr != nil && frPrev != nil && Int(fr!.rounded()) != Int(frPrev!.rounded())),
            Kpi(label: "ATTEMPTS / SEND",
                value: aps.map(fixed1) ?? "—",
                caption: "at \(hardGradeThreshold)+",
                delta: apsDeltaText,
                deltaStrong: aps != nil && apsPrev != nil && round1(aps!) != round1(apsPrev!)),
            Kpi(label: "VOLUME AT \(hardGradeThreshold)+",
                value: String(vol),
                caption: "sends / \(rangeLabel)",
                delta: sessionCount > 0 ? "— \(fixed1(Double(vol) / Double(sessionCount))) per session" : "— no sessions yet",
                deltaStrong: false),
        ]
    }

    static func fmtDay(_ iso: String) -> String {
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        return "\(p[2]) \(months[p[1] - 1])"
    }

    /* ── Send pyramid (numbered gyms only) ───────────────────────────── */

    public struct PyramidRow: Sendable, Hashable {
        public var grade: Int
        public var count: Int
        public var flashed: Int
        /// 0–1 of the widest row
        public var width: Double
        /// 0–1 flashed share of this row
        public var flashShare: Double
    }

    public static func sendPyramid(_ climbs: [Climb], top: Int = 13, bottom: Int = 7) -> [PyramidRow] {
        let sends = climbs.filter { isNumeric($0) && isSend($0) }
        var rows: [PyramidRow] = []
        for g in stride(from: top, through: bottom, by: -1) {
            let at = sends.filter { $0.grade == g }
            let flashed = at.filter(isFlash).count
            rows.append(.init(grade: g, count: at.count, flashed: flashed, width: 0,
                              flashShare: at.isEmpty ? 0 : Double(flashed) / Double(at.count)))
        }
        let maxCount = Swift.max(1, rows.map(\.count).max() ?? 0)
        return rows.map { var r = $0; r.width = Double(r.count) / Double(maxCount); return r }
    }

    public static func pyramidRead(_ rows: [PyramidRow]) -> String {
        let nonEmpty = rows.filter { $0.count > 0 }
        guard nonEmpty.count >= 2 else { return "Not enough sends in this range to read a shape yet." }
        let widest = nonEmpty.dropFirst().reduce(nonEmpty[0]) { $1.count > $0.count ? $1 : $0 }
        let top = nonEmpty[0]
        let consolidating = nonEmpty.first { $0.grade < top.grade && $0.count >= 5 }
        var parts = ["Base is widest at \(widest.grade)"]
        if let c = consolidating {
            parts.append(c.flashed > 0
                ? "the \(c.grade)s are consolidating (\(c.count) sends, \(c.flashed) flashed)"
                : "the \(c.grade)s are going but none first go yet (\(c.count) sends)")
        }
        parts.append(top.count <= 2
            ? "only \(top.count) send\(top.count == 1 ? "" : "s") at \(top.grade) — that is the projecting edge"
            : "\(top.grade) is established at \(top.count) sends")
        return parts.joined(separator: " and ") + "."
    }

    /* ── Camp5 colour tally ──────────────────────────────────────────── */

    public struct TagBar: Sendable, Hashable {
        public var tagId: String
        public var ordinal: Int
        public var count: Int
        /// 0–1 of the tallest bar
        public var height: Double
    }

    public static func camp5Tally(_ climbs: [Climb], tags: [String] = Vocab.camp5Tags) -> [TagBar] {
        let sends = climbs.filter { isTag($0) && isSend($0) }
        let bars = tags.enumerated().map { i, tag in
            TagBar(tagId: tag, ordinal: i + 1, count: sends.filter { $0.tagId == tag }.count, height: 0)
        }
        let maxCount = Swift.max(1, bars.map(\.count).max() ?? 0)
        return bars.map { var b = $0; b.height = Double(b.count) / Double(maxCount); return b }
    }

    public static func camp5Read(_ bars: [TagBar]) -> String {
        let untouched = bars.filter { $0.count == 0 }.sorted { $0.ordinal < $1.ordinal }
        guard let hardest = bars.filter({ $0.count > 0 }).last else { return "No Camp5 sends in this range yet." }
        let name = Vocab.colourCode(hardest.tagId)
        if let chase = untouched.first(where: { $0.ordinal > hardest.ordinal }) {
            return "\(hardest.count) \(name.lowercased()) tag\(hardest.count == 1 ? "" : "s") this range. \(Vocab.colourCode(chase.tagId)) is still untouched — that is the Camp5 milestone to chase."
        }
        return "Everything up to \(name.lowercased()) has gone this range."
    }

    /* ── Style × grade heatmap ───────────────────────────────────────── */

    /// Documented intensity ramp, keyed off send-rate %. (The iOS heatmap uses 0.07 + pct × 0.78, see DESIGN §3.1.)
    public static func intensityAlpha(_ pct: Int) -> Double {
        switch pct {
        case 90...: 1
        case 80...: 0.82
        case 76...: 0.78
        case 72...: 0.68
        case 69...: 0.62
        case 64...: 0.6
        case 58...: 0.55
        case 42...: 0.4
        case 36...: 0.32
        case 28...: 0.28
        case 20...: 0.2
        default: 0.15
        }
    }

    public struct HeatCell: Sendable, Hashable {
        public var band: String
        /// nil = no attempts logged in this band
        public var pct: Int?
        public var attempts: Int
    }

    public struct HeatRow: Sendable, Hashable {
        public var style: String
        public var cells: [HeatCell]
        public var weak: Bool
        public var comment: String
    }

    public static let heatmapStyles = ["Slopey", "Coordination", "Slab", "Compression", "Crimpy"]

    /// Style send rate = sends ÷ (sends + attempt-only) per style × grade band.
    public static func styleSendRate(_ climbs: [Climb], style: String, min: Int, max: Int) -> (pct: Double?, attempts: Int) {
        let pool = climbs.filter { isNumeric($0) && $0.styles.contains(style) && $0.grade >= min && $0.grade <= max }
        guard !pool.isEmpty else { return (nil, 0) }
        return (Double(pool.filter(isSend).count) / Double(pool.count) * 100, pool.count)
    }

    public static func styleGradeMatrix(_ climbs: [Climb]) -> [HeatRow] {
        struct Raw { var style: String; var cells: [HeatCell]; var weak: Bool; var zeroIdx: Int }
        let rows: [Raw] = heatmapStyles.map { style in
            let cells = Vocab.gradeBands.map { b -> HeatCell in
                let r = styleSendRate(climbs, style: style, min: b.min, max: b.max)
                return HeatCell(band: b.label, pct: r.pct.map { Int($0.rounded()) }, attempts: r.attempts)
            }
            // a zero cell above the easy bands is a gap, not just a bad night
            let zeroIdx = cells.indices.first { cells[$0].pct == 0 && $0 >= 2 } ?? -1
            return Raw(style: style, cells: cells, weak: zeroIdx >= 0, zeroIdx: zeroIdx)
        }

        // only the strongest surviving row gets to claim it carries the pyramid
        func ceiling(_ r: Raw) -> Int {
            r.cells.enumerated().reduce(-1) { best, e in
                if let p = e.element.pct, p > 0 { return e.offset * 100 + p }
                return best
            }
        }
        var strongest: Raw?
        for r in rows where !r.weak {
            if strongest == nil || ceiling(r) > ceiling(strongest!) { strongest = r }
        }

        return rows.map { r in
            var comment = "steady"
            if r.weak {
                comment = "gap — nothing above \(Vocab.gradeBands[Swift.max(0, r.zeroIdx - 1)].max)"
            } else if strongest?.style == r.style {
                comment = "strength — carries the pyramid"
            } else if (r.cells[1].pct ?? 0) >= 75 {
                comment = "comp-ready"
            }
            return HeatRow(style: r.style, cells: r.cells, weak: r.weak, comment: comment)
        }
    }

    public static func heatmapRead(_ rows: [HeatRow], compName: String? = nil) -> String {
        let strong = rows.filter { !$0.weak }.map { $0.style.lowercased() }
        let weak = rows.filter(\.weak).map { $0.style.lowercased() }
        guard !weak.isEmpty else {
            return "No style is capping you inside this range — every row still has sends at its top band."
        }
        let target = compName.map { "the \($0)" } ?? "your next comp"
        return "Your ceiling is style-specific, not physical — the hard grades go down on \(strong.prefix(2).joined(separator: " and ")), nothing at the top band that is \(weak.joined(separator: " or ")). Two \(weak[0]) blocks a week for four weeks would move that row before \(target)."
    }

    /* ── Board panel ─────────────────────────────────────────────────── */

    public struct BoardSummary: Sendable, Hashable {
        public var boardId: String
        public var name: String
        public var code: String
        public var angle: Int
        public var sends: Int
        public var sessionsPerWeek: Double
        public var maxV: Int?
        public var prevMaxV: Int?
    }

    public static func boardSummaries(cur: [Climb], prev: [Climb], boards: [Board], weeks: Int) -> [BoardSummary] {
        var out: [BoardSummary] = []
        for board in boards {
            let mine = cur.filter { $0.boardId == board.id && isSend($0) }
            guard !mine.isEmpty else { continue }
            // headline the angle with the most sends (first-seen wins ties, as the web Map did)
            var order: [Int] = []
            var byAngle: [Int: [Climb]] = [:]
            for c in mine {
                let a = c.angle ?? 0
                if byAngle[a] == nil { order.append(a) }
                byAngle[a, default: []].append(c)
            }
            var angle = order[0]
            for a in order where byAngle[a]!.count > byAngle[angle]!.count { angle = a }
            let at = byAngle[angle]!
            let sessions = Set(at.map(\.sessionId)).count
            let prevAt = prev.filter { $0.boardId == board.id && isSend($0) && ($0.angle ?? 0) == angle }
            out.append(.init(boardId: board.id, name: board.name, code: board.code, angle: angle, sends: at.count,
                             sessionsPerWeek: weeks > 0 ? round1(Double(sessions) / Double(weeks)) : 0,
                             maxV: at.map(\.grade).max(), prevMaxV: prevAt.map(\.grade).max()))
        }
        return out
    }

    public struct VBar: Sendable, Hashable {
        public var v: Int
        public var count: Int
        public var height: Double
        public var isMax: Bool
    }

    public static func boardHistogram(_ climbs: [Climb], boardId: String, angle: Int) -> [VBar] {
        let sends = climbs.filter { $0.boardId == boardId && ($0.angle ?? 0) == angle && isSend($0) }
        var counts: [Int: Int] = [:]
        for c in sends { counts[c.grade, default: 0] += 1 }
        let maxV = sends.map(\.grade).max() ?? 0
        let hi = Swift.max(maxV + 2, 7)
        let maxCount = Swift.max(1, counts.values.max() ?? 0)
        var bars: [VBar] = []
        for v in 1...Swift.min(hi, 10) {
            let count = counts[v] ?? 0
            bars.append(.init(v: v, count: count, height: Double(count) / Double(maxCount), isMax: v == maxV && count > 0))
        }
        // trim leading empties so the chart starts where the data does
        if let first = bars.firstIndex(where: { $0.count > 0 }), first > 0 {
            return Array(bars[Swift.max(0, first - 1)...])
        }
        return bars
    }

    /* ── Comp readiness ──────────────────────────────────────────────── */

    public struct ReadinessRow: Sendable, Hashable {
        public var label: String
        public var score: Int
        public var warn: Bool
    }

    /// Chips that push a readiness row up (+) or down (−).
    static let chipSignal: [String: Double] = [
        "Felt strong": 0.15, "Good tension": 0.12, "Locked in": 0.1, "Confident first go": 0.12,
        "Coordination dialled": 0.15, "Good beta reading": 0.1, "Felt weak": -0.15, "Fatigued early": -0.15,
        "Poor recovery": -0.12, "Distracted": -0.08, "Hesitant": -0.1, "Scared of the fall": -0.12,
        "Missed the timing": -0.12, "Sloppy feet": -0.1, "Read beta wrong": -0.1,
    ]

    public static let readinessStyle: [String: String] = [
        "Coordination": "Coordination", "Power": "Power", "Slab": "Slab", "Power endurance": "Power",
        "Compression": "Compression", "Crimps": "Crimpy",
    ]

    static let readinessChips: [String: [String]] = [
        "Coordination": ["Coordination dialled", "Missed the timing", "Good beta reading", "Read beta wrong"],
        "Power": ["Felt strong", "Felt weak", "Confident first go"],
        "Slab": ["Sloppy feet", "Scared of the fall", "Good beta reading"],
        "Power endurance": ["Fatigued early", "Poor recovery", "Good tension"],
        "Compression": ["Good tension", "Felt weak"],
        "Crimps": ["Felt strong", "Felt weak", "Fatigued early"],
    ]

    /// 0–100 per style — normalised blend of send rate at the top two occupied grade bands,
    /// recency of exposure, and review-chip signal. Below 55 is flagged warn.
    public static func compReadiness(_ climbs: [Climb], reviews: [SessionReview], today: String) -> [ReadinessRow] {
        let rows = Vocab.readinessRows.map { label -> ReadinessRow in
            let style = readinessStyle[label]!

            // send rate across the two highest bands that actually have attempts
            let bandStats = Vocab.gradeBands.compactMap { styleSendRate(climbs, style: style, min: $0.min, max: $0.max).pct }
            let topTwo = bandStats.suffix(2)
            let rate = topTwo.isEmpty ? 0 : topTwo.reduce(0, +) / Double(topTwo.count) / 100
            // a 75% send rate at your top two bands is already comp-ready, so that is the ceiling
            let rateNorm = Swift.min(1, rate / 0.75)

            // recency — climbs touching this style in the last 21 days, 6 = saturated
            let since = Day.add(today, -21)
            let recent = climbs.filter { $0.styles.contains(style) && $0.day >= since }.count
            let recency = Swift.min(1, Double(recent) / 6)

            // review-chip signal, centred on 0.5
            let relevant = readinessChips[label] ?? []
            var signal = 0.5
            for r in reviews.suffix(8) {
                for chip in r.chips where relevant.contains(chip) { signal += (chipSignal[chip] ?? 0) / 2 }
            }
            signal = Swift.max(0, Swift.min(1, signal))

            let score = Int((100 * (0.5 * rateNorm + 0.25 * recency + 0.25 * signal)).rounded())
            return ReadinessRow(label: label, score: score, warn: score < Vocab.readinessWarnBelow)
        }
        return stableSorted(rows) { $0.score > $1.score }
    }

    /* ── Chip trends (`1g`) ──────────────────────────────────────────── */

    public struct ChipTrendRow: Sendable, Hashable {
        public var chip: String
        public var cells: [Bool]
        public var count: Int
    }

    public static func chipTrends(_ reviews: [SessionReview], sessions: [Session], window: Int = 12) -> [ChipTrendRow] {
        var dates: [String: String] = [:]
        for s in sessions { dates[s.id] = s.date }
        let ordered = stableSorted(reviews) { (dates[$0.sessionId] ?? "") < (dates[$1.sessionId] ?? "") }
        let last = Array(ordered.suffix(window))
        var order: [String] = []
        var counts: [String: Int] = [:]
        for r in last {
            for c in r.chips {
                if counts[c] == nil { order.append(c) }
                counts[c, default: 0] += 1
            }
        }
        let ranked = stableSorted(order) { counts[$0]! > counts[$1]! }.prefix(6)
        return ranked.map { chip in
            var cells: [Bool] = []
            for i in 0..<window {
                let idx = i - (window - last.count)
                cells.append(idx >= 0 && idx < last.count && last[idx].chips.contains(chip))
            }
            return ChipTrendRow(chip: chip, cells: cells, count: cells.filter { $0 }.count)
        }
    }

    /// Chips worth acting on — the ones that name something going wrong.
    static let watchChips: Set<String> = [
        "Felt weak", "Fatigued early", "Poor recovery", "Distracted", "Hesitant", "Scared of the fall",
        "Missed the timing", "Sloppy feet", "Read beta wrong",
    ]

    public static func chipPattern(_ rows: [ChipTrendRow], window: Int = 12) -> String? {
        let threshold = Int((Double(window) / 3).rounded(.up))
        if let watch = rows.first(where: { watchChips.contains($0.chip) && $0.count >= threshold }) {
            return "“\(watch.chip)” shows up in \(watch.count) of the last \(window) sessions. That is a habit, not a bad night — worth a dedicated block in the warm-up."
        }
        guard let top = rows.first(where: { $0.count >= Int((Double(window) / 2).rounded(.up)) }) else { return nil }
        return "“\(top.chip)” shows up in \(top.count) of the last \(window) sessions and nothing negative recurs as often. Whatever you changed, keep doing it."
    }

    /* ── Rehab adherence ─────────────────────────────────────────────── */

    public struct Adherence: Sendable, Hashable {
        public var days: [(date: String, done: Bool)] { zip(dates, done).map { ($0, $1) } }
        public var dates: [String]
        public var done: [Bool]
        public var streak: Int
        public var doneDays: Int
        public var total: Int
        public var missedLabel: String?
    }

    /// Completed exercise-days ÷ prescribed days over the last `window` days.
    public static func rehabAdherence(_ exercises: [RehabExercise], logs: [RehabLog], window: Int = 12, today: String) -> Adherence {
        let ids = Set(exercises.map(\.id))
        var doneDays = Set<String>()
        for l in logs where l.done && ids.contains(l.exerciseId) { doneDays.insert(l.date) }
        let dates = (0..<window).reversed().map { Day.add(today, -$0) }
        let done = dates.map { doneDays.contains($0) }
        var streak = 0
        for d in done.reversed() { if d { streak += 1 } else { break } }
        let missed = dates.indices.last { !done[$0] }.map { dates[$0] }
        return Adherence(dates: dates, done: done, streak: streak, doneDays: done.filter { $0 }.count, total: window, missedLabel: missed)
    }

    /* ── Load rules ──────────────────────────────────────────────────── */

    public struct LoadRuleUsage: Sendable, Hashable {
        public var ruleId: String
        public var headline: String
        public var used: Int
        public var cap: Int?
        public var condition: String
        /// at or over the cap
        public var blocked: Bool
        /// one under the cap
        public var nearing: Bool
    }

    /// Usage is counted per ISO week over *sessions* that included at least one climb
    /// of the ruled style — a single crimpy session is one use, not one per climb.
    public static func loadRuleUsage(_ rules: [LoadRule], climbs: [Climb], weekStart: String) -> [LoadRuleUsage] {
        let weekEnd = Day.add(weekStart, 6)
        return rules.map { rule in
            let inWeek = climbs.filter { $0.day >= weekStart && $0.day <= weekEnd && $0.styles.contains(rule.styleOrType) }
            let used = Set(inWeek.map(\.sessionId)).count
            return LoadRuleUsage(ruleId: rule.id, headline: rule.headline, used: used, cap: rule.maxPerWeek,
                                 condition: rule.condition,
                                 blocked: rule.maxPerWeek.map { used >= $0 } ?? true,
                                 nearing: rule.maxPerWeek.map { used == $0 - 1 } ?? false)
        }
    }

    /* ── Session helpers ─────────────────────────────────────────────── */

    public static func sessionSends(_ climbs: [Climb], sessionId: String) -> [Climb] {
        climbs.filter { $0.sessionId == sessionId && isSend($0) }
    }

    public enum TopGrades: Sendable, Hashable {
        case number([Int]), v([String]), tag([String])

        public var isEmpty: Bool {
            switch self {
            case .number(let xs): xs.isEmpty
            case .v(let xs), .tag(let xs): xs.isEmpty
            }
        }
    }

    public static func topGrades(_ climbs: [Climb]) -> TopGrades {
        let sends = climbs.filter(isSend)
        guard !sends.isEmpty else { return .number([]) }
        let half = Double(sends.count) / 2
        let tags = sends.filter(isTag)
        if Double(tags.count) >= half {
            var seen: [String] = []
            for c in tags where !seen.contains(c.tagId ?? "") { seen.append(c.tagId ?? "") }
            let ordered = stableSorted(seen) {
                (Vocab.camp5Tags.firstIndex(of: $0) ?? -1) > (Vocab.camp5Tags.firstIndex(of: $1) ?? -1)
            }
            return .tag(Array(ordered.prefix(2)))
        }
        let boards = sends.filter(isBoard)
        if Double(boards.count) >= half {
            return .v(Set(boards.map(\.grade)).sorted(by: >).prefix(2).map { "V\($0)" })
        }
        return .number(Array(Set(sends.filter(isNumeric).map(\.grade)).sorted(by: >).prefix(3)))
    }

    public static func weeksOut(today: String, compDate: String) -> Int {
        Swift.max(0, Int((Double(Day.between(today, compDate)) / 7).rounded(.up)))
    }
}

/// `Array.sort` is not documented as stable; the web relied on stable sorts for tie order.
func stableSorted<T>(_ xs: [T], by less: (T, T) -> Bool) -> [T] {
    xs.enumerated().sorted { a, b in
        if less(a.element, b.element) { return true }
        if less(b.element, a.element) { return false }
        return a.offset < b.offset
    }.map(\.element)
}
