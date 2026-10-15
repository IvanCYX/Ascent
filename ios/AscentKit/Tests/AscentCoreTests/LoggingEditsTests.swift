import Foundation
import Testing
@testable import AscentCore

/// Edit gym, gym styles and the board log (DESIGN §12).
@Suite struct LoggingEditsTests {
    static let ropes = Gym(id: "ropes", name: "Batuu rope area", shortName: "Batuu rope area", scaleType: .french,
                           minGrade: 3, maxGrade: 24, sortOrder: 8)

    static func climb(gym: String, _ kind: GradeKind, _ grade: Int, sent: Bool = true) -> Climb {
        Climb(sessionId: "s", gymId: gym, gradeKind: kind, grade: grade,
              tickType: Vocab.tickType(attempts: 1, sent: sent), attempts: 1)
    }

    @Test func gymStylesIncludeHooks() {
        #expect(Vocab.climbStyles == ["Crimpy", "Compression", "Slopey", "Slab", "Coordination", "Power", "Heel hook", "Toe hook"])
        // Load rules can still cap board-only and campus work, even though board climbs no longer carry styles.
        #expect(Vocab.ruleStyles == Vocab.climbStyles + ["Tension", "Campus"])
    }

    @Test func boardAnglesRunTenToSeventyInFives() {
        #expect(Vocab.boardAngles.first == 10)
        #expect(Vocab.boardAngles.last == 70)
        #expect(Vocab.boardAngles.count == 13)
        #expect(Vocab.defaultBoardAngle == 40)
    }

    /// The slider opens at the angle of the last climb on that board, from any session (DESIGN §13).
    @Test func boardAngleOpensAtTheLastOneLogged() {
        func climb(_ board: String, _ angle: Int?, _ day: String, _ hour: Int) -> Climb {
            Climb(sessionId: "s-\(day)", boardId: board, angle: angle, gradeKind: .v, grade: 5,
                  tickType: .flash, attempts: 1, createdAt: Seed.at(day, hour, 0))
        }
        let climbs = [
            climb("kilter", 40, "2026-10-01", 19),
            climb("kilter", 45, "2026-10-08", 20),
            climb("kilter", 30, "2026-10-08", 19),
            climb("moon", 25, "2026-09-02", 18),
            climb("tb2", nil, "2026-10-09", 18),
        ]
        #expect(Vocab.lastBoardAngle("kilter", climbs: climbs) == 45)
        // A one-angle board keeps its angle across sessions instead of falling back to 40.
        #expect(Vocab.lastBoardAngle("moon", climbs: climbs) == 25)
        // No angle on record, or no climbs yet: 40.
        #expect(Vocab.lastBoardAngle("tb2", climbs: climbs) == 40)
        #expect(Vocab.lastBoardAngle("spray", climbs: climbs) == 40)
        // Old logs outside the slider's range snap onto it.
        #expect(Vocab.lastBoardAngle("old", climbs: [climb("old", 8, "2026-01-01", 9)]) == 10)
        #expect(Vocab.lastBoardAngle("old", climbs: [climb("old", 42, "2026-01-01", 9)]) == 40)
    }

    @Test func boardOutcomeFollowsTheCount() {
        #expect(BoardOutcome.of(attempts: 1, sent: true) == .flash)
        #expect(BoardOutcome.of(attempts: 2, sent: true) == .secondGo)
        #expect(BoardOutcome.of(attempts: 3, sent: true) == .project)
        #expect(BoardOutcome.of(attempts: 12, sent: true) == .project)
        #expect(BoardOutcome.of(attempts: 1, sent: false) == .attempt)
        #expect(BoardOutcome.allCases.map(\.label) == ["Flash", "2nd go", "Project", "Attempt only"])
    }

    @Test func pickingAnOutcomeSetsTheCount() {
        #expect(BoardOutcome.flash.attempts(from: 7) == 1)
        #expect(BoardOutcome.secondGo.attempts(from: 7) == 2)
        #expect(BoardOutcome.project.attempts(from: 1) == 3)
        #expect(BoardOutcome.project.attempts(from: 7) == 7)
        #expect(BoardOutcome.attempt.attempts(from: 5) == 5)
        #expect(!BoardOutcome.attempt.sent)
        #expect(BoardOutcome.project.sent)
        // Saved exactly as the gym log would derive it.
        for o in BoardOutcome.allCases {
            let n = o.attempts(from: 4)
            #expect(BoardOutcome.of(attempts: n, sent: o.sent) == o)
        }
    }

    @Test func boardOutcomeHints() {
        #expect(BoardOutcome.flash.hint(attempts: 1) == "First go")
        #expect(BoardOutcome.secondGo.hint(attempts: 2) == "Sent on your second go")
        #expect(BoardOutcome.project.hint(attempts: 7) == "7 tries, tap to type")
        #expect(BoardOutcome.attempt.hint(attempts: 1) == "1 attempt, not sent")
        #expect(BoardOutcome.attempt.hint(attempts: 3) == "3 attempts, not sent")
    }

    @Test func loggedRangeCoversEveryClimbOnTheGymsScale() {
        let f = { Vocab.frenchGrades.firstIndex(of: $0)! }
        let climbs = [
            Self.climb(gym: "ropes", .french, f("5c")),
            Self.climb(gym: "ropes", .french, f("7a"), sent: false),
            Self.climb(gym: "ropes", .french, f("6b")),
            Self.climb(gym: "batuu", .number, 14),
        ]
        #expect(GymEdit.loggedRange([Self.ropes], climbs: climbs) == f("5c")...f("7a"))
        #expect(GymEdit.loggedRange([Self.ropes], climbs: []) == nil)
        #expect(GymEdit.climbCount([Self.ropes], climbs: climbs) == 3)
    }

    @Test func renamingKeepsAShortNameThatDiffered() {
        let camp5 = Seed.gyms.first { $0.isRanked }!
        #expect(camp5.shortName != camp5.name)
        let renamed = camp5.renamed("Camp5 Eco City KL")
        #expect(renamed.name == "Camp5 Eco City KL")
        #expect(renamed.shortName == camp5.shortName)

        let fixed = Self.ropes.renamed("  Batuu ropes  ")
        #expect(fixed.name == "Batuu ropes")
        #expect(fixed.shortName == "Batuu ropes")
        #expect(fixed.id == Self.ropes.id)
    }

    @MainActor @Test func editingAGymKeepsItsClimbs() {
        let store = AscentStore(database: Seed.demo(now: Seed.at("2026-10-14", 20, 0)))
        let gym = store.db.gyms.first { $0.id == "batuu" }!
        let before = store.db.climbs.filter { $0.gymId == gym.id }.count
        var edited = gym.renamed("Batuu Kuala Lumpur")
        edited.maxGrade = 14
        store.saveGym(edited)
        #expect(store.db.gym("batuu")?.name == "Batuu Kuala Lumpur")
        #expect(store.db.gym("batuu")?.maxGrade == 14)
        #expect(store.db.climbs.filter { $0.gymId == gym.id }.count == before)
    }
}
