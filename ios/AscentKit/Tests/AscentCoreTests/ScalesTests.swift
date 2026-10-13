import Foundation
import Testing
@testable import AscentCore

/// V gyms and French routes (DESIGN §11).
@Suite struct ScaleTests {
    static let tensionHouse = Gym(id: "th", name: "TensionHouse", shortName: "TensionHouse", scaleType: .v,
                                  minGrade: -1, maxGrade: 10, sortOrder: 7)
    static let ropes = Gym(id: "ropes", name: "Batuu rope area", shortName: "Batuu ropes", scaleType: .french,
                           minGrade: 3, maxGrade: 24, sortOrder: 8)
    static let gyms = Seed.gyms + [tensionHouse, ropes]

    static func french(_ label: String) -> Int { Vocab.frenchGrades.firstIndex(of: label)! }

    static func climb(_ kind: GradeKind, _ grade: Int, attempts: Int = 1, sent: Bool = true, styles: [String] = [],
                      day: String = "2026-09-24") -> Climb {
        let gymId = kind == .gymV ? "th" : kind == .french ? "ropes" : "batuu"
        return Climb(sessionId: "s-\(gymId)-\(day)", gymId: gymId, gradeKind: kind, grade: grade, styles: styles,
                     tickType: Vocab.tickType(attempts: attempts, sent: sent), attempts: attempts,
                     createdAt: Seed.at(day, 19, 0))
    }

    @Test func labelsFollowTheScale() {
        #expect(Vocab.gradeLabel(.number, 11) == "11")
        #expect(Vocab.gradeLabel(.gymV, -1) == "VB")
        #expect(Vocab.gradeLabel(.gymV, 5) == "V5")
        #expect(Vocab.gradeLabel(.v, 6) == "V6")
        #expect(Vocab.gradeLabel(.french, Self.french("6b+")) == "6b+")
        #expect(Vocab.gradeLabel(.tag, 4, tagId: "orange") == "Orange")
        #expect(Vocab.frenchGrades.first == "4a")
        #expect(Vocab.frenchGrades.last == "9a")
        #expect(Vocab.frenchGrades.count == 28)
    }

    @Test func gymsKnowTheirScaleAndRange() {
        #expect(Self.tensionHouse.gradeKind == .gymV)
        #expect(Self.tensionHouse.grades == Array(-1...10))
        #expect(Self.ropes.gradeKind == .french)
        #expect(Self.ropes.grades.first.map { Vocab.gradeLabel(.french, $0) } == "5a")
        #expect(Self.ropes.grades.last.map { Vocab.gradeLabel(.french, $0) } == "8b+")
        let batuu = Seed.gyms[0]
        #expect(batuu.gradeKind == .number)
        #expect(batuu.grades == Array(1...15))
        #expect(Seed.gyms[1].gradeKind == .tag)
        #expect(Self.tensionHouse.gradeSpan == "VB to V10")
        #expect(Self.ropes.gradeSpan == "5a to 8b+")
        #expect(batuu.gradeSpan == "1 to 15")
        #expect(Seed.gyms[1].gradeSpan == "pink to black")
    }

    @Test func vGymsAndFrenchRoutesWeighAgainstTheirOwnNormal() {
        let normals = NormalGrades(numbered: 10, tag: "orange", v: 5, gymV: 4, french: Self.french("6b"))
        // two V grades above normal doubles the weight
        #expect(Load.climbLoad(Self.climb(.gymV, 6), gyms: Self.gyms, normals: normals) == 2)
        // 7a is four French steps above 6b, worth two grade steps
        #expect(Load.climbLoad(Self.climb(.french, Self.french("7a")), gyms: Self.gyms, normals: normals) == 2)
        // a board V6 still weighs against the board normal
        let board = Climb(sessionId: "s", boardId: "kilter", angle: 40, gradeKind: .v, grade: 6, tickType: .flash, attempts: 1)
        #expect(abs(Load.climbLoad(board, gyms: Self.gyms, normals: normals) - pow(2, 0.5)) < 0.0001)
        // no normal on a scale: skipped
        #expect(Load.climbLoad(Self.climb(.gymV, 6), gyms: Self.gyms, normals: NormalGrades(numbered: 10)) == 0)
    }

    func db(_ climbs: [Climb]) -> Database {
        var d = Database()
        d.gyms = Self.gyms
        d.climbs = climbs
        d.normalise()
        return d
    }

    @Test func suggestsANormalPerScale() {
        let d = db([Self.climb(.gymV, 3), Self.climb(.gymV, 4), Self.climb(.gymV, 5),
                    Self.climb(.french, Self.french("6a")), Self.climb(.french, Self.french("6b"))])
        let s = Load.suggestedNormals(d, today: "2026-09-27")
        #expect(s.gymV == 4)
        #expect(s.french == Self.french("6a+"))
        #expect(s.v == nil) // boards are their own scale
    }

