import SwiftUI
import AscentCore

/* Every data mark uses the accent. Amber marks caution, injury red stays red, hold colours never change. */

/* ── Pillar rings (DESIGN §4) ───────────────────────────────────────────── */

/// A ring that fills clockwise from 12 o'clock. Over 100 % draws a second lap on top with a cut-out at its tip,
/// capped at 200 %. Draws in on first appear unless Reduce Motion is on.
struct PillarRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 8
    /// The card colour behind the ring, for the second lap's cut-out
    var cutout: Color = Palette.surface
    /// A muted dashed partial ring while there isn't enough history
    var dashed = false
    var delay: Double = 0
    @State private var shown: Double = 0

    var body: some View {
        let p = min(2, max(0, shown))
        ZStack {
            Circle().stroke(Palette.track, lineWidth: lineWidth)
            if dashed {
                Circle().trim(from: 0, to: min(1, p))
                    .stroke(Palette.secondary.opacity(0.6), style: StrokeStyle(lineWidth: lineWidth, dash: [lineWidth * 0.75, lineWidth * 0.8]))
            } else {
                Circle().trim(from: 0, to: min(1, p))
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: p >= 1 ? .butt : .round))
                // a lap shorter than ~2 % reads as a stray dot at 12 o'clock
                if p > 1.02 {
                    Circle().trim(from: 0, to: p - 1)
                        .stroke(cutout, style: StrokeStyle(lineWidth: lineWidth + 3.5, lineCap: .round))
                    Circle().trim(from: 0, to: p - 1)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
        }
        .rotationEffect(.degrees(-90))
        .padding(lineWidth / 2)
        .onAppear {
            if reduceMotion { shown = progress } else {
                withAnimation(.smooth(duration: 0.9).delay(delay)) { shown = progress }
            }
        }
        .onChange(of: progress) { _, new in withAnimation(.smooth(duration: 0.6)) { shown = new } }
        .accessibilityHidden(true)
    }
}

/* ── Stat tiles ─────────────────────────────────────────────────────────── */

struct Stat: Hashable {
    var label: String
    var value: String
    var chip: String?
    var chipTone: DeltaChip.Tone = .neutral
    var caption: String?
}

/// 2 × 2 cards; one column at accessibility sizes.
struct StatGrid: View {
    var stats: [Stat]
    @Environment(\.dynamicTypeSize) private var type

    var body: some View {
        let columns = type.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(stats, id: \.self) { s in
                Card(padding: 16) {
                    Text(s.label).micro()
                    HStack(alignment: .center, spacing: 8) {
                        Text(s.value).font(.num(32, relativeTo: .largeTitle)).foregroundStyle(Palette.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText())
                        if let chip = s.chip { DeltaChip(text: chip, tone: s.chipTone) }
                    }
                    .padding(.top, 6)
                    if let caption = s.caption {
                        Text(caption).font(.sans(12)).foregroundStyle(Palette.secondary).padding(.top, 6).lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// r2 KPIs, drawn as stat tiles.
struct KpiGrid: View {
    var kpis: [Metrics.Kpi]
    var body: some View {
        StatGrid(stats: kpis.map { Stat(label: $0.label.sentenceCased, value: $0.value, caption: $0.caption.isEmpty ? nil : $0.caption) })
    }
}

/* ── Charts ─────────────────────────────────────────────────────────────── */

struct PyramidView: View {
    @Environment(\.accent) private var accent
    var rows: [Metrics.PyramidRow]
    var barHeight: CGFloat = 22
    var showCounts = true

    var body: some View {
        // "6c+" and "V10" need more room than the spine's two digits
        let wide = rows.contains { $0.label.count > 2 }
        VStack(spacing: barHeight > 14 ? 8 : 4) {
            ForEach(rows, id: \.grade) { r in
                HStack(spacing: 10) {
                    Text(r.label).font(.num(barHeight > 14 ? 14 : 11)).foregroundStyle(Palette.text).lineLimit(1).fixedSize()
                        .frame(width: (barHeight > 14 ? 24 : 16) + (wide ? 12 : 0), alignment: .trailing)
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Palette.track)
                            Rectangle().fill(accent.color.opacity(0.4)).frame(width: g.size.width * r.width)
                            Rectangle().fill(accent.color).frame(width: g.size.width * r.width * r.flashShare)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: barHeight > 14 ? 6 : 3, style: .continuous))
                    }
                    .frame(height: barHeight)
                    if showCounts {
                        Text("\(r.count)").font(.num(13)).foregroundStyle(Palette.secondary).frame(width: 26, alignment: .leading)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Grade \(r.label): \(r.count) sends, \(r.flashed) flashed")
            }
        }
    }
}

struct PyramidLegend: View {
    @Environment(\.accent) private var accent
    var body: some View {
        HStack(spacing: 10) {
            legend(accent.color, "Flashed")
            legend(accent.color.opacity(0.4), "Worked")
        }
    }
    func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 8, height: 8)
            Text(t).font(.sans(12)).foregroundStyle(Palette.secondary)
        }
    }
}

