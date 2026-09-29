import Foundation
import Testing
@testable import AscentCore

/// A fixed "now": Sun 27 Sep 2026, 20:14 local — the draft's demo day.
let demoNow: Date = {
    var c = DateComponents()
    c.year = 2026; c.month = 9; c.day = 27; c.hour = 20; c.minute = 14
    return Day.calendar.date(from: c)!
}()

@Suite struct DatesTests {
    @Test func isoRoundTrip() {
        #expect(Day.iso(Day.date("2026-09-27")) == "2026-09-27")
        #expect(Day.add("2026-09-27", 42) == "2026-11-08")
        #expect(Day.between("2026-09-27", "2026-11-08") == 42)
    }

    @Test func weekHelpers() {
        #expect(Day.weekStart("2026-09-27") == "2026-09-21") // Sunday belongs to the Monday before
        #expect(Day.weekStart("2026-09-21") == "2026-09-21")
        #expect(Day.isoWeek("2026-09-27").week == 39)
        #expect(Day.weekRangeLabel("2026-09-27") == "WK 39 · 21–27 SEP 2026")
        #expect(Day.weekRangeShort("2026-09-27") == "WK 39 · 21–27 SEP")
        #expect(Day.weekRangeLabel("2026-09-30") == "WK 40 · 28 SEP–4 OCT 2026")
    }

    @Test func labels() {
        #expect(Day.short("2026-07-26") == "26 JUL")
        #expect(Day.pretty("2026-01-12") == "12 Jan")
        #expect(Day.plan("2026-07-28") == "TUE 28 JUL")
        #expect(Day.long("2026-11-08") == "Sun 8 Nov 2026")
    }
}

@Suite struct SeedTests {
    /// First draws of mulberry32(20260728), computed with the web implementation in Node.
    @Test func prngMatchesWeb() {
        var rng = Seed.RNG(a: 20_260_728)
        let first = (0..<3).map { _ in rng.next() }
        #expect(first == [0.9747507595457137, 0.5334605739917606, 0.3748035260941833])
    }

    @Test func demoShape() {
        let db = Seed.demo(now: demoNow)
        #expect(db.gyms.count == 6)
        #expect(db.boards.count == 2)
        #expect(db.activeSession?.gymId == "batuu")
        #expect(Metrics.sessionSends(db.climbs, sessionId: db.activeSession!.id).count == 7)
        #expect(db.plannedSession(on: "2026-09-27")?.intent == "Max strength")
        #expect(db.sessions.filter { $0.status == .done }.count > 60)
        // Camp5 climbs never carry a number outside the tag ordinal
        #expect(db.climbs.filter { $0.gymId == "camp5" }.allSatisfy { $0.gradeKind == .tag && $0.tagId != nil })
        #expect(db.nextComp(from: "2026-09-27")?.name == "Bump Bouldering League · rd 3")
    }
}

@Suite struct BackupTests {
    @Test func roundTrip() throws {
        let db = Seed.demo(now: demoNow)
        let back = try Backup.decode(Backup.encode(db))
        #expect(back == db)
    }

