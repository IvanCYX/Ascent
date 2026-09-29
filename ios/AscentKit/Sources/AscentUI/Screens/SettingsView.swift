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

            Section {
                AccentDots()
                AccentPreview()
            } header: { header("Accent") } footer: {
                if settings.accent.isNearInjuryRed {
                    Text("This colour is close to the injury red. Charts will use it too, so pain bars and load flags may be harder to tell apart.")
                        .foregroundStyle(Palette.warn)
                } else {
                    Text("Used for the tab bar, the + button, primary buttons and every chart. Injury red and hold colours never change.")
                }
            }

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
                    Text("Set up a passcode in iOS Settings to use the lock.")
                } else {
                    Text("Asks for Face ID when you open Ascent and hides the app in the app switcher. While the lock is on and your iPhone is locked, widgets and the live session show only session counts, your streak and weeks to the next comp.")
                }
            }

            Section {
                NavigationLink(value: Route.gyms) {
                    LabeledContent("Gyms & boards", value: "\(db.gyms.count) gyms · \(db.boards.count) boards")
                }
                Picker("Dashboard range", selection: Binding(get: { db.settings.dashboardRange }, set: { store.setDashboardRange($0) })) {
                    ForEach(RangeID.allCases) { Text($0.label).tag($0) }
                }
            } header: { header("Climbing") } footer: {
                Text("Competitions, the season calendar and your weekly target live in Plan → Season.")
            }

            Section {
                Button {
                    do { exportDoc = BackupDocument(data: try store.exportData()); exporting = true }
                    catch { dataError = error.localizedDescription }
                } label: { LabeledContent { Text("JSON") } label: { Label("Export backup", systemImage: "square.and.arrow.up") } }
                Button { importing = true } label: { Label("Import backup", systemImage: "square.and.arrow.down") }
                Button { confirmReset = true } label: { Label("Reset to demo data…", systemImage: "arrow.counterclockwise") }
                    .foregroundStyle(Palette.ink)
                Button(role: .destructive) { confirmClear = true } label: { Label("Clear everything…", systemImage: "trash") }
            } header: { header("Data") } footer: {
                Text("\(Text("Stored only on this iPhone.").bold().foregroundStyle(Palette.ink)) No account, no iCloud. Nothing leaves this phone unless you export it. Export a backup before you delete the app.")
            }

            Section {
                LabeledContent("Version", value: Self.version)
                LabeledContent("Climbs logged", value: db.climbs.count.formatted())
            } header: { header("About") }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Palette.grouped)
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
            Text("This deletes the \(db.climbs.count.formatted()) climbs on this iPhone and loads the backup instead.")
        }
        .confirmationDialog("Reset to demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Export backup first") {
                if let d = try? store.exportData() { exportDoc = BackupDocument(data: d); exporting = true }
            }
            Button("Reset to demo data", role: .destructive) { store.resetToDemo() }
        } message: {
            Text("Replace everything with the demo dataset? This deletes \(db.climbs.count.formatted()) climbs. Export a backup first if you care about this log.")
        }
        .confirmationDialog("Clear everything?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Export backup first") {
                if let d = try? store.exportData() { exportDoc = BackupDocument(data: d); exporting = true }
            }
            Button("Clear everything", role: .destructive) { store.clearAll() }
        } message: {
            Text("Keeps your gyms and boards, deletes every session, climb, review and injury.")
        }
        .alert("Couldn’t do that", isPresented: Binding(get: { dataError != nil }, set: { if !$0 { dataError = nil } })) {
            Button("OK") { dataError = nil }
        } message: { Text(dataError ?? "") }
    }

    func header(_ t: String) -> some View {
        Text(t).font(.mono(11)).tracking(1.3).textCase(.uppercase).foregroundStyle(Palette.muted)
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
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Palette.ruleStrong, lineWidth: 1))
                        .padding(3)
                        .overlay(Circle().strokeBorder(Palette.ink, lineWidth: on ? 2 : 0))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(p.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            ColorPicker(selection: Binding(
                get: { RGB(hex: settings.accentHex)?.color ?? Palette.inkLight.color },
                set: { settings.accentHex = hex(of: $0) }
            ), supportsOpacity: false) {
                Text("Custom")
            }
            .labelsHidden()
            .overlay(Circle().strokeBorder(Palette.ink, lineWidth: current.name == "Custom" ? 2 : 0).padding(-3).allowsHitTesting(false))
            .accessibilityLabel("Custom colour")
            Spacer()
            Text(current.name.uppercased()).font(.mono(11)).foregroundStyle(Palette.muted).fixedSize()
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
                ForEach([0.4, 0.7, 1, 0.55, 0.85], id: \.self) { h in Rectangle().fill(accent.color).frame(width: 12, height: 30 * h) }
            }
            .frame(height: 30, alignment: .bottom)
            Spacer()
            Image(systemName: "plus").font(.system(size: 15, weight: .semibold)).foregroundStyle(accent.onAccent)
                .frame(width: 34, height: 34).background(Circle().fill(accent.color))
            Text("Send").font(.sans(13, .semibold)).foregroundStyle(accent.onAccent).frame(width: 62, height: 30).background(accent.color)
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
                            Text("Boards").font(.sans(14.5, .semibold))
                            Text("V-SCALE · NEVER MERGED").font(.mono(10.5)).tracking(0.6).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text("\(db.climbs.filter { $0.boardId != nil && Metrics.isSend($0) }.count)").font(.serif(20))
                    }
                    ChipFlow {
                        ForEach(db.boards) { b in Chip(label: "\(b.name) · \(b.angles.map(String.init).joined(separator: "/"))°", small: true) {} }
                    }
                }
                .padding(.vertical, 14)

                Text("\(Text("Two kinds of scale · ").bold().foregroundStyle(Palette.ink))Numbered gyms share the 1–15 spine with a soft/hard offset, so BHUB 10 and Batuu 10 are not counted as the same climb. Camp5 is ranked, not numbered: its tags stay tags, ordered yellow → black, and chart in their own column.")
                    .font(.sans(13)).foregroundStyle(Palette.muted)
                    .padding(14).background(Palette.card).overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: 1))
                    .padding(.top, 6)
            }
            .padding(.horizontal, 16).padding(.bottom, 100)
        }
        .background(Palette.paper)
        .navigationTitle("Gyms & boards")
        .navigationSubtitle("\(db.gyms.count) GYMS · \(db.boards.count) BOARDS · \(db.climbs.count.formatted()) CLIMBS")
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
                    Text(label).font(.sans(14.5, .semibold))
                    Text(meta(first, shared: gyms.count > 1)).font(.mono(10.5)).tracking(0.6).foregroundStyle(Palette.muted)
                }
                Spacer()
                Text("\(sends)").font(.serif(20))
            }
            if first.isRanked {
                HStack(spacing: 4) {
                    Text("EASY").font(.mono(9)).foregroundStyle(Palette.muted)
                    ForEach(first.tags ?? [], id: \.self) { t in
                        VStack(spacing: 4) {
                            Rectangle().fill(Palette.hold(t)).frame(height: 16)
                                .overlay(Rectangle().strokeBorder(Palette.ruleStrong, lineWidth: Palette.needsHairline(t) ? 1 : 0))
                            Text(Vocab.colourCode(t)).font(.mono(8.5)).foregroundStyle(Palette.ink)
                        }
                    }
                    Text("HARD").font(.mono(9)).foregroundStyle(Palette.muted)
                }
            } else {
                let max = first.maxGrade ?? 12
                HStack(spacing: 2) {
                    ForEach(1...max, id: \.self) { g in
                        Text("\(g)").font(.mono(10, .medium)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(sent.contains(g) ? Palette.paper : Palette.ink)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(sent.contains(g) ? Palette.ink : Palette.card)
                            .overlay(Rectangle().strokeBorder(Palette.rule, lineWidth: sent.contains(g) ? 0 : 1))
                    }
                    if max < 15 {
                        Text("NO \(max + 1)–15\(first.offset < 0 ? " · SOFT" : first.offset > 0 ? " · HARD" : "")")
                            .font(.mono(8.5)).foregroundStyle(Palette.faint).lineLimit(1).minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .overlay(Rectangle().strokeBorder(Palette.ruleStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            .layoutPriority(-1)
                            .frame(width: nil)
                    }
                }
            }
            if gyms.count == 1 && sends == 0 {
                LinkButton(title: "Remove", color: Palette.faint) { store.deleteGym(first.id) }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Hairline() }
    }

    func meta(_ g: Gym, shared: Bool) -> String {
        if g.isRanked { return "COLOUR TAGS ONLY" }
        var parts = ["NUMBERS", "MAX \(g.maxGrade ?? 12)"]
        if shared { parts.append("ONE SHARED SCALE") }
        else if g.offset != 0 { parts.append("OFFSET \(g.offset > 0 ? "+" : "−")\(abs(g.offset).formatted())") }
        else if g.id == "batuu" { parts.append("REFERENCE") }
        return parts.joined(separator: " · ")
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
            TextFieldRow(label: "NAME", placeholder: "Camp5 KL Gateway", text: $name).padding(.bottom, 14)
            Text("Grades").micro().padding(.bottom, 10)
            SquareSegment(options: [(false, "Numbers"), (true, "Colour tags")], selection: $ranked).padding(.bottom, 16)
            if !ranked {
                FieldRow(label: "MAX GRADE") {
                    Spacer()
                    SquareStepper(value: "\(maxGrade)", decrement: { maxGrade = max(1, maxGrade - 1) }, increment: { maxGrade = min(20, maxGrade + 1) })
                }
                .padding(.bottom, 8)
            }
            FieldRow(label: "OFFSET VS BATUU") {
                Spacer()
                SquareStepper(value: offset == 0 ? "0" : "\(offset > 0 ? "+" : "−")\(abs(offset).formatted())",
                              decrement: { offset = max(-1, offset - 0.5) }, increment: { offset = min(1, offset + 0.5) })
            }
            Text("Offset is the soft/hard correction against Batuu, −1 to +1 in steps of 0.5. A soft gym gets a negative offset so its 10 does not count as a Batuu 10 in aggregate charts.")
                .font(.sans(12.5)).foregroundStyle(Palette.muted).padding(.top, 10)
        }
    }
}
