import SwiftUI
import UniformTypeIdentifiers
import AscentCore

/// The 5th tab (DESIGN §4). The only appearance control in the app lives here.
struct SettingsView: View {
    @Environment(AscentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AppLock.self) private var lock
    @Environment(\.accent) private var accent

    @State private var exporting = false
    @State private var exportDoc: BackupDocument?
    @State private var importing = false
    @State private var pendingImport: Data?
    @State private var confirmReset = false
    @State private var confirmClear = false
    @State private var dataError: String?
    @State private var lockBusy = false

    var body: some View {
        @Bindable var settings = settings
        let db = store.db

        Form {
            Section {
                Picker("Appearance", selection: $settings.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            } header: { header("Appearance") }
            .listRowBackground(Palette.surface)

            Section {
                AccentDots()
                AccentPreview()
            } header: { header("Accent") } footer: {
                if settings.accent.isNearInjuryRed {
                    Text("Close to injury red. Pain bars may be harder to spot.")
                        .foregroundStyle(Palette.injuryText)
                } else if settings.accent.isNearCaution {
                    Text("Close to the amber used for warnings. Spiking load may be harder to spot.")
                        .foregroundStyle(Palette.cautionText)
                } else {
                    Text("\(settings.accent.name). Colours the tab bar, buttons and charts.")
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                NavigationLink(value: Route.normalGrade) {
                    LabeledContent("Your normal grade", value: NormalGradeView.summary(Load.normals(db, today: store.today),
                                                                                      main: Pillars.mainScale(db, today: store.today),
                                                                                      scales: NormalGradeView.scales(db)))
                }
                Stepper(value: Binding(get: { db.settings.weeklyTarget }, set: { store.setWeeklyTarget($0) }), in: 1...7) {
                    LabeledContent("Weekly target", value: "\(db.settings.weeklyTarget) session\(db.settings.weeklyTarget == 1 ? "" : "s")")
                }
            } header: { header("Training") } footer: {
                Text("Load weighs each climb against your normal grade.")
            }
            .listRowBackground(Palette.surface)

            Section {
                Toggle(isOn: Binding(get: { settings.faceIDLock }, set: { on in
                    lockBusy = true
                    Task { await lock.setEnabled(on); lockBusy = false }
                })) {
                    Label(lock.rowTitle, systemImage: lock.kind == .touchID ? "touchid" : lock.kind == .passcode ? "lock" : "faceid")
                }
                .disabled(lock.kind == .unavailable || lockBusy)
                Picker("Require \(lock.kind == .passcode ? "passcode" : "Face ID")", selection: $settings.requireInterval) {
                    ForEach(RequireInterval.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!settings.faceIDLock)
            } header: { header("Privacy") } footer: {
                if lock.kind == .unavailable {
                    Text("Needs a device passcode.")
                } else {
                    Text("Also hides details in widgets and the Live Activity.")
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                NavigationLink(value: Route.gyms) {
                    LabeledContent("Gyms and boards", value: "\(db.gyms.count) gyms, \(db.boards.count) boards")
                }
            } header: { header("Places") } footer: {
                Text("Comps live in Plan, Season.")
            }
            .listRowBackground(Palette.surface)

            Section {
                Button {
                    do { exportDoc = BackupDocument(data: try store.exportData()); exporting = true }
                    catch { dataError = error.localizedDescription }
                } label: { LabeledContent { Text("JSON") } label: { Label("Export backup", systemImage: "square.and.arrow.up") } }
                Button { importing = true } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
                Button { confirmReset = true } label: { Label("Reset to demo data…", systemImage: "arrow.counterclockwise") }
                    .foregroundStyle(Palette.text)
                Button(role: .destructive) { confirmClear = true } label: { Label("Clear everything…", systemImage: "trash") }
            } header: { header("Data") } footer: {
                Text("\(Text("Stored only on this iPhone.").bold().foregroundStyle(Palette.text)) Export a backup before deleting the app.")
            }
            .listRowBackground(Palette.surface)

            Section {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Climbs logged", value: db.climbs.count.formatted())
            } header: { header("About") }
            .listRowBackground(Palette.surface)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.ground)
        .navigationTitle("Settings")
        .largeTitle()
        .tint(accent.color)
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .json,
                      defaultFilename: "ascent-\(store.today).json") { result in
            if case .failure(let e) = result { dataError = e.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    _ = try Backup.decode(data) // validate before asking
                    pendingImport = data
                } catch { dataError = "That file is not an Ascent backup." }
            case .failure(let e): dataError = e.localizedDescription
            }
        }
        .confirmationDialog("Replace your log with this backup?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
                            titleVisibility: .visible) {
            Button("Replace everything", role: .destructive) {
                if let d = pendingImport { do { try store.importData(d) } catch { dataError = error.localizedDescription } }
                pendingImport = nil
            }
        } message: {
            Text("Deletes \(db.climbs.count.formatted()) climbs on this iPhone.")
        }
        .confirmationDialog("Reset to demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Export backup first") {
                if let d = try? store.exportData() { exportDoc = BackupDocument(data: d); exporting = true }
            }
            Button("Reset to demo data", role: .destructive) { store.resetToDemo() }
        } message: {
            Text("Deletes \(db.climbs.count.formatted()) climbs. Export a backup first.")
        }
        .confirmationDialog("Clear everything?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Export backup first") {
                if let d = try? store.exportData() { exportDoc = BackupDocument(data: d); exporting = true }
            }
            Button("Clear everything", role: .destructive) { store.clearAll() }
        } message: {
            Text("Deletes all sessions, climbs, reviews and injuries. Gyms and boards stay.")
        }
        .alert("Couldn’t do that", isPresented: Binding(get: { dataError != nil }, set: { if !$0 { dataError = nil } })) {
            Button("OK") { dataError = nil }
        } message: { Text(dataError ?? "") }
    }

