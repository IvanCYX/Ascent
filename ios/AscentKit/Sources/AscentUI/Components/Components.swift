import SwiftUI
import AscentCore

/* ── Layout ─────────────────────────────────────────────────────────────── */

/// A rounded content card on the ground (DESIGN §7.4): radius 22, padding 18.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    var fill: Color = Palette.surface
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(fill))
    }
}

/// A content section: a card with the 16 pt gutter, 12 pt above. (r2's hairline band, now a card.)
struct Band<Content: View>: View {
    var top = true
    var bottomPadding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        Card { content }
            .padding(.horizontal, 16)
            .padding(.top, 12)
    }
}

struct Hairline: View {
    var color: Color = Palette.hairline
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// Card title on the left, a secondary note on the right.
struct SectionHead<Trailing: View>: View {
    var title: String
    var size: CGFloat = 17
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.sans(17, .semibold)).foregroundStyle(Palette.text)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.bottom, 14)
    }
}

extension SectionHead where Trailing == AnyView {
    init(_ title: String, note: String? = nil, noteColor: Color = Palette.secondary, size: CGFloat = 17) {
        self.title = title
        self.size = size
        self.trailing = AnyView(Group {
            if let note { Text(note).note(noteColor).multilineTextAlignment(.trailing) }
        })
    }
}

/// The screen's one insight, in a tinted row.
struct Insight: View {
    var label: String?
    var text: String
    var color: Color = Palette.text

    var body: some View {
        Text("\(Text(label.map { "\($0) " } ?? "").font(.sans(14, .semibold)))\(Text(text).font(.sans(14)))")
            .foregroundStyle(color)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.raised))
            .padding(.top, 14)
    }
}

/// Red inline row — never a modal.
struct WarnPanel: View {
    var lead: String
    var text: String
    var tone: Tone = .injury

    enum Tone { case injury, caution }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(tone == .injury ? Palette.injury : Palette.caution).frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text("\(Text("\(lead): ").font(.sans(13, .semibold)))\(Text(text).font(.sans(13)))")
                .foregroundStyle(tone == .injury ? Palette.injuryText : Palette.cautionText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tone == .injury ? Palette.injuryBg : Palette.cautionBg))
    }
}

/// `+1`, `−0.3`, `Flat` (DESIGN §0 copy rules).
struct DeltaChip: View {
    enum Tone { case neutral, caution, quiet }
    var text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.sans(12, .semibold)).monospacedDigit()
            .foregroundStyle(tone == .caution ? Palette.cautionText : tone == .quiet ? Palette.secondary : Palette.text)
            .padding(.horizontal, 7).frame(minHeight: 20)
            .background(Capsule().fill(tone == .caution ? Palette.cautionBg : Palette.text.opacity(tone == .quiet ? 0.06 : 0.12)))
    }
}

/* ── Chips & selection ──────────────────────────────────────────────────── */

struct Chip: View {
    enum Kind { case normal, pain, dashed }
    @Environment(\.accent) private var accent
    var label: String
    var on = false
    var small = false
    var kind: Kind = .normal
    var blocked = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.sans(small ? 14 : 15, on ? .semibold : .medium))
                .strikethrough(blocked)
                .lineLimit(1)
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: small ? 36 : 40)
                .background(Capsule().fill(background))
                .overlay(Capsule().strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .opacity(kind == .dashed ? 1 : 0))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var foreground: Color {
        if blocked { return Palette.tertiary }
        switch kind {
        case .pain: return on ? .white : Palette.injuryText
        case .dashed: return Palette.secondary
        case .normal: return on ? accent.onAccent : Palette.text
        }
    }

    private var background: Color {
        if kind == .dashed { return .clear }
        if blocked { return Palette.raised }
        switch kind {
        case .pain: return on ? Palette.injury : Palette.injuryBg
        default: return on ? accent.color : Palette.raised
        }
    }
}

/// Wrapping row of chips.
struct ChipFlow<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content
    var body: some View {
        FlowLayout(spacing: spacing) { content }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

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

/// The rounded segmented control (`8 weeks | 6 months | Season`, `Gym | Board`…).
struct SquareSegment<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, label in
                let on = value == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = value } } label: {
                    Text(label)
                        .font(.sans(14, on ? .semibold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .foregroundStyle(on ? Palette.text : Palette.secondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Palette.segment : .clear)
                            .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 2, y: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.raised))
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/* ── Buttons ────────────────────────────────────────────────────────────── */

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var enabled
    var height: CGFloat = 52

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(16, .semibold, relativeTo: .headline))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(enabled ? accent.onAccent : Palette.tertiary)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 14)
            .background(Capsule().fill(enabled ? accent.color : Palette.raised))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var dashed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.sans(16, .semibold, relativeTo: .headline))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 14)
            .background(Capsule().fill(dashed ? .clear : Palette.raised))
            .overlay(Capsule().strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 3])).opacity(dashed ? 1 : 0))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// A plain text action in the accent.
