import SwiftUI
import AscentCore

/// 3.5 — New / Edit comp. Every field in the §3.5 table.
struct CompEditorSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accent) private var accent
    var compId: String?
    var presetDate: String?

    @State private var name = ""
    @State private var date = Date.now
    @State private var multiDay = false
    @State private var endDate = Date.now
    @State private var location = ""
    @State private var gymId: String?
    @State private var category = "Open"
    @State private var format = "Onsight rounds"
    @State private var rounds: [String] = ["Qualifiers", "Final"]
    @State private var priority: CompPriority = .a
    @State private var notes = ""
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextFieldRow(label: "NAME", placeholder: "KL Open · Bouldering", text: $name).padding(.bottom, 8)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("DATE").font(.mono(11)).tracking(0.66).foregroundStyle(Palette.muted)
                            Spacer()
                            Text(Day.long(Day.iso(date))).font(.sans(14, .medium))
                        }
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                            .datePickerStyle(.graphical).labelsHidden().tint(accent.color)
                    }
                    .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
                    .background(Palette.card).overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
                    .padding(.bottom, 8)

                    FieldRow(label: "MULTI-DAY") { Spacer(); Toggle("Multi-day", isOn: $multiDay).labelsHidden().tint(accent.color) }
                        .padding(.bottom, 8)
                    if multiDay {
                        FieldRow(label: "ENDS") {
                            Spacer()
                            DatePicker("Ends", selection: $endDate, in: date..., displayedComponents: .date).labelsHidden()
                        }
                        .padding(.bottom, 8)
                    }

                    FieldRow(label: "WHERE") {
                        TextField("Bukit Jalil, Kuala Lumpur", text: $location).font(.sans(14)).textFieldStyle(.plain)
                        Menu {
                            ForEach(store.db.gyms) { g in
                                Button(g.name) { gymId = g.id; location = g.name }
                            }
                            if gymId != nil { Button("Not a saved gym") { gymId = nil } }
                        } label: {
                            Image(systemName: "building.2").foregroundStyle(Palette.ink).frame(width: 36, height: 36)
                        }
                        .accessibilityLabel("Pick a saved gym")
                    }
                    .padding(.bottom, 14)

                    group("Category") {
                        ForEach(Vocab.compCategories, id: \.self) { c in Chip(label: c, on: category == c, small: true) { category = c } }
                    }
                    group("Format") {
                        ForEach(Vocab.compFormats, id: \.self) { f in Chip(label: f, on: format == f, small: true) { format = f } }
                    }
                    group("Rounds") {
                        ForEach(Vocab.compRounds, id: \.self) { r in
                            Chip(label: r, on: rounds.contains(r), small: true) {
                                if rounds.contains(r) { rounds.removeAll { $0 == r } } else { rounds = Vocab.compRounds.filter { rounds.contains($0) || $0 == r } }
                            }
                        }
                    }

                    Text("Priority · sets the taper").micro().padding(.bottom, 9)
                    SquareSegment(options: [(CompPriority.a, "A · peak"), (.b, "B · mini taper"), (.c, "C · train through")], selection: $priority)
                    Text("A gets a full two-week taper. B gets one lighter week. C only gets a rest day before.")
                        .font(.sans(12)).foregroundStyle(Palette.muted).padding(.top, 8).padding(.bottom, 12)

                    NoteBox(placeholder: "Notes: registration, category cut-offs, warm-up wall…", text: $notes)
                }
                .padding(.horizontal, 16).padding(.bottom, 120)
            }
            .background(Palette.paper)
            .safeAreaInset(edge: .bottom) {
                Button(compId == nil ? "Add comp" : "Save") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Palette.paper)
            }
            .navigationTitle(compId == nil ? "New comp" : "Edit comp")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).tint(accent.color)
                }
            }
        }
        .onAppear(perform: load)
    }

    @ViewBuilder func group<C: View>(_ title: String, @ViewBuilder chips: () -> C) -> some View {
        Text(title).micro().padding(.bottom, 9)
        ChipFlow { chips() }.padding(.bottom, 14)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = compId, let c = store.db.competitions.first(where: { $0.id == id }) {
            name = c.name; date = Day.date(c.date); multiDay = c.endDate != nil
            endDate = Day.date(c.endDate ?? c.date); location = c.location ?? ""; gymId = c.gymId
            category = c.category ?? "Open"; format = c.format ?? "Onsight rounds"; rounds = c.rounds ?? []
            priority = c.effectivePriority; notes = c.notes ?? ""
        } else if let presetDate {
            date = Day.date(presetDate); endDate = date
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let existing = compId.flatMap { id in store.db.competitions.first { $0.id == id } }
        let start = Day.iso(date)
        let end = multiDay ? max(start, Day.iso(endDate)) : nil
        store.saveCompetition(Competition(id: existing?.id ?? uid(), name: trimmed, date: start, endDate: end == start ? nil : end,
                                          location: location.isEmpty ? nil : location, gymId: gymId, category: category,
                                          format: format, rounds: rounds, priority: priority,
                                          notes: notes.isEmpty ? nil : notes, result: existing?.result))
        dismiss()
    }
}

