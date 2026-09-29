import Foundation

/// Demo data — a port of the web `src/db/seed.ts`. The PRNG and every draw happen in the same order,
/// so the demo log has the same shape as the web app's.
public enum Seed {
    /* ── Fixed reference data ────────────────────────────────────────── */

    public static let gyms: [Gym] = [
        Gym(id: "batuu", name: "Batuu", shortName: "Batuu", scaleType: .numeric, maxGrade: 15, offset: 0,
            note: "Reference scale for the numbered spine.", sortOrder: 1),
        Gym(id: "camp5", name: "Camp5 Eco City", shortName: "Camp5", scaleType: .rankedColour, tags: Vocab.camp5Tags,
            offset: 0, note: "Ranked colour tags only — never numbered.", sortOrder: 2),
        Gym(id: "bump-pbj", name: "Bump PBJ", shortName: "Bump PBJ", scaleType: .numeric, maxGrade: 12, offset: 0,
            note: "Shares one 1–12 scale with J1 and SSQ.", sortOrder: 3),
        Gym(id: "bump-j1", name: "Bump J1", shortName: "Bump J1", scaleType: .numeric, maxGrade: 12, offset: 0, sortOrder: 4),
        Gym(id: "bump-ssq", name: "Bump SSQ", shortName: "Bump SSQ", scaleType: .numeric, maxGrade: 12, offset: 0, sortOrder: 5),
        Gym(id: "bhub", name: "BHUB", shortName: "BHUB", scaleType: .numeric, maxGrade: 10, offset: -0.5,
            note: "Soft relative to Batuu.", sortOrder: 6),
    ]

    public static let boards: [Board] = [
        Board(id: "kilter", name: "KilterBoard", code: "KB", angles: [25, 30, 40, 45], sortOrder: 1),
        Board(id: "tb2", name: "TensionBoard 2", code: "TB", angles: [25, 40], sortOrder: 2),
    ]

    /// Send-rate targets per style across the five grade bands — shapes the heatmap.
    static let sendRate: [String: [Double]] = [
        "Slopey": [0.92, 0.78, 0.61, 0.24, 0],
        "Coordination": [0.95, 0.83, 0.66, 0.31, 0],
        "Slab": [0.84, 0.7, 0.45, 0.17, 0],
        "Compression": [0.74, 0.39, 0.18, 0, 0],
        "Crimpy": [0.68, 0.34, 0.15, 0, 0],
        "Power": [0.88, 0.72, 0.52, 0.2, 0],
    ]

    static func bandIndex(_ grade: Int) -> Int { min(4, max(0, Int((Double(grade - 6) / 2).rounded(.down)))) }

    static let flashByGrade: [Int: Double] = [6: 0.82, 7: 0.73, 8: 0.5, 9: 0.42, 10: 0.3, 11: 0.2, 12: 0.18, 13: 0, 14: 0, 15: 0]

    /// Weights are over *attempted* climbs, not sends — the high grades carry a lot
    /// of failed attempts, which is what puts a taper on the send pyramid.
    static let gymGradeWeights: [(Int, Double)] = [(6, 10), (7, 26), (8, 48), (9, 38), (10, 40), (11, 22), (12, 16), (13, 6)]

    /// Batuu is the home gym; BHUB is the soft one you drop into.
    static let gymWeights: [(String, Double)] = [("batuu", 34), ("bump-pbj", 20), ("bump-j1", 15), ("bump-ssq", 11), ("bhub", 20)]

    static let tagWeights: [(String, Int)] = [("yellow", 7), ("pink", 10), ("blue", 14), ("orange", 17), ("green", 14), ("purple", 10), ("red", 5)]

    static let holdPool = ["yellow", "pink", "blue", "orange", "green", "purple", "red", "black", "white"]

    static let locations = [
        "cave, right of the arête", "main wall roof", "slab corner", "comp wall", "the prow", "left of the volume", "training bay",
    ]

    static let boardClimbNames = [
        "shrimp cocktail", "tiny dancer", "gravity check", "sloper heaven", "the pinch", "moon boots", "crimp city", "hangdog",
    ]

