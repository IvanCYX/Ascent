import Foundation

/// Exact vocabularies from the handoff. Strings are final — do not paraphrase.
public enum Vocab {
    public static let climbStyles: [String] = [
        "Crimpy", "Compression", "Slopey", "Slab", "Coordination", "Power", "Heel hook", "Toe hook",
    ]

    /// Styles a load rule can cap. Board climbs carry no styles (DESIGN §12.3), but Tension and Campus rules stay.
    public static let ruleStyles: [String] = climbStyles + ["Tension", "Campus"]

    /// The board angle slider: 10° to 70° in 5° steps, opening at 40° (DESIGN §12.3).
    public static let boardAngles: [Int] = Array(stride(from: 10, through: 70, by: 5))
    public static let defaultBoardAngle = 40

    /// Where the slider opens: the angle of the last climb on that board, from any session, snapped onto the
    /// slider's steps; 40° for a board with none (DESIGN §13).
    public static func lastBoardAngle(_ boardId: String, climbs: [Climb]) -> Int {
        guard let last = climbs.filter({ $0.boardId == boardId && $0.angle != nil }).max(by: { $0.createdAt < $1.createdAt }),
              let angle = last.angle else { return defaultBoardAngle }
        let snapped = Int((Double(angle) / 5).rounded()) * 5
        return min(boardAngles.last!, max(boardAngles.first!, snapped))
    }

    public static let sessionIntents: [String] = [
        "Max strength", "Power endurance", "Coordination", "Comp sim", "Slab / technique", "Chill maintenance",
    ]

    /// High-cost intents are struck through during a taper.
    public static let highCostIntents: Set<String> = ["Max strength", "Power endurance"]

    public static let tickTypes: [(id: TickType, label: String)] = [
        (.flash, "Flash"), (.secondGo, "2nd go"), (.project, "Project"), (.attempt, "Not sent"),
    ]

    public static func tickLabel(_ t: TickType) -> String {
        tickTypes.first { $0.id == t }?.label ?? t.rawValue
    }

    /// r3: the attempt counter is the source of truth; the tick type follows from it.
    public static func tickType(attempts: Int, sent: Bool) -> TickType {
        if !sent { return .attempt }
        switch attempts {
        case ...1: return .flash
        case 2: return .secondGo
        default: return .project
        }
    }

    /// 1 → "Flash", 2 → "2nd go", 3+ → "N tries"; not sent → "N attempts".
    public static func attemptsLabel(_ attempts: Int, sent: Bool) -> String {
        let n = max(1, attempts)
        if !sent { return n == 1 ? "1 attempt" : "\(n) attempts" }
        switch n {
        case 1: return "Flash"
        case 2: return "2nd go"
        default: return "\(n) tries"
        }
    }

    public static func attemptsLabel(_ c: Climb) -> String { attemptsLabel(c.attempts, sent: c.tickType != .attempt) }

    public struct HoldColour: Sendable, Hashable {
        public let id: String
        public let label: String
        public let code: String
        public let hex: String
    }

    /// Hold / tag colours — the only place saturated colour is allowed.
    public static let holdColours: [HoldColour] = [
        .init(id: "yellow", label: "Yellow", code: "YEL", hex: "#f2c744"),
        .init(id: "pink", label: "Pink", code: "PNK", hex: "#ec6ba8"),
        .init(id: "blue", label: "Blue", code: "BLU", hex: "#3f7fd6"),
        .init(id: "orange", label: "Orange", code: "ORG", hex: "#f08a3c"),
        .init(id: "green", label: "Green", code: "GRN", hex: "#4caf6a"),
        .init(id: "purple", label: "Purple", code: "PUR", hex: "#8a63d2"),
        .init(id: "red", label: "Red", code: "RED", hex: "#d8443c"),
        .init(id: "black", label: "Black", code: "BLK", hex: "#1b1b1b"),
        .init(id: "white", label: "White", code: "WHT", hex: "#ffffff"),
    ]

    public static func colourHex(_ id: String?) -> String? { holdColours.first { $0.id == id }?.hex }
    public static func colourCode(_ id: String?) -> String { holdColours.first { $0.id == id }?.code ?? "—" }
    public static func colourLabel(_ id: String?) -> String { holdColours.first { $0.id == id }?.label ?? "" }

    /// Camp5 ranked-colour tags, easiest first, ordinal 1–8. Never mapped onto 1–15.
    public static let camp5Tags: [String] = ["pink", "blue", "yellow", "orange", "green", "purple", "red", "black"]

