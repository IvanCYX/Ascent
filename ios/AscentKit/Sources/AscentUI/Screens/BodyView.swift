import SwiftUI
import AscentCore

/// Web `1k` — injury & rehab (DESIGN §3.8).
struct BodyView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @State private var filter: String?

    var body: some View {
        let db = store.db
        let visible = db.injuries.filter { $0.status != .resolved }.filter { filter == nil || $0.bodyPart == filter }
        let active = visible.filter { $0.status == .active }
        let watching = visible.filter { $0.status == .watching }
        let shown = active.isEmpty ? visible : active
        let resolved = db.injuries.filter { $0.status == .resolved }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Card {
                    HStack(alignment: .center, spacing: 18) {
                        BodyMapView(status: bodyStatus(db), selected: filter) { filter = $0 }
                            .frame(width: 120)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(db.activeInjuries) { legend(Palette.injury, shortInjury($0.name), bold: true) }
                            ForEach(db.watchingInjuries) { legend(Palette.caution, shortInjury($0.name), bold: false) }
                            if db.activeInjuries.isEmpty && db.watchingInjuries.isEmpty {
                                Text("Nothing logged").font(.sans(14)).foregroundStyle(Palette.secondary)
                            }
                            if filter != nil { LinkButton(title: "Clear filter") { filter = nil } }
                            else { Text("Tap an area to filter").font(.sans(12)).foregroundStyle(Palette.secondary) }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 4)

                if shown.isEmpty {
                    Text("Nothing logged here.")
                        .font(.sans(14)).foregroundStyle(Palette.secondary).padding(20)
                }

                ForEach(shown) { inj in InjuryDetail(injury: inj) }

                if !watching.isEmpty && !active.isEmpty && filter == nil {
                    Band {
                        SectionHead("Watching")
                        ForEach(Array(watching.enumerated()), id: \.element.id) { i, w in
                            HStack(spacing: 12) {
                                Circle().fill(Palette.caution).frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.name).font(.sans(15, .medium)).foregroundStyle(Palette.text)
                                    Text("Since \(Day.pretty(w.onsetDate))").font(.sans(13)).foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                                LinkButton(title: "Escalate") {
                                    store.updateInjury(w.id) { $0.status = .active; $0.rehabStart = store.today }
                                }
                            }
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) { if i < watching.count - 1 { Hairline() } }
                        }
                    }
                }

                if !resolved.isEmpty && filter == nil {
                    Band {
                        SectionHead("Resolved")
                        ForEach(resolved) { r in
                            HStack {
                                Text(r.name).font(.sans(14)).foregroundStyle(Palette.secondary)
                                Spacer()
                                LinkButton(title: "Reopen") { store.updateInjury(r.id) { $0.status = .watching } }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 96)
        }
        .background(Palette.ground)
        .navigationTitle("Body")
        .navigationSubtitle("\(db.activeInjuries.count) active, \(db.watchingInjuries.count) watching")
        .largeTitle()
        .toolbar {
            ToolbarItem(placement: .trailing) { Button("Log new") { router.sheet = .newInjury } }
        }
    }

    func legend(_ c: Color, _ label: String, bold: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(c).frame(width: 10, height: 10)
            Text(label).font(.sans(14, bold ? .semibold : .regular)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    func bodyStatus(_ db: Database) -> [String: BodyMapView.Status] {
        var map: [String: BodyMapView.Status] = [:]
        for inj in db.injuries where inj.status != .resolved {
            if inj.status == .active || map[inj.bodyPart] != .active {
                map[inj.bodyPart] = inj.status == .active ? .active : .watching
            }
        }
        return map
    }
}

struct InjuryDetail: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accent) private var accent
    var injury: Injury

    var body: some View {
        let db = store.db
        let today = store.today
        let pain = db.painEntries.filter { $0.injuryId == injury.id }.sorted { $0.date < $1.date }.suffix(12)
        let todayLevel = db.painEntries.first { $0.injuryId == injury.id && $0.date == today }?.level
        let exercises = db.rehabExercises.filter { $0.injuryId == injury.id }
        let adh = Metrics.rehabAdherence(exercises, logs: db.rehabLogs, today: today)
        let rehabWeek = injury.rehabStart.map { max(1, Day.weeksBetween($0, today) + 1) }
        let rules = db.loadRules.filter { $0.injuryId == injury.id }
        let usage = Metrics.loadRuleUsage(rules.filter { $0.maxPerWeek != nil }, climbs: db.climbs, weekStart: Day.weekStart(today))

        VStack(alignment: .leading, spacing: 0) {
            Card {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shortInjury(injury.name).replacingOccurrences(of: "L ", with: "Left ").replacingOccurrences(of: "R ", with: "Right "))
                            .font(.sans(20, .bold)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        Text([injury.name.components(separatedBy: " · ").dropFirst().first, rehabWeek.map { "rehab week \($0)" }]
                                .compactMap { $0 }.joined(separator: ", ").ifEmpty("Since \(Day.pretty(injury.onsetDate))"))
                            .font(.sans(14)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Menu {
                        Button(injury.status == .active ? "Downgrade to watching" : injury.status == .watching ? "Resolve" : "Reopen") {
                            store.updateInjury(injury.id) {
                                $0.status = injury.status == .active ? .watching : injury.status == .watching ? .resolved : .active
                            }
                        }
                        if injury.status == .active {
                            Button("Resolve") { store.updateInjury(injury.id) { $0.status = .resolved } }
                        }
                        Button("Edit") { router.sheet = .editInjury(injury.id) }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.text)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Palette.raised))
                            .frame(width: 44, height: 44)
                    }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Injury actions")
                }
                if let severity = injury.severity ?? injury.diagnosis {
                    Text([injury.severity, injury.diagnosis].compactMap { $0 }.joined(separator: ", ").ifEmpty(severity))
                        .font(.sans(13)).foregroundStyle(Palette.secondary).padding(.top, 6)
                }

                if let last = pain.last {
                    HStack(alignment: .center, spacing: 8) {
                        Text("\(last.level)\(Text("/10").font(.num(20)).foregroundStyle(Palette.secondary))").font(.num(40, relativeTo: .largeTitle))
                            .foregroundStyle(Palette.text)
                        if let first = pain.first, first.id != last.id, first.level != last.level {
                            let d = last.level - first.level
                            DeltaChip(text: "\(d > 0 ? "+" : "−")\(abs(d)) since \(Day.pretty(first.date))", tone: d > 0 ? .caution : .neutral)
                        }
                    }
                    .padding(.top, 16)
                    PainBars(levels: pain.map(\.level), height: 64, fullCount: 2).padding(.top, 14)
                } else {
                    Text("No pain logged yet").font(.sans(14)).foregroundStyle(Palette.secondary).padding(.top, 16)
                }

                Text("Pain today").font(.sans(15, .semibold)).foregroundStyle(Palette.text).padding(.top, 18).padding(.bottom, 10)
                PainRow(selected: todayLevel) { store.addPainEntry(injuryId: injury.id, level: $0) }
            }
            .padding(.horizontal, 16)

            Band(top: false) {
                SectionHead("Rehab today", note: exercises.isEmpty ? nil : "\(Metrics.rehabAdherence(exercises, logs: db.rehabLogs, window: 7, today: today).doneDays) of 7 this week")
                ForEach(exercises) { e in
                    RehabRow(exercise: e)
                        .swipeToDelete { store.deleteRehabExercise(e.id) }
                }
                if exercises.isEmpty { Text("No exercises yet.").font(.sans(14)).foregroundStyle(Palette.secondary) }
                if adh.streak > 0 {
                    Text("\(adh.streak)-day streak").font(.sans(13)).foregroundStyle(Palette.secondary).padding(.top, 4)
                }
                LinkButton(title: "Add exercise") { router.sheet = .addExercise(injuryId: injury.id) }.padding(.top, 4)
            }

            Band {
                SectionHead("Load rules")
                ForEach(rules) { r in
                    LoadRuleCard(rule: r, usage: usage.first { $0.ruleId == r.id }) { store.deleteLoadRule(r.id) }
                }
                LinkButton(title: "Add load rule") { router.sheet = .addLoadRule(injuryId: injury.id) }
                if injury.physioNext != nil || injury.physioNote != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if let next = injury.physioNext {
                            Text("Physio next \(Day.weekdayShort(next)) \(Day.pretty(next))").micro()
                        }
                        if let note = injury.physioNote {
                            Text("“\(note)”").font(.sans(14)).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.raised))
                    .padding(.top, 10)
                }
            }
        }
        .padding(.top, 10)
    }
}

