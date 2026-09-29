import SwiftUI
import AscentCore

/* ── Layout ─────────────────────────────────────────────────────────────── */

/// A content band: 16 pt gutter, 20 pt vertical padding, hairline on top.
struct Band<Content: View>: View {
    var top = true
    var bottomPadding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, bottomPadding)
            .overlay(alignment: .top) { if top { Hairline() } }
    }
}

struct Hairline: View {
    var color: Color = Palette.rule
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// Newsreader title on the left, mono caps note on the right.
struct SectionHead<Trailing: View>: View {
    var title: String
    var size: CGFloat = 21
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.serif(size, relativeTo: .title3)).foregroundStyle(Palette.ink)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 14)
    }
}

extension SectionHead where Trailing == AnyView {
    init(_ title: String, note: String? = nil, noteColor: Color = Palette.muted, size: CGFloat = 21) {
        self.title = title
        self.size = size
        self.trailing = AnyView(Group {
            if let note { Text(note).note(noteColor).multilineTextAlignment(.trailing) }
        })
    }
}

/// "Read:" / "Comp prep:" / "Pattern:" lines.
struct Insight: View {
    var label: String?
    var text: String
    var color: Color = Palette.muted

    var body: some View {
        Text("\(Text(label.map { "\($0) " } ?? "").font(.sans(13, .semibold)).foregroundStyle(color == Palette.muted ? Palette.ink : color))\(Text(text).font(.sans(13)).foregroundStyle(color))")
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 14)
    }
}

/// Red inline panel — never a modal.
struct WarnPanel: View {
    var lead: String
    var text: String

    var body: some View {
        Text("\(Text("\(lead) · ").font(.sans(13, .semibold)).foregroundStyle(Palette.warn))\(Text(text).font(.sans(13)).foregroundStyle(Palette.muted))")
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Palette.warnBg)
            .overlay(Rectangle().strokeBorder(Palette.warnBorder, lineWidth: 1))
    }
}

/* ── Chips & selection ──────────────────────────────────────────────────── */

struct Chip: View {
    enum Kind { case normal, pain, dashed }
    var label: String
    var on = false
    var small = false
    var kind: Kind = .normal
    var blocked = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.sans(small ? 13 : 14, .medium))
                .strikethrough(blocked)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, small ? 12 : 14)
                .frame(minHeight: small ? 36 : 40)
                .background(background)
                .overlay(Rectangle().strokeBorder(border, style: StrokeStyle(lineWidth: 1, dash: kind == .dashed ? [4, 3] : [])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var foreground: Color {
        if blocked { return Palette.faint }
        switch kind {
        case .pain: return on ? .white : Palette.warn
        default: return on ? Palette.paper : Palette.ink
        }
    }

    private var background: Color {
        if kind == .dashed { return .clear }
        if on { return kind == .pain ? Palette.warn : Palette.ink }
        return Palette.card
    }

    private var border: Color {
        if blocked { return Palette.rule }
        switch kind {
        case .pain: return on ? Palette.warn : Palette.warnBorder
        case .dashed: return Palette.ruleStrong
        case .normal: return on ? Palette.ink : Palette.ruleChip
        }
    }
}

/// Wrapping row of chips.
struct ChipFlow<Content: View>: View {
    var spacing: CGFloat = 6
    @ViewBuilder var content: Content
    var body: some View {
        FlowLayout(spacing: spacing) { content }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowH = max(rowH, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}

/// Square segmented control on the paper layer (`8 weeks | 6 months | Season`, `Gym | Board`…).
struct SquareSegment<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button { selection = value } label: {
                    Text(label)
                        .font(.sans(13, .medium))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Palette.paper : Palette.muted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(on ? Palette.ink : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.track)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/* ── Buttons ────────────────────────────────────────────────────────────── */

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var enabled
    var height: CGFloat = 50

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(15, .semibold, relativeTo: .headline))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(enabled ? accent.onAccent : Palette.faint)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 12)
            .background(enabled ? accent.color : Palette.track)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 50
    var dashed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(15, .semibold, relativeTo: .headline))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 12)
            .overlay(Rectangle().strokeBorder(Palette.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 3] : [])))
            .background(configuration.isPressed ? Palette.track : .clear)
            .contentShape(Rectangle())
    }
}

/// Underlined accent link.
struct LinkButton: View {
    @Environment(\.accent) private var accent
    var title: String
    var color: Color?
    var size: CGFloat = 13
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.sans(size, .medium)).underline().foregroundStyle(color ?? accent.color)
                .frame(minHeight: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/* ── Fields ─────────────────────────────────────────────────────────────── */

struct FieldRow<Trailing: View>: View {
    var label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text(label).font(.mono(11)).tracking(0.66).foregroundStyle(Palette.muted)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Palette.card)
        .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
    }
}

struct TextFieldRow: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        FieldRow(label: label) {
            TextField(placeholder, text: $text)
                .font(.sans(14))
                .foregroundStyle(Palette.ink)
                .textFieldStyle(.plain)
        }
    }
}

/// Dashed note box.
struct NoteBox: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.sans(13.5))
            .foregroundStyle(Palette.ink)
            .lineLimit(3...8)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(minHeight: 64, alignment: .topLeading)
            .overlay(Rectangle().strokeBorder(Palette.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
    }
}