    func header(_ t: String) -> some View {
        Text(t).font(.sans(13, .semibold)).textCase(nil).foregroundStyle(Palette.secondary)
    }

    static var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

struct AccentDots: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let current = settings.accent
        HStack(spacing: 10) {
            ForEach(AccentTheme.presets, id: \.name) { p in
                let on = current.name == p.name
                Button { settings.accentHex = p.hex } label: {
                    Circle().fill(AccentTheme(hex: p.hex).color)
                        .frame(width: 32, height: 32)
                        .overlay(Circle().strokeBorder(Palette.hairlineStrong, lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(Palette.text, lineWidth: on ? 2 : 0))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            ColorPicker(selection: Binding(
                get: { RGB(hex: settings.accentHex)?.color ?? Palette.textLight.color },
                set: { settings.accentHex = hex(of: $0) }
            ), supportsOpacity: false) {
                Text("Custom")
            }
            .labelsHidden()
            .overlay(Circle().strokeBorder(Palette.text, lineWidth: current.name == "Custom" ? 2 : 0).padding(-3).allowsHitTesting(false))
            .accessibilityLabel("Custom colour")
            Spacer()
        }
        .padding(.vertical, 4)
    }

    func hex(of color: Color) -> String {
        let r = color.resolve(in: EnvironmentValues())
        let cg = r.cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? r.cgColor
        let c = cg.components ?? [0, 0, 0]
        let rgb = c.count >= 3 ? RGB(Double(c[0]), Double(c[1]), Double(c[2])) : RGB(Double(c[0]), Double(c[0]), Double(c[0]))
        return RGB(min(1, max(0, rgb.r)), min(1, max(0, rgb.g)), min(1, max(0, rgb.b))).hex
    }
}

struct AccentPreview: View {
    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach([0.4, 0.7, 1, 0.55, 0.85], id: \.self) { h in RoundedRectangle(cornerRadius: 3).fill(accent.color).frame(width: 12, height: 30 * h) }
            }
            .frame(height: 30, alignment: .bottom)
            Spacer()
            Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent.onAccent)
                .frame(width: 34, height: 34).background(Circle().fill(accent.color))
            Text("Send").font(.sans(14, .semibold)).foregroundStyle(accent.onAccent).frame(width: 70, height: 34).background(Capsule().fill(accent.color))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the accent on charts, the plus button and the send button")
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/* ── Gyms and boards (DESIGN §11.2) ────────────────────────────────────── */

struct GymsView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let db = store.db
        let sends = db.climbs.filter(Metrics.isSend)
        let byGym = Dictionary(grouping: sends.filter { $0.gymId != nil }, by: { $0.gymId! }).mapValues(\.count)
        let byBoard = Dictionary(grouping: sends.filter { $0.boardId != nil }, by: { $0.boardId! }).mapValues(\.count)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header("Gyms")
                ForEach(Self.groupedRows(db.gyms), id: \.first!.id) { group in
                    GymCard(gyms: group, sends: group.reduce(0) { $0 + (byGym[$1.id] ?? 0) })
                }