    /// Camp5's own V-scale bands; they overlap, so each tag covers about three V grades.
    public static let camp5Ranges: [String: String] = [
        "pink": "VB–V1", "blue": "V0–V2", "yellow": "V1–V3", "orange": "V2–V4",
        "green": "V3–V5", "purple": "V4–V6", "red": "V5–V7", "black": "V6–V8+",
    ]

    public enum ChipGroup: String, CaseIterable, Sendable { case body = "BODY", head = "HEAD", execution = "EXECUTION" }

    public static let reviewChips: [ChipGroup: [String]] = [
        .body: ["Felt strong", "Felt weak", "Fatigued early", "Good tension", "Poor recovery"],
        .head: ["Locked in", "Distracted", "Hesitant", "Confident first go", "Scared of the fall"],
        .execution: ["Coordination dialled", "Missed the timing", "Sloppy feet", "Read beta wrong", "Good beta reading"],
    ]

    public static var allReviewChips: [String] {
        ChipGroup.allCases.flatMap { reviewChips[$0] ?? [] }
    }

    public struct GradeBand: Sendable, Hashable {
        public let label: String
        public let min: Int
        public let max: Int
    }

    /* ── Grade scales (DESIGN §11) ──────────────────────────────────── */

    /// French route grades, easiest first. A French climb stores its index here; the label is all that shows.
    public static let frenchGrades: [String] = [
        "4a", "4b", "4c", "5a", "5a+", "5b", "5b+", "5c", "5c+", "6a", "6a+", "6b", "6b+", "6c", "6c+",
        "7a", "7a+", "7b", "7b+", "7c", "7c+", "8a", "8a+", "8b", "8b+", "8c", "8c+", "9a",
    ]
    /// 5a to 8b+, a new French gym's range.
    public static let frenchDefaultRange = 3...24
    /// VB is stored as −1.
    public static let vGrades = -1...17

    /// How a grade reads on its scale: `11`, `V5`, `VB`, `6b+`, or the tag's colour.
    public static func gradeLabel(_ kind: GradeKind, _ grade: Int, tagId: String? = nil) -> String {
        switch kind {
        case .number: "\(grade)"
        case .v, .gymV: grade < 0 ? "VB" : "V\(grade)"
        case .french: frenchGrades.indices.contains(grade) ? frenchGrades[grade] : "–"
        case .tag: colourLabel(tagId ?? (camp5Tags.indices.contains(grade - 1) ? camp5Tags[grade - 1] : nil))
        }
    }

    /// The scale's name on the Progress switch and in Settings.
    public static func scaleName(_ kind: GradeKind) -> String {
        switch kind {
        case .number: "1–15"
        case .tag: "Camp5"
        case .gymV: "V"
        case .french: "French"
        case .v: "Boards"
        }
    }

    /// The easiest grade a scale can hold.
    public static func lowestGrade(_ kind: GradeKind) -> Int {
        switch kind {
        case .number, .tag: 1
        case .v, .gymV: vGrades.lowerBound
        case .french: 0
        }
    }

    /// Heatmap and readiness bands per scale.
    public static func gradeBands(_ kind: GradeKind) -> [GradeBand] {
        switch kind {
        case .gymV, .v:
            [.init(label: "V0–1", min: 0, max: 1), .init(label: "V2–3", min: 2, max: 3), .init(label: "V4–5", min: 4, max: 5),
             .init(label: "V6–7", min: 6, max: 7), .init(label: "V8+", min: 8, max: vGrades.upperBound)]
        case .french:
            // each letter with its +; everything from 7a+ up is one band
            [.init(label: "5", min: 3, max: 8), .init(label: "6a", min: 9, max: 10), .init(label: "6b", min: 11, max: 12),
             .init(label: "6c", min: 13, max: 14), .init(label: "7a+", min: 15, max: frenchGrades.count - 1)]
        case .number, .tag:
            gradeBands
        }
    }

    /// Grade bands used by the style × grade heatmap on the numbered spine.
    public static let gradeBands: [GradeBand] = [
        .init(label: "6–7", min: 6, max: 7),
        .init(label: "8–9", min: 8, max: 9),
        .init(label: "10–11", min: 10, max: 11),
        .init(label: "12–13", min: 12, max: 13),
        .init(label: "14–15", min: 14, max: 15),
    ]

    /// Readiness rows on the dashboard blend styles with a couple of training qualities.
    public static let readinessRows: [String] = [
        "Coordination", "Power", "Slab", "Power endurance", "Compression", "Crimps",
    ]

