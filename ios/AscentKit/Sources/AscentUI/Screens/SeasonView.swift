import SwiftUI
import AscentCore

/// Plan → Season (DESIGN §3.4): next comp, calendar, taper plan, upcoming comps, weekly target.
struct SeasonView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accent) private var accent
    @State private var selected: String?

    var body: some View {
        let db = store.db
        let today = store.today
        let comps = db.upcomingComps(from: today)
        let governing = Taper.governingComp(db.competitions, on: today)
        let selectedDay = selected ?? today

        VStack(alignment: .leading, spacing: 0) {
            if let next = governing ?? comps.first {
                NextCompCard(comp: next, today: today)
                    .padding(.horizontal, 16)
            } else {
                Text("No comps planned. Add one to get a taper plan.").font(.sans(13)).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 16)
            }

            Band(top: false) {
                SeasonCalendar(db: db, today: today, selected: $selected)
                CalendarLegend().padding(.top, 14)
            }

            Band {
                DayCard(day: selectedDay, db: db, today: today)
            }

            if let comp = governing ?? comps.first {
                Band {
                    SectionHead("Taper plan", note: "\(comp.shortName) · \(comp.effectivePriority.rawValue) · FROM YOUR 8-WK AVG")
                    let weakest = Metrics.compReadiness(Metrics.climbsInRange(db.climbs, from: Day.add(today, -55), to: today),
                                                        reviews: db.reviews, today: today).last
                    ForEach(Taper.planRows(db, comp: comp, today: today, weakest: weakest)) { row in TaperRow(row: row) }
                    if let check = injuryCheck(db, comp: comp) {
                        WarnPanel(lead: "Injury check", text: check).padding(.top, 14)
                    }
                }
            }

            Band {
                SectionHead("Upcoming comps", note: "\(comps.count) THIS SEASON")
                if comps.isEmpty { Text("Nothing on the calendar.").font(.sans(13)).foregroundStyle(Palette.muted) }
                ForEach(comps) { c in
                    NavigationLink(value: Route.comp(c.id)) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Day.dayOfMonth(c.date))").font(.serif(20))
                                Text(Day.short(c.date).components(separatedBy: " ").last ?? "").font(.mono(10)).foregroundStyle(Palette.muted)
                            }
                            .frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(c.name).font(.sans(14, .semibold))
                                Text(Taper.summary(c, all: db.competitions)).font(.sans(12.5)).foregroundStyle(Palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.faint)
                        }
                        .foregroundStyle(Palette.ink)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) { Hairline() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                FieldRow(label: "SESSIONS / WEEK TARGET") {
                    Spacer()
                    SquareStepper(value: "\(db.settings.weeklyTarget)",
                                  decrement: { store.setWeeklyTarget(db.settings.weeklyTarget - 1) },
                                  increment: { store.setWeeklyTarget(db.settings.weeklyTarget + 1) })
                }
                .padding(.top, 16)
                Text("Also drives the Lock Screen gauge. Taper weeks scale it down automatically.")
                    .font(.sans(12)).foregroundStyle(Palette.muted).padding(.top, 8)
            }
            .padding(.bottom, 80)
        }
    }

    private func injuryCheck(_ db: Database, comp: Competition) -> String? {
        guard let injury = db.activeInjuries.first,
              let rule = db.loadRules.first(where: { $0.injuryId == injury.id && $0.maxPerWeek != nil }) else { return nil }
        let when = Taper.peakStart(comp) ?? Taper.taperStart(comp) ?? comp.date
        let w = Day.weekday(when)
        return "If \(shortInjury(injury.name)) is still above 1/10 on \(w.prefix(1))\(w.dropFirst().lowercased()) \(Day.pretty(when)), \(comp.effectivePriority == .a ? "peak-week" : "taper") comp sims skip \(rule.styleOrType.lowercased()) boulders. The \(rule.styleOrType) cap stays in force through the taper."
    }
}

struct NextCompCard: View {
    @Environment(Router.self) private var router
    var comp: Competition
    var today: String

