import Foundation

/* ── Entities — field-for-field with the web schema so backups round-trip ── */

public enum ScaleType: String, Codable, Sendable { case numeric, rankedColour = "ranked-colour" }
public enum GradeKind: String, Codable, Sendable { case number, tag, v }
public enum TickType: String, Codable, Sendable, CaseIterable { case flash, secondGo = "second-go", project, attempt }
public enum SessionStatus: String, Codable, Sendable { case planned, active, done }
public enum InjuryStatus: String, Codable, Sendable { case active, watching, resolved }
public enum CompPriority: String, Codable, Sendable, CaseIterable { case a = "A", b = "B", c = "C" }

public struct Gym: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var shortName: String
    public var scaleType: ScaleType
    /// numeric gyms only — top of the gym's own label range on the 1–15 spine
    public var maxGrade: Int?
    /// ranked-colour gyms only — ordered easiest → hardest, values are hold colour ids
    public var tags: [String]?
    /// soft/hard offset, -1..+1, applied when comparing gyms in aggregate
    public var offset: Double
    public var note: String?
    public var sortOrder: Int

    public init(id: String, name: String, shortName: String, scaleType: ScaleType, maxGrade: Int? = nil,
                tags: [String]? = nil, offset: Double = 0, note: String? = nil, sortOrder: Int) {
        self.id = id; self.name = name; self.shortName = shortName; self.scaleType = scaleType
        self.maxGrade = maxGrade; self.tags = tags; self.offset = offset; self.note = note; self.sortOrder = sortOrder
    }

    public var isRanked: Bool { scaleType == .rankedColour }
}

public struct Board: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var code: String
    public var angles: [Int]
    public var sortOrder: Int
}

public struct Climb: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var sessionId: String
    public var gymId: String?
    public var boardId: String?
    public var angle: Int?
    public var gradeKind: GradeKind
    /// numeric gyms: 1–15 · ranked-colour: tag ordinal 1–8 · boards: V-grade 1–10
    public var grade: Int
    /// ranked-colour gyms only — the tag itself
    public var tagId: String?
    public var holdColour: String?
    public var styles: [String]
    public var location: String?
    public var name: String?
    public var tickType: TickType
    public var attempts: Int
    public var createdAt: Date {
        didSet { day = Day.iso(createdAt) }
    }
    /// Local calendar day of `createdAt`; derived, never stored.
    public private(set) var day: String

    public init(id: String = uid(), sessionId: String, gymId: String? = nil, boardId: String? = nil, angle: Int? = nil,
                gradeKind: GradeKind, grade: Int, tagId: String? = nil, holdColour: String? = nil,
                styles: [String] = [], location: String? = nil, name: String? = nil,
                tickType: TickType, attempts: Int, createdAt: Date = .now) {
        self.id = id; self.sessionId = sessionId; self.gymId = gymId; self.boardId = boardId; self.angle = angle
        self.gradeKind = gradeKind; self.grade = grade; self.tagId = tagId; self.holdColour = holdColour
        self.styles = styles; self.location = location; self.name = name; self.tickType = tickType
        self.attempts = attempts; self.createdAt = createdAt; self.day = Day.iso(createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case id, sessionId, gymId, boardId, angle, gradeKind, grade, tagId, holdColour, styles, location, name,
             tickType, attempts, createdAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        gymId = try c.decodeIfPresent(String.self, forKey: .gymId)
        boardId = try c.decodeIfPresent(String.self, forKey: .boardId)
        angle = try c.decodeIfPresent(Int.self, forKey: .angle)
        gradeKind = try c.decode(GradeKind.self, forKey: .gradeKind)
        grade = try c.decode(Int.self, forKey: .grade)
        tagId = try c.decodeIfPresent(String.self, forKey: .tagId)
        holdColour = try c.decodeIfPresent(String.self, forKey: .holdColour)
        styles = try c.decodeIfPresent([String].self, forKey: .styles) ?? []
        location = try c.decodeIfPresent(String.self, forKey: .location)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        tickType = try c.decode(TickType.self, forKey: .tickType)
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 1
        let raw = try c.decode(String.self, forKey: .createdAt)
        createdAt = ISO8601.parse(raw) ?? .distantPast
        day = Day.iso(createdAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sessionId, forKey: .sessionId)
        try c.encodeIfPresent(gymId, forKey: .gymId)
        try c.encodeIfPresent(boardId, forKey: .boardId)
        try c.encodeIfPresent(angle, forKey: .angle)
        try c.encode(gradeKind, forKey: .gradeKind)
        try c.encode(grade, forKey: .grade)
        try c.encodeIfPresent(tagId, forKey: .tagId)
        try c.encodeIfPresent(holdColour, forKey: .holdColour)
        try c.encode(styles, forKey: .styles)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(tickType, forKey: .tickType)
        try c.encode(attempts, forKey: .attempts)
        try c.encode(ISO8601.string(createdAt), forKey: .createdAt)
    }
}