    @Test func thresholdsComeFromTheNormalOffTheSpine() {
        let normals = NormalGrades(numbered: 10, gymV: 3, french: Self.french("6b"))
        #expect(Metrics.thresholds(.number, normals: normals) == Metrics.Thresholds(flash: 8, hard: 10))
        #expect(Metrics.thresholds(.gymV, normals: normals) == Metrics.Thresholds(flash: 3, hard: 5))
        #expect(Metrics.thresholds(.french, normals: normals) == Metrics.Thresholds(flash: Self.french("6b"), hard: Self.french("7a")))
        #expect(Metrics.thresholds(.gymV, normals: NormalGrades()) == nil)
    }

    @Test func keyNumbersRunOnTheChosenScale() {
        let climbs = [Self.climb(.gymV, 3), Self.climb(.gymV, 4, attempts: 2), Self.climb(.gymV, 5, attempts: 3),
                      Self.climb(.gymV, 6), Self.climb(.gymV, 7, attempts: 4, sent: false), Self.climb(.number, 12)]
        let top = Metrics.maxGradeSent(climbs, gyms: Self.gyms, kind: .gymV)
        #expect(top.grade == 6)
        #expect(top.gymName == "TensionHouse")
        #expect(Metrics.flashRate(climbs, threshold: 3, kind: .gymV) == 50)
        #expect(Metrics.volumeAtHard(climbs, threshold: 5, kind: .gymV) == 2)
        #expect(Metrics.attemptsPerSend(climbs, threshold: 5, kind: .gymV) == 2)
        // the numbered spine ignores V climbs
        #expect(Metrics.maxGradeSent(climbs, gyms: Self.gyms).grade == 12)
        #expect(Metrics.volumeAtHard(climbs) == 1)
    }

    @Test func pyramidSpansSevenGradesDownFromTheTopSend() {
        let climbs = [Self.climb(.gymV, 6), Self.climb(.gymV, 3), Self.climb(.gymV, 3, attempts: 2)]
        let rows = Metrics.sendPyramid(climbs, kind: .gymV)
        #expect(rows.map(\.label) == ["V6", "V5", "V4", "V3", "V2", "V1", "V0"])
        #expect(rows.first { $0.label == "V3" }?.count == 2)
        #expect(Metrics.pyramidRead(rows, kind: .gymV).hasPrefix("Most sends at V3."))
        // French stops at the bottom of its list
        let low = Metrics.sendPyramid([Self.climb(.french, Self.french("4c"))], kind: .french)
        #expect(low.map(\.label) == ["4c", "4b", "4a"])
        // the numbered pyramid is unchanged: 13 down to 7
        #expect(Metrics.sendPyramid([Self.climb(.number, 9)]).map(\.label) == ["13", "12", "11", "10", "9", "8", "7"])
        #expect(Metrics.sendPyramid([], kind: .gymV).isEmpty)
    }

    @Test func heatmapBandsFollowTheScale() {
        #expect(Vocab.gradeBands(.number).map(\.label) == ["6–7", "8–9", "10–11", "12–13", "14–15"])
        #expect(Vocab.gradeBands(.gymV).map(\.label) == ["V0–1", "V2–3", "V4–5", "V6–7", "V8+"])
        #expect(Vocab.gradeBands(.french).map(\.label) == ["5", "6a", "6b", "6c", "7a+"])
        let climbs = [Self.climb(.gymV, 4, styles: ["Crimpy"]), Self.climb(.gymV, 5, sent: false, styles: ["Crimpy"])]
        let crimpy = Metrics.styleGradeMatrix(climbs, kind: .gymV).first { $0.style == "Crimpy" }!
        #expect(crimpy.cells[2].pct == 50)
        #expect(crimpy.cells[0].pct == nil)
    }

    @Test func progressFollowsTheMainScaleUntilYouPickOne() {
        var d = db([Self.climb(.gymV, 4), Self.climb(.gymV, 5), Self.climb(.gymV, 6), Self.climb(.number, 11)])
        d.settings.normalGymV = 4
        #expect(Pillars.scales(d, today: "2026-09-27") == [.number, .gymV])
        #expect(Pillars.progressScale(d, today: "2026-09-27") == .gymV)
        let p = Pillars.progress(d, today: "2026-09-27")
        #expect(p.scale == .gymV)
        #expect(p.topLabel == "V6")
        #expect(p.hardSends == 1)

        d.settings.progressScale = .number
        #expect(Pillars.progressScale(d, today: "2026-09-27") == .number)
        #expect(Pillars.progress(d, today: "2026-09-27").topLabel == "11")

        // a remembered scale with nothing in range falls back to the main one
        d.settings.progressScale = .french
        #expect(Pillars.progressScale(d, today: "2026-09-27") == .gymV)
    }

