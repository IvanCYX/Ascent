import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// What the live session shows outside the app (Dynamic Island, Lock Screen).
public struct LiveSessionState: Codable, Hashable, Sendable {
    public var startedAt: Date
    public var sends: Int
    /// "12", "V5", "6b+", or "PUR" for a Camp5 tag — never a number for Camp5
    public var high: String
    public var flashed: Int
    public var gymName: String
    public var intent: String?
    /// Mirrors the Face ID lock so the activity can redact while the phone is locked.
    public var privacyLock: Bool

    public init(startedAt: Date, sends: Int, high: String, flashed: Int, gymName: String, intent: String?, privacyLock: Bool) {
        self.startedAt = startedAt; self.sends = sends; self.high = high; self.flashed = flashed
        self.gymName = gymName; self.intent = intent; self.privacyLock = privacyLock
    }

    public static func from(_ db: Database, privacyLock: Bool) -> LiveSessionState? {
        guard let s = db.activeSession else { return nil }
        let sends = Metrics.sessionSends(db.climbs, sessionId: s.id)
        let gym = db.gym(s.gymId)
        return LiveSessionState(startedAt: s.startedAt ?? .now, sends: sends.count, high: Metrics.sessionHigh(sends, gym: gym) ?? "—",
                                flashed: sends.filter(Metrics.isFlash).count, gymName: gym?.name ?? "Session",
                                intent: s.intent, privacyLock: privacyLock)
    }
}

#if canImport(ActivityKit) && os(iOS)
public struct LiveSessionAttributes: ActivityAttributes {
    public typealias ContentState = LiveSessionState
    public var sessionId: String

    public init(sessionId: String) { self.sessionId = sessionId }
}
#endif
