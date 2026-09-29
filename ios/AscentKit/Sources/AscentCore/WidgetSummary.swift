import Foundation

/// Everything the Home and Lock Screen widgets draw, derived from the log (DESIGN §6).
/// The "limited" fields are the only ones a locked phone may show when the Face ID lock is on.
public struct WidgetSummary: Sendable, Hashable {
    /* limited — safe while locked */
    public var sessionsThisWeek: Int
    /// Mon–Sun, true where a session was logged or is live
    public var weekStrip: [Bool]
    public var todayIndex: Int
    public var streakWeeks: Int
    public var weeklyTarget: Int
    public var weeksToComp: Int?

    /* full — hidden while locked */
    public var topGrade: String?
    public var topGym: String?
    public var topDelta: String?
    public var sendsThisWeek: Int
    public var flashRate: Int?
    public var pyramid: [Metrics.PyramidRow]
    public var camp5: [Metrics.TagBar]
    public var kpis: [Metrics.Kpi]
    public var injuryShort: String?
    public var painNow: Int?
    public var rehabStreak: Int?
    public var rehabDue: Int
    public var compName: String?
    public var weakest: String?
    public var liveGym: String?

    public static let placeholder = WidgetSummary(
        sessionsThisWeek: 3, weekStrip: [true, false, true, false, false, true, false], todayIndex: 6, streakWeeks: 5,
        weeklyTarget: 4, weeksToComp: 6, topGrade: "12", topGym: "Batuu", topDelta: "▲ +1", sendsThisWeek: 21,
        flashRate: 38, pyramid: [], camp5: [], kpis: [], injuryShort: "L ring", painNow: 2, rehabStreak: 9, rehabDue: 2,
        compName: "KL Open", weakest: "Compression 42", liveGym: nil)

    public static func compute(_ db: Database, now: Date = .now) -> WidgetSummary {
        let today = Day.iso(now)
        let monday = Day.weekStart(today)
        let weekDays = (0..<7).map { Day.add(monday, $0) }
        let logged = db.sessions.filter { $0.status != .planned }
        let sessionDays = Set(logged.map(\.date))
        let thisWeek = logged.filter { $0.date >= monday && $0.date <= weekDays[6] }
        let target = Taper.weeklyTarget(db, today: today)

        // weeks in a row with at least one session; this week joins once it has one
        func hasSession(inWeekOf start: String) -> Bool {
            logged.contains { $0.date >= start && $0.date <= Day.add(start, 6) }
        }
        var streak = 0
        var cursor = thisWeek.isEmpty ? Day.add(monday, -7) : monday
        while hasSession(inWeekOf: cursor) && streak < 520 {
            streak += 1
            cursor = Day.add(cursor, -7)
        }

        let weekClimbs = Metrics.climbsInRange(db.climbs, from: monday, to: today)
        let lastWeekClimbs = Metrics.climbsInRange(db.climbs, from: Day.add(monday, -7), to: Day.add(monday, -1))
        let top = Metrics.maxGradeSent(weekClimbs, gyms: db.gyms)
        let prevTop = Metrics.maxGradeSent(lastWeekClimbs, gyms: db.gyms)
        var delta: String?
        if let t = top.grade, let p = prevTop.grade {
            delta = t > p ? "▲ +\(t - p)" : t < p ? "▼ \(t - p)" : "— level"
        }

        let w = db.settings.dashboardRange.windows(today: today)
        let cur = Metrics.climbsInRange(db.climbs, from: w.from, to: w.to)
        let prev = Metrics.climbsInRange(db.climbs, from: w.prevFrom, to: w.prevTo)
        let sessionsInRange = db.sessions.filter { $0.status == .done && $0.date >= w.from && $0.date <= w.to }.count
        let kpis = Metrics.buildKpis(cur: cur, prev: prev, gyms: db.gyms, sessionCount: sessionsInRange,
                                     rangeLabel: db.settings.dashboardRange.label.lowercased())

        let injury = db.activeInjuries.first
        let pain = injury.flatMap { inj in db.painEntries.filter { $0.injuryId == inj.id }.max { $0.date < $1.date } }
        let exercises = injury.map { inj in db.rehabExercises.filter { $0.injuryId == inj.id } } ?? []
        let adherence = Metrics.rehabAdherence(exercises, logs: db.rehabLogs, today: today)
        let due = exercises.filter { e in
            e.frequency >= 7 && !db.rehabLogs.contains { $0.exerciseId == e.id && $0.date == today && $0.done }
        }.count

        let comp = Taper.governingComp(db.competitions, on: today) ?? db.nextComp(from: today)
        let weakest = Metrics.compReadiness(cur, reviews: db.reviews, today: today).last

        return WidgetSummary(
            sessionsThisWeek: thisWeek.count,
            weekStrip: weekDays.map { sessionDays.contains($0) },
            todayIndex: Day.between(monday, today),
            streakWeeks: streak,
            weeklyTarget: target,
            weeksToComp: comp.map { Metrics.weeksOut(today: today, compDate: $0.date) },
            topGrade: top.grade.map(String.init),
            topGym: top.grade == nil ? nil : top.gymName,
            topDelta: delta,
            sendsThisWeek: weekClimbs.filter(Metrics.isSend).count,
            flashRate: Metrics.flashRate(weekClimbs).map { Int($0.rounded()) },
            pyramid: Metrics.sendPyramid(cur),
            camp5: Metrics.camp5Tally(cur, tags: db.gyms.first(where: \.isRanked)?.tags ?? Vocab.camp5Tags),
            kpis: kpis,
            injuryShort: injury.map { shortInjury($0.name).replacingOccurrences(of: " finger", with: "") },
            painNow: pain?.level,
            rehabStreak: injury == nil ? nil : adherence.streak,
            rehabDue: due,
            compName: comp.map { $0.displayName },
            weakest: weakest.map { "\($0.label) \($0.score)" },
            liveGym: db.activeSession.flatMap { db.gym($0.gymId)?.name })
    }
}
