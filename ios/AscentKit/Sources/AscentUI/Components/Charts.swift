import SwiftUI
import AscentCore

/* Every data mark uses the accent (`data` token). Injury red and hold colours never change. */

struct KpiGrid: View {
    var kpis: [Metrics.Kpi]
    @Environment(\.dynamicTypeSize) private var type

    var body: some View {
        let columns = type.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)]
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(Array(kpis.enumerated()), id: \.offset) { i, k in
                VStack(alignment: .leading, spacing: 0) {
                    Text(k.label).micro()
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(k.value).font(.serif(40, relativeTo: .largeTitle)).foregroundStyle(Palette.ink)
                        Text(k.caption).font(.sans(11.5)).foregroundStyle(Palette.muted).lineLimit(2)
                    }
                    .padding(.top, 10)
                    Text(k.delta).font(.mono(11)).foregroundStyle(k.deltaStrong ? Palette.ink : Palette.muted)
                        .padding(.top, 8).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 18)
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .trailing) {
                    if !type.isAccessibilitySize && i % 2 == 0 { Rectangle().fill(Palette.rule).frame(width: 1) }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

struct PyramidView: View {
    @Environment(\.accent) private var accent
    var rows: [Metrics.PyramidRow]
    var barHeight: CGFloat = 20
    var showCounts = true

    var body: some View {
        VStack(spacing: barHeight > 14 ? 6 : 4) {
            ForEach(rows, id: \.grade) { r in
                HStack(spacing: 10) {
                    Text("\(r.grade)").font(.serif(barHeight > 14 ? 16 : 12)).frame(width: barHeight > 14 ? 24 : 16, alignment: .trailing)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Palette.track)
                            Rectangle().fill(Palette.worked).frame(width: g.size.width * r.width)
                            Rectangle().fill(accent.color).frame(width: g.size.width * r.width * r.flashShare)
                        }
                    }
                    .frame(height: barHeight)
                    if showCounts {
                        Text("\(r.count)").font(.mono(12)).foregroundStyle(Palette.muted).frame(width: 22, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Grade \(r.grade): \(r.count) sends, \(r.flashed) flashed")
            }
        }
    }
}

struct PyramidLegend: View {
    @Environment(\.accent) private var accent
    var body: some View {
        HStack(spacing: 12) {
            legend(accent.color, "flashed")
            legend(Palette.worked, "worked")
        }
    }
    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 4) { Rectangle().fill(c).frame(width: 9, height: 9); Text(t).font(.sans(11)).foregroundStyle(Palette.muted) }
    }
}

/// Camp5 — ranked, not numbered. Counts and codes only.
struct TallyView: View {
    var bars: [Metrics.TagBar]
    var height: CGFloat = 66

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(bars, id: \.tagId) { b in
                VStack(spacing: 6) {
                    Text("\(b.count)").font(.mono(11)).foregroundStyle(b.count > 0 ? Palette.muted : Palette.faint)
                    Rectangle()
                        .fill(b.count == 0 ? Palette.worked : Palette.hold(b.tagId))
                        .frame(height: b.count == 0 ? 3 : max(6, b.height * height))
                        .overlay(Rectangle().strokeBorder(Palette.ruleStrong, lineWidth: b.count > 0 && Palette.needsHairline(b.tagId) ? 1 : 0))
                    Text(Vocab.colourCode(b.tagId)).font(.mono(9.5)).foregroundStyle(b.count == 0 ? Palette.faint : Palette.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Vocab.colourLabel(b.tagId)) tag: \(b.count)")
            }
        }
    }
}

struct BoardCard: View {
    var b: Metrics.BoardSummary