/// 11-cell 0–10 row, 30 × 44 pt cells.
struct PainRow: View {
    var selected: Int?
    var last: Int?
    var onPick: (Int) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0...10, id: \.self) { n in
                let on = selected == n
                Button { onPick(n) } label: {
                    Text("\(n)").font(.num(13))
                        .foregroundStyle(on ? Color.white : n == last ? Palette.injuryText : Palette.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? Palette.injury : Palette.raised))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.injuryBorder, lineWidth: n == last && !on ? 1 : 0))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Pain \(n) of 10")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

struct RehabRow: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.accent) private var accent
    var exercise: RehabExercise
    var onToggle: ((Bool) -> Void)?

    var body: some View {
        let db = store.db
        let today = store.today
        let doneToday = db.rehabLogs.contains { $0.exerciseId == exercise.id && $0.date == today && $0.done }
        let thisWeek = db.rehabLogs.filter { $0.exerciseId == exercise.id && $0.date >= Day.weekStart(today) && $0.done }.count
        let status = exercise.frequency >= 7 ? (doneToday ? "Done" : "Due") : "\(min(thisWeek, exercise.frequency)) of \(exercise.frequency)"

        Button {
            store.toggleRehab(exercise.id)
            onToggle?(!doneToday)
        } label: {
            HStack(spacing: 12) {
                Circle().fill(doneToday ? Palette.injury : .clear)
                    .frame(width: 28, height: 28)
                    .overlay(Circle().strokeBorder(Palette.injury, lineWidth: doneToday ? 0 : 2))
                    .overlay { if doneToday { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) } }
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.sans(15)).foregroundStyle(doneToday ? Palette.secondary : Palette.text)
                        .strikethrough(doneToday, color: Palette.secondary)
                    Text(exercise.prescription.sentenceCased).font(.sans(13)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text(status).font(.sans(13, .medium)).foregroundStyle(status == "Due" ? Palette.injuryText : Palette.secondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: doneToday) { _, new in new }
        .accessibilityAddTraits(doneToday ? .isSelected : [])
        .accessibilityValue(status.lowercased())
    }
}

