import SwiftUI
import AscentCore
#if canImport(UIKit)
import UIKit
#endif

/// The app: five tabs in the floating glass bar, the + above it, sheets, lock (DESIGN §1–2, §5).
public struct AscentRoot: View {
    let model: AppModel

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        RootView()
            .environment(model.store)
            .environment(model.settings)
            .environment(model.router)
            .environment(model.lock)
            .environment(\.accent, model.settings.accent)
            .preferredColorScheme(model.settings.appearance.scheme)
            .tint(model.settings.accent.color)
    }
}

struct RootView: View {
    @Environment(AscentStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @Environment(AppLock.self) private var lock
    @Environment(\.accent) private var accent
    @Environment(\.scenePhase) private var phase
    @Namespace private var ns
    #if canImport(UIKit)
    @State private var overlay = OverlayWindowController()
    #endif

    var body: some View {
        @Bindable var router = router
        GeometryReader { geo in
            let hasIsland = geo.safeAreaInsets.top >= 51
            let bottomInset = geo.safeAreaInsets.bottom
            TabView(selection: Binding(get: { router.tab }, set: { router.select($0) })) {
                Tab("Today", systemImage: "chart.bar", value: AppTab.today) { stack(.today) { TodayView() } }
                Tab("Plan", systemImage: "list.bullet.clipboard", value: AppTab.plan) { stack(.plan) { PlanView() } }
                Tab("History", systemImage: "clock", value: AppTab.history) { stack(.history) { HistoryView() } }
                Tab("Body", systemImage: "figure.stand", value: AppTab.body) { stack(.body) { BodyView() } }
                Tab("Settings", systemImage: "gearshape", value: AppTab.settings) { stack(.settings) { SettingsView() } }
            }
            .noSystemTabBarMinimize()
            .overlay(alignment: .bottom) {
                PlusButton(ns: ns, hasIsland: hasIsland, bottomInset: bottomInset)
            }
            // Above the + (and the timer capsule on phones without a Dynamic Island), from the safe area; the
            // overlay adds the bar's height itself, so this view doesn't re-render when the bar hides.
            .toastOverlay(inSheet: false, bottom: 60 + (store.db.activeSession != nil && !hasIsland ? 34 : 0),
                          clearsTabBar: true)
            .ignoresSafeArea(.keyboard)
            .environment(\.hasDynamicIsland, hasIsland)
        }
        .sheet(item: $router.sheet) { route in
            sheet(route)
                .environment(store).environment(settings).environment(router).environment(lock)
                .environment(\.accent, accent)
                .preferredColorScheme(settings.appearance.scheme)
                .tint(accent.color)
        }
        .onChange(of: router.tab) { router.barHidden = false }
        .onOpenURL { router.open($0, hasLiveSession: store.db.activeSession != nil) }
        .onChange(of: phase) { _, p in
            lock.scenePhaseChanged(to: p)
            if p == .active { store.reload() }
        }
        #if canImport(UIKit)
        .background(WindowSceneReader { scene in
            overlay.install(in: scene) {
                LockOverlayContent()
                    .environment(store).environment(settings).environment(router).environment(lock)
            }
            overlay.setVisible(shouldCover)
        })
        .onChange(of: shouldCover) { _, v in overlay.setVisible(v) }
        .onChange(of: settings.appearance) { _, a in overlay.setStyle(a) }
        #else
        .overlay { if shouldCover { LockOverlayContent() } }
        #endif
    }

    var shouldCover: Bool { lock.isLocked || (settings.faceIDLock && phase != .active) }

    func stack<V: View>(_ tab: AppTab, @ViewBuilder root: () -> V) -> some View {
        NavigationStack(path: router.path(tab)) {
            root()
                .tracksBarScroll()
                .contentMargins(.bottom, 20, for: .scrollContent)
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case .session(let id): SessionDetailView(sessionId: id)
                        case .comp(let id): CompDetailView(compId: id)
                        case .planDay(let day): PlanDayScreen(date: day)
                        case .gyms: GymsView()
                        }
                    }
                    .tracksBarScroll()
                }
        }
    }

    @ViewBuilder func sheet(_ route: SheetRoute) -> some View {
        switch route {
        case .quickAdd: QuickAddSheet().zoomTransition("plus", in: ns)
        case .logging(let start, let step): LoggingSheet(start: start, step: step).toastOverlay(inSheet: true, bottom: 120)
        case .reviewEdit(let id): LoggingSheet(start: false, step: .review, reviewSessionId: id)
        case .painCheckIn: PainCheckInSheet()
        case .rehabToday: RehabTodaySheet()
        case .compEditor(let c, let d): CompEditorSheet(compId: c, presetDate: d)
        case .newInjury: InjuryEditorSheet(injuryId: nil)
        case .editInjury(let id): InjuryEditorSheet(injuryId: id)
        case .addExercise(let id): AddExerciseSheet(injuryId: id)
        case .addLoadRule(let id): AddLoadRuleSheet(injuryId: id)
        case .addGym: AddGymSheet()
        }
    }
}