    var body: some View {
        let up = b.prevMaxV != nil && b.maxV != nil && b.maxV! > b.prevMaxV!
        HStack(spacing: 12) {
            Text(b.code).font(.mono(11, .medium)).foregroundStyle(Palette.paper).frame(width: 36, height: 36).background(Palette.ink)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(b.name) · \(b.angle)°").font(.sans(14, .medium)).foregroundStyle(Palette.ink)
                Text("\(b.sends) sends · \(Metrics.fixed1(b.sessionsPerWeek)) sessions/wk").font(.mono(11)).foregroundStyle(Palette.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("V\(b.maxV ?? 0)").font(.serif(24)).foregroundStyle(Palette.ink)
                Text(up ? "▲ V\(b.prevMaxV!)→V\(b.maxV!)" : "— flat this range").font(.mono(10.5))
                    .foregroundStyle(up ? Palette.ink : Palette.muted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Palette.card)
        .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Pain bars — the last one full red, the one before mid, the rest soft.
struct PainBars: View {
    var levels: [Int]
    var height: CGFloat = 36
    var fullCount = 1

    var body: some View {
        HStack(alignment: .bottom, spacing: levels.count > 8 ? 4 : 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { i, v in
                let fromEnd = levels.count - 1 - i
                Rectangle()
                    .fill(fromEnd < fullCount ? Palette.warn : fromEnd == fullCount ? Palette.warnMid : Palette.warnSoft)
                    .frame(height: max(height * 0.08, height * CGFloat(v) / 10))
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pain " + levels.map { "\($0)" }.joined(separator: ", ") + " out of 10")
    }
}

struct ReadinessRows: View {
    var rows: [Metrics.ReadinessRow]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(rows, id: \.label) { r in
                HStack(spacing: 10) {
                    Text(r.label).font(.sans(13, r.warn ? .semibold : .regular))
                        .foregroundStyle(r.warn ? Palette.warn : Palette.ink).frame(width: 118, alignment: .leading)
                    Meter(pct: Double(r.score), warn: r.warn)
                    Text("\(r.score)").font(.mono(12)).foregroundStyle(r.warn ? Palette.warn : Palette.muted).frame(width: 26, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Style × grade heatmap. Fill is the accent at alpha 0.07 + pct × 0.78, paper text from 0.5 up.
struct HeatmapView: View {
    @Environment(\.accent) private var accent
    @Environment(\.dynamicTypeSize) private var type
    var rows: [Metrics.HeatRow]

    var body: some View {
        if type.isAccessibilitySize { stacked } else { grid }
    }

    /// Accessibility sizes (DESIGN §7): one column, the style name above its own labelled cells.
    var stacked: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows, id: \.style) { row in
                VStack(alignment: .leading, spacing: 6) {
                    Text(row.style).font(.sans(12, row.weak ? .semibold : .medium))
                        .foregroundStyle(row.weak ? Palette.warn : Palette.ink)
                    HStack(spacing: 4) {
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                            VStack(spacing: 3) {
                                Text(cell.band).font(.mono(9.5)).foregroundStyle(Palette.muted).lineLimit(1).minimumScaleFactor(0.6)
                                heatCell(cell, weak: row.weak)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder var grid: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                Color.clear.frame(width: 84, height: 12)
                ForEach(Vocab.gradeBands, id: \.label) { b in
                    Text(b.label).font(.mono(9.5)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
                }
            }
            ForEach(rows, id: \.style) { row in
                GridRow {
                    Text(row.style).font(.sans(12, row.weak ? .semibold : .medium))
                        .foregroundStyle(row.weak ? Palette.warn : Palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 84, alignment: .leading)
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        heatCell(cell, weak: row.weak)
                    }
                }
            }
        }
    }

    @ViewBuilder func heatCell(_ cell: Metrics.HeatCell, weak: Bool) -> some View {
        if let pct = cell.pct {
            let gap = weak && pct <= 20
            let alpha = 0.07 + Double(pct) / 100 * 0.78
            Text("\(pct)")
                .font(.mono(11.5, pct == 0 ? .semibold : .medium))
                .foregroundStyle(gap ? (pct == 0 ? Palette.warn : Palette.ink) : alpha >= 0.5 ? Palette.paper : Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(gap ? (pct == 0 ? Palette.warnBg : Palette.warnSoft) : accent.color.opacity(alpha))
                .overlay(Rectangle().strokeBorder(Palette.warnMid, lineWidth: gap ? 1 : 0))
                .accessibilityLabel("\(cell.band): \(pct) percent sent, \(cell.attempts) logged")
        } else {
            Text("—").font(.mono(11.5)).foregroundStyle(Palette.faint)
                .frame(maxWidth: .infinity, minHeight: 36).background(Palette.track)
                .accessibilityLabel("\(cell.band): nothing attempted")
        }
    }
}

/// `1g` — "What keeps coming up": one row per chip, one cell per recent session.
struct ChipTrendPanel: View {
    @Environment(\.accent) private var accent
    var rows: [Metrics.ChipTrendRow]
    var pattern: String?
    var window = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("What keeps coming up", note: "LAST \(window) SESSIONS")
            if rows.isEmpty {
                Text("No reviews saved yet — chips start trending after a few sessions.").font(.sans(13)).foregroundStyle(Palette.muted)
            }
            VStack(spacing: 11) {
                ForEach(rows, id: \.chip) { r in
                    HStack(spacing: 12) {
                        Text(r.chip).font(.sans(13)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: 124, alignment: .leading)
                        HStack(spacing: 3) {
                            ForEach(Array(r.cells.enumerated()), id: \.offset) { _, on in
                                Rectangle().fill(on ? accent.color : Palette.track).frame(height: 16)
                            }
                        }
                        Text("\(r.count)×").font(.mono(11.5)).foregroundStyle(Palette.ink).frame(width: 28, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(r.chip): \(r.count) of the last \(window) sessions")
                }
            }
            if let pattern {
                Hairline().padding(.top, 16)
                Insight(label: "Pattern:", text: pattern).padding(.top, -2)
            }
        }
    }
}

struct BoardHistogramView: View {
    @Environment(\.accent) private var accent
    var bars: [Metrics.VBar]

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(bars, id: \.v) { b in
                VStack(spacing: 6) {
                    Rectangle()
                        .fill(b.count == 0 ? Palette.track : b.isMax ? accent.color : Palette.worked)
                        .frame(height: b.count == 0 ? 3 : max(6, b.height * 48))
                    Text("V\(b.v)").font(.mono(9)).foregroundStyle(b.count == 0 ? Palette.faint : b.isMax ? Palette.ink : Palette.muted)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("V\(b.v): \(b.count) sends")
            }
        }
        .frame(height: 70, alignment: .bottom)
    }
}

struct AdherenceStrip: View {
    @Environment(\.accent) private var accent
    var done: [Bool]
    var height: CGFloat = 20

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(done.enumerated()), id: \.offset) { _, d in
                Rectangle().fill(d ? accent.color : Palette.track).frame(height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done.filter { $0 }.count) of \(done.count) days done")
    }
}

/// Ledger row: date block, gym + intent · boards, top grades, sends + felt, chevron.
struct LedgerRow: View {
    var session: Session
    var db: Database

    var body: some View {
        let sends = Metrics.sessionSends(db.climbs, sessionId: session.id)
        let boards = Set(db.climbs.filter { $0.sessionId == session.id }.compactMap(\.boardId))
            .compactMap { db.board($0)?.name }.sorted()
        let review = db.review(for: session.id)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Day.dayOfMonth(session.date))").font(.serif(20)).foregroundStyle(Palette.ink)
                Text(Day.weekday(session.date)).font(.mono(10)).foregroundStyle(Palette.muted)
            }
            .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(db.gym(session.gymId)?.name ?? "—").font(.sans(14, .semibold)).foregroundStyle(Palette.ink)
                Text(([session.intent] + boards.map(Optional.some)).compactMap { $0 }.joined(separator: " · ").ifEmpty("—"))
                    .font(.sans(12.5)).foregroundStyle(Palette.muted).lineLimit(1)
                TopGradesView(top: Metrics.topGrades(sends))
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(sends.count)").font(.serif(17))
                    Text("SENDS").font(.mono(10)).foregroundStyle(Palette.muted)
                }
                if let review {
                    HStack(spacing: 6) {
                        Meter(pct: review.overallScore * 10, height: 5).frame(width: 40)
                        Text(String(format: "%.1f", review.overallScore)).font(.serif(14))
                    }
                } else {
                    Text("NOT RATED").font(.mono(10)).foregroundStyle(Palette.faint)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.faint)
        }
        .foregroundStyle(Palette.ink)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}

/// Plain geometric body map. Tap a part to filter.
struct BodyMapView: View {
    enum Status { case active, watching, clear }
    var status: [String: Status]
    var selected: String?
    var onSelect: (String?) -> Void

    var body: some View {
        VStack(spacing: 5) {
            part("head", w: 42, h: 42, r: 21)
            HStack(alignment: .top, spacing: 6) {
                limb("l")
                part("torso", w: 78, h: 118, r: 12)
                limb("r")
            }
            HStack(spacing: 8) {
                part("l-leg", w: 26, h: 96, r: 10)
                part("r-leg", w: 26, h: 96, r: 10)
            }
            .padding(.top, 2)
        }
    }

    func limb(_ side: String) -> some View {
        VStack(spacing: 4) {
            part("\(side)-shoulder", w: 15, h: 15, r: 7.5)
            part("\(side)-elbow", w: 13, h: 74, r: 8)
            part("\(side)-hand", w: 22, h: 22, r: 6)
        }
        .padding(.top, 6)
    }

    func part(_ id: String, w: CGFloat, h: CGFloat, r: CGFloat) -> some View {
        let s = status[id] ?? .clear
        let sel = selected == id
        let fill: Color = switch s {
        case .active: Palette.warn
        case .watching: Palette.watch
        case .clear: Palette.card
        }
        return Button { onSelect(sel ? nil : id) } label: {
            RoundedRectangle(cornerRadius: r).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: r).strokeBorder(sel ? Palette.ink : s == .clear ? Palette.ruleStrong : Palette.ink,
                                                                         lineWidth: sel ? 2 : 1))
                .frame(width: w, height: h)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Vocab.bodyPartLabel(id))
        .accessibilityValue(s == .active ? "active injury" : s == .watching ? "watching" : "clear")
        .accessibilityAddTraits(sel ? .isSelected : [])
    }
}
