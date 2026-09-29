import SwiftUI
import LocalAuthentication

/// Face ID app lock (DESIGN §5). iOS supplies the passcode fallback through `.deviceOwnerAuthentication`.
@MainActor
@Observable
public final class AppLock {
    public private(set) var isLocked: Bool
    public private(set) var isAuthenticating = false
    public var lastError: String?
    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private let settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
        // Cold launch always locks.
        isLocked = settings.faceIDLock
    }

    public enum Kind { case faceID, touchID, opticID, passcode, unavailable }

    /// What this device can use. Unavailable = no passcode set, so the toggle is disabled.
    public var kind: Kind {
        let ctx = LAContext()
        var err: NSError?
        let canBio = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        if canBio {
            switch ctx.biometryType {
            case .faceID: return .faceID
            case .touchID: return .touchID
            case .opticID: return .opticID
            default: break
            }
        }
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) ? .passcode : .unavailable
    }

    public var rowTitle: String {
        switch kind {
        case .faceID, .unavailable: "Face ID lock"
        case .touchID: "Touch ID lock"
        case .opticID: "Optic ID lock"
        case .passcode: "Passcode lock"
        }
    }

    /// Runs the system prompt. iOS has no passcode-only policy, so "Use passcode" runs the same one and the
    /// system offers the passcode as soon as Face ID is declined.
    @discardableResult
    public func authenticate(passcodeOnly: Bool = false) async -> Bool {
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "Use Passcode"
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your climbing log")
            if ok { isLocked = false; lastError = nil }
            return ok
        } catch {
            lastError = (error as? LAError)?.code == .userCancel ? nil : error.localizedDescription
            return false
        }
    }

    /// Turning the lock on needs one successful evaluation first.
    public func setEnabled(_ on: Bool) async {
        if !on { settings.faceIDLock = false; isLocked = false; return }
        let ctx = LAContext()
        do {
            if try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Turn on the lock for your climbing log") {
                settings.faceIDLock = true
            }
        } catch {
            settings.faceIDLock = false
        }
    }

    /// Record the time on `.background`; on `.active`, lock if the Require interval has passed.
    public func scenePhaseChanged(to phase: ScenePhase) {
        guard settings.faceIDLock else { isLocked = false; return }
        switch phase {
        case .background:
            backgroundedAt = backgroundedAt ?? .now
        case .active:
            if let at = backgroundedAt, Date.now.timeIntervalSince(at) >= Double(settings.requireInterval.rawValue) {
                isLocked = true
            }
            backgroundedAt = nil
        default:
            break
        }
    }
}