    /* ── Deterministic PRNG (mulberry32, bit-exact with the web) ─────── */

    struct RNG {
        var a: UInt32

        mutating func next() -> Double {
            a = a &+ 0x6D2B_79F5
            var t = (a ^ (a >> 15)) &* (1 | a)
            t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }

        mutating func pick<T>(_ xs: [T]) -> T { xs[Int(next() * Double(xs.count))] }
        mutating func chance(_ p: Double) -> Bool { next() < p }
        mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(next() * Double(hi - lo + 1)) }

        mutating func weighted<T>(_ entries: [(T, Double)]) -> T {
            let total = entries.reduce(0) { $0 + $1.1 }
            var r = next() * total
            for (v, w) in entries {
                r -= w
                if r <= 0 { return v }
            }
            return entries[entries.count - 1].0
        }
    }

    /* ── Generators ──────────────────────────────────────────────────── */

    static func stylesForIntent(_ intent: String) -> [String] {
        switch intent {
        case "Coordination": ["Coordination", "Coordination", "Slopey", "Power"]
        case "Slab / technique": ["Slab", "Slab", "Slopey", "Crimpy"]
        case "Max strength": ["Crimpy", "Compression", "Power", "Slopey"]
        case "Power endurance": ["Power", "Slopey", "Coordination", "Compression"]
        case "Comp sim": Vocab.climbStyles
        default: ["Slopey", "Slab", "Coordination"]
        }
    }

    static func tickFor(_ grade: Int, sent: Bool, _ rnd: inout RNG) -> (TickType, Int) {
        if !sent { return (.attempt, rnd.int(2, 6)) }
        if rnd.chance(flashByGrade[grade] ?? 0.3) { return (.flash, 1) }
        // hard sends take more goes, which is what attempts-per-send is measuring
        if rnd.chance(grade >= 10 ? 0.45 : 0.6) { return (.secondGo, 2) }
        return (.project, rnd.int(3, 8))
    }

    static func at(_ date: String, _ hour: Int, _ minute: Int) -> Date {
        Day.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Day.date(date))!
    }

    static func buildGymClimbs(_ sessionId: String, _ gymId: String, _ date: String, _ intent: String, _ rnd: inout RNG) -> [Climb] {
        var climbs: [Climb] = []
        let pool = stylesForIntent(intent)
        let cap = gymId == "bhub" ? 10 : gymId == "batuu" ? 13 : 12
        let n = rnd.int(8, 14)
        for i in 0..<n {
            // resample rather than clamp, so a low-ceiling gym does not pile up on its top grade
            var grade = rnd.weighted(gymGradeWeights)
            var tries = 0
            while grade > cap && tries < 6 { grade = rnd.weighted(gymGradeWeights); tries += 1 }
            if grade > cap { grade = cap }
            let primary = rnd.pick(pool)
            var styles = [primary]
            if rnd.chance(0.3) {
                let second = rnd.pick(Vocab.climbStyles)
                if second != primary { styles.append(second) }
            }
            let rate = sendRate[primary]?[bandIndex(grade)] ?? 0.6
            let sent = rnd.chance(rate)
            let (tick, attempts) = tickFor(grade, sent: sent, &rnd)
            let hold = rnd.pick(holdPool)
            let location = rnd.chance(0.55) ? rnd.pick(locations) : nil
            climbs.append(Climb(sessionId: sessionId, gymId: gymId, gradeKind: .number, grade: grade, holdColour: hold,
                                styles: styles, location: location, tickType: tick, attempts: attempts,
                                createdAt: at(date, 18 + i / 5, (i * 11) % 60)))
        }
        return climbs
    }

    /// Independent sampling leaves a single tag missing from a whole range often enough to look like a bug,
    /// so each session draws from a proportional urn — the tally then holds its intended hump across the range.
    static let tagUrn: [String] = tagWeights.flatMap { tag, w in Array(repeating: tag, count: w) }

    static func buildCamp5Climbs(_ sessionId: String, _ date: String, _ rnd: inout RNG) -> [Climb] {
        var climbs: [Climb] = []
        let n = rnd.int(10, 15)
        let offset = Int(rnd.next() * Double(tagUrn.count))
        let step = 7 // coprime with the urn size, so a session walks the whole spread
        for i in 0..<n {
            let tagId = tagUrn[(offset + i * step) % tagUrn.count]
            let ordinal = (Vocab.camp5Tags.firstIndex(of: tagId) ?? 0) + 1
            let sent = rnd.chance(ordinal >= 7 ? 0.45 : ordinal >= 5 ? 0.72 : 0.9)
            let (tick, attempts) = tickFor(min(13, 5 + ordinal), sent: sent, &rnd)
            climbs.append(Climb(sessionId: sessionId, gymId: "camp5", gradeKind: .tag, grade: ordinal, tagId: tagId,
                                holdColour: tagId, styles: [rnd.pick(Vocab.climbStyles)], tickType: tick, attempts: attempts,
                                createdAt: at(date, 19 + i / 6, (i * 9) % 60)))
        }
        return climbs
    }

    static func buildBoardClimbs(_ sessionId: String, _ date: String, _ boardId: String, _ angle: Int, _ rnd: inout RNG) -> [Climb] {
        var climbs: [Climb] = []
        let maxV = boardId == "kilter" ? 6 : 5
        let n = rnd.int(1, 3)
        for i in 0..<n {
            let v = rnd.weighted([(max(1, maxV - 3), 3.0), (max(1, maxV - 2), 7), (maxV - 1, 8), (maxV, 5), (maxV + 1, 3)])
            let sent = rnd.chance(v > maxV ? 0 : v == maxV ? 0.4 : 0.78)
            let (tick, attempts) = tickFor(min(13, 6 + v), sent: sent, &rnd)
            let name = rnd.pick(boardClimbNames)
            let styles = rnd.chance(0.5) ? ["Crimpy", "Tension"] : [rnd.pick(["Compression", "Power", "Tension"])]
            climbs.append(Climb(sessionId: sessionId, boardId: boardId, angle: angle, gradeKind: .v, grade: v,
                                styles: styles, name: name, tickType: tick, attempts: attempts,
                                createdAt: at(date, 20, 10 + i * 13)))
        }
        return climbs
    }

    static func buildReview(_ sessionId: String, _ intent: String, _ sends: Int, _ date: String, _ rnd: inout RNG) -> SessionReview {
        var chips: [String] = []
        let good = sends >= 8
        chips.append(good ? "Felt strong" : rnd.pick(["Felt weak", "Fatigued early"]))
        if rnd.chance(0.5) { chips.append("Good tension") }
        chips.append(rnd.pick(Vocab.reviewChips[.head]!))
        if intent == "Comp sim" { chips.append("Sloppy feet") }
        else if rnd.chance(0.45) { chips.append(rnd.pick(Vocab.reviewChips[.execution]!)) }
        if intent == "Coordination" && rnd.chance(0.7) { chips.append("Coordination dialled") }
        let score = max(3, min(9.6, ((4.5 + Double(sends) * 0.32 + rnd.next() * 1.4) * 10).rounded() / 10))
        let note: String? = rnd.chance(0.35) ? rnd.pick([
            "First 12 went second go after resting 8 min. Long rests are working.",
            "Skin was gone by the third block. Cut it short.",
            "Felt light on the feet all night — keep the warm-up length.",
            "Shoulder grumbled on the big span. Watch it.",
        ]) : nil
        var unique: [String] = []
        for c in chips where !unique.contains(c) { unique.append(c) }
        return SessionReview(sessionId: sessionId, chips: unique, overallScore: score, note: note, createdAt: at(date, 21, 15))
    }

    /// The random walk gets the shape right but leaves the very top of the pyramid to luck, and an empty 12/13 row
    /// reads as a broken chart rather than a hard grade. This tops the tail up to the counts the demo is meant to show.
    static func topUpMilestones(_ sessions: [Session], _ climbs: inout [Climb], _ today: String, _ rnd: inout RNG) {
        let since = Day.add(today, -55)
        let recent = sessions.filter { $0.date >= since }
        func inWindow(_ c: Climb) -> Bool { c.day >= since }
        func isSent(_ c: Climb) -> Bool { c.tickType != .attempt }

        func add(_ session: Session?, _ body: Climb, _ minute: Int) {
            guard let session else { return }
            var c = body
            c.sessionId = session.id
            c.createdAt = at(session.date, 20, minute % 60)
            climbs.append(c)
        }
        func lastAt(_ gymIds: [String]) -> Session? { recent.last { $0.gymId.map(gymIds.contains) ?? false } }

        /* one 13 at Batuu — the projecting edge */
        if !climbs.contains(where: { inWindow($0) && $0.gradeKind == .number && $0.grade == 13 && isSent($0) }) {
            add(lastAt(["batuu"]), Climb(sessionId: "", gymId: "batuu", gradeKind: .number, grade: 13, holdColour: "black",
                                         styles: ["Slopey", "Power"], location: "the prow", tickType: .project, attempts: 9), 41)
        }

        /* The 12–13 band is where the style story lives: the hard grades go down on slopers and coordination,
           and nothing crimpy or compressive goes at all. Small samples up there leave that to chance, so pin it. */
        let hosts = recent.filter { $0.gymId != nil && $0.gymId != "camp5" && $0.gymId != "bhub" }
        func band3(_ c: Climb) -> Bool { inWindow(c) && c.gradeKind == .number && c.grade >= 12 && c.grade <= 13 }
        func addAt12(_ style: String, _ tick: TickType, _ attempts: Int, _ minute: Int) {
            let host = hosts.isEmpty ? nil : hosts[minute % max(1, hosts.count)]
            let hold = rnd.pick(holdPool)
            add(host, Climb(sessionId: "", gymId: host?.gymId, gradeKind: .number, grade: 12, holdColour: hold,
                            styles: [style], tickType: tick, attempts: attempts), minute)
        }

        // strong styles keep a foothold at 12, at roughly the send rate the row claims
        for (si, (style, target, rate)) in [("Slopey", 2, 0.24), ("Coordination", 2, 0.31), ("Slab", 1, 0.17)].enumerated() {
            let sentAt12 = climbs.filter { band3($0) && isSent($0) && $0.grade == 12 && $0.styles.contains(style) }.count
            if sentAt12 < target {
                for i in sentAt12..<target {
                    let attempts = i == 0 ? 2 : rnd.int(3, 7)
                    addAt12(style, i == 0 ? .secondGo : .project, attempts, 44 + si * 3 + i)
                }
            }
            let wantTotal = Int((Double(target) / rate).rounded())
            let total = climbs.filter { band3($0) && $0.styles.contains(style) }.count
            if total < wantTotal {
                for i in total..<wantTotal { addAt12(style, .attempt, rnd.int(2, 6), 70 + si * 6 + i) }
            }
        }

        // the two gap styles: attempts up there, never a send
        for (si, style) in ["Compression", "Crimpy"].enumerated() {
            for idx in climbs.indices where band3(climbs[idx]) && isSent(climbs[idx]) && climbs[idx].styles.contains(style) {
                climbs[idx].tickType = .attempt
                climbs[idx].attempts = rnd.int(3, 7)
            }
            let tried = climbs.filter { band3($0) && $0.styles.contains(style) }.count
            if tried < 5 { for i in tried..<5 { addAt12(style, .attempt, rnd.int(3, 7), 56 + si * 4 + i) } }
        }

        /* five reds at Camp5 — first of the season */
        let reds = climbs.filter { inWindow($0) && $0.tagId == "red" && isSent($0) }.count
        let camp5Sessions = recent.filter { $0.gymId == "camp5" }
        if !camp5Sessions.isEmpty && reds < 5 {
            for i in reds..<5 {
                let style = rnd.pick(Vocab.climbStyles)
                let attempts = rnd.int(3, 7)
                add(camp5Sessions[i % camp5Sessions.count],
                    Climb(sessionId: "", gymId: "camp5", gradeKind: .tag, grade: 7, tagId: "red", holdColour: "red",
                          styles: [style], tickType: .project, attempts: attempts), 30 + i)
            }
        }

        /* each board's ceiling gets touched at least once */
        for (boardId, angle, maxV) in [("kilter", 40, 6), ("tb2", 25, 5)] {
            let hit = climbs.contains { inWindow($0) && $0.boardId == boardId && $0.angle == angle && $0.grade == maxV && isSent($0) }
            if hit { continue }
            let host = recent.last { s in climbs.contains { $0.sessionId == s.id && $0.boardId == boardId } }
            let name = rnd.pick(boardClimbNames)
            let attempts = rnd.int(5, 9)
            add(host ?? recent.last, Climb(sessionId: "", boardId: boardId, angle: angle, gradeKind: .v, grade: maxV,
                                           styles: ["Crimpy", "Tension"], name: name, tickType: .project, attempts: attempts), 52)
        }
    }

    /* ── Seed ────────────────────────────────────────────────────────── */

    public static func demo(now: Date = .now) -> Database {
        var rnd = RNG(a: 20_260_728)
        let today = Day.iso(now)
        var db = Database()
        db.gyms = gyms
        db.boards = boards

        /* Competitions — the web's one comp, plus the r2 season around it */
        db.competitions = [
            Competition(name: "Bump Bouldering League · rd 3", date: Day.add(today, 20), location: "Bump PBJ", gymId: "bump-pbj",
                        category: "League", format: "Redpoint / jam", rounds: ["Final"], priority: .c),
            Competition(name: "KL Open · Bouldering", date: Day.add(today, 42), location: "Bukit Jalil, Kuala Lumpur",
                        category: "Open", format: "Onsight rounds", rounds: ["Qualifiers", "Final"], priority: .a,
                        notes: "Registration closes two weeks out. Warm-up wall is small — bring a band."),
            Competition(name: "National Championships", date: Day.add(today, 76), location: "Venue TBC",
                        category: "Open", format: "Onsight rounds", rounds: ["Qualifiers", "Semi-final", "Final"], priority: .a),
        ]

        /* ── Injuries ────────────────────────────────────────────────── */
        let a2 = Injury(id: "inj-a2", bodyPart: "l-hand", name: "Left ring finger · A2 pulley strain",
                        onsetDate: Day.add(today, -197), status: .active, severity: "grade I",
                        diagnosis: "self-diagnosed, confirmed by physio 19 Jan", rehabStart: Day.add(today, -20),
                        physioNext: Day.add(today, 7),
                        physioNote: "Cleared for 40° board at V6 as long as it is not a full-crimp move. Reassess edge size in two weeks.")
        db.injuries = [
            a2,
            Injury(id: "inj-shoulder", bodyPart: "r-shoulder", name: "Right shoulder · impingement niggle",
                   onsetDate: Day.add(today, -60), status: .watching, severity: "niggle"),
            Injury(id: "inj-elbow", bodyPart: "l-elbow", name: "Left elbow · medial tendinopathy",
                   onsetDate: Day.add(today, -95), status: .watching, severity: "low grade"),
        ]

        db.rehabExercises = [
            RehabExercise(id: "rx-1", injuryId: a2.id, name: "No-hang half crimp", prescription: "10S × 5 · 60% BW · DAILY", frequency: 7),
            RehabExercise(id: "rx-2", injuryId: a2.id, name: "Finger extensor band", prescription: "3 × 15 · DAILY", frequency: 7),
            RehabExercise(id: "rx-3", injuryId: a2.id, name: "Tendon glides", prescription: "2 × 10 · MORNING & NIGHT", frequency: 7),
            RehabExercise(id: "rx-4", injuryId: a2.id, name: "Progressive edge loading", prescription: "20MM · 7S × 4 · 3×/WEEK", frequency: 3),
        ]

        /* 11 of the last 12 days done — one missed */
        let missedDay = Day.add(today, -8)
        for i in stride(from: 11, through: 0, by: -1) {
            let date = Day.add(today, -i)
            if date == missedDay { continue }
            db.rehabLogs.append(RehabLog(id: uid(), exerciseId: "rx-1", date: date, done: true))
            if i > 0 || rnd.chance(0.5) { db.rehabLogs.append(RehabLog(id: uid(), exerciseId: "rx-2", date: date, done: true)) }
            if i % 3 == 0 { db.rehabLogs.append(RehabLog(id: uid(), exerciseId: "rx-4", date: date, done: true)) }
        }

        db.loadRules = [
            LoadRule(id: "lr-1", injuryId: a2.id, styleOrType: "Crimpy", maxPerWeek: 2, condition: "while A2 pain is above 1/10",
                     headline: "Crimpy sessions · max 2 per week"),
            LoadRule(id: "lr-2", injuryId: a2.id, styleOrType: "Campus", maxPerWeek: nil,
                     condition: "until pain ≤ 1/10 for 14 straight days", headline: "No campus / no full crimp"),
        ]

        /* ── Sessions across 26 weeks ────────────────────────────────── */
        var sessions: [Session] = []
        var climbs: [Climb] = []
        var reviews: [SessionReview] = []

        var cursor = Day.add(today, -182)
        var camp5Countdown = 0
        var boardCountdown = 0
        var boardBlock = 0
        let intents: [(String, Double)] = Vocab.sessionIntents.map { ($0, $0 == "Comp sim" ? 1.4 : 1) }

        while cursor < today {
            let dow = Day.parts(cursor).dow
            // train Mon / Wed / Thu / Sat, roughly
            let trains = [1, 3, 4, 6].contains(dow) && rnd.chance(0.86)
            if !trains { cursor = Day.add(cursor, 1); continue }

            let isCamp5 = camp5Countdown <= 0 && rnd.chance(0.4)
            let gymId = isCamp5 ? "camp5" : rnd.weighted(gymWeights)
            if isCamp5 { camp5Countdown = 2 } else { camp5Countdown -= 1 }

            let intent = rnd.weighted(intents)
            let id = uid() + String(sessions.count)
            var sessionClimbs = isCamp5 ? buildCamp5Climbs(id, cursor, &rnd) : buildGymClimbs(id, gymId, cursor, intent, &rnd)

            let withBoard = !isCamp5 && boardCountdown <= 0 && rnd.chance(0.8)
            if withBoard {
                boardCountdown = 1
                // Kilter is the main board — two blocks on it for every one on the TB2
                boardBlock += 1
                let boardId = boardBlock % 3 == 0 ? "tb2" : "kilter"
                sessionClimbs += buildBoardClimbs(id, cursor, boardId, boardId == "kilter" ? 40 : 25, &rnd)
            } else {
                boardCountdown -= 1
            }

            sessions.append(Session(id: id, date: cursor, gymId: gymId, intent: intent, durationMin: rnd.int(75, 145),
                                    status: .done, startedAt: at(cursor, 18, 30), endedAt: at(cursor, 21, 0)))
            climbs += sessionClimbs
            let sends = sessionClimbs.filter { $0.tickType != .attempt }.count
            reviews.append(buildReview(id, intent, sends, cursor, &rnd))

            cursor = Day.add(cursor, 1)
        }

        topUpMilestones(sessions, &climbs, today, &rnd)

        /* ── Pain entries: last 12 sessions, 7/10 → 2/10 ─────────────── */
        let painCurve = [7, 8, 6, 6, 5, 5, 4, 4, 3, 3, 2, 2]
        db.painEntries = sessions.suffix(12).enumerated().map { i, s in
            PainEntry(id: uid() + "p\(i)", injuryId: a2.id, sessionId: s.id, date: s.date, level: painCurve[i])
        }

        /* ── Tonight: a live session at Batuu, 7 sends ───────────────── */
        let liveId = uid() + "live"
        let started = now.addingTimeInterval(-72 * 60)
        let live = Session(id: liveId, date: today, gymId: "batuu", intent: "Comp sim", status: .active, startedAt: started)
        let tonight: [(Int, String, [String], TickType, Int, String?)] = [
            (9, "green", ["Slopey"], .flash, 1, nil),
            (8, "blue", ["Slab"], .flash, 1, "slab corner"),
            (10, "purple", ["Coordination"], .flash, 1, nil),
            (9, "pink", ["Power"], .secondGo, 2, "comp wall"),
            (10, "yellow", ["Compression"], .project, 5, "main wall roof"),
            (8, "red", ["Crimpy"], .secondGo, 2, nil),
            (11, "orange", ["Crimpy"], .project, 4, "cave, right of the arête"),
        ]
        let liveClimbs = tonight.enumerated().map { i, t in
            Climb(id: uid() + "t\(i)", sessionId: liveId, gymId: "batuu", gradeKind: .number, grade: t.0, holdColour: t.1,
                  styles: t.2, location: t.5, tickType: t.3, attempts: t.4, createdAt: started.addingTimeInterval(Double(i) * 11 * 60))
        }

        /* ── A plan sitting on today ─────────────────────────────────── */
        let plan = Session(id: uid() + "plan", date: today, gymId: "bump-j1", intent: "Max strength", focusStyles: ["Compression"],
                           plannedBlocks: [
                               PlanBlock(20, "Warm-up + footwork drill", target: "easy 5–7"),
                               PlanBlock(45, "Kilter 40° · limit boulders, long rests", target: "V5–V7 · 4 tries max", emphasis: true),
                               PlanBlock(30, "Compression project · main wall roof", target: "grade 11–12"),
                               PlanBlock(10, "A2 rehab · no-hang 10s × 5", target: "rehab", rehab: true),
                           ], status: .planned)

        db.sessions = sessions + [live, plan]
        db.climbs = climbs + liveClimbs
        db.reviews = reviews

        var s = Settings()
        s.activeSessionId = liveId
        s.dashboardRange = .eightWeeks
        s.blockStart = Day.weekStart(Day.add(today, -21))
        s.blockWeeks = 6
        s.blockPhase = "BUILD"
        s.seededAt = today
        db.settings = s
        db.normalise()
        return db
    }

    /// "Clear everything": the reference gyms and boards, nothing logged.
    public static func empty() -> Database {
        var db = Database()
        db.gyms = gyms
        db.boards = boards
        return db
    }
}

