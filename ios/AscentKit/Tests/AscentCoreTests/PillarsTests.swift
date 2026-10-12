import Foundation
import Testing
@testable import AscentCore

@Suite struct AttemptTests {
    @Test func countDrivesTheTick() {
        #expect(Vocab.tickType(attempts: 1, sent: true) == .flash)
        #expect(Vocab.tickType(attempts: 2, sent: true) == .secondGo)
        #expect(Vocab.tickType(attempts: 5, sent: true) == .project)
        #expect(Vocab.tickType(attempts: 3, sent: false) == .attempt)
        #expect(Vocab.attemptsLabel(1, sent: true) == "Flash")
        #expect(Vocab.attemptsLabel(2, sent: true) == "2nd go")
        #expect(Vocab.attemptsLabel(4, sent: true) == "4 tries")
        #expect(Vocab.attemptsLabel(1, sent: false) == "1 attempt")
        #expect(Vocab.attemptsLabel(3, sent: false) == "3 attempts")
    }

    @Test func camp5OrderIsEasiestFirst() {
        #expect(Vocab.camp5Tags == ["pink", "blue", "yellow", "orange", "green", "purple", "red", "black"])
        #expect(Vocab.camp5Ranges["green"] == "V3–V5")
    }

    @Test func oldLogsAreReranked() {
        var db = Database()
        db.gyms = [Gym(id: "camp5", name: "Camp5", shortName: "Camp5", scaleType: .rankedColour,
                       tags: ["yellow", "pink", "blue", "orange", "green", "purple", "red", "black"], sortOrder: 1)]
        // saved before r3: yellow was 1, pink 2
        db.climbs = [Climb(sessionId: "s", gymId: "camp5", gradeKind: .tag, grade: 1, tagId: "yellow", tickType: .flash, attempts: 1),
                     Climb(sessionId: "s", gymId: "camp5", gradeKind: .tag, grade: 2, tagId: "pink", tickType: .flash, attempts: 1)]
        db.normalise()
        #expect(db.gyms[0].tags == Vocab.camp5Tags)
        #expect(db.climbs.first { $0.tagId == "pink" }?.grade == 1)
        #expect(db.climbs.first { $0.tagId == "yellow" }?.grade == 3)
    }
}

@Suite struct LoadTests {
    let gyms = Seed.gyms
    let normals = NormalGrades(numbered: 10, tag: "orange", v: 5)

    func numbered(_ grade: Int, attempts: Int = 1, day: String = "2026-09-27", sent: Bool = true) -> Climb {
        Climb(sessionId: "s-\(day)", gymId: "batuu", gradeKind: .number, grade: grade,
              tickType: Vocab.tickType(attempts: attempts, sent: sent), attempts: attempts, createdAt: Seed.at(day, 19, 0))
    }

    @Test func weightDoublesEveryTwoGrades() {
        #expect(Load.climbLoad(numbered(10), gyms: gyms, normals: normals) == 1)
        #expect(Load.climbLoad(numbered(12), gyms: gyms, normals: normals) == 2)
        #expect(Load.climbLoad(numbered(8), gyms: gyms, normals: normals) == 0.5)
        #expect(Load.climbLoad(numbered(10, attempts: 3), gyms: gyms, normals: normals) == 3)
        // not sent still counts
        #expect(Load.climbLoad(numbered(10, attempts: 4, sent: false), gyms: gyms, normals: normals) == 4)
    }

    @Test func camp5TagStepIsTwoAndAHalfGrades() {
        let green = Climb(sessionId: "s", gymId: "camp5", gradeKind: .tag, grade: 5, tagId: "green", tickType: .flash, attempts: 1)
        let load = Load.climbLoad(green, gyms: gyms, normals: normals)
        #expect(abs(load - pow(2, 1.25)) < 0.0001)
    }

    @Test func boardsUseV() {
        let v7 = Climb(sessionId: "s", boardId: "kilter", angle: 40, gradeKind: .v, grade: 7, tickType: .flash, attempts: 1)
        #expect(Load.climbLoad(v7, gyms: gyms, normals: normals) == 2)
        #expect(Load.climbLoad(v7, gyms: gyms, normals: NormalGrades(numbered: 10)) == 0) // no normal for V: skipped
    }

    func db(_ climbs: [Climb]) -> Database {
        var d = Database()
        d.gyms = gyms
        d.climbs = climbs
        d.settings.normalNumbered = 10
        d.normalise()
        return d
    }

    @Test func buildsBaselineFirst() {
        let w = Load.window(db([numbered(10, day: "2026-09-20"), numbered(10, day: "2026-09-27")]), today: "2026-09-27")
        #expect(w.band == .building)
        #expect(w.weeksOfBaseline == 0)
    }

    @Test func comparesLastSevenDaysWithTheFourWeeksBefore() {
        // one normal-grade climb a day for five weeks, then double that in the last week
        var climbs: [Climb] = []
        for back in 7..<35 { climbs.append(numbered(10, day: Day.add("2026-09-27", -back))) }
        for back in 0..<7 { climbs.append(numbered(10, attempts: 2, day: Day.add("2026-09-27", -back))) }
        let w = Load.window(db(climbs), today: "2026-09-27")
        #expect(w.baseline == 7)
        #expect(w.acute == 14)
        #expect(w.ratio == 2)
        #expect(w.band == .spiking)
        #expect(Load.daily(db(climbs), today: "2026-09-27").count == 7)
        #expect(Load.weekly(db(climbs), today: "2026-09-27").last?.isCurrent == true)
    }

    @Test func suggestsTheMedian() {
        var d = db([numbered(9), numbered(10), numbered(11), numbered(12), numbered(12)])
        d.settings.normalNumbered = nil
        #expect(Load.suggestedNormals(d, today: "2026-09-27").numbered == 11)
        #expect(Load.normals(d, today: "2026-09-27").numbered == 11)
        d.settings.normalNumbered = 9
        #expect(Load.normals(d, today: "2026-09-27").numbered == 9)
    }
}

@Suite struct PillarTests {
    @Test func bodyStates() {
        var d = Database()
        #expect(Pillars.body(d, today: "2026-09-27").state == .clear)
        let inj = Injury(id: "i", bodyPart: "l-hand", name: "Left ring finger · A2", onsetDate: "2026-09-01", status: .active)
        d.injuries = [inj]
        d.painEntries = [PainEntry(id: "p1", injuryId: "i", date: "2026-09-20", level: 2), PainEntry(id: "p2", injuryId: "i", date: "2026-09-26", level: 4)]
        #expect(Pillars.body(d, today: "2026-09-27").state == .caution)
        d.loadRules = [LoadRule(injuryId: "i", styleOrType: "Crimpy", maxPerWeek: 1, condition: "", headline: "")]
        d.climbs = [Climb(sessionId: "s", gymId: "batuu", gradeKind: .number, grade: 9, styles: ["Crimpy"], tickType: .flash,
                          attempts: 1, createdAt: Seed.at("2026-09-24", 19, 0))]
        let b = Pillars.body(d, today: "2026-09-27")
        #expect(b.state == .warning)
        #expect(b.pain == 4)
    }

    @Test func demoHasAnInsightAndProgress() {
        let d = Seed.demo(now: demoNow)
        let p = Pillars.progress(d, today: "2026-09-27")
        #expect(p.top != nil)
        #expect(Insights.today(d, today: "2026-09-27") != nil)
    }
}
