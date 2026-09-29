import SwiftUI
import AscentCore

public enum AppTab: String, Hashable, CaseIterable, Sendable {
    case today, plan, history, body, settings
}

/// Pushes inside the tab stacks.
public enum Route: Hashable {
    case session(String)
    case comp(String)
    case planDay(String)
    case gyms
}

/// Steps inside the logging sheet's own stack.
public enum LogStep: Hashable {
    case log(LogMode)
    case review
}

public enum LogMode: String, Hashable { case gym, board }

/// Every sheet the app presents. Switching the item while one is up dismisses it and presents the next.
public enum SheetRoute: Identifiable, Hashable {
    case quickAdd
    /// start: show the Start session step first; then land on `step`
    case logging(start: Bool, step: LogStep)
    case painCheckIn
    case rehabToday
    case compEditor(compId: String?, date: String?)
    case newInjury
    case editInjury(String)
    case addExercise(injuryId: String)
    case addLoadRule(injuryId: String)
    case addGym
    case reviewEdit(sessionId: String)

    public var id: String {
        switch self {
        case .quickAdd: "quickAdd"
        case .logging(let s, let step): "logging-\(s)-\(step)"
        case .painCheckIn: "pain"
        case .rehabToday: "rehab"
        case .compEditor(let c, let d): "comp-\(c ?? "")-\(d ?? "")"
        case .newInjury: "newInjury"
        case .editInjury(let id): "editInjury-\(id)"
        case .addExercise(let id): "addExercise-\(id)"
        case .addLoadRule(let id): "addRule-\(id)"
        case .addGym: "addGym"
        case .reviewEdit(let id): "reviewEdit-\(id)"
        }
    }
}

public struct Toast: Equatable, Identifiable {
    public let id = UUID()
    public var title: String
    public var detail: String
    public var undo: (() -> Void)?

    public static func == (a: Toast, b: Toast) -> Bool { a.id == b.id }
}

@MainActor
@Observable
public final class Router {
    public var tab: AppTab = .today
    public var paths: [AppTab: NavigationPath] = [:]
    public var sheet: SheetRoute?
    public var planSegment: PlanSegment = .today
    public var toast: Toast?
    /// The tab bar slides away while scrolling down and returns while scrolling up; the + follows it.
    public var barHidden = false

    public init() {}

    public enum PlanSegment: String, Hashable { case today, season }

    public func path(_ tab: AppTab) -> Binding<NavigationPath> {
        Binding(get: { self.paths[tab] ?? NavigationPath() }, set: { self.paths[tab] = $0 })
    }

    /// Tapping the active tab pops it to the root.
    public func select(_ next: AppTab) {
        if next == tab { paths[next] = NavigationPath() }
        tab = next
    }

    /// Closes the sheet that's up, optionally landing on a tab's root. Views pushed inside a sheet's own
    /// stack can't use `dismiss` for this: there it only pops back a step.
    public func closeSheet(then next: AppTab? = nil) {
        sheet = nil
        if let next {
            paths[next] = NavigationPath()
            tab = next
        }
    }

    public func show(_ toast: Toast) {
        self.toast = toast
        let id = toast.id
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if self.toast?.id == id { self.toast = nil }
        }
    }

    /// `ascent://today`, `…/body`, `…/log`, `…/review`, `…/rehab`, `…/season`
    public func open(_ url: URL, hasLiveSession: Bool) {
        guard url.scheme == "ascent" else { return }
        switch url.host() ?? url.path() {
        case "today": sheet = nil; tab = .today
        case "body": sheet = nil; tab = .body
        case "season": sheet = nil; tab = .plan; planSegment = .season
        case "log": sheet = .logging(start: !hasLiveSession, step: .log(.gym))
        case "review": sheet = .logging(start: false, step: .review)
        case "rehab": sheet = .rehabToday
        default: break
        }
    }
}