    /// A file exported by the web app, before the iOS fields existed.
    @Test func readsWebExport() throws {
        let json = """
        {"version":1,"exportedAt":"2026-07-28T10:00:00.000Z","data":{
          "gyms":[{"id":"batuu","name":"Batuu","shortName":"Batuu","scaleType":"numeric","maxGrade":15,"offset":0,"sortOrder":1}],
          "boards":[],"reviews":[],"injuries":[],"painEntries":[],"rehabExercises":[],"rehabLogs":[],
          "climbs":[{"id":"c1","sessionId":"s1","gymId":"batuu","gradeKind":"number","grade":11,"holdColour":"blue",
                     "styles":["Crimpy"],"tickType":"second-go","attempts":2,"createdAt":"2026-07-28T11:02:03.456Z"}],
          "sessions":[{"id":"s1","date":"2026-07-28","gymId":"batuu","status":"active","startedAt":"2026-07-28T10:30:00.000Z"}],
          "loadRules":[{"id":"r","injuryId":"i","styleOrType":"Campus","maxPerWeek":null,"condition":"x","headline":"No campus"}],
          "competitions":[{"id":"k","name":"KL Open · Bouldering","date":"2026-09-08"}],
          "settings":[{"key":"activeSessionId","value":"s1"},{"key":"dashboardRange","value":"6m"},
                      {"key":"blockWeeks","value":6},{"key":"template:Comp sim","value":[{"durationMin":30,"description":"x"}]}]}}
        """
        let db = try Backup.decode(Data(json.utf8))
        #expect(db.activeSession?.id == "s1")
        #expect(db.settings.dashboardRange == .sixMonths)
        #expect(db.settings.templates["Comp sim"]?.first?.durationMin == 30)
        #expect(db.loadRules.first?.maxPerWeek == nil)
        #expect(db.competitions.first?.effectivePriority == .a)
        #expect(db.climbs.first?.tickType == .secondGo)
    }
}

@Suite struct MetricsTests {
    func climb(_ grade: Int, _ tick: TickType, styles: [String] = [], gym: String = "batuu", day: String = "2026-09-20") -> Climb {
        Climb(sessionId: "s-\(day)", gymId: gym, gradeKind: .number, grade: grade, styles: styles, tickType: tick,
              attempts: tick == .flash ? 1 : 3, createdAt: Seed.at(day, 19, 0))
    }

    @Test func maxGradeUsesOffset() {
        let gyms = Seed.gyms
        let c = [climb(10, .flash, gym: "bhub"), climb(10, .project, gym: "batuu", day: "2026-09-01")]
        let m = Metrics.maxGradeSent(c, gyms: gyms)
        #expect(m.grade == 10)
        #expect(m.gymName == "Batuu") // BHUB 10 is softer than Batuu 10
    }

    @Test func loadRulesCountSessionsNotClimbs() {
        let rule = LoadRule(injuryId: "i", styleOrType: "Crimpy", maxPerWeek: 2, condition: "", headline: "")
        let climbs = [climb(9, .flash, styles: ["Crimpy"], day: "2026-09-21"), climb(10, .flash, styles: ["Crimpy"], day: "2026-09-21"),
                      climb(8, .flash, styles: ["Crimpy"], day: "2026-09-23")]
        let u = Metrics.loadRuleUsage([rule], climbs: climbs, weekStart: "2026-09-21")[0]
        #expect(u.used == 2)
        #expect(u.blocked)
        let hard = LoadRule(injuryId: "i", styleOrType: "Campus", maxPerWeek: nil, condition: "", headline: "")
        #expect(Metrics.loadRuleUsage([hard], climbs: [], weekStart: "2026-09-21")[0].blocked)
    }

    @Test func topGradesNeverNumbersForCamp5() {
        let tags = ["purple", "blue", "red"].map {
            Climb(sessionId: "s", gymId: "camp5", gradeKind: .tag, grade: Vocab.camp5Tags.firstIndex(of: $0)! + 1, tagId: $0,
                  tickType: .flash, attempts: 1)
        }
        #expect(Metrics.topGrades(tags) == .tag(["red", "purple"]))
    }
}

@Suite struct TaperTests {
    let klOpen = Competition(name: "KL Open · Bouldering", date: "2026-11-08", priority: .a)

    @Test func aPhases() {
        #expect(Taper.phase(of: klOpen, on: "2026-09-27") == .build)
        #expect(Taper.phase(of: klOpen, on: "2026-10-19") == .peak)
        #expect(Taper.phase(of: klOpen, on: "2026-10-26") == .taper)
        #expect(Taper.phase(of: klOpen, on: "2026-11-02") == .compWeek)
        #expect(Taper.phase(of: klOpen, on: "2026-11-08") == .comp)
        #expect(Taper.phase(of: klOpen, on: "2026-11-09") == nil)
        #expect(Taper.taperStart(klOpen) == "2026-10-26")
    }

