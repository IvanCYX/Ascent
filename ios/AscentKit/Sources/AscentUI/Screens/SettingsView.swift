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
                    LabeledContent("Your normal grade", value: NormalGradeView.summary(Load.normals(db, today: store.today)))
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

/* ── Gyms & boards (web /gyms) ──────────────────────────────────────────── */

struct GymsView: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let db = store.db
        let sendsByGym = Dictionary(grouping: db.climbs.filter { $0.gymId != nil && Metrics.isSend($0) }, by: { $0.gymId! }).mapValues(\.count)
        let rows = Self.groupedRows(db.gyms)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.first!.id) { group in GymRow(gyms: group, sends: group.reduce(0) { $0 + (sendsByGym[$1.id] ?? 0) }) }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Boards").font(.sans(16, .semibold))
                            Text("V-scale, never merged").font(.sans(13)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Text("\(db.climbs.filter { $0.boardId != nil && Metrics.isSend($0) }.count)").font(.num(20))
                    }
                    ChipFlow {
                        ForEach(db.boards) { b in Chip(label: "\(b.name), \(b.angles.map(String.init).joined(separator: "/"))°", small: true) {} }
                    }
                }
                .padding(.vertical, 14)

                Text("\(Text("Two kinds of scale. ").bold().foregroundStyle(Palette.text))Numbered gyms share the 1 to 15 spine with a soft or hard offset, so BHUB 10 and Batuu 10 are not counted as the same climb. Camp5 is ranked, not numbered: its tags stay tags, ordered pink to black, and chart in their own column.")
                    .font(.sans(14)).foregroundStyle(Palette.secondary)
                    .padding(16).background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.surface))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
        }
        .background(Palette.ground)
        .navigationTitle("Gyms and boards")
        .navigationSubtitle("\(db.gyms.count) gyms, \(db.boards.count) boards, \(db.climbs.count.formatted()) climbs")
        .largeTitle()
        .toolbar { ToolbarItem(placement: .trailing) { Button("Add gym") { router.sheet = .addGym } } }
    }
}

extension GymsView {
    /// Bump PBJ / J1 / SSQ share one scale — one row for the three.
    static func groupedRows(_ gyms: [Gym]) -> [[Gym]] {
        let bump = gyms.filter { $0.name.hasPrefix("Bump") }
        var rows = gyms.filter { !$0.name.hasPrefix("Bump") }.map { [$0] }
        if !bump.isEmpty { rows.insert(bump, at: min(2, rows.count)) }
        return rows
    }
}

struct GymRow: View {
    @Environment(AscentStore.self) private var store
    var gyms: [Gym]
    var sends: Int

    var body: some View {
        let first = gyms[0]
        let sent = Set(store.db.climbs.filter { c in gyms.contains { $0.id == c.gymId } && c.gradeKind == .number && Metrics.isSend(c) }.map(\.grade))
        let label = gyms.count > 1 ? "Bump " + gyms.map { $0.name.replacingOccurrences(of: "Bump ", with: "") }.joined(separator: " · ") : first.name
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label).font(.sans(16, .semibold))
                    Text(meta(first, shared: gyms.count > 1)).font(.sans(13)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text("\(sends)").font(.num(20))
            }
            if first.isRanked {
                HStack(spacing: 4) {
                    Text("Easy").font(.sans(11)).foregroundStyle(Palette.secondary)
                    ForEach(first.tags ?? [], id: \.self) { t in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Palette.hold(t)).frame(height: 18)
                                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.hairlineStrong, lineWidth: Palette.needsHairline(t) ? 1 : 0))
                            Text(Vocab.colourCode(t)).font(.sans(10, .semibold)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Text("Hard").font(.sans(11)).foregroundStyle(Palette.secondary)
                }
            } else {
                let max = first.maxGrade ?? 12
                HStack(spacing: 2) {
                    ForEach(1...max, id: \.self) { g in
                        Text("\(g)").font(.num(11)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(sent.contains(g) ? Palette.ground : Palette.text)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(sent.contains(g) ? Palette.text : Palette.raised))
                    }
                    if max < 15 {
                        Text("No \(max + 1)–15\(first.offset < 0 ? ", soft" : first.offset > 0 ? ", hard" : "")")
                            .font(.sans(10)).foregroundStyle(Palette.tertiary).lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 28)
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            .layoutPriority(-1)
                            .frame(width: nil)
                    }
                }
            }
            if gyms.count == 1 && sends == 0 {
                LinkButton(title: "Remove", color: Palette.tertiary) { store.deleteGym(first.id) }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    func meta(_ g: Gym, shared: Bool) -> String {
        if g.isRanked { return "Colour tags only" }
        var parts = ["Numbers to \(g.maxGrade ?? 12)"]
        if shared { parts.append("one shared scale") }
        else if g.offset != 0 { parts.append("offset \(g.offset > 0 ? "+" : "−")\(abs(g.offset).formatted())") }
        else if g.id == "batuu" { parts.append("reference") }
        return parts.joined(separator: ", ")
    }
}

struct AddGymSheet: View {
    @Environment(AscentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ranked = false
    @State private var maxGrade = 12
    @State private var offset = 0.0

    var body: some View {
        SheetScaffold(title: "New gym", action: "Done", actionEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
            let n = name.trimmingCharacters(in: .whitespaces)
            store.saveGym(Gym(id: uid(), name: n, shortName: n, scaleType: ranked ? .rankedColour : .numeric,
                              maxGrade: ranked ? nil : maxGrade, tags: ranked ? Vocab.camp5Tags : nil,
                              offset: offset, sortOrder: store.db.gyms.count + 1))
            dismiss()
        } content: {
            TextFieldRow(label: "Name", placeholder: "Camp5 KL Gateway", text: $name).padding(.bottom, 16)
            FieldLabel(title: "Grades")
            SquareSegment(options: [(false, "Numbers"), (true, "Colour tags")], selection: $ranked).padding(.bottom, 16)
            if !ranked {
                FieldRow(label: "Max grade") {
                    Spacer()
                    SquareStepper(value: "\(maxGrade)", decrement: { maxGrade = max(1, maxGrade - 1) }, increment: { maxGrade = min(20, maxGrade + 1) })
                }
                .padding(.bottom, 8)
            }
            FieldRow(label: "Offset vs Batuu") {
                Spacer()
                SquareStepper(value: offset == 0 ? "0" : "\(offset > 0 ? "+" : "−")\(abs(offset).formatted())",
                              decrement: { offset = max(-1, offset - 0.5) }, increment: { offset = min(1, offset + 0.5) })
            }
            Text("Grade correction vs Batuu, −1 to +1. Softer gyms get a negative offset.")
                .font(.sans(13)).foregroundStyle(Palette.secondary).padding(.top, 10)
        }
    }
}