                header("Boards").padding(.top, 10)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(db.boards.enumerated()), id: \.element.id) { i, b in
                            HStack(spacing: 14) {
                                Text(b.code).font(.sans(13, .bold)).foregroundStyle(Palette.text)
                                    .frame(width: 40, height: 40)
                                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.raised))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(b.name).font(.sans(15, .semibold)).foregroundStyle(Palette.text)
                                    Text(Self.angles(b.angles)).font(.sans(13)).foregroundStyle(Palette.secondary)
                                }
                                Spacer()
                                Text("\(byBoard[b.id] ?? 0)").font(.num(20)).foregroundStyle(Palette.text)
                            }
                            .padding(.vertical, 12)
                            .overlay(alignment: .bottom) { if i < db.boards.count - 1 { Hairline() } }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, 18).padding(.vertical, 4)
                }

                Text("Numbered gyms share one 1 to 15 scale. V, French and colour tags keep their own grades and are never converted. Boards stay on V and never mix with gyms.")
                    .font(.sans(13)).foregroundStyle(Palette.secondary).padding(.horizontal, 4).padding(.top, 2)
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 100)
        }
        .background(Palette.ground)
        .navigationTitle("Gyms and boards")
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .trailing) { Button("Add") { router.sheet = .addGym } } }
    }

    func header(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("Sends")
        }
        .font(.sans(13, .semibold)).foregroundStyle(Palette.secondary).padding(.horizontal, 4)
    }

    /// "25, 30, 40 and 45°"
    static func angles(_ xs: [Int]) -> String {
        let s = xs.map(String.init)
        guard let last = s.last else { return "" }
        return s.count == 1 ? "\(last)°" : s.dropLast().joined(separator: ", ") + " and \(last)°"
    }
}

extension GymsView {
    /// Bump PBJ / J1 / SSQ share one scale — one card for the three.
    static func groupedRows(_ gyms: [Gym]) -> [[Gym]] {
        let bump = gyms.filter { $0.name.hasPrefix("Bump") }
        var rows = gyms.filter { !$0.name.hasPrefix("Bump") }.map { [$0] }
        if !bump.isEmpty { rows.insert(bump, at: min(2, rows.count)) }
        return rows
    }
}