/* ── Session plan templates (web `BLOCK_TEMPLATES`) ─────────────────────── */

public enum PlanTemplates {
    public static let blocks: [String: [PlanBlock]] = [
        "Max strength": [
            PlanBlock(20, "Warm-up + footwork drill", target: "easy 5–7"),
            PlanBlock(45, "Kilter 40° · limit boulders, long rests", target: "V5–V7 · 4 tries max", emphasis: true),
            PlanBlock(30, "Project block · main wall roof", target: "grade 11–12"),
        ],
        "Power endurance": [
            PlanBlock(20, "Warm-up + easy circuit", target: "easy 5–7"),
            PlanBlock(40, "4×4s on mid-grade boulders", target: "grade 8–9", emphasis: true, dropInTaper: true),
            PlanBlock(20, "Down-climbs, no matching", target: "grade 6–7"),
        ],
        "Coordination": [
            PlanBlock(15, "Warm-up + dynamic mobility", target: "easy 5–6"),
            PlanBlock(45, "Comp-style dynos and run-and-jumps", target: "grade 9–11", emphasis: true),
            PlanBlock(20, "Repeat the two you flashed, faster", target: "flow"),
        ],
        "Comp sim": [
            PlanBlock(20, "Warm-up, then no previews", target: "easy 6–7"),
            PlanBlock(50, "5 boulders · 4 min on, 4 min off", target: "grade 9–12", emphasis: true),
            PlanBlock(15, "Cool-down + notes while it is fresh", target: "—"),
        ],
        "Slab / technique": [
            PlanBlock(15, "Warm-up + silent-feet drill", target: "easy 5–6"),
            PlanBlock(45, "Slab ladder, no hand matching", target: "grade 8–10", emphasis: true),
            PlanBlock(20, "Balance holds, 10s each", target: "technique"),
        ],
        "Chill maintenance": [
            PlanBlock(15, "Long easy warm-up", target: "easy 5–6"),
            PlanBlock(45, "Volume at two grades below limit", target: "grade 7–9", emphasis: true),
            PlanBlock(15, "Stretch + antagonists", target: "recovery"),
        ],
    ]

    /// A saved template wins over the built-in one.
    public static func blocks(for intent: String, in db: Database) -> [PlanBlock] {
        db.settings.templates[intent] ?? blocks[intent] ?? []
    }
}