    public static let readinessWarnBelow = 55

    public struct BodyPart: Sendable, Hashable {
        public let id: String
        public let label: String
    }

    /// Body parts offered by the injury body map.
    public static let bodyParts: [BodyPart] = [
        .init(id: "head", label: "Head / neck"),
        .init(id: "torso", label: "Torso / core"),
        .init(id: "l-shoulder", label: "L shoulder"),
        .init(id: "r-shoulder", label: "R shoulder"),
        .init(id: "l-elbow", label: "L elbow"),
        .init(id: "r-elbow", label: "R elbow"),
        .init(id: "l-hand", label: "L hand / fingers"),
        .init(id: "r-hand", label: "R hand / fingers"),
        .init(id: "l-leg", label: "L leg / knee"),
        .init(id: "r-leg", label: "R leg / knee"),
    ]

    public static func bodyPartLabel(_ id: String) -> String {
        bodyParts.first { $0.id == id }?.label ?? id
    }

    /* ── Competitions (iOS r2) ─────────────────────────────────────────── */

    public static let compCategories = ["Novice", "Intermediate", "Open", "Youth", "Masters", "Para"]
    public static let compFormats = ["Onsight rounds", "Flash", "Redpoint / jam"]
    public static let compRounds = ["Qualifiers", "Semi-final", "Final"]
}

/// "Left ring finger · A2 pulley strain" → "L ring finger"
public func shortInjury(_ name: String) -> String {
    var head = name.components(separatedBy: "·").first?.trimmingCharacters(in: .whitespaces) ?? name
    if head.hasPrefix("Left ") { head = "L " + head.dropFirst(5) }
    else if head.hasPrefix("Right ") { head = "R " + head.dropFirst(6) }
    return head
}

/// The four board outcomes (DESIGN §12.3). They and the attempt counter are one value: a sent climb's outcome
/// follows its count, as `Vocab.tickType` derives it.
public enum BoardOutcome: String, CaseIterable, Sendable {
    case flash, secondGo, project, attempt

    public var label: String {
        switch self {
        case .flash: "Flash"
        case .secondGo: "2nd go"
        case .project: "Project"
        case .attempt: "Attempt only"
        }
    }

    public var sent: Bool { self != .attempt }

    public static func of(attempts: Int, sent: Bool) -> BoardOutcome {
        switch Vocab.tickType(attempts: attempts, sent: sent) {
        case .flash: .flash
        case .secondGo: .secondGo
        case .project: .project
        case .attempt: .attempt
        }
    }

    /// The count after picking this outcome. Project keeps a count of 3 or more; Attempt only keeps any count.
    public func attempts(from current: Int) -> Int {
        switch self {
        case .flash: 1
        case .secondGo: 2
        case .project: max(3, current)
        case .attempt: max(1, current)
        }
    }

    public func hint(attempts: Int) -> String {
        switch self {
        case .flash: "First go"
        case .secondGo: "Sent on your second go"
        case .project: "\(attempts) tries, tap to type"
        case .attempt: "\(attempts == 1 ? "1 attempt" : "\(attempts) attempts"), not sent"
        }
    }
}

/// Edit gym (DESIGN §12.1): what the climbs already logged at a gym (or the Bump trio) pin down.
public enum GymEdit {
    static func climbs(_ gyms: [Gym], _ climbs: [Climb]) -> [Climb] {
        let ids = Set(gyms.map(\.id))
        return climbs.filter { ids.contains($0.gymId ?? "") }
    }

    public static func climbCount(_ gyms: [Gym], climbs: [Climb]) -> Int { Self.climbs(gyms, climbs).count }

    /// The easiest to the hardest grade logged on the gyms' own scale; the range can't be edited to cut these out.
    public static func loggedRange(_ gyms: [Gym], climbs: [Climb]) -> ClosedRange<Int>? {
        guard let kind = gyms.first?.gradeKind else { return nil }
        let grades = Self.climbs(gyms, climbs).filter { $0.gradeKind == kind }.map(\.grade)
        guard let lo = grades.min(), let hi = grades.max() else { return nil }
        return lo...hi
    }
}

extension Gym {
    /// A new name; a short name that matched the old name follows it, a separate one ("Camp5") stays.
    public func renamed(_ newName: String) -> Gym {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        var g = self
        if shortName == name { g.shortName = trimmed }
        g.name = trimmed
        return g
    }
}
