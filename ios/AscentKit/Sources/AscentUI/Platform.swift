import SwiftUI

/// iOS-only modifiers behind one name, so the package also compiles (and renders previews) on macOS.
extension View {
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    func largeTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    /// The app drives the bar itself (`tabBarHidden`), so the system's own minimise stays off.
    func noSystemTabBarMinimize() -> some View {
        #if os(iOS)
        tabBarMinimizeBehavior(.never)
        #else
        self
        #endif
    }

    func tabBarHidden(_ hidden: Bool) -> some View {
        #if os(iOS)
        toolbarVisibility(hidden ? .hidden : .visible, for: .tabBar)
        #else
        self
        #endif
    }

    func numberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    func sentenceCase() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.sentences)
        #else
        self
        #endif
    }

    /// Zoom from the + into the quick-add selector.
    func zoomTransition(_ id: String, in ns: Namespace.ID) -> some View {
        #if os(iOS)
        navigationTransition(.zoom(sourceID: id, in: ns))
        #else
        self
        #endif
    }
}

extension ToolbarItemPlacement {
    static var trailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    static var leading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }
}