/// One gym (or the Bump trio): name, scale line, sends, and its grades with the sent ones filled.
struct GymCard: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.accent) private var accent
    var gyms: [Gym]
    var sends: Int

    var body: some View {
        let first = gyms[0]
        let kind = first.gradeKind
        let ids = Set(gyms.map(\.id))
        let sent = Set(store.db.climbs.filter { ids.contains($0.gymId ?? "") && $0.gradeKind == kind && Metrics.isSend($0) }.map(\.grade))
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.name(gyms)).font(.sans(16, .semibold)).foregroundStyle(Palette.text)
                        Text(Self.meta(first, shared: gyms.count > 1)).font(.sans(13)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Text("\(sends)").font(.num(20)).foregroundStyle(Palette.text)
                }
                if first.isRanked {
                    HStack(spacing: 6) {
                        ForEach(first.tags ?? Vocab.camp5Tags, id: \.self) { t in
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.hold(t)).frame(height: 18)
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Palette.hairlineStrong, lineWidth: Palette.needsHairline(t) ? 1 : 0))
                                Text(Vocab.colourCode(t)).font(.sans(10, .semibold)).foregroundStyle(Palette.secondary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Tags pink to black")
                } else {
                    let grades = first.grades
                    let cols = kind == .gymV ? 6 : kind == .french ? 8 : grades.count
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: max(1, cols)), spacing: 3) {
                        ForEach(grades, id: \.self) { g in
                            let on = sent.contains(g)
                            Text(Vocab.gradeLabel(kind, g))
                                .font(.num(grades.count > 12 && kind == .number ? 10 : kind == .french ? 11 : 12))
                                .lineLimit(1).minimumScaleFactor(0.6)
                                .foregroundStyle(on ? accent.onAccent : Palette.secondary)
                                .frame(maxWidth: .infinity, minHeight: 26)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? accent.color : Palette.raised))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(sent.count) of \(grades.count) grades sent")
                }
                if gyms.count == 1 && sends == 0 {
                    LinkButton(title: "Remove", color: Palette.tertiary) { store.deleteGym(first.id) }
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
    }

    /// "Bump PBJ, J1 and SSQ"
    static func name(_ gyms: [Gym]) -> String {
        guard gyms.count > 1 else { return gyms[0].name }
        let short = gyms.map { $0.name.replacingOccurrences(of: "Bump ", with: "") }
        return "Bump " + short.dropLast().joined(separator: ", ") + " and " + short.last!
    }

    static func meta(_ g: Gym, shared: Bool) -> String {
        let kind = g.gradeKind
        let grades = g.grades
        let span = "\(Vocab.gradeLabel(kind, grades.first ?? 0)) to \(Vocab.gradeLabel(kind, grades.last ?? 0))"
        switch g.scaleType {
        case .rankedColour: return "Colour tags, pink to black"
        case .v: return "V scale, \(span)"
        case .french: return "French routes, \(span)"
        case .numeric:
            var parts = ["Numbers", span]
            if shared { parts.append("one scale for all three") }
            else if g.offset != 0 {
                let size = abs(g.offset) == 0.5 ? "half a grade" : abs(g.offset) == 1 ? "a grade" : "\(abs(g.offset).formatted()) grades"
                parts.append("\(size) \(g.offset < 0 ? "soft" : "hard")")
            } else if g.id == "batuu" { parts.append("the reference") }
            return parts.joined(separator: ", ")
        }
    }
}

/* ── Add gym (DESIGN §11.2) ─────────────────────────────────────────────── */

