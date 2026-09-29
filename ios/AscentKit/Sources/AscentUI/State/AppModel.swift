import SwiftUI
import WidgetKit
import AscentCore
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// Owns the app's state and wires the side effects of a write: widget reloads and the Live Activity.
@MainActor
@Observable
public final class AppModel {
    public let store: AscentStore
    public let settings: AppSettings
    public let router: Router
    public let lock: AppLock
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    public init(store: AscentStore? = nil, settings: AppSettings? = nil) {
        AscentFonts.register()
        let settings = settings ?? AppSettings()
        self.store = store ?? AscentStore()
        self.settings = settings
        self.router = Router()
        self.lock = AppLock(settings: settings)
        Self.styleNavigationBars()
        self.store.onChange = { [weak self] db in self?.didWrite(db) }
        settings.onWidgetRelevantChange = { [weak self] in
            guard let self else { return }
            self.reloadWidgets()
            LiveActivityController.sync(self.store.db, privacyLock: self.settings.faceIDLock)
        }
        LiveActivityController.sync(self.store.db, privacyLock: settings.faceIDLock)
    }

    private func didWrite(_ db: Database) {
        reloadWidgets()
        LiveActivityController.sync(db, privacyLock: settings.faceIDLock)
    }

    /// Coalesces bursts of writes (a tally run) into one reload.
    private func reloadWidgets() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Large titles in Newsreader 36, inline titles in Archivo SemiBold 16 (DESIGN §3).
    static func styleNavigationBars() {
        #if canImport(UIKit)
        let serif = UIFontDescriptor(fontAttributes: [.family: "Newsreader"])
        let sans = UIFontDescriptor(fontAttributes: [.family: "Archivo"])
            .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        let large = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: UIFont(descriptor: serif, size: 36))
        let inline = UIFontMetrics(forTextStyle: .headline).scaledFont(for: UIFont(descriptor: sans, size: 16))
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: large]
        UINavigationBar.appearance().titleTextAttributes = [.font: inline]
        #endif
    }
}

/// Starts, updates and ends the ActivityKit Live Activity so it always mirrors the live session.
enum LiveActivityController {
    @MainActor
    static func sync(_ db: Database, privacyLock: Bool) {
        #if canImport(ActivityKit) && os(iOS)
        let live = db.activeSession
        let state = LiveSessionState.from(db, privacyLock: privacyLock)
        let stale = Date.now.addingTimeInterval(8 * 3600)
        Task {
            for activity in Activity<LiveSessionAttributes>.activities {
                if activity.attributes.sessionId != live?.id {
                    // The session ended (or was replaced): close it with its final numbers.
                    await activity.end(nil, dismissalPolicy: .immediate)
                } else if let state {
                    await activity.update(ActivityContent(state: state, staleDate: stale))
                }
            }
            guard let live, let state,
                  !Activity<LiveSessionAttributes>.activities.contains(where: { $0.attributes.sessionId == live.id }),
                  ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            _ = try? Activity.request(attributes: LiveSessionAttributes(sessionId: live.id),
                                      content: ActivityContent(state: state, staleDate: stale))
        }
        #endif
    }
}