struct LoadRuleCard: View {
    var rule: LoadRule
    var usage: Metrics.LoadRuleUsage?
    var onDelete: () -> Void

    var body: some View {
        let capped = rule.maxPerWeek != nil
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.styleOrType).font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                Text(capped ? "Max \(rule.maxPerWeek!) a week, \(rule.condition)" : "Not at all, \(rule.condition)")
                    .font(.sans(13)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if capped, let u = usage {
                Text("\(u.used) of \(rule.maxPerWeek!)")
                    .font(.sans(13, .semibold)).monospacedDigit()
                    .foregroundStyle(u.blocked ? Palette.injuryText : u.nearing ? Palette.cautionText : Palette.secondary)
                    .padding(.horizontal, 9).frame(minHeight: 24)
                    .background(Capsule().fill(u.blocked ? Palette.injuryBg : u.nearing ? Palette.cautionBg : Palette.raised))
            } else if !capped {
                Text("Off").font(.sans(13, .semibold)).foregroundStyle(Palette.injuryText)
                    .padding(.horizontal, 9).frame(minHeight: 24).background(Capsule().fill(Palette.injuryBg))
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .contextMenu { Button("Delete rule", role: .destructive, action: onDelete) }
        .swipeToDelete(perform: onDelete)
    }
}

/* ── Sheets ─────────────────────────────────────────────────────────────── */

struct SheetScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var subtitle: String?
    var action: String?
    var actionEnabled = true
    var onAction: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 16).padding(.bottom, 40)
            }
            .background(Palette.sheet)
            .navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
                if let action, let onAction {
                    ToolbarItem(placement: .confirmationAction) { Button(action, action: onAction).disabled(!actionEnabled) }
                }
            }
        }
    }
}