struct AddGymSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var scale: ScaleType = .numeric
    @State private var maxGrade = 12
    @State private var offset = 0.0
    @State private var vLow = -1
    @State private var vHigh = 10
    @State private var frenchLow = Vocab.frenchDefaultRange.lowerBound
    @State private var frenchHigh = Vocab.frenchDefaultRange.upperBound

    static let options: [(scale: ScaleType, title: String, example: String)] = [
        (.numeric, "Numbers", "1 to 15"), (.rankedColour, "Colour tags", "Pink to black"),
        (.v, "V scale", "VB to V17"), (.french, "French routes", "4a to 9a"),
    ]

    var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    /// The gym as it would be saved.
    var draft: Gym {
        Gym(id: uid(), name: trimmed, shortName: trimmed, scaleType: scale,
            minGrade: scale == .v ? vLow : scale == .french ? frenchLow : nil,
            maxGrade: scale == .v ? vHigh : scale == .french ? frenchHigh : scale == .numeric ? maxGrade : nil,
            tags: scale == .rankedColour ? Vocab.camp5Tags : nil,
            offset: scale == .numeric ? offset : 0, sortOrder: store.db.gyms.count + 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextFieldRow(label: "Name", placeholder: "Gym name", text: $name).padding(.bottom, 20)

                    FieldLabel(title: "Grades")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(Self.options, id: \.scale) { o in
                            ScaleOption(title: o.title, example: o.example, on: scale == o.scale) { scale = o.scale }
                        }
                    }
                    .padding(.bottom, 16)

                    controls

                    FieldLabel(title: "Preview").padding(.top, 20)
                    preview

                    Text("The scale is fixed once the gym has climbs.")
                        .font(.sans(13)).foregroundStyle(Palette.secondary).padding(.top, 16)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 120)
            }
            .background(Palette.sheet)
            .safeAreaInset(edge: .bottom) {
                Button("Add") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmed.isEmpty)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Palette.sheet)
            }
            .navigationTitle("New gym")
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
            .sensoryFeedback(.selection, trigger: scale)
        }
    }

    @ViewBuilder var controls: some View {
        switch scale {
        case .numeric:
            VStack(alignment: .leading, spacing: 8) {
                FieldRow(label: "Hardest grade") {
                    Spacer()
                    SquareStepper(value: "\(maxGrade)", decrement: { maxGrade = max(4, maxGrade - 1) },
                                  increment: { maxGrade = min(20, maxGrade + 1) })
                }
                FieldRow(label: "Against Batuu") {
                    Spacer()
                    SquareStepper(value: offset == 0 ? "0" : "\(offset > 0 ? "+" : "−")\(abs(offset).formatted())",
                                  decrement: { offset = max(-1, offset - 0.5) }, increment: { offset = min(1, offset + 0.5) })
                }
                Text("Softer gyms go below 0.").font(.sans(13)).foregroundStyle(Palette.secondary).padding(.top, 2)
            }
        case .rankedColour:
            Text("Tags follow the Camp5 order, pink to black.")
                .font(.sans(14)).foregroundStyle(Palette.text)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.raised))
        case .v:
            rangeRows(.gymV, low: $vLow, high: $vHigh, bounds: Vocab.vGrades)
        case .french:
            rangeRows(.french, low: $frenchLow, high: $frenchHigh, bounds: 0...(Vocab.frenchGrades.count - 1))
        }
    }

    func rangeRows(_ kind: GradeKind, low: Binding<Int>, high: Binding<Int>, bounds: ClosedRange<Int>) -> some View {
        VStack(spacing: 8) {
            FieldRow(label: "Easiest grade") {
                Spacer()
                SquareStepper(value: Vocab.gradeLabel(kind, low.wrappedValue),
                              decrement: { low.wrappedValue = max(bounds.lowerBound, low.wrappedValue - 1) },
                              increment: { low.wrappedValue = min(high.wrappedValue - 1, low.wrappedValue + 1) })
            }
            FieldRow(label: "Hardest grade") {
                Spacer()
                SquareStepper(value: Vocab.gradeLabel(kind, high.wrappedValue),
                              decrement: { high.wrappedValue = max(low.wrappedValue + 1, high.wrappedValue - 1) },
                              increment: { high.wrappedValue = min(bounds.upperBound, high.wrappedValue + 1) })
            }
        }
    }

    @ViewBuilder var preview: some View {
        if scale == .rankedColour {
            HStack(spacing: 6) {
                ForEach(Vocab.camp5Tags, id: \.self) { t in
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.hold(t)).frame(height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Palette.hairlineStrong, lineWidth: Palette.needsHairline(t) ? 1 : 0))
                }
            }
            .accessibilityHidden(true)
        } else {
            let gym = draft
            ChipFlow(spacing: 4) {
                ForEach(gym.grades, id: \.self) { g in
                    Text(Vocab.gradeLabel(gym.gradeKind, g)).font(.num(13)).foregroundStyle(Palette.text)
                        .padding(.horizontal, 6).frame(minWidth: 38, minHeight: 30)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.raised))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(gym.grades.count) grades")
        }
    }

    func save() {
        store.saveGym(draft)
        dismiss()
    }
}

/// One of the four scale tiles in Add gym; both lines centred.
struct ScaleOption: View {
    @Environment(\.accent) private var accent
    var title: String
    var example: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title).font(.sans(16, .semibold))
                Text(example).font(.sans(13)).opacity(0.7)
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(on ? accent.onAccent : Palette.text)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? accent.color : Palette.raised))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
