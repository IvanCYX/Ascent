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
                HStack(alignment: .top, spacing: 10) {
                    BodyMapView(status: bodyStatus(db), selected: filter) { filter = $0 }
                        .frame(width: 150)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tap an area to filter").micro()
                        legend(Palette.warn, "Active", db.activeInjuries)
                        legend(Palette.watch, "Watching", db.watchingInjuries)
                        if filter != nil { LinkButton(title: "Clear filter") { filter = nil } }
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 16).padding(.bottom, 6)

                if shown.isEmpty {
                    Text("Nothing logged for this area. Tap another part, or clear the filter.")
                        .font(.sans(13)).foregroundStyle(Palette.muted).padding(16)
                }

                ForEach(shown) { inj in InjuryDetail(injury: inj) }

                if !watching.isEmpty && !active.isEmpty && filter == nil {
                    Band {
                        Text("Watching").micro().padding(.bottom, 10)
                        ForEach(watching) { w in
                            HStack(spacing: 12) {
                                RoundedRectangle(cornerRadius: 3).fill(Palette.watch).frame(width: 11, height: 11)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(w.name).font(.sans(13.5, .medium))
                                    Text("SINCE \(Day.pretty(w.onsetDate).uppercased())").font(.mono(10)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                LinkButton(title: "Escalate") {
                                    store.updateInjury(w.id) { $0.status = .active; $0.rehabStart = store.today }
                                }
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Palette.card)
                            .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
                            .padding(.bottom, 6)
                        }
                    }
                }

                if !resolved.isEmpty && filter == nil {
                    Band {
                        Text("Resolved").micro().padding(.bottom, 10)
                        ForEach(resolved) { r in
                            HStack {
                                Text(r.name).font(.sans(13)).foregroundStyle(Palette.muted)
                                Spacer()
                                LinkButton(title: "Reopen") { store.updateInjury(r.id) { $0.status = .watching } }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .background(Palette.paper)
        .navigationTitle("Body")
        .navigationSubtitle("\(db.activeInjuries.count) ACTIVE · \(db.watchingInjuries.count) WATCHING")
        .largeTitle()
        .toolbar {
            ToolbarItem(placement: .trailing) { Button("Log new") { router.sheet = .newInjury } }
        }
    }

    func legend(_ c: Color, _ label: String, _ items: [Injury]) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(c).frame(width: 11, height: 11).padding(.top, 3)
            Text("\(Text(label).bold()) · \(items.map { shortInjury($0.name) }.joined(separator: ", ").ifEmpty("none"))")
                .font(.sans(13)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
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
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(injury.name).font(.serif(22, relativeTo: .title2)).fixedSize(horizontal: false, vertical: true)
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
                        Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                            .frame(width: 36, height: 36)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .menuIndicator(.hidden)
                    .accessibilityLabel("Injury actions")
                }
                Text(["Onset \(Day.pretty(injury.onsetDate))", injury.severity, injury.diagnosis].compactMap { $0 }.joined(separator: " · "))
                    .font(.sans(12.5)).foregroundStyle(Palette.muted).padding(.top, 7)
                if let rehabWeek, injury.status == .active {
                    Text("REHAB WK \(rehabWeek)").font(.mono(10.5)).tracking(1).foregroundStyle(Palette.warn).padding(.top, 8)
                }

                Text("Pain 0–10 · by session").micro().padding(.top, 18).padding(.bottom, 10)
                if pain.isEmpty {
                    Text("no entries yet").font(.sans(12)).foregroundStyle(Palette.muted)
                } else {
                    PainBars(levels: pain.map(\.level), height: 70, fullCount: 2)
                        .overlay(alignment: .bottom) { Hairline(color: Palette.ruleStrong) }
                    HStack {
                        Text("\(Day.short(pain.first!.date)) · \(pain.first!.level)/10")
                        Spacer()
                        Text("NOW · \(pain.last!.level)/10")
                    }
                    .font(.mono(10.5)).foregroundStyle(Palette.muted).padding(.top, 7)
                }

                Text("Log today").micro().padding(.top, 14).padding(.bottom, 8)
                PainRow(selected: todayLevel) { store.addPainEntry(injuryId: injury.id, level: $0) }

                if !exercises.isEmpty {
                    Text("Adherence").micro().padding(.top, 20).padding(.bottom, 6)
                    Text("\(adh.streak)\(Text(" day streak").font(.serif(15)).foregroundStyle(Palette.muted))").font(.serif(34, relativeTo: .largeTitle))
                    AdherenceStrip(done: adh.done).padding(.top, 12)
                    Text("\(adh.doneDays) of \(adh.total) days\(adh.missedLabel.map { " · missed \(Day.weekday($0).prefix(1))\(Day.weekday($0).dropFirst().lowercased()) \(Day.pretty($0))" } ?? "")")
                        .font(.sans(11.5)).foregroundStyle(Palette.muted).padding(.top, 8)
                }
            }
            .padding(16)
            .overlay(Rectangle().strokeBorder(Palette.ruleStrong, lineWidth: 1))
            .padding(.horizontal, 16)

            Band(top: false) {
                SectionHead("Rehab protocol", note: "TAP TO TICK TODAY")
                ForEach(exercises) { e in
                    RehabRow(exercise: e)
                        .swipeToDelete { store.deleteRehabExercise(e.id) }
                }
                if exercises.isEmpty { Text("No exercises yet.").font(.sans(13)).foregroundStyle(Palette.muted) }
                LinkButton(title: "+ Add exercise") { router.sheet = .addExercise(injuryId: injury.id) }.padding(.top, 6)
            }

            Band {
                SectionHead("Load rules & notes")
                ForEach(rules) { r in
                    LoadRuleCard(rule: r, usage: usage.first { $0.ruleId == r.id }) { store.deleteLoadRule(r.id) }
                }
                LinkButton(title: "+ Add load rule") { router.sheet = .addLoadRule(injuryId: injury.id) }.padding(.bottom, 8)
                if injury.physioNext != nil || injury.physioNote != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        if let next = injury.physioNext {
                            Text("Physio · next \(Day.weekday(next).prefix(1))\(Day.weekday(next).dropFirst().lowercased()) \(Day.pretty(next))").micro()
                        }
                        if let note = injury.physioNote {
                            Text("“\(note)”").font(.sans(13)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .overlay(Rectangle().strokeBorder(Palette.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 3])))
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
        HStack(spacing: 2) {
            ForEach(0...10, id: \.self) { n in
                let on = selected == n
                Button { onPick(n) } label: {
                    Text("\(n)").font(.mono(12, on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white : n == last ? Palette.warn : Palette.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(on ? Palette.warn : Palette.card)
                        .overlay(Rectangle().strokeBorder(n == last && !on ? Palette.warnBorder : Palette.ruleChip, lineWidth: 1))
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
        let status = exercise.frequency >= 7 ? (doneToday ? "DONE" : "DUE") : "\(min(thisWeek, exercise.frequency)) OF \(exercise.frequency)"

        Button {
            store.toggleRehab(exercise.id)
            onToggle?(!doneToday)
        } label: {
            HStack(spacing: 11) {
                Rectangle().fill(doneToday ? accent.color : .clear)
                    .frame(width: 20, height: 20)
                    .overlay(Rectangle().strokeBorder(doneToday ? accent.color : Palette.ruleStrong, lineWidth: 1))
                    .overlay { if doneToday { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(accent.onAccent) } }
                VStack(alignment: .leading, spacing: 5) {
                    Text(exercise.name).font(.sans(14, .medium)).foregroundStyle(Palette.ink)
                    Text(exercise.prescription).font(.mono(10.5)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text(status).font(.mono(10.5)).foregroundStyle(status == "DUE" ? Palette.warn : Palette.muted)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(Palette.card)
            .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: doneToday) { _, new in new }
        .accessibilityAddTraits(doneToday ? .isSelected : [])
        .accessibilityValue(status.lowercased())
        .padding(.bottom, 8)
    }
}

struct LoadRuleCard: View {
    var rule: LoadRule
    var usage: Metrics.LoadRuleUsage?
    var onDelete: () -> Void

    var body: some View {
        let capped = rule.maxPerWeek != nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(rule.headline).font(.sans(13, .semibold)).foregroundStyle(capped ? Palette.warn : Palette.ink)
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.faint).frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete rule")
            }
            if capped, let u = usage {
                HStack(spacing: 4) {
                    ForEach(0..<(rule.maxPerWeek! + 1), id: \.self) { i in
                        Rectangle().fill(i < u.used ? Palette.warn : Palette.track).frame(width: 28, height: 8)
                    }
                }
            }
            Text(capped && usage != nil
                 ? "Used \(usage!.used) of \(rule.maxPerWeek!) this week \(rule.condition). Planning a \(rule.styleOrType.lowercased()) day will warn you."
                 : "In force \(rule.condition).")
                .font(.sans(12.5)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 15).padding(.vertical, 13)
        .background(capped ? Palette.warnBg : Palette.card)
        .overlay(Rectangle().strokeBorder(capped ? Palette.warnBorder : Palette.rule, lineWidth: 1))
        .swipeToDelete(perform: onDelete)
        .padding(.bottom, 11)
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
            .background(Palette.paper)
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
        SheetScaffold(title: injuryId == nil ? "Log something new" : "Edit", subtitle: "GOES STRAIGHT INTO THE BODY LOG",
                      action: injuryId == nil ? "Add" : "Save", actionEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty, onAction: save) {
            TextFieldRow(label: "WHAT", placeholder: "Left ring finger · A2 pulley strain", text: $name).padding(.bottom, 14)
            Text("Where").micro().padding(.bottom, 9)
            ChipFlow { ForEach(Vocab.bodyParts, id: \.id) { p in Chip(label: p.label, on: part == p.id, small: true) { part = p.id } } }
                .padding(.bottom, 14)
            Text("Status").micro().padding(.bottom, 9)
            SquareSegment(options: [(InjuryStatus.active, "Active"), (.watching, "Watching")], selection: $status).padding(.bottom, 14)
            TextFieldRow(label: "SEVERITY", placeholder: "grade I", text: $severity).padding(.bottom, 8)
            TextFieldRow(label: "DIAGNOSIS", placeholder: "confirmed by physio", text: $diagnosis).padding(.bottom, 8)
            FieldRow(label: "PHYSIO NEXT") {
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
                                   prescription: dose.trimmingCharacters(in: .whitespaces).uppercased().ifEmpty(frequency >= 7 ? "DAILY" : "\(frequency)×/WEEK"),
                                   frequency: frequency)
            dismiss()
        } content: {
            TextFieldRow(label: "NAME", placeholder: "Tendon glides", text: $name).padding(.bottom, 8)
            TextFieldRow(label: "DOSE", placeholder: "2 × 10 · MORNING & NIGHT", text: $dose).padding(.bottom, 8)
            FieldRow(label: "TIMES / WEEK") {
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
        SheetScaffold(title: "Add load rule", subtitle: "CAP A STYLE", action: "Add") {
            store.addLoadRule(LoadRule(injuryId: injuryId, styleOrType: style, maxPerWeek: prohibition ? nil : cap,
                                       condition: prohibition ? "until \(short) is pain-free" : "while \(short) is above 1/10",
                                       headline: prohibition ? "No \(style.lowercased())" : "\(style) sessions · max \(cap) per week"))
            dismiss()
        } content: {
            Text("Style").micro().padding(.bottom, 9)
            ChipFlow { ForEach(Vocab.boardStyles + ["Campus"], id: \.self) { s in Chip(label: s, on: style == s, small: true) { style = s } } }
                .padding(.bottom, 14)
            SquareSegment(options: [(false, "Weekly cap"), (true, "Not at all")], selection: $prohibition).padding(.bottom, 10)
            if !prohibition {
                FieldRow(label: "MAX / WEEK") {
                    Spacer()
                    SquareStepper(value: "\(cap)", decrement: { cap = max(0, cap - 1) }, increment: { cap = min(7, cap + 1) })
                }
            }
            Text("Usage counts sessions, not climbs — one crimpy session is one use. Planning and logging a ruled style both warn inline.")
                .font(.sans(12.5)).foregroundStyle(Palette.muted).padding(.top, 10)
        }
    }
}