    @Test func bAndC() {
        let b = Competition(name: "B", date: "2026-11-08", priority: .b)
        #expect(Taper.phase(of: b, on: "2026-11-02") == .taper)
        #expect(Taper.phase(of: b, on: "2026-11-01") == .build)
        let c = Competition(name: "C", date: "2026-11-08", priority: .c)
        #expect(Taper.phase(of: c, on: "2026-11-07") == .build)
    }

    @Test func aWinsOverC() {
        let c = Competition(name: "League", date: "2026-10-28", priority: .c)
        #expect(Taper.dayPhase([c, klOpen], on: "2026-10-27")?.comp.name == klOpen.name)
        #expect(Taper.summary(c, all: [c, klOpen]).contains("the A plan wins"))
    }

    @Test func scalingRoundsToFiveAndKeepsRehab() {
        let blocks = PlanTemplates.blocks["Power endurance"]! + [PlanBlock(10, "rehab", rehab: true)]
        let scaled = Taper.scale(blocks, factor: 0.7)
        #expect(scaled.blocks.map(\.durationMin) == [15, 15, 10]) // 4×4s dropped, rehab kept at 10
        #expect(scaled.dropped.count == 1)
        #expect(scaled.explanation.hasPrefix("Blocks were shortened from 80 to 30 min. The 4×4s block was dropped."))
        let comp = Taper.scale(PlanTemplates.blocks["Comp sim"]!, factor: 0.7)
        #expect(comp.blocks[1].target == "grade 9–12 · was 50 min")
        #expect(comp.blocks.map(\.durationMin) == [15, 35, 10])
    }

    @Test func seasonLine() {
        var db = Seed.demo(now: demoNow)
        db.competitions = [klOpen]
        #expect(Taper.seasonLine(db, today: "2026-09-27") == "BUILD · 6 WK TO KL OPEN")
        #expect(Taper.seasonLine(db, today: "2026-10-27") == "TAPER · WK 1 OF 2 · 12 DAYS TO KL OPEN")
        db.settings.weeklyTarget = 4
        #expect(Taper.weeklyTarget(db, today: "2026-10-27") == 3)
        #expect(Taper.weeklyTarget(db, today: "2026-11-03") == 2)
    }
}

@Suite @MainActor struct StoreTests {
    @Test func sessionLifecycle() {
        let store = AscentStore(database: Seed.empty())
        var clock = demoNow
        store.now = { clock }
        let id = store.startSession(gymId: "batuu", intent: "Comp sim")
        #expect(store.db.activeSession?.id == id)
        store.addClimb(Climb(sessionId: id, gymId: "batuu", gradeKind: .number, grade: 11, holdColour: "blue",
                             tickType: .flash, attempts: 1))
        clock = demoNow.addingTimeInterval(95 * 60)
        store.saveReview(sessionId: id, chips: ["Locked in"], score: 7.4, note: nil)
        store.endSession(id)
        #expect(store.db.activeSession == nil)
        #expect(store.db.session(id)?.durationMin == 95)
        #expect(store.db.review(for: id)?.overallScore == 7.4)
    }

    @Test func painOncePerDay() {
        let store = AscentStore(database: Seed.demo(now: demoNow))
        store.now = { demoNow }
        let before = store.db.painEntries.count
        store.addPainEntry(injuryId: "inj-a2", level: 3, date: "2026-09-28")
        store.addPainEntry(injuryId: "inj-a2", level: 1, date: "2026-09-28")
        #expect(store.db.painEntries.count == before + 1)
        #expect(store.db.painEntries.last { $0.date == "2026-09-28" }?.level == 1)
    }
}

