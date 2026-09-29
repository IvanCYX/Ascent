import Foundation

/// The whole (single-user, small) log. One value, like the web app's `Snapshot`.
public struct Database: Sendable, Hashable {
    public var gyms: [Gym] = []
    public var boards: [Board] = []
    public var climbs: [Climb] = []
    public var sessions: [Session] = []
    public var reviews: [SessionReview] = []
    public var injuries: [Injury] = []
    public var painEntries: [PainEntry] = []
    public var rehabExercises: [RehabExercise] = []
    public var rehabLogs: [RehabLog] = []
    public var loadRules: [LoadRule] = []
    public var competitions: [Competition] = []
    public var settings = Settings()

    public init() {}

    /// Keeps the orderings the web snapshot guaranteed: gyms/boards by sortOrder, climbs and sessions oldest first.
    public mutating func normalise() {
        gyms.sort { $0.sortOrder < $1.sortOrder }
        boards.sort { $0.sortOrder < $1.sortOrder }
        climbs.sort { $0.createdAt < $1.createdAt }
        sessions.sort { $0.date < $1.date }
        // readiness reads the last 8 reviews, so keep them in session order however they were saved
        var dates: [String: String] = [:]
        for s in sessions { dates[s.id] = s.date }
        reviews = stableSorted(reviews) { (dates[$0.sessionId] ?? "") < (dates[$1.sessionId] ?? "") }
    }

    /* ── Lookups ─────────────────────────────────────────────────────── */

    public func gym(_ id: String?) -> Gym? { gyms.first { $0.id == id } }
    public func board(_ id: String?) -> Board? { boards.first { $0.id == id } }
    public func session(_ id: String?) -> Session? { sessions.first { $0.id == id } }
    public func review(for sessionId: String?) -> SessionReview? { reviews.first { $0.sessionId == sessionId } }

    public var activeSession: Session? {
        sessions.first { $0.id == settings.activeSessionId && $0.status == .active }
    }

    public func plannedSession(on day: String) -> Session? {
        sessions.first { $0.status == .planned && $0.date == day }
    }

    public var activeInjuries: [Injury] { injuries.filter { $0.status == .active } }
    public var watchingInjuries: [Injury] { injuries.filter { $0.status == .watching } }

    public func upcomingComps(from today: String) -> [Competition] {
        competitions.filter { $0.lastDay >= today }.sorted { $0.date < $1.date }
    }

    /// The web dashboard took the earliest comp regardless of date; iOS takes the next one that has not happened.
    public func nextComp(from today: String) -> Competition? { upcomingComps(from: today).first }
}

/* ── Backup format — identical to the web export so either app can read the other's file ── */

extension Database: Codable {
    enum Tables: String, CodingKey {
        case gyms, boards, climbs, sessions, reviews, injuries, painEntries, rehabExercises, rehabLogs, loadRules,
             competitions, settings
    }

    struct SettingRow: Codable {
        var key: String
        var value: JSONValue
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Tables.self)
        gyms = try c.decodeIfPresent([Gym].self, forKey: .gyms) ?? []
        boards = try c.decodeIfPresent([Board].self, forKey: .boards) ?? []
        climbs = try c.decodeIfPresent([Climb].self, forKey: .climbs) ?? []
        sessions = try c.decodeIfPresent([Session].self, forKey: .sessions) ?? []
        reviews = try c.decodeIfPresent([SessionReview].self, forKey: .reviews) ?? []
        injuries = try c.decodeIfPresent([Injury].self, forKey: .injuries) ?? []
        painEntries = try c.decodeIfPresent([PainEntry].self, forKey: .painEntries) ?? []
        rehabExercises = try c.decodeIfPresent([RehabExercise].self, forKey: .rehabExercises) ?? []
        rehabLogs = try c.decodeIfPresent([RehabLog].self, forKey: .rehabLogs) ?? []
        loadRules = try c.decodeIfPresent([LoadRule].self, forKey: .loadRules) ?? []
        competitions = try c.decodeIfPresent([Competition].self, forKey: .competitions) ?? []
        let rows = try c.decodeIfPresent([SettingRow].self, forKey: .settings) ?? []
        var s = Settings()
        for row in rows {
            switch row.key {
            case "activeSessionId": s.activeSessionId = row.value.string
            case "dashboardRange": s.dashboardRange = row.value.string.flatMap(RangeID.init) ?? .eightWeeks
            case "blockStart": s.blockStart = row.value.string
            case "blockWeeks": s.blockWeeks = row.value.int ?? 6
            case "blockPhase": s.blockPhase = row.value.string ?? "BUILD"
            case "seededAt": s.seededAt = row.value.string
            case "weeklyTarget": s.weeklyTarget = row.value.int ?? 4
            case "taperOverrideDay": s.taperOverrideDay = row.value.string
            case let key where key.hasPrefix("template:"):
                if let blocks = try? row.value.decode([PlanBlock].self) {
                    s.templates[String(key.dropFirst("template:".count))] = blocks
                }
            default: break
            }
        }
        settings = s
        normalise()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Tables.self)
        try c.encode(gyms, forKey: .gyms)
        try c.encode(boards, forKey: .boards)
        try c.encode(climbs, forKey: .climbs)
        try c.encode(sessions, forKey: .sessions)
        try c.encode(reviews, forKey: .reviews)
        try c.encode(injuries, forKey: .injuries)
        try c.encode(painEntries, forKey: .painEntries)
        try c.encode(rehabExercises, forKey: .rehabExercises)
        try c.encode(rehabLogs, forKey: .rehabLogs)
        try c.encode(loadRules, forKey: .loadRules)
        try c.encode(competitions, forKey: .competitions)
        var rows: [SettingRow] = [
            .init(key: "activeSessionId", value: settings.activeSessionId.map(JSONValue.string) ?? .null),
            .init(key: "dashboardRange", value: .string(settings.dashboardRange.rawValue)),
            .init(key: "blockWeeks", value: .number(Double(settings.blockWeeks))),
            .init(key: "blockPhase", value: .string(settings.blockPhase)),
            .init(key: "weeklyTarget", value: .number(Double(settings.weeklyTarget))),
        ]
        if let v = settings.blockStart { rows.append(.init(key: "blockStart", value: .string(v))) }
        if let v = settings.seededAt { rows.append(.init(key: "seededAt", value: .string(v))) }
        if let v = settings.taperOverrideDay { rows.append(.init(key: "taperOverrideDay", value: .string(v))) }
        for (intent, blocks) in settings.templates.sorted(by: { $0.key < $1.key }) {
            rows.append(.init(key: "template:\(intent)", value: try JSONValue(encoding: blocks)))
        }
        try c.encode(rows, forKey: .settings)
    }
}

public struct Backup: Codable, Sendable {
    public var version: Int
    public var exportedAt: String
    public var data: Database

    public init(data: Database) {
        version = 1
        exportedAt = ISO8601.string(.now)
        self.data = data
    }

    public static func encode(_ db: Database) throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(Backup(data: db))
    }

    public static func decode(_ data: Data) throws -> Database {
        try JSONDecoder().decode(Backup.self, from: data).data
    }
}

/// Just enough JSON to carry the web app's untyped settings values.
enum JSONValue: Codable, Hashable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    init<T: Encodable>(encoding value: T) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(self))
    }

    var string: String? { if case .string(let s) = self { s } else { nil } }
    var int: Int? { if case .number(let n) = self { Int(n) } else { nil } }
}