/// Comp detail: every field, edit, delete, notes, and a result after the comp.
struct CompDetailView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    var compId: String
    @State private var confirmDelete = false
    @State private var result = ""
    @State private var notes = ""

    var body: some View {
        if let comp = store.db.competitions.first(where: { $0.id == compId }) {
            let today = store.today
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(comp.effectivePriority.rawValue) PRIORITY · \(Taper.phase(of: comp, on: today)?.rawValue ?? "DONE")").micro()
                        Text(comp.name).font(.serif(32, relativeTo: .largeTitle)).fixedSize(horizontal: false, vertical: true)
                        Text(Day.long(comp.date) + (comp.endDate.map { " – \(Day.long($0))" } ?? "")).font(.sans(14)).foregroundStyle(Palette.muted)
                    }
                    .padding(.horizontal, 16).padding(.bottom, 16)

                    PhaseBar(comp: comp, today: today).padding(.horizontal, 16).padding(.bottom, 20)

                    Band {
                        detail("WHERE", comp.location)
                        detail("CATEGORY", comp.category)
                        detail("FORMAT", comp.format)
                        detail("ROUNDS", comp.rounds?.joined(separator: " → "))
                        detail("TAPER", Taper.summary(comp, all: store.db.competitions).components(separatedBy: " · ").last)
                        if let t = Taper.taperStart(comp) { detail("TAPER STARTS", Day.long(t)) }
                    }

                    Band {
                        SectionHead("Warm-up & notes")
                        NoteBox(placeholder: "Warm-up plan, what to eat, who's driving…", text: $notes)
                            .onChange(of: notes) { _, v in store.saveCompetition(with(comp) { $0.notes = v.isEmpty ? nil : v }) }
                    }

                    if comp.date <= today {
                        Band {
                            SectionHead("Result", note: "OPTIONAL")
                            TextFieldRow(label: "RESULT", placeholder: "Semi-final · 3T 5Z", text: $result)
                                .onChange(of: result) { _, v in store.saveCompetition(with(comp) { $0.result = v.isEmpty ? nil : v }) }
                        }
                    }

                    Band {
                        Button("Delete comp", role: .destructive) { confirmDelete = true }
                            .buttonStyle(SecondaryButtonStyle())
                            .foregroundStyle(Palette.warn)
                    }
                    .padding(.bottom, 80)
                }
            }
            .background(Palette.paper)
            .navigationTitle(comp.displayName)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .trailing) {
                    Button("Edit") { router.sheet = .compEditor(compId: comp.id, date: nil) }
                }
            }
            .onAppear { notes = comp.notes ?? ""; result = comp.result ?? "" }
            .confirmationDialog("Delete \(comp.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete comp", role: .destructive) { dismiss(); store.deleteCompetition(comp.id) }
            } message: {
                Text("The taper plan built around it goes too.")
            }
        } else {
            Text("This comp was deleted.").font(.sans(14)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.paper)
        }
    }

    func with(_ c: Competition, _ change: (inout Competition) -> Void) -> Competition {
        var copy = c
        change(&copy)
        return copy
    }

    @ViewBuilder func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.mono(11)).tracking(0.66).foregroundStyle(Palette.muted).frame(width: 110, alignment: .leading)
                Text(value).font(.sans(14)).foregroundStyle(Palette.ink)
                Spacer()
            }
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Hairline() }
        }
    }
}