/// Writes the demo log and the Swift metric results so `scripts/parity.mjs` can diff them against the web code.
@Suite struct ParityExport {
    @Test func export() throws {
        guard let dir = ProcessInfo.processInfo.environment["PARITY_DIR"] else { return }
        let db = Seed.demo(now: demoNow)
        let today = Day.iso(demoNow)
        try Backup.encode(db).write(to: URL(fileURLWithPath: dir).appendingPathComponent("db.json"))
        try JSONSerialization.data(withJSONObject: parityResults(db, today: today), options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("swift.json"))
    }
}

func parityResults(_ db: Database, today: String) -> [String: Any] {
    var out: [String: Any] = ["today": today]
    for range in RangeID.allCases {
        let w = range.windows(today: today)
        let cur = Metrics.climbsInRange(db.climbs, from: w.from, to: w.to)
        let prev = Metrics.climbsInRange(db.climbs, from: w.prevFrom, to: w.prevTo)
        let sessionsInRange = db.sessions.filter { $0.status == .done && $0.date >= w.from && $0.date <= w.to }
        let weeks = max(1, Day.weeksBetween(w.from, w.to))
        let pyramid = Metrics.sendPyramid(cur)
        let heat = Metrics.styleGradeMatrix(cur)
        let tally = Metrics.camp5Tally(cur)
        out[range.rawValue] = [
            "count": cur.count,
            "kpis": Metrics.buildKpis(cur: cur, prev: prev, gyms: db.gyms, sessionCount: sessionsInRange.count,
                                      rangeLabel: range.label.lowercased()).map { [$0.label, $0.value, $0.caption, $0.delta] },
            "pyramid": pyramid.map { [$0.grade, $0.count, $0.flashed] },
            "pyramidRead": Metrics.pyramidRead(pyramid),
            "tally": tally.map { [$0.tagId, $0.count] },
            "camp5Read": Metrics.camp5Read(tally),
            "boards": Metrics.boardSummaries(cur: cur, prev: prev, boards: db.boards, weeks: weeks)
                .map { [$0.boardId, $0.angle, $0.sends, $0.sessionsPerWeek, $0.maxV ?? -1, $0.prevMaxV ?? -1] as [Any] },
            "heat": heat.map { r in [r.style, r.weak, r.comment, r.cells.map { $0.pct ?? -1 }] as [Any] },
            "heatRead": Metrics.heatmapRead(heat, compName: "KL Open · Bouldering"),
            "readiness": Metrics.compReadiness(cur, reviews: db.reviews, today: today).map { [$0.label, $0.score] as [Any] },
        ]
    }
    let trends = Metrics.chipTrends(db.reviews, sessions: db.sessions)
    out["trends"] = trends.map { [$0.chip, $0.count, $0.cells.map { $0 ? 1 : 0 }] as [Any] }
    out["pattern"] = Metrics.chipPattern(trends) ?? NSNull()
    let adh = Metrics.rehabAdherence(db.rehabExercises.filter { $0.injuryId == "inj-a2" }, logs: db.rehabLogs, today: today)
    out["adherence"] = [adh.streak, adh.doneDays, adh.missedLabel ?? ""] as [Any]
    out["loadRules"] = Metrics.loadRuleUsage(db.loadRules, climbs: db.climbs, weekStart: Day.weekStart(today))
        .map { [$0.ruleId, $0.used, $0.blocked, $0.nearing] as [Any] }
    out["histKilter40"] = Metrics.boardHistogram(db.climbs, boardId: "kilter", angle: 40).map { [$0.v, $0.count, $0.isMax] as [Any] }
    out["topGrades"] = db.sessions.suffix(10).map { s -> String in
        switch Metrics.topGrades(Metrics.sessionSends(db.climbs, sessionId: s.id)) {
        case .number(let xs): "n:" + xs.map(String.init).joined(separator: ",")
        case .v(let xs): "v:" + xs.joined(separator: ",")
        case .tag(let xs): "t:" + xs.joined(separator: ",")
        }
    }
    return out
}