/// − value + stepper as two square buttons.
struct SquareStepper: View {
    var value: String
    var decrement: () -> Void
    var increment: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text(value).font(.serif(20)).foregroundStyle(Palette.ink).monospacedDigit()
            HStack(spacing: 2) {
                ForEach([("−", decrement), ("+", increment)], id: \.0) { label, action in
                    Button(action: action) {
                        Text(label).font(.sans(17, .medium)).foregroundStyle(Palette.ink)
                            .frame(width: 46, height: 36).background(Palette.track).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label == "+" ? "Increase" : "Decrease")
                }
            }
        }
    }
}

/* ── Small data marks ───────────────────────────────────────────────────── */

struct Meter: View {
    @Environment(\.accent) private var accent
    var pct: Double
    var warn = false
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.track)
                Rectangle().fill(warn ? Palette.warn : accent.color)
                    .frame(width: g.size.width * min(1, max(0, pct / 100)))
            }
        }
        .frame(height: height)
    }
}

/// Fill = share, tick = 100 % (the 8-week average).
struct LoadBar: View {
    @Environment(\.accent) private var accent
    var fill: Double
    var tick: Double = 1

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Palette.track).frame(height: 6)
                Rectangle().fill(accent.color).frame(width: g.size.width * min(1, max(0, fill)), height: 6)
                Rectangle().fill(Palette.ink).frame(width: 1.5, height: 12)
                    .offset(x: min(g.size.width - 1.5, g.size.width * tick))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 12)
        .padding(.top, 5)
    }
}

/// A hold/tag colour square. Black and white get an inner hairline.
struct Swatch: View {
    var colour: String?
    var size: CGFloat = 15

    var body: some View {
        Rectangle()
            .fill(colour == nil ? Palette.track : Palette.hold(colour))
            .frame(width: size, height: size)
            .overlay(Rectangle().strokeBorder(Palette.ruleStrong, lineWidth: Palette.needsHairline(colour) || colour == nil ? 1 : 0))
            .accessibilityLabel(Vocab.colourLabel(colour))
    }
}

/// Top grades cell — Camp5 never shows numbers.
struct TopGradesView: View {
    var top: Metrics.TopGrades

    var body: some View {
        switch top {
        case .tag(let tags):
            HStack(spacing: 4) {
                ForEach(tags, id: \.self) { Swatch(colour: $0, size: 14) }
                Text(tags.map(Vocab.colourCode).joined(separator: " · ")).font(.mono(10.5)).foregroundStyle(Palette.muted)
            }
        case .number(let xs):
            gradeChips(xs.map(String.init))
        case .v(let xs):
            gradeChips(xs)
        }
    }

    func gradeChips(_ values: [String]) -> some View {
        HStack(spacing: 4) {
            if values.isEmpty { Text("—").font(.mono(10)).foregroundStyle(Palette.faint) }
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                Text(v).font(.mono(10.5, .medium))
                    .foregroundStyle(i == 0 ? Palette.paper : Palette.ink)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(i == 0 ? Palette.ink : Palette.track)
            }
        }
    }
}

/* ── Glass controls (control layer) ─────────────────────────────────────── */

/// 44 pt glass circle — close, back, more.
struct GlassIconButton: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// The glass toast: `✓ Sent · 12 blue · 3 tries   Undo`
struct ToastView: View {
    @Environment(\.accent) private var accent
    var toast: Toast
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold))
            Text("\(Text(toast.title).font(.sans(14, .semibold)))\(Text(toast.detail.isEmpty ? "" : " · \(toast.detail)").font(.sans(14, .medium)))")
                .lineLimit(1)
            if let undo = toast.undo {
                Button("Undo") { undo(); dismiss() }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent.color)
                    .padding(.horizontal, 6)
            }
        }
        .foregroundStyle(Palette.ink)
        .padding(.leading, 18).padding(.trailing, toast.undo == nil ? 18 : 8)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/* ── Formatting ─────────────────────────────────────────────────────────── */

func climbDetail(_ c: Climb) -> String {
    [c.styles.isEmpty ? nil : c.styles.joined(separator: " + "),
     c.tickType == .flash ? "flash" : "\(c.attempts) tries",
     c.location].compactMap { $0 }.joined(separator: " · ")
}

func boardDetail(_ c: Climb) -> String {
    [c.name, c.angle.map { "\($0)°" }, c.tickType == .flash ? "flash" : "\(c.attempts) tries"]
        .compactMap { $0 }.joined(separator: " · ")
}

func gradeLabel(_ c: Climb) -> String {
    switch c.gradeKind {
    case .tag: ""
    case .v: "V\(c.grade)"
    case .number: "\(c.grade)"
    }
}

/// "1h 12m" → "1 hour 12 minutes" for VoiceOver
func spokenDuration(from start: Date, now: Date = .now) -> String {
    let mins = max(0, Int(now.timeIntervalSince(start) / 60))
    let h = mins / 60, m = mins % 60
    return [h > 0 ? "\(h) hour\(h == 1 ? "" : "s")" : nil, "\(m) minute\(m == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: " ")
}