    @Test func camp5InProgressLeavesThePillarOnTheMainScale() {
        var d = db([Self.climb(.number, 11),
                    Climb(sessionId: "s", gymId: "camp5", gradeKind: .tag, grade: 5, tagId: "green", tickType: .flash,
                          attempts: 1, createdAt: Seed.at("2026-09-24", 19, 0))])
        d.settings.progressScale = .tag
        #expect(Pillars.progressScale(d, today: "2026-09-27") == .tag)
        #expect(Pillars.progress(d, today: "2026-09-27").scale == .number)
        #expect(Pillars.gradedScale(d, today: "2026-09-27") == .number)
    }

    @Test func aCamp5OnlyLogOpensOnCamp5() {
        let d = db([Climb(sessionId: "s", gymId: "camp5", gradeKind: .tag, grade: 5, tagId: "green", tickType: .flash,
                          attempts: 1, createdAt: Seed.at("2026-09-24", 19, 0))])
        #expect(Pillars.scales(d, today: "2026-09-27") == [.tag])
        #expect(Pillars.progressScale(d, today: "2026-09-27") == .tag)
        #expect(Vocab.scaleName(.tag) == "Camp5")
        #expect(Vocab.scaleName(.number) == "1–15")
        #expect(Vocab.scaleName(.french) == "French")
    }

    @Test func sessionHighsUseTheScaleLabels() {
        #expect(Metrics.topGrades([Self.climb(.gymV, 5), Self.climb(.gymV, 6)]) == .labels(["V6", "V5"]))
        #expect(Metrics.topGrades([Self.climb(.french, Self.french("6c"))]) == .labels(["6c"]))
    }

    @Test func newScalesSurviveABackup() throws {
        var d = Seed.demo(now: demoNow)
        d.settings.normalGymV = 4
        d.settings.normalFrench = Self.french("6b")
        d.settings.progressScale = .french
        let back = try Backup.decode(Backup.encode(d))
        #expect(back == d)
        #expect(back.gyms.contains { $0.scaleType == .v })
        #expect(back.climbs.contains { $0.gradeKind == .french })
        #expect(back.settings.progressScale == .french)
    }

    @Test func demoHasAVGymAndTheRopeArea() {
        let d = Seed.demo(now: demoNow)
        #expect(d.gyms.contains { $0.name == "TensionHouse" && $0.gradeKind == .gymV })
        #expect(d.gyms.contains { $0.name == "Batuu rope area" && $0.gradeKind == .french })
        #expect(d.climbs.contains { $0.gradeKind == .gymV })
        #expect(d.climbs.contains { $0.gradeKind == .french })
    }
}

@Suite @MainActor struct ScaleStoreTests {
    @Test func keepsTheNewNormalsOnTheirScale() {
        let store = AscentStore(database: Seed.demo(now: demoNow))
        store.setNormalGymV(-5)
        #expect(store.db.settings.normalGymV == -1)
        store.setNormalFrench(99)
        #expect(store.db.settings.normalFrench == Vocab.frenchGrades.count - 1)
        store.setProgressScale(.french)
        #expect(store.db.settings.progressScale == .french)
    }
}

@Suite struct ScaleOutsideTheAppTests {
    @Test func widgetsFollowTheProgressScale() {
        var d = Seed.demo(now: demoNow)
        d.settings.progressScale = .gymV
        let s = WidgetSummary.compute(d, now: demoNow)
        #expect(s.scale == .gymV)
        #expect(s.topGrade == "V6")
        #expect(s.topGym == "TensionHouse")
        #expect(s.pyramid.first?.label == "V6")
        let numbered = WidgetSummary.compute(Seed.demo(now: demoNow), now: demoNow)
        #expect(numbered.scale == .number)
        #expect(numbered.pyramid.first?.label == "13")
    }

    @Test func liveHighUsesTheGymsScale() {
        var d = Seed.demo(now: demoNow)
        let id = d.activeSession!.id
        d.sessions[d.sessions.firstIndex { $0.id == id }!].gymId = "tensionhouse"
        d.climbs.removeAll { $0.sessionId == id }
        d.climbs.append(Climb(sessionId: id, gymId: "tensionhouse", gradeKind: .gymV, grade: 5, tickType: .flash, attempts: 1))
        d.climbs.append(Climb(sessionId: id, gymId: "tensionhouse", gradeKind: .gymV, grade: -1, tickType: .flash, attempts: 1))
        #expect(LiveSessionState.from(d, privacyLock: false)?.high == "V5")
    }
}