public struct PlanBlock: Codable, Sendable, Hashable {
    public var durationMin: Int
    public var description: String
    public var target: String?
    public var emphasis: Bool?
    public var rehab: Bool?
    /// iOS r2 — removed from the plan while tapering.
    public var dropInTaper: Bool?

    public init(_ durationMin: Int, _ description: String, target: String? = nil, emphasis: Bool = false,
                rehab: Bool = false, dropInTaper: Bool = false) {
        self.durationMin = durationMin; self.description = description; self.target = target
        self.emphasis = emphasis ? true : nil; self.rehab = rehab ? true : nil; self.dropInTaper = dropInTaper ? true : nil
    }

    public var isEmphasis: Bool { emphasis ?? false }
    public var isRehab: Bool { rehab ?? false }
    public var isDroppedInTaper: Bool { dropInTaper ?? false }
}

public struct Session: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var date: String
    public var gymId: String?
    public var intent: String?
    public var focusStyles: [String]?
    public var plannedBlocks: [PlanBlock]?
    public var durationMin: Int?
    public var notes: String?
    public var status: SessionStatus
    public var startedAt: Date?
    public var endedAt: Date?

    public init(id: String = uid(), date: String, gymId: String? = nil, intent: String? = nil, focusStyles: [String]? = nil,
                plannedBlocks: [PlanBlock]? = nil, durationMin: Int? = nil, notes: String? = nil,
                status: SessionStatus, startedAt: Date? = nil, endedAt: Date? = nil) {
        self.id = id; self.date = date; self.gymId = gymId; self.intent = intent; self.focusStyles = focusStyles
        self.plannedBlocks = plannedBlocks; self.durationMin = durationMin; self.notes = notes; self.status = status
        self.startedAt = startedAt; self.endedAt = endedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, date, gymId, intent, focusStyles, plannedBlocks, durationMin, notes, status, startedAt, endedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        date = try c.decode(String.self, forKey: .date)
        gymId = try c.decodeIfPresent(String.self, forKey: .gymId)
        intent = try c.decodeIfPresent(String.self, forKey: .intent)
        focusStyles = try c.decodeIfPresent([String].self, forKey: .focusStyles)
        plannedBlocks = try c.decodeIfPresent([PlanBlock].self, forKey: .plannedBlocks)
        durationMin = try c.decodeIfPresent(Int.self, forKey: .durationMin)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        status = try c.decode(SessionStatus.self, forKey: .status)
        startedAt = try c.decodeIfPresent(String.self, forKey: .startedAt).flatMap(ISO8601.parse)
        endedAt = try c.decodeIfPresent(String.self, forKey: .endedAt).flatMap(ISO8601.parse)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(date, forKey: .date)
        try c.encodeIfPresent(gymId, forKey: .gymId)
        try c.encodeIfPresent(intent, forKey: .intent)
        try c.encodeIfPresent(focusStyles, forKey: .focusStyles)
        try c.encodeIfPresent(plannedBlocks, forKey: .plannedBlocks)
        try c.encodeIfPresent(durationMin, forKey: .durationMin)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(startedAt.map(ISO8601.string), forKey: .startedAt)
        try c.encodeIfPresent(endedAt.map(ISO8601.string), forKey: .endedAt)
    }
}

public struct SessionReview: Codable, Sendable, Hashable {
    public var sessionId: String
    public var chips: [String]
    /// 0–10, one decimal
    public var overallScore: Double
    public var note: String?
    public var createdAt: String

    public init(sessionId: String, chips: [String], overallScore: Double, note: String? = nil, createdAt: Date = .now) {
        self.sessionId = sessionId; self.chips = chips; self.overallScore = overallScore; self.note = note
        self.createdAt = ISO8601.string(createdAt)
    }
}

public struct Injury: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var bodyPart: String
    public var name: String
    public var onsetDate: String
    public var status: InjuryStatus
    public var severity: String?
    public var diagnosis: String?
    public var rehabStart: String?
    public var physioNext: String?
    public var physioNote: String?

    public init(id: String = uid(), bodyPart: String, name: String, onsetDate: String, status: InjuryStatus,
                severity: String? = nil, diagnosis: String? = nil, rehabStart: String? = nil,
                physioNext: String? = nil, physioNote: String? = nil) {
        self.id = id; self.bodyPart = bodyPart; self.name = name; self.onsetDate = onsetDate; self.status = status
        self.severity = severity; self.diagnosis = diagnosis; self.rehabStart = rehabStart
        self.physioNext = physioNext; self.physioNote = physioNote
    }
}

