import SwiftUI
import Testing
import AppKit
@testable import AscentUI
@testable import AscentWidgetsUI
import AscentCore

@MainActor
@Suite struct Snapshots {
    static let demoNow: Date = {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 27; c.hour = 20; c.minute = 14
        return Day.calendar.date(from: c)!
    }()

    func env<V: View>(_ v: V, dark: Bool, width: CGFloat = 393, height: CGFloat, accent: String = "") -> some View {
        let store = AscentStore(database: Seed.demo(now: Self.demoNow))
        store.now = { Self.demoNow }
        let settings = AppSettings(defaults: UserDefaults(suiteName: "snapshots-\(UUID().uuidString)")!)
        settings.accentHex = accent
        return v
            .environment(store).environment(settings).environment(Router()).environment(AppLock(settings: settings))
            .environment(\.accent, AccentTheme(hex: accent))
            .environment(\.colorScheme, dark ? .dark : .light)
            .frame(width: width, height: height)
            .background(Palette.paper)
    }

    func write<V: View>(_ name: String, _ view: V, dark: Bool = false) {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] else { return }
        AscentFonts.register()
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { Issue.record("no rep \(name)"); return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    @Test func screens() {
        for dark in [false, true] {
            let sfx = dark ? "dark" : "light"
            NSApplication.shared.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            write("today-\(sfx)", env(TodayView(), dark: dark, height: 3600), dark: dark)
            write("plan-\(sfx)", env(ScrollView { PlanDayEditor(date: "2026-09-27") }, dark: dark, height: 1700), dark: dark)
            write("plan-taper-\(sfx)", env(ScrollView { PlanDayEditor(date: "2026-10-27") }, dark: dark, height: 1700), dark: dark)
            write("season-\(sfx)", env(ScrollView { SeasonView() }, dark: dark, height: 3600, accent: dark ? "" : "#2c55c7"), dark: dark)
            write("history-\(sfx)", env(HistoryView(), dark: dark, height: 1600), dark: dark)
            write("body-\(sfx)", env(BodyView(), dark: dark, height: 2600), dark: dark)
            write("settings-\(sfx)", env(SettingsView(), dark: dark, height: 1500), dark: dark)
            write("quickadd-\(sfx)", env(QuickAddSheet(), dark: dark, height: 452), dark: dark)
            write("log-\(sfx)", env(LoggingSheet(start: false, step: .log(.gym)), dark: dark, height: 1400), dark: dark)
            write("review-\(sfx)", env(LoggingSheet(start: false, step: .review), dark: dark, height: 1500), dark: dark)
            write("lock-\(sfx)", env(LockView(autoPrompt: false), dark: dark, height: 852), dark: dark)
        }
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        // Accessibility text sizes: heatmap in one column, calendar as week rows (DESIGN §7).
        write("today-ax", env(TodayView().environment(\.dynamicTypeSize, .accessibility2), dark: false, height: 5200))
        write("season-ax", env(ScrollView { SeasonView() }.environment(\.dynamicTypeSize, .accessibility2), dark: false, height: 4200))
        let summary = WidgetSummary.compute(Seed.demo(now: Self.demoNow), now: Self.demoNow)
        for (kind, w, h) in [(AscentWidgetKind.small, 170.0, 170.0), (.medium, 364, 170), (.large, 364, 382)] {
            for locked in [false, true] {
                let v = AscentWidgetView(kind: kind, summary: summary, privacyLock: true, accent: AccentTheme(hex: ""))
                    .redacted(reason: locked ? .privacy : [])
                    .padding(16).frame(width: w, height: h).background(Palette.paper)
                write("widget-\(kind)-\(locked ? "locked" : "open")", v)
            }
        }
    }
}

@MainActor
@Suite struct LockSnapshot {
    @Test func lockParts() {
        let s = Snapshots()
        s.write("lockexp-noGlass", s.env(ZStack { Palette.paper; VStack { Text("ASCENT"); Text("Your log is locked").font(.serif(30)) } }, dark: false, height: 400))
        s.write("lockexp-full", s.env(LockView(autoPrompt: false), dark: false, height: 852))
        s.write("lockexp-cover", s.env(PrivacyCover(), dark: false, height: 400))
    }
}
