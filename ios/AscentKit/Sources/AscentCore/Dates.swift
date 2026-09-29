import Foundation

/// Date helpers. Days are ISO `yyyy-MM-dd` strings in local time, exactly as in the web app,
/// so string comparison orders them and every metric ports unchanged.
public enum Day {
    static let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let days = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.firstWeekday = 2
        return c
    }

    public static func iso(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func date(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) ?? .distantPast
    }

    public static func today(_ now: Date = .now) -> String { iso(now) }

    public static func add(_ iso: String, _ days: Int) -> String {
        Self.iso(calendar.date(byAdding: .day, value: days, to: date(iso))!)
    }

    public static func between(_ a: String, _ b: String) -> Int {
        calendar.dateComponents([.day], from: date(a), to: date(b)).day ?? 0
    }

    static func parts(_ iso: String) -> (y: Int, m: Int, d: Int, dow: Int) {
        let d = date(iso)
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: d)
        return (c.year!, c.month!, c.day!, c.weekday! - 1)
    }

    /// "26 JUL"
    public static func short(_ iso: String) -> String {
        let p = parts(iso)
        return "\(p.d) \(months[p.m - 1])"
    }

    /// "12 Jan"
    public static func pretty(_ iso: String) -> String {
        let p = parts(iso)
        let m = months[p.m - 1]
        return "\(p.d) \(m.prefix(1))\(m.dropFirst().lowercased())"
    }

    /// "TUE 28 JUL"
    public static func plan(_ iso: String) -> String {
        let p = parts(iso)
        return "\(days[p.dow]) \(p.d) \(months[p.m - 1])"
    }

    /// "Sun 8 Nov 2026"
    public static func long(_ iso: String) -> String {
        let p = parts(iso)
        let d = days[p.dow]
        let m = months[p.m - 1]
        return "\(d.prefix(1))\(d.dropFirst().lowercased()) \(p.d) \(m.prefix(1))\(m.dropFirst().lowercased()) \(p.y)"
    }

    /// "SUN"
    public static func weekday(_ iso: String) -> String { days[parts(iso).dow] }
    public static func dayOfMonth(_ iso: String) -> Int { parts(iso).d }
    public static func monthName(_ iso: String) -> String {
        let p = parts(iso)
        return "\(months[p.m - 1].prefix(1))\(months[p.m - 1].dropFirst().lowercased())"
    }
    public static func monthKey(_ iso: String) -> String { String(iso.prefix(7)) }

    /// ISO week number (Mon-based), used for load-rule counting.
    public static func isoWeek(_ iso: String) -> (year: Int, week: Int, key: String) {
        var c = Calendar(identifier: .iso8601)
        c.timeZone = .current
        let comps = c.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date(iso))
        let y = comps.yearForWeekOfYear!, w = comps.weekOfYear!
        return (y, w, "\(y)-W\(w)")
    }

    /// Monday of the ISO week containing `iso`.
    public static func weekStart(_ iso: String) -> String {
        let dow = parts(iso).dow
        return add(iso, -((dow + 6) % 7))
    }

    /// "WK 30 · 20–26 JUL 2026"
    public static func weekRangeLabel(_ iso: String) -> String {
        let start = weekStart(iso)
        let end = add(start, 6)
        let s = parts(start), e = parts(end)
        let left = s.m == e.m ? "\(s.d)" : "\(s.d) \(months[s.m - 1])"
        return "WK \(isoWeek(iso).week) · \(left)–\(e.d) \(months[e.m - 1]) \(e.y)"
    }

    /// "WK 39 · 21–27 SEP" — the Today subtitle drops the year.
    public static func weekRangeShort(_ iso: String) -> String {
        let full = weekRangeLabel(iso)
        return String(full.dropLast(5))
    }

    public static func timeOfDay(_ date: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    public static func elapsedLabel(from start: Date, now: Date = .now) -> String {
        let mins = max(0, Int((now.timeIntervalSince(start) / 60).rounded()))
        let h = mins / 60
        return h > 0 ? "\(h)h \(mins % 60)m" : "\(mins)m"
    }

    public static func weeksBetween(_ a: String, _ b: String) -> Int {
        Int((Double(between(a, b)) / 7).rounded())
    }

    public static func inRange(_ iso: String, _ from: String, _ to: String) -> Bool { iso >= from && iso <= to }
}

/* ── Dashboard range ────────────────────────────────────────────────────── */

public enum RangeID: String, Codable, CaseIterable, Sendable, Identifiable {
    case eightWeeks = "8w"
    case sixMonths = "6m"
    case season

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .eightWeeks: "8 weeks"
        case .sixMonths: "6 months"
        case .season: "Season"
        }
    }
    public var days: Int {
        switch self {
        case .eightWeeks: 56
        case .sixMonths: 183
        case .season: 365
        }
    }

    /// Current window [from, to] and the immediately preceding window of equal length.
    public func windows(today: String) -> (from: String, to: String, prevFrom: String, prevTo: String) {
        (Day.add(today, -days + 1), today, Day.add(today, -days * 2 + 1), Day.add(today, -days))
    }
}