public struct PainEntry: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var injuryId: String
    public var sessionId: String?
    public var date: String
    /// 0–10
    public var level: Int
}

public struct RehabExercise: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var injuryId: String
    public var name: String
    public var prescription: String
    /// times per week; 7 = daily
    public var frequency: Int
}

public struct RehabLog: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var exerciseId: String
    public var date: String
    public var done: Bool
}

public struct LoadRule: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var injuryId: String
    /// a climb style, or a free-form type like "campus"
    public var styleOrType: String
    /// nil = a hard prohibition rather than a weekly cap
    public var maxPerWeek: Int?
    public var condition: String
    public var headline: String

    enum CodingKeys: String, CodingKey { case id, injuryId, styleOrType, maxPerWeek, condition, headline }

    public init(id: String = uid(), injuryId: String, styleOrType: String, maxPerWeek: Int?, condition: String, headline: String) {
        self.id = id; self.injuryId = injuryId; self.styleOrType = styleOrType; self.maxPerWeek = maxPerWeek
        self.condition = condition; self.headline = headline
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(injuryId, forKey: .injuryId)
        try c.encode(styleOrType, forKey: .styleOrType)
        try c.encode(maxPerWeek, forKey: .maxPerWeek) // explicit null, as the web writes it
        try c.encode(condition, forKey: .condition)
        try c.encode(headline, forKey: .headline)
    }
}

/// The web entity, extended for the iOS Season view (r2). Every new field is optional so web backups import.
public struct Competition: Codable, Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var date: String
    public var endDate: String?
    public var location: String?
    public var gymId: String?
    public var category: String?
    public var format: String?
    public var rounds: [String]?
    public var priority: CompPriority?
    public var notes: String?
    /// Optional result, after the comp: "Semi-final · 3T 5Z"
    public var result: String?

    public init(id: String = uid(), name: String, date: String, endDate: String? = nil, location: String? = nil,
                gymId: String? = nil, category: String? = nil, format: String? = nil, rounds: [String]? = nil,
                priority: CompPriority = .a, notes: String? = nil, result: String? = nil) {
        self.id = id; self.name = name; self.date = date; self.endDate = endDate; self.location = location
        self.gymId = gymId; self.category = category; self.format = format; self.rounds = rounds
        self.priority = priority; self.notes = notes; self.result = result
    }

    /// Web comps carry no priority; they were always the one comp being peaked for.
    public var effectivePriority: CompPriority { priority ?? .a }
    public var lastDay: String { endDate ?? date }

    /// "KL Open · Bouldering" → "KL Open"
    public var displayName: String {
        (name.components(separatedBy: "·").first ?? name).trimmingCharacters(in: .whitespaces)
    }

    /// "KL Open · Bouldering" → "KL OPEN"
    public var shortName: String {
        (name.components(separatedBy: "·").first ?? name).trimmingCharacters(in: .whitespaces).uppercased()
    }
}

/* ── Settings — the web `settings` table, typed ─────────────────────────── */

public struct Settings: Sendable, Hashable {
    public var activeSessionId: String?
    public var dashboardRange: RangeID = .eightWeeks
    public var blockStart: String?
    public var blockWeeks: Int = 6
    public var blockPhase: String = "BUILD"
    public var seededAt: String?
    /// "template:<intent>" in the web app
    public var templates: [String: [PlanBlock]] = [:]
    /// iOS r2 — sessions per week, drives the Lock Screen gauge
    public var weeklyTarget: Int = 4
    /// iOS r2 — "Use full plan" pressed for this day
    public var taperOverrideDay: String?

    public init() {}
}

/* ── Helpers ────────────────────────────────────────────────────────────── */

public func uid() -> String {
    let t = String(Int(Date.now.timeIntervalSince1970 * 1000), radix: 36)
    let r = String(UInt32.random(in: 0...UInt32.max), radix: 36)
    return t + String(r.prefix(6))
}

public enum ISO8601 {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let lock = NSLock()

    public static func parse(_ s: String) -> Date? {
        lock.withLock { fractional.date(from: s) ?? plain.date(from: s) }
    }

    public static func string(_ d: Date) -> String {
        lock.withLock { fractional.string(from: d) }
    }
}