struct LinkButton: View {
    @Environment(\.accent) private var accent
    var title: String
    var color: Color?
    var size: CGFloat = 14
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.sans(size, .semibold)).foregroundStyle(color ?? accent.color)
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
            Text(label.sentenceCased).font(.sans(14)).foregroundStyle(Palette.secondary)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.raised))
    }
}

struct TextFieldRow: View {
    var label: String
    var placeholder: String
    @Binding var text: String

    var body: some View {
        FieldRow(label: label) {
            TextField(placeholder, text: $text)
                .font(.sans(15))
                .foregroundStyle(Palette.text)
                .textFieldStyle(.plain)
        }
    }
}

struct NoteBox: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(.sans(15))
            .foregroundStyle(Palette.text)
            .lineLimit(3...8)
            .textFieldStyle(.plain)
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(minHeight: 64, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.raised))
    }
}

/// − value + stepper.
struct SquareStepper: View {
    var value: String
    var decrement: () -> Void
    var increment: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            StepButton(systemName: "minus", label: "Decrease", action: decrement)
            Text(value).font(.num(18)).foregroundStyle(Palette.text).frame(minWidth: 40)
                .contentTransition(.numericText())
            StepButton(systemName: "plus", label: "Increase", action: increment)
        }
    }
}

struct StepButton: View {
    var systemName: String
    var label: String
    var size: CGFloat = 40
    var fill: Color = Palette.surface
    var disabled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 15, weight: .bold))
                .foregroundStyle(disabled ? Palette.tertiary : Palette.text)
                .frame(width: size, height: size)
                .background(Circle().fill(fill))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

/* ── Small data marks ───────────────────────────────────────────────────── */

struct Meter: View {
    @Environment(\.accent) private var accent
    var pct: Double
    var warn = false
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.track)
                Capsule().fill(warn ? Palette.caution : accent.color)
                    .frame(width: max(height, g.size.width * min(1, max(0, pct / 100))))
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
                Capsule().fill(Palette.track).frame(height: 8)
                Capsule().fill(accent.color).frame(width: max(8, g.size.width * min(1, max(0, fill))), height: 8)
                Capsule().fill(Palette.text).frame(width: 3, height: 16)
                    .offset(x: min(g.size.width - 3, g.size.width * tick))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
        .padding(.top, 8)
    }
}

/// A hold/tag colour dot. Black and white get an inner hairline.
struct Swatch: View {
    var colour: String?
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(colour == nil ? Palette.track : Palette.hold(colour))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Palette.hairlineStrong, lineWidth: Palette.needsHairline(colour) || colour == nil ? 1 : 0))
            .accessibilityLabel(Vocab.colourLabel(colour))
    }
}

/// Top grades — Camp5 never shows numbers.
struct TopGradesView: View {
    var top: Metrics.TopGrades

    var body: some View {
        switch top {
        case .tag(let tags):
            HStack(spacing: 5) {
                ForEach(tags, id: \.self) { Swatch(colour: $0, size: 12) }
                Text(tags.map(Vocab.colourLabel).joined(separator: ", ")).font(.sans(13)).foregroundStyle(Palette.secondary)
            }
        case .number(let xs):
            gradeChips(xs.map(String.init))
        case .v(let xs):
            gradeChips(xs)
        }
    }

    func gradeChips(_ values: [String]) -> some View {
        HStack(spacing: 4) {
            if values.isEmpty { Text("–").font(.sans(13)).foregroundStyle(Palette.tertiary) }
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                Text(v).font(.num(12))
                    .foregroundStyle(i == 0 ? Palette.text : Palette.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.raised))
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
            Image(systemName: systemName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }
}

/// The toast: `Logged 11, Flash   Undo`
struct ToastView: View {
    @Environment(\.accent) private var accent
    var toast: Toast
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("\(Text(toast.title).font(.sans(15, .semibold)))\(Text(toast.detail.isEmpty ? "" : ", \(toast.detail)").font(.sans(15)))")
                .lineLimit(1)
            if let undo = toast.undo {
                Button { undo(); dismiss() } label: {
                    Text("Undo").font(.sans(14, .semibold)).foregroundStyle(Palette.text)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(Capsule().fill(Palette.text.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Palette.text)
        .padding(.leading, 18).padding(.trailing, toast.undo == nil ? 18 : 7)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/* ── Formatting ─────────────────────────────────────────────────────────── */

func climbDetail(_ c: Climb) -> String {
    [Vocab.attemptsLabel(c), c.styles.isEmpty ? nil : c.styles.joined(separator: ", "), c.location]
        .compactMap { $0 }.joined(separator: ", ")
}

func boardDetail(_ c: Climb) -> String {
    [Vocab.attemptsLabel(c), c.angle.map { "\($0)°" }, c.name].compactMap { $0 }.joined(separator: ", ")
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

extension String {
    /// "PHYSIO NEXT" → "Physio next"; mixed-case strings are left alone.
    var sentenceCased: String {
        guard self == uppercased(), contains(where: \.isLetter) else { return self }
        let lower = lowercased()
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }
}