struct LockOverlayContent: View {
    @Environment(AppLock.self) private var lock
    @Environment(AppSettings.self) private var settings
    var body: some View {
        // Read the accent here: the overlay window is installed once, so a captured value would go stale.
        Group {
            if lock.isLocked { LockView() } else { PrivacyCover() }
        }
        .environment(\.accent, settings.accent)
        .tint(settings.accent.color)
    }
}

/* ── The + (DESIGN §2) ──────────────────────────────────────────────────── */

struct PlusButton: View {
    @Environment(AscentStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.accent) private var accent
    var ns: Namespace.ID
    var hasIsland: Bool
    var bottomInset: CGFloat

    var body: some View {
        let live = store.db.activeSession
        let min = router.barHidden
        let size: CGFloat = min ? 48 : 58
        let ring = live != nil && hasIsland
        // Measured from the bottom safe area (the overlay stays inside it). On iOS 26 the floating bar's top sits
        // 48 pt above that line, so 58 leaves the spec's 10 pt gap. The live ring sits 8 pt outside the circle and
        // lifts the + by as much, so the ring keeps that gap too. With the bar away, the + drops to its row.
        let bottom: CGFloat = (min ? (bottomInset > 0 ? 4 : 14) : (bottomInset > 0 ? 58 : 78)) + (ring ? 8 : 0)

        GlassEffectContainer(spacing: 8) {
            VStack(spacing: min ? 6 : 8) {
                if let live, !hasIsland, let start = live.startedAt {
                    Button { router.sheet = .logging(start: false, step: .log(.gym)) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(accent.color).frame(width: 6, height: 6)
                            Text(timerInterval: start...Date.distantFuture, countsDown: false)
                                .font(.mono(11, .semibold)).monospacedDigit()
                                .foregroundStyle(Palette.ink)
                        }
                        .padding(.horizontal, 10).frame(height: 26)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Session running, \(spokenDuration(from: start))")
                    .accessibilityHint("Opens the log")
                }
                Button { router.sheet = .quickAdd } label: {
                    Image(systemName: "plus")
                        .font(.system(size: min ? 22 : 26, weight: .semibold))
                        .foregroundStyle(accent.onAccent)
                        .frame(width: size, height: size)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(accent.color).interactive(), in: .circle)
                .overlay {
                    if ring {
                        Circle().strokeBorder(accent.color.opacity(0.85), lineWidth: 2).padding(-8).allowsHitTesting(false)
                    }
                }
                .matchedTransitionSource(id: "plus", in: ns)
                .accessibilityLabel("Quick add")
                .accessibilityHint("Log a send, board climb, pain or rehab")
                .sensoryFeedback(.impact(weight: .light), trigger: router.sheet == .quickAdd)
            }
        }
        .padding(.bottom, bottom)
        .animation(.snappy, value: min)
        .animation(.snappy, value: live?.id)
    }
}

/* ── Tab bar follows the scroll direction ──────────────────────────────── */

/// Hides the tab bar while scrolling down and brings it back while scrolling up, anywhere on the page. The system
/// minimise can't be read or steered (it also re-expands on the bounce at either end), so the app owns the state
/// and the + follows the same flag.
///
/// Showing or hiding the bar changes the page's insets: the content offset shifts and the scrollable height
/// changes by about the bar's height, so at the bottom the page is suddenly past its end and rubber-bands back.
/// Counted as scrolling, either flips the bar straight back (a feedback loop: the bar lingers, the + bounces). So
/// only movement the user drives counts: while the finger is on the page, or while a fling coasts on in its own
/// direction (a reversal after the finger lifts is the bounce), inside the page's normal range, with an unchanged
/// scrollable height, and not in the moment after a toggle.
///
/// Every tab stays alive and a page can hold several scroll views (chip strips), all reported through the same
/// callbacks, so only the page on screen reacts and only its main vertical scroller counts.
struct BarScrollTracker: ViewModifier {
    @Environment(Router.self) private var router
    /// A plain box, not observed state: writing it from the scroll callbacks must not re-render the page.
    @State private var state = TrackState()