/// Camp5 — ranked, not numbered. Counts and codes only.
struct TallyView: View {
    var bars: [Metrics.TagBar]
    var height: CGFloat = 96

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(bars, id: \.tagId) { b in
                VStack(spacing: 6) {
                    Text("\(b.count)").font(.num(12)).foregroundStyle(b.count > 0 ? Palette.secondary : Palette.tertiary)
                    RoundedRectangle(cornerRadius: b.count == 0 ? 2 : 6, style: .continuous)
                        .fill(b.count == 0 ? Palette.track : Palette.hold(b.tagId))
                        .frame(height: b.count == 0 ? 4 : max(8, b.height * height))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Palette.hairlineStrong, lineWidth: b.count > 0 && Palette.needsHairline(b.tagId) ? 1 : 0))
                    Text(Vocab.colourCode(b.tagId)).font(.sans(11, .semibold)).foregroundStyle(b.count == 0 ? Palette.tertiary : Palette.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(Vocab.colourLabel(b.tagId)) tag: \(b.count)")
            }
        }
    }
}

/// One board and angle, as a row inside a card.
struct BoardCard: View {
    var b: Metrics.BoardSummary

    var body: some View {
        let up = b.prevMaxV != nil && b.maxV != nil && b.maxV! > b.prevMaxV!
        HStack(spacing: 14) {
            Text(b.code).font(.sans(13, .bold)).foregroundStyle(Palette.text)
                .frame(width: 40, height: 40).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.track))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(b.name) \(b.angle)°").font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                Text("\(b.sends) sends").font(.sans(13)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if up { DeltaChip(text: "+\(b.maxV! - b.prevMaxV!)") } else { DeltaChip(text: "Flat", tone: .quiet) }
            Text("V\(b.maxV ?? 0)").font(.num(22)).foregroundStyle(Palette.text)
        }
        .padding(.vertical, 8)
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
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(fromEnd < fullCount ? Palette.injury : fromEnd == fullCount ? Palette.injuryMid : Palette.injurySoft)
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
        VStack(spacing: 12) {
            ForEach(rows, id: \.label) { r in
                HStack(spacing: 10) {
                    Text(r.label).font(.sans(14)).foregroundStyle(Palette.text).frame(width: 124, alignment: .leading)
                    Meter(pct: Double(r.score), warn: r.warn)
                    Text("\(r.score)").font(.num(13)).foregroundStyle(r.warn ? Palette.cautionText : Palette.text).frame(width: 30, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Style × grade heatmap. Fill is the accent at alpha 0.07 + pct × 0.78.
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
                    Text(row.style).font(.sans(13, .medium)).foregroundStyle(row.weak ? Palette.cautionText : Palette.text)
                    HStack(spacing: 4) {
                        ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                            VStack(spacing: 3) {
                                Text(cell.band).font(.sans(11)).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.6)
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
                Color.clear.frame(width: 92, height: 12)
                ForEach(rows.first?.cells.map(\.band) ?? Vocab.gradeBands.map(\.label), id: \.self) { band in
                    Text(band).font(.sans(11)).foregroundStyle(Palette.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(rows, id: \.style) { row in
                GridRow {
                    Text(row.style).font(.sans(13)).foregroundStyle(row.weak ? Palette.cautionText : Palette.text)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 92, alignment: .leading)
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
                .font(.sans(11, .semibold)).monospacedDigit()
                .foregroundStyle(gap ? Palette.cautionText : alpha >= 0.5 ? accent.onAccent : Palette.text)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(gap ? Palette.cautionBg : accent.color.opacity(alpha)))
                .accessibilityLabel("\(cell.band): \(pct) percent sent, \(cell.attempts) logged")
        } else {
            Text("–").font(.sans(11)).foregroundStyle(Palette.tertiary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.raised))
                .accessibilityLabel("\(cell.band): nothing attempted")
        }
    }
}

/// "How sessions felt": one row per chip, one dot per recent session. Chips that name a problem go amber.
struct ChipTrendPanel: View {
    @Environment(\.accent) private var accent
    var rows: [Metrics.ChipTrendRow]
    var pattern: String?
    var window = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHead("How sessions felt", note: "Last \(window)")
            if rows.isEmpty {
                Text("Save a few reviews to see trends.").font(.sans(14)).foregroundStyle(Palette.secondary)
            }
            VStack(spacing: 12) {
                ForEach(rows, id: \.chip) { r in
                    let bad = Metrics.watchChips.contains(r.chip)
                    HStack(spacing: 10) {
                        Text(r.chip).font(.sans(14)).foregroundStyle(Palette.text).lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: 118, alignment: .leading)
                        HStack(spacing: 0) {
                            ForEach(Array(r.cells.enumerated()), id: \.offset) { i, on in
                                Circle().fill(on ? (bad ? Palette.caution : accent.color) : Palette.track).frame(width: 11, height: 11)
                                if i < r.cells.count - 1 { Spacer(minLength: 2) }
                            }
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(r.chip): \(r.count) of the last \(window) sessions")
                }
            }
            if let pattern {
                Insight(label: nil, text: pattern)
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
                    RoundedRectangle(cornerRadius: b.count == 0 ? 2 : 4, style: .continuous)
                        .fill(b.count == 0 ? Palette.track : b.isMax ? accent.color : accent.color.opacity(0.4))
                        .frame(height: b.count == 0 ? 4 : max(8, b.height * 52))
                    Text("V\(b.v)").font(.sans(11, b.isMax ? .semibold : .regular)).foregroundStyle(b.count == 0 ? Palette.tertiary : b.isMax ? Palette.text : Palette.secondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("V\(b.v): \(b.count) sends")
            }
        }
        .frame(height: 76, alignment: .bottom)
    }
}

struct AdherenceStrip: View {
    @Environment(\.accent) private var accent
    var done: [Bool]
    var height: CGFloat = 10

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(done.enumerated()), id: \.offset) { _, d in
                Capsule().fill(d ? Palette.injury : Palette.track).frame(height: height)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done.filter { $0 }.count) of \(done.count) days done")
    }
}

/// Session row: date block, gym, "intent, N sends, high X", review score.
struct LedgerRow: View {
    @Environment(\.accent) private var accent
    var session: Session
    var db: Database
    var showDivider = true

    var body: some View {
        let sends = Metrics.sessionSends(db.climbs, sessionId: session.id)
        let boards = Set(db.climbs.filter { $0.sessionId == session.id }.compactMap(\.boardId)).compactMap { db.board($0)?.name }.sorted()
        let review = db.review(for: session.id)
        let live = session.status == .active
        let place = db.gym(session.gymId)?.name ?? boards.first ?? "Session"
        let detail = [session.intent, "\(sends.count) send\(sends.count == 1 ? "" : "s")", sends.isEmpty ? nil : "high \(LiveSummary.high(sends, db: db, sessionGym: session.gymId))"]
            .compactMap { $0 }.joined(separator: ", ")
        HStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("\(Day.dayOfMonth(session.date))").font(.num(20)).foregroundStyle(Palette.text)
                Text(Day.weekday(session.date).prefix(1) + Day.weekday(session.date).dropFirst().lowercased())
                    .font(.sans(11)).foregroundStyle(Palette.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(place).font(.sans(16, .semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    if live {
                        Text("Live").font(.sans(11, .bold)).foregroundStyle(accent.onAccent)
                            .padding(.horizontal, 6).frame(height: 18).background(Capsule().fill(accent.color))
                    }
                }
                Text(detail).font(.sans(13)).foregroundStyle(Palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let review {
                Text(String(format: "%.1f", review.overallScore)).font(.num(17)).foregroundStyle(Palette.text)
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.tertiary)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { if showDivider { Hairline() } }
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
    var scale: CGFloat = 1
    var onSelect: (String?) -> Void

    var body: some View {
        VStack(spacing: 5 * scale) {
            part("head", w: 30, h: 30, r: 15)
            HStack(alignment: .top, spacing: 5 * scale) {
                limb("l")
                part("torso", w: 54, h: 80, r: 14)
                limb("r")
            }
            HStack(spacing: 6 * scale) {
                part("l-leg", w: 20, h: 66, r: 10)
                part("r-leg", w: 20, h: 66, r: 10)
            }
            .padding(.top, 2)
        }
    }

    func limb(_ side: String) -> some View {
        VStack(spacing: 3 * scale) {
            part("\(side)-shoulder", w: 13, h: 13, r: 6.5)
            part("\(side)-elbow", w: 12, h: 46, r: 6)
            part("\(side)-hand", w: 17, h: 16, r: 6)
        }
        .padding(.top, 4)
    }

    func part(_ id: String, w: CGFloat, h: CGFloat, r: CGFloat) -> some View {
        let s = status[id] ?? .clear
        let sel = selected == id
        let fill: Color = switch s {
        case .active: Palette.injury
        case .watching: Palette.caution
        case .clear: Palette.track
        }
        return Button { onSelect(sel ? nil : id) } label: {
            RoundedRectangle(cornerRadius: r * scale, style: .continuous).fill(fill)
                .overlay(RoundedRectangle(cornerRadius: r * scale, style: .continuous).strokeBorder(Palette.text, lineWidth: sel ? 2 : 0))
                .frame(width: w * scale, height: h * scale)
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Vocab.bodyPartLabel(id))
        .accessibilityValue(s == .active ? "active injury" : s == .watching ? "watching" : "clear")
        .accessibilityAddTraits(sel ? .isSelected : [])
    }
}