struct InjuryEditorSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var injuryId: String?
    @State private var name = ""
    @State private var part = Vocab.bodyParts[6].id
    @State private var status: InjuryStatus = .watching
    @State private var severity = ""
    @State private var diagnosis = ""
    @State private var physioNote = ""
    @State private var hasPhysio = false
    @State private var physioNext = Date.now
    @State private var loaded = false

    var body: some View {
        SheetScaffold(title: injuryId == nil ? "Log something new" : "Edit", subtitle: "Body log",
                      action: injuryId == nil ? "Add" : "Save", actionEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty, onAction: save) {
            TextFieldRow(label: "What", placeholder: "Left ring finger · A2 pulley strain", text: $name).padding(.bottom, 16)
            FieldLabel(title: "Where")
            ChipFlow { ForEach(Vocab.bodyParts, id: \.id) { p in Chip(label: p.label, on: part == p.id, small: true) { part = p.id } } }
                .padding(.bottom, 16)
            FieldLabel(title: "Status")
            SquareSegment(options: [(InjuryStatus.active, "Active"), (.watching, "Watching")], selection: $status).padding(.bottom, 14)
            TextFieldRow(label: "Severity", placeholder: "Grade I", text: $severity).padding(.bottom, 8)
            TextFieldRow(label: "Diagnosis", placeholder: "Confirmed by physio", text: $diagnosis).padding(.bottom, 8)
            FieldRow(label: "Physio next") {
                Spacer()
                if hasPhysio { DatePicker("Physio", selection: $physioNext, displayedComponents: .date).labelsHidden() }
                Toggle("Physio booked", isOn: $hasPhysio).labelsHidden()
            }
            .padding(.bottom, 8)
            NoteBox(placeholder: "What the physio said…", text: $physioNote)
        }
        .onAppear(perform: load)
    }

    func load() {
        guard !loaded, let id = injuryId, let inj = store.db.injuries.first(where: { $0.id == id }) else { loaded = true; return }
        loaded = true
        name = inj.name; part = inj.bodyPart; status = inj.status == .active ? .active : .watching
        severity = inj.severity ?? ""; diagnosis = inj.diagnosis ?? ""; physioNote = inj.physioNote ?? ""
        hasPhysio = inj.physioNext != nil; physioNext = inj.physioNext.map(Day.date) ?? .now
    }

    func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let today = store.today
        if let id = injuryId {
            store.updateInjury(id) { i in
                i.name = trimmed; i.bodyPart = part
                if i.status != .resolved {
                    if status == .active && i.status != .active { i.rehabStart = i.rehabStart ?? today }
                    i.status = status
                }
                i.severity = severity.isEmpty ? nil : severity; i.diagnosis = diagnosis.isEmpty ? nil : diagnosis
                i.physioNote = physioNote.isEmpty ? nil : physioNote; i.physioNext = hasPhysio ? Day.iso(physioNext) : nil
            }
        } else {
            store.createInjury(Injury(bodyPart: part, name: trimmed, onsetDate: today, status: status,
                                      severity: severity.isEmpty ? nil : severity, diagnosis: diagnosis.isEmpty ? nil : diagnosis,
                                      rehabStart: status == .active ? today : nil, physioNext: hasPhysio ? Day.iso(physioNext) : nil,
                                      physioNote: physioNote.isEmpty ? nil : physioNote))
        }
        dismiss()
    }
}

struct AddExerciseSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var injuryId: String
    @State private var name = ""
    @State private var dose = ""
    @State private var frequency = 7

    var body: some View {
        SheetScaffold(title: "Add exercise", subtitle: nil, action: "Add", actionEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
            store.addRehabExercise(injuryId: injuryId, name: name.trimmingCharacters(in: .whitespaces),
                                   prescription: dose.trimmingCharacters(in: .whitespaces).ifEmpty(frequency >= 7 ? "Daily" : "\(frequency)× a week"),
                                   frequency: frequency)
            dismiss()
        } content: {
            TextFieldRow(label: "Name", placeholder: "Tendon glides", text: $name).padding(.bottom, 8)
            TextFieldRow(label: "Dose", placeholder: "2 × 10, morning and night", text: $dose).padding(.bottom, 8)
            FieldRow(label: "Times a week") {
                Spacer()
                SquareStepper(value: frequency >= 7 ? "Daily" : "\(frequency)",
                              decrement: { frequency = max(1, frequency - 1) }, increment: { frequency = min(7, frequency + 1) })
            }
        }
    }
}

struct AddLoadRuleSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var injuryId: String
    @State private var style = "Crimpy"
    @State private var cap = 2
    @State private var prohibition = false

    var body: some View {
        let injury = store.db.injuries.first { $0.id == injuryId }
        let short = injury.map { shortInjury($0.name) } ?? "the injury"
        SheetScaffold(title: "Add load rule", subtitle: "Cap a style", action: "Add") {
            store.addLoadRule(LoadRule(injuryId: injuryId, styleOrType: style, maxPerWeek: prohibition ? nil : cap,
                                       condition: prohibition ? "until \(short) is pain-free" : "while \(short) is above 1/10",
                                       headline: prohibition ? "No \(style.lowercased())" : "\(style) sessions · max \(cap) per week"))
            dismiss()
        } content: {
            FieldLabel(title: "Style")
            ChipFlow { ForEach(Vocab.boardStyles + ["Campus"], id: \.self) { s in Chip(label: s, on: style == s, small: true) { style = s } } }
                .padding(.bottom, 14)
            SquareSegment(options: [(false, "Weekly cap"), (true, "Not at all")], selection: $prohibition).padding(.bottom, 10)
            if !prohibition {
                FieldRow(label: "Max a week") {
                    Spacer()
                    SquareStepper(value: "\(cap)", decrement: { cap = max(0, cap - 1) }, increment: { cap = min(7, cap + 1) })
                }
            }
            Text("Counts sessions, not climbs.")
                .font(.sans(13)).foregroundStyle(Palette.secondary).padding(.top, 10)
        }
    }
}