    var body: some View {
        let days = Day.between(today, comp.date)
        Button { router.paths[.plan, default: NavigationPath()].append(Route.comp(comp.id)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("NEXT COMP · \(comp.effectivePriority.rawValue) PRIORITY").micro(Palette.ink)
                    Spacer()
                    Text("\(days) DAY\(days == 1 ? "" : "S")").font(.mono(10.5)).foregroundStyle(Palette.muted)
                }
                Text(comp.name).font(.serif(26, relativeTo: .title)).foregroundStyle(Palette.ink).padding(.top, 10)
                    .fixedSize(horizontal: false, vertical: true)
                Text([Day.long(comp.date).components(separatedBy: " ").dropLast().joined(separator: " "), comp.location, comp.category,
                      comp.rounds.map { $0.map { $0.lowercased() }.joined(separator: " → ") }]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                    .font(.sans(13)).foregroundStyle(Palette.muted).padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
                PhaseBar(comp: comp, today: today).padding(.top, 16)
            }
            .padding(16)
            .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the comp detail")
    }
}

struct PhaseBar: View {
    @Environment(\.accent) private var accent
    var comp: Competition
    var today: String

    struct Segment: Identifiable {
        var id: String { label + start }
        var label: String
        var phase: Phase
        var start: String
        var weight: CGFloat
    }

    var segments: [Segment] {
        let week = Day.weekStart(comp.date)
        let buildStart = min(Day.weekStart(today), week)
        switch comp.effectivePriority {
        case .a:
            let peak = Day.add(week, -14)
            let buildWeeks = max(1, CGFloat(Day.between(buildStart, peak)) / 7)
            return [.init(label: "BUILD", phase: .build, start: buildStart, weight: buildWeeks),
                    .init(label: "PEAK", phase: .peak, start: peak, weight: 1),
                    .init(label: "TAPER", phase: .taper, start: Day.add(week, -7), weight: 1),
                    .init(label: "COMP WK", phase: .compWeek, start: week, weight: 1)]
        case .b:
            return [.init(label: "BUILD", phase: .build, start: buildStart, weight: max(1, CGFloat(Day.between(buildStart, week)) / 7)),
                    .init(label: "TAPER", phase: .taper, start: week, weight: 1)]
        case .c:
            return [.init(label: "BUILD", phase: .build, start: buildStart, weight: max(1, CGFloat(Day.between(buildStart, comp.date)) / 7))]
        }
    }

    var body: some View {
        let now = Taper.phase(of: comp, on: today)
        let segs = segments
        let total = segs.reduce(0) { $0 + $1.weight } + 0.45
        GeometryReader { g in
            let unit = (g.size.width - CGFloat(segs.count) * 2) / total
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(segs) { s in
                        let isNow = s.phase == now
                        ZStack {
                            if s.phase.isTaper {
                                Hatch(fg: Palette.worked, bg: Palette.track)
                            } else {
                                Rectangle().fill(isNow ? accent.color : Palette.track)
                            }
                            Text(isNow ? "\(s.label) · NOW" : s.label)
                                .font(.mono(9.5, .medium)).tracking(0.8).lineLimit(1).minimumScaleFactor(0.6)
                                .foregroundStyle(isNow && !s.phase.isTaper ? accent.onAccent : s.phase.isTaper ? Palette.ink : Palette.muted)
                                .padding(.horizontal, 2)
                        }
                        .frame(width: unit * s.weight, height: 30)
                    }
                    Rectangle().fill(accent.color).frame(width: unit * 0.45, height: 30)
                        .overlay(Image(systemName: "flag.fill").font(.system(size: 11)).foregroundStyle(accent.onAccent))
                }
                ZStack(alignment: .topLeading) {
                    ForEach(Array(segs.enumerated()), id: \.offset) { i, s in
                        let x = segs.prefix(i).reduce(0) { $0 + $1.weight * unit + 2 }
                        Text(Day.short(s.start)).font(.mono(9.5)).foregroundStyle(Palette.muted).fixedSize().offset(x: x)
                    }
                    Text("\(Day.dayOfMonth(comp.date))").font(.mono(9.5)).foregroundStyle(Palette.muted)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(height: 50)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Season phases: " + segs.map { $0.label }.joined(separator: ", ") + ", then the comp. Now: \(now?.rawValue ?? "")")
    }
}

/// Diagonal hatch for taper days.
struct Hatch: View {
    var fg: Color
    var bg: Color = .clear

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(bg))
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 8
            }
            ctx.stroke(p, with: .color(fg), lineWidth: 3)
        }
        .clipped()
    }
}

