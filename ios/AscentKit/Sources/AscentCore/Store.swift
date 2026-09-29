import Foundation
import Observation

/// Where everything lives. One App Group so the widgets can read what the app writes. Nothing syncs anywhere.
public enum AppGroup {
    public static let id = "group.com.ivancyx.ascent"

    public static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }

    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        // Tests and previews without the entitlement.
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent("AscentGroup", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    public static var storeURL: URL { containerURL.appendingPathComponent("ascent-log.json") }
}

/// Keys shared with the widget extension through App Group defaults.
public enum SharedKey {
    public static let privacyLock = "privacyLock"
    public static let accentHex = "accentHex"
    public static let appearance = "appearance"
    public static let requireInterval = "requireInterval"
}

/// Reads and writes the log file. Stateless, so the widget extension can use it too.
public enum LogFile {
    public static func load(from url: URL = AppGroup.storeURL) -> Database? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Backup.decode(data)
    }

    public static func save(_ db: Database, to url: URL = AppGroup.storeURL) throws {
        let data = try JSONEncoder().encode(Backup(data: db))
        #if os(iOS)
        // Readable after first unlock so the widgets can render while the phone is locked.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
}

/// The app's single source of truth. Every mutation mirrors a function in the web `src/db/store.ts`.
@MainActor
@Observable
public final class AscentStore {
    public private(set) var db: Database
    /// Called after every write — the app hooks widget reloads and the Live Activity onto it.
    @ObservationIgnored public var onChange: ((Database) -> Void)?
    @ObservationIgnored private let url: URL
    @ObservationIgnored public var now: () -> Date = { .now }

    public init(url: URL = AppGroup.storeURL, seedIfEmpty: Bool = true) {
        self.url = url
        if let loaded = LogFile.load(from: url) {
            db = loaded
        } else {
            db = seedIfEmpty ? Seed.demo() : Seed.empty()
            try? LogFile.save(db, to: url)
        }
    }

    /// In-memory store for previews and tests.
    public init(database: Database) {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ascent-preview-\(UUID().uuidString).json")
        db = database
    }

    public var today: String { Day.iso(now()) }

    private func write(_ change: (inout Database) -> Void) {
        var next = db
        change(&next)
        next.normalise()
        db = next
        try? LogFile.save(next, to: url)
        onChange?(next)
    }

    /// Picks up writes made while the app was in the background (nothing else writes today, but be safe).
    public func reload() {
        if let loaded = LogFile.load(from: url), loaded != db { db = loaded }
    }

    /* ── Settings ────────────────────────────────────────────────────── */

    public func setDashboardRange(_ r: RangeID) { write { $0.settings.dashboardRange = r } }
    public func setWeeklyTarget(_ n: Int) { write { $0.settings.weeklyTarget = min(7, max(1, n)) } }
    public func saveTemplate(_ intent: String, blocks: [PlanBlock]) { write { $0.settings.templates[intent] = blocks } }
    public func setTaperOverride(_ day: String?) { write { $0.settings.taperOverrideDay = day } }

    /* ── Sessions ────────────────────────────────────────────────────── */

    @discardableResult
    public func startSession(gymId: String?, intent: String?, focusStyles: [String]? = nil,
                             plannedBlocks: [PlanBlock]? = nil, fromPlanId: String? = nil) -> String {
        let id = fromPlanId ?? uid()
        let start = now()
        let day = Day.iso(start)
        write { db in
            let existing = db.sessions.firstIndex { $0.id == fromPlanId }
            var s = existing.map { db.sessions[$0] } ?? Session(id: id, date: day, status: .active)
            s.id = id
            s.date = day
            s.gymId = gymId ?? s.gymId
            s.intent = intent ?? s.intent
            s.focusStyles = focusStyles ?? s.focusStyles
            s.plannedBlocks = plannedBlocks ?? s.plannedBlocks
            s.status = .active
            s.startedAt = start
            if let i = existing { db.sessions[i] = s } else { db.sessions.append(s) }
            db.settings.activeSessionId = id
        }
        return id
    }

    public func endSession(_ id: String) {
        let end = now()
        write { db in
            guard let i = db.sessions.firstIndex(where: { $0.id == id }) else { return }
            var s = db.sessions[i]
            s.status = .done
            s.endedAt = end
            if let start = s.startedAt { s.durationMin = max(1, Int((end.timeIntervalSince(start) / 60).rounded())) }
            db.sessions[i] = s
            db.settings.activeSessionId = nil
        }
    }

    public func updateSession(_ id: String, _ patch: (inout Session) -> Void) {
        write { db in
            guard let i = db.sessions.firstIndex(where: { $0.id == id }) else { return }
            patch(&db.sessions[i])
        }
    }

    @discardableResult
    public func savePlan(id: String?, date: String, gymId: String?, intent: String?, focusStyles: [String],
                         plannedBlocks: [PlanBlock]) -> String {
        let pid = id ?? uid()
        write { db in
            if let i = db.sessions.firstIndex(where: { $0.id == pid }) {
                db.sessions[i].date = date
                db.sessions[i].gymId = gymId
                db.sessions[i].intent = intent
                db.sessions[i].focusStyles = focusStyles
                db.sessions[i].plannedBlocks = plannedBlocks
            } else {
                db.sessions.append(Session(id: pid, date: date, gymId: gymId, intent: intent, focusStyles: focusStyles,
                                           plannedBlocks: plannedBlocks, status: .planned))
            }
        }
        return pid
    }

