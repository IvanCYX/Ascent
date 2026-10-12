import Foundation

/// Exact vocabularies from the handoff. Strings are final — do not paraphrase.
public enum Vocab {
    public static let climbStyles: [String] = [
        "Crimpy", "Compression", "Slopey", "Slab", "Coordination", "Power",
    ]

    /// Tension is board-only.
    public static let boardStyles: [String] = climbStyles + ["Tension"]

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

    /// Grade bands used by the style × grade heatmap.
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