struct TaperRow: View {
    var row: Taper.PlanRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.phase.rawValue).font(.mono(10.5, .medium)).tracking(0.8).foregroundStyle(Palette.ink)
                Text(row.range.replacingOccurrences(of: " – ", with: "\n–")).font(.mono(10.5)).foregroundStyle(Palette.muted)
            }
            .frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Text(row.lead).foregroundStyle(Palette.ink).font(.sans(13, .semibold))) \(row.body)")
                    .font(.sans(13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if let f = row.factor { LoadBar(fill: f) }
            }
        }
        .padding(.vertical, 13)
        .background(row.isNow ? Palette.track : .clear)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }
}

/* ── Calendar ───────────────────────────────────────────────────────────── */

struct SeasonCalendar: View {
    var db: Database
    var today: String
    @Binding var selected: String?

    var months: [String] {
        let first = String(today.prefix(7)) + "-01"
        let last = db.upcomingComps(from: today).last?.lastDay ?? Day.add(today, 60)
        var out: [String] = []
        var m = first
        while m <= last || out.count < 2 {
            out.append(m)
            m = Day.iso(Day.calendar.date(byAdding: .month, value: 1, to: Day.date(m))!)
            if out.count > 18 { break }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(months, id: \.self) { MonthGrid(month: $0, db: db, today: today, selected: $selected) }
        }
    }
}

struct MonthGrid: View {
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var type
    var month: String
    var db: Database
    var today: String
    @Binding var selected: String?

    var body: some View {
        if type.isAccessibilitySize { weekList } else { grid }
    }

    /// Accessibility sizes (DESIGN §7): one row per week instead of 46 pt day cells.
    var weekList: some View {
        let first = Day.date(month)
        let count = Day.calendar.range(of: .day, in: .month, for: first)!.count
        let days = (1...count).map { String(format: "%@-%02d", String(month.prefix(7)), $0) }
        // Split the month's days at each Monday.
        let weeks = days.reduce(into: [[String]]()) { out, iso in
            if out.isEmpty || Day.weekday(iso) == "MON" { out.append([iso]) } else { out[out.count - 1].append(iso) }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(Day.monthName(month)) \(month.prefix(4))").font(.serif(20)).foregroundStyle(Palette.ink)
            ForEach(weeks, id: \.first) { week in
                WeekRow(week: week, db: db, today: today, selected: $selected)
            }
        }
    }

    @ViewBuilder var grid: some View {
        let first = Day.date(month)
        let count = Day.calendar.range(of: .day, in: .month, for: first)!.count
        let lead = (Day.calendar.component(.weekday, from: first) + 5) % 7
        let logged = Set(db.sessions.filter { $0.status != .planned }.map(\.date))
        let planned = Set(db.sessions.filter { $0.status == .planned }.map(\.date))
        let comps = db.competitions

        VStack(alignment: .leading, spacing: 12) {
            Text("\(Day.monthName(month)) \(month.prefix(4))").font(.serif(20)).foregroundStyle(Palette.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                ForEach(cells(count: count, lead: lead), id: \.self) { cell in
                    if cell.hasPrefix("dow") {
                        Text(String(cell.last!)).font(.mono(10)).foregroundStyle(Palette.muted).padding(.bottom, 6)
                    } else if cell.hasPrefix("pad") {
                        Color.clear.frame(height: 46)
                    } else {
                        let iso = cell
                        let comp = comps.first { iso >= $0.date && iso <= $0.lastDay }
                        DayCell(day: Day.dayOfMonth(iso), iso: iso, isToday: iso == today, isSelected: iso == (selected ?? today),
                                comp: comp, phase: Taper.dayPhase(comps, on: iso)?.phase,
                                dot: logged.contains(iso) ? .logged : planned.contains(iso) ? .planned : nil) {
                            selected = iso
                        }
                    }
                }
            }
        }
    }
}