    public func setActiveGym(_ sessionId: String, gymId: String) { updateSession(sessionId) { $0.gymId = gymId } }

    /// Deletes a session and everything hanging off it.
    public func deleteSession(_ id: String) {
        write { db in
            db.sessions.removeAll { $0.id == id }
            db.climbs.removeAll { $0.sessionId == id }
            db.reviews.removeAll { $0.sessionId == id }
            db.painEntries.removeAll { $0.sessionId == id }
            if db.settings.activeSessionId == id { db.settings.activeSessionId = nil }
        }
    }

    /* ── Climbs ──────────────────────────────────────────────────────── */

    @discardableResult
    public func addClimb(_ climb: Climb) -> String {
        var c = climb
        c.id = uid()
        c.createdAt = now()
        write { $0.climbs.append(c) }
        return c.id
    }

    public func deleteClimb(_ id: String) { write { $0.climbs.removeAll { $0.id == id } } }

    /// Undo puts a deleted climb back exactly as it was.
    public func restoreClimb(_ climb: Climb) { write { $0.climbs.append(climb) } }

    /* ── Reviews ─────────────────────────────────────────────────────── */

    public func saveReview(sessionId: String, chips: [String], score: Double, note: String?) {
        let review = SessionReview(sessionId: sessionId, chips: chips, overallScore: score, note: note, createdAt: now())
        write { db in
            db.reviews.removeAll { $0.sessionId == sessionId }
            db.reviews.append(review)
        }
    }

    /* ── Injuries, pain, rehab ───────────────────────────────────────── */

    /// One entry per injury per day; a second log on the same day replaces the first.
    public func addPainEntry(injuryId: String, level: Int, sessionId: String? = nil, date: String? = nil) {
        let day = date ?? today
        write { db in
            if let i = db.painEntries.firstIndex(where: { $0.injuryId == injuryId && $0.date == day }) {
                db.painEntries[i].level = level
                db.painEntries[i].sessionId = sessionId
            } else {
                db.painEntries.append(PainEntry(id: uid(), injuryId: injuryId, sessionId: sessionId, date: day, level: level))
            }
        }
    }

    @discardableResult
    public func createInjury(_ injury: Injury) -> String {
        write { $0.injuries.append(injury) }
        return injury.id
    }

    public func updateInjury(_ id: String, _ patch: (inout Injury) -> Void) {
        write { db in
            guard let i = db.injuries.firstIndex(where: { $0.id == id }) else { return }
            patch(&db.injuries[i])
        }
    }

    public func toggleRehab(_ exerciseId: String, date: String? = nil) {
        let day = date ?? today
        write { db in
            if let i = db.rehabLogs.firstIndex(where: { $0.exerciseId == exerciseId && $0.date == day }) {
                db.rehabLogs.remove(at: i)
            } else {
                db.rehabLogs.append(RehabLog(id: uid(), exerciseId: exerciseId, date: day, done: true))
            }
        }
    }

    public func addRehabExercise(injuryId: String, name: String, prescription: String, frequency: Int = 7) {
        write { $0.rehabExercises.append(RehabExercise(id: uid(), injuryId: injuryId, name: name, prescription: prescription, frequency: frequency)) }
    }

    public func deleteRehabExercise(_ id: String) {
        write { db in
            db.rehabExercises.removeAll { $0.id == id }
            db.rehabLogs.removeAll { $0.exerciseId == id }
        }
    }

    public func addLoadRule(_ rule: LoadRule) { write { $0.loadRules.append(rule) } }
    public func deleteLoadRule(_ id: String) { write { $0.loadRules.removeAll { $0.id == id } } }

    /* ── Gyms ────────────────────────────────────────────────────────── */

    public func saveGym(_ gym: Gym) {
        write { db in
            if let i = db.gyms.firstIndex(where: { $0.id == gym.id }) { db.gyms[i] = gym } else { db.gyms.append(gym) }
        }
    }

    public func deleteGym(_ id: String) { write { $0.gyms.removeAll { $0.id == id } } }

    /* ── Competitions ────────────────────────────────────────────────── */

    public func saveCompetition(_ comp: Competition) {
        write { db in
            if let i = db.competitions.firstIndex(where: { $0.id == comp.id }) { db.competitions[i] = comp }
            else { db.competitions.append(comp) }
        }
    }

    public func deleteCompetition(_ id: String) { write { $0.competitions.removeAll { $0.id == id } } }

    /* ── Backup ──────────────────────────────────────────────────────── */

    public func exportData() throws -> Data { try Backup.encode(db) }

    /// Replaces the whole log. Throws before touching anything if the file does not parse.
    public func importData(_ data: Data) throws {
        let imported = try Backup.decode(data)
        write { $0 = imported }
    }

    public func resetToDemo() { write { $0 = Seed.demo(now: now()) } }
    public func clearAll() { write { $0 = Seed.empty() } }
}