    final class TrackState {
        var visible = false
        var phase = ScrollPhase.idle
        /// Direction of the last finger movement (+1 down the page, −1 up); a fling keeps it while coasting.
        var direction: CGFloat = 0
        var last: Sample?
        /// Distance scrolled in the current direction; flips reset it.
        var travel: CGFloat = 0
        /// Offset changes before this come from the bar's own inset change, not the user.
        var settleUntil = Date.distantPast
    }

    struct Sample: Equatable {
        var offset: CGFloat
        var maxOffset: CGFloat
    }

    /// Chip strips and other short scrollers aren't the page.
    static func isPage(_ g: ScrollGeometry) -> Bool { g.containerSize.height > 300 }

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase, context in
                guard Self.isPage(context.geometry) else { return }
                state.phase = phase
            }
            .onScrollGeometryChange(for: Sample?.self) { g in
                guard Self.isPage(g) else { return nil }
                return Sample(offset: g.contentOffset.y + g.contentInsets.top,
                              maxOffset: max(0, g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom - g.containerSize.height))
            } action: { _, new in
                guard state.visible, let new else { return }
                let previous = state.last
                state.last = new
                // Near the top the bar always shows, however the page got there.
                if new.offset < 24 { state.travel = 0; setHidden(false); return }
                guard state.phase == .interacting || state.phase == .decelerating,
                      Date.now >= state.settleUntil, let previous,
                      previous.maxOffset == new.maxOffset,
                      (0...new.maxOffset).contains(previous.offset), (0...new.maxOffset).contains(new.offset)
                else { return }
                let delta = new.offset - previous.offset
                guard delta != 0 else { return }
                if state.phase == .interacting {
                    state.direction = delta > 0 ? 1 : -1
                } else if (delta > 0 ? 1 : -1) != state.direction {
                    return
                }
                if (delta > 0) != (state.travel > 0) { state.travel = 0 }
                state.travel += delta
                if state.travel > 12 { setHidden(true) } else if state.travel < -12 { setHidden(false) }
            }
            .tabBarHidden(router.barHidden)
            // Every page (a push, a pop back, a tab switch) starts with the bar showing.
            .onAppear {
                state.visible = true
                state.last = nil
                state.travel = 0
                setHidden(false)
            }
            .onDisappear { state.visible = false }
    }

    private func setHidden(_ hidden: Bool) {
        guard router.barHidden != hidden else { return }
        state.travel = 0
        state.settleUntil = .now.addingTimeInterval(0.35)
        withAnimation(.snappy(duration: 0.25)) { router.barHidden = hidden }
    }
}

extension View {
    func tracksBarScroll() -> some View { modifier(BarScrollTracker()) }
}

private struct HasIslandKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var hasDynamicIsland: Bool {
        get { self[HasIslandKey.self] }
        set { self[HasIslandKey.self] = newValue }
    }
}

/* ── Lock overlay window: above tabs *and* sheets ───────────────────────── */

#if canImport(UIKit)
@MainActor
final class OverlayWindowController {
    private var window: UIWindow?

    func install<V: View>(in scene: UIWindowScene, @ViewBuilder content: () -> V) {
        guard window == nil else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear
        w.rootViewController = host
        w.isHidden = true
        window = w
        setStyle(Appearance(rawValue: AppGroup.defaults.string(forKey: SharedKey.appearance) ?? "") ?? .system)
    }

    func setVisible(_ visible: Bool) {
        guard let window, window.isHidden == visible else { return }
        if visible {
            window.makeKeyAndVisible()
        } else {
            window.isHidden = true
            // Hand key status back to the app's own window so text fields and sheets keep working.
            window.windowScene?.windows.first { $0 !== window && !$0.isHidden }?.makeKey()
        }
    }

    func setStyle(_ a: Appearance) {
        window?.overrideUserInterfaceStyle = switch a {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

struct WindowSceneReader: UIViewRepresentable {
    var onScene: (UIWindowScene) -> Void

    func makeUIView(context: Context) -> SceneView {
        let v = SceneView()
        v.onScene = onScene
        v.isUserInteractionEnabled = false
        return v
    }

    func updateUIView(_ uiView: SceneView, context: Context) {}

    final class SceneView: UIView {
        var onScene: ((UIWindowScene) -> Void)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if let scene = window?.windowScene { onScene?(scene) }
        }
    }
}
#endif