extension MonthGrid {
    /// Weekday heads, leading pads, then one ISO date per day — each with its own id.
    func cells(count: Int, lead: Int) -> [String] {
        ["M", "T", "W", "T", "F", "S", "S"].enumerated().map { "dow\($0.offset)\($0.element)" }
            + (0..<lead).map { "pad\($0)" }
            + (1...count).map { String(format: "%@-%02d", String(month.prefix(7)), $0) }
    }
}

struct WeekRow: View {
    @Environment(\.accent) private var accent
    var week: [String]
    var db: Database
    var today: String
    @Binding var selected: String?

    var body: some View {
        let range = week.first!...week.last!
        let comp = db.competitions.first { range.contains($0.date) }
        let logged = db.sessions.filter { $0.status != .planned && range.contains($0.date) }.count
        let planned = db.sessions.filter { $0.status == .planned && range.contains($0.date) }.count
        let phase = Taper.dayPhase(db.competitions, on: week.first!)?.phase
        let isSelected = range.contains(selected ?? today)
        let label = week.count == 1 ? Day.pretty(week[0])
            : "\(Day.dayOfMonth(week.first!))–\(Day.dayOfMonth(week.last!)) \(Day.monthName(week.first!))"
        // Like the grid, only the phases that shade the calendar are named.
        let parts = [phase.flatMap { $0 == .build ? nil : $0.rawValue }, logged > 0 ? "\(logged) LOGGED" : nil, planned > 0 ? "\(planned) PLANNED" : nil,
                     range.contains(today) ? "TODAY" : nil].compactMap { $0 }

        Button {
            selected = comp?.date ?? (range.contains(today) ? today : week.first!)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label).font(.sans(15, .semibold, relativeTo: .body)).foregroundStyle(Palette.ink)
                    Spacer(minLength: 8)
                    if let comp { Text(comp.shortName).font(.sans(14, .semibold)).foregroundStyle(accent.color) }
                }
                if !parts.isEmpty { Text(parts.joined(separator: " · ")).micro() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background {
                switch phase {
                case .peak: Palette.track
                case .taper: Hatch(fg: Palette.track)
                case .compWeek: Hatch(fg: Palette.worked)
                default: Palette.card
                }
            }
            .overlay(Rectangle().strokeBorder(isSelected ? Palette.ink : Palette.rule, lineWidth: isSelected ? 2 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct DayCell: View {
    @Environment(\.accent) private var accent
    enum Dot { case logged, planned }
    var day: Int
    var iso: String
    var isToday: Bool
    var isSelected: Bool
    var comp: Competition?
    var phase: Phase?
    var dot: Dot?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text("\(day)")
                    .font(.sans(15, comp != nil ? .semibold : .regular, relativeTo: .body))
                    .foregroundStyle(comp != nil ? accent.onAccent : isSelected ? Palette.paper : Palette.ink)
                    .frame(width: 28, height: 28)
                    .background(comp != nil ? accent.color : isSelected ? Palette.ink : .clear)
                    .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: isToday && comp == nil ? 1.5 : 0))
                if let comp {
                    Text(comp.shortName.components(separatedBy: " ").prefix(2).joined(separator: " "))
                        .font(.mono(7.5, .semibold)).foregroundStyle(accent.color).lineLimit(1).minimumScaleFactor(0.7)
                } else if let dot {
                    Rectangle().fill(dot == .logged ? accent.color : .clear)
                        .overlay(Rectangle().strokeBorder(accent.color, lineWidth: dot == .planned ? 1 : 0))
                        .frame(width: 5, height: 5)
                } else {
                    Color.clear.frame(width: 5, height: 5)
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, minHeight: 46, alignment: .top)
            .background {
                switch phase {
                case .peak: Palette.track
                case .taper: Hatch(fg: Palette.track)
                case .compWeek: Hatch(fg: Palette.worked)
                default: Color.clear
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel(Day.long(iso) + (comp.map { ", \($0.name)" } ?? "") + (dot == .logged ? ", session logged" : dot == .planned ? ", session planned" : ""))
        .accessibilityValue(phase?.rawValue.lowercased() ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct CalendarLegend: View {
    @Environment(\.accent) private var accent

    var body: some View {
        ChipFlow(spacing: 14) {
            item("logged") { Rectangle().fill(accent.color) }
            item("planned") { Rectangle().strokeBorder(accent.color, lineWidth: 1) }
            item("peak") { Rectangle().fill(Palette.track) }
            item("taper") { Hatch(fg: Palette.worked) }
            item("comp") { Rectangle().fill(accent.color) }
        }
    }

    func item<S: View>(_ label: String, @ViewBuilder swatch: () -> S) -> some View {
        HStack(spacing: 4) {
            swatch().frame(width: 9, height: 9)
            Text(label).font(.sans(11)).foregroundStyle(Palette.muted)
        }
    }
}

/// Selected date: what's on it, plus Plan a session / Add comp.
struct DayCard: View {
    @Environment(Router.self) private var router
    var day: String
    var db: Database
    var today: String

    var body: some View {
        let dp = Taper.dayPhase(db.competitions, on: day)
        let sessions = db.sessions.filter { $0.date == day }
        let comps = db.competitions.filter { day >= $0.date && day <= $0.lastDay }
        let weekOffset = dp.map { Day.between(Day.weekStart($0.comp.date), Day.weekStart(day)) / 7 }

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Day.long(day).components(separatedBy: " ").dropLast().joined(separator: " "))\(day == today ? " · today" : "")")
                    .font(.sans(14, .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                if let dp, let weekOffset {
                    Text("\(dp.phase.rawValue)\(weekOffset < 0 ? " · WK \(weekOffset)" : "")").font(.mono(10.5)).foregroundStyle(Palette.muted)
                }
            }
            Text(describe(sessions: sessions, comps: comps)).font(.sans(13)).foregroundStyle(Palette.muted).padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if day >= today {
                    Button("Plan a session") {
                        if day == today { router.planSegment = .today } else { router.paths[.plan, default: NavigationPath()].append(Route.planDay(day)) }
                    }
                    .buttonStyle(SecondaryButtonStyle(height: 42))
                    Button("Add comp") { router.sheet = .compEditor(compId: nil, date: day) }.buttonStyle(SecondaryButtonStyle(height: 42))
                } else if let s = sessions.first(where: { $0.status == .done }) {
                    Button("Open session") { router.paths[.plan, default: NavigationPath()].append(Route.session(s.id)) }
                        .buttonStyle(SecondaryButtonStyle(height: 42))
                }
            }
            .padding(.top, 12)
        }
        .padding(14)
        .background(Palette.card)
        .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
    }

    func describe(sessions: [Session], comps: [Competition]) -> String {
        var parts: [String] = comps.map { "\($0.name) · \($0.effectivePriority.rawValue) priority." }
        for s in sessions {
            let gym = db.gym(s.gymId)?.name ?? "no gym"
            switch s.status {
            case .active: parts.append("Live session at \(gym)\(s.intent.map { ", \($0.lowercased())" } ?? "").")
            case .planned: parts.append("Planned: \(s.intent ?? "session") at \(gym).")
            case .done:
                let sends = Metrics.sessionSends(db.climbs, sessionId: s.id).count
                parts.append("\(s.intent ?? "Session") at \(gym) · \(sends) sends.")
            }
        }
        if parts.isEmpty { parts.append("Nothing on this day.") }
        if day >= today { parts.append("Tap any date to plan a session or add a comp on it.") }
        return parts.joined(separator: " ")
    }
}
