import SwiftUI

/// 5.1 — full-screen paper overlay above everything. Auto-evaluates on appear.
public struct LockView: View {
    @Environment(AppLock.self) private var lock
    @Environment(\.accent) private var accent
    @Environment(\.scenePhase) private var phase

    var autoPrompt: Bool

    public init(autoPrompt: Bool = true) { self.autoPrompt = autoPrompt }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Text("ASCENT").font(.sans(15, .semibold)).tracking(3.6)
                Text("Your log is locked").font(.serif(30, relativeTo: .title)).padding(.top, 6)
                Text("Stored only on this iPhone").micro()
                if let err = lock.lastError {
                    Text(err).font(.sans(12)).foregroundStyle(Palette.muted).padding(.top, 6)
                }
            }
            .foregroundStyle(Palette.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 40)
            Spacer()
            GlassEffectContainer {
                Button { Task { await lock.authenticate() } } label: {
                    Label(lock.kind == .passcode ? "Unlock with passcode" : "Unlock with Face ID",
                          systemImage: lock.kind == .passcode ? "lock.open" : "faceid")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent.onAccent)
                        .padding(.horizontal, 24).frame(height: 54)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(accent.color).interactive(), in: .capsule)
            }
            if lock.kind != .passcode {
                LinkButton(title: "Use passcode", color: Palette.ink, size: 14) { Task { await lock.authenticate(passcodeOnly: true) } }
                    .padding(.top, 16)
            }
            Spacer().frame(height: 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.paper.ignoresSafeArea())
        .task {
            if autoPrompt && phase == .active { await lock.authenticate() }
        }
    }
}

/// 5.5 — shown in the app switcher while the lock is on.
public struct PrivacyCover: View {
    public init() {}
    public var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Palette.paper.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 22, weight: .semibold))
                Text("ASCENT").font(.sans(13, .semibold)).tracking(3.1)
            }
            .foregroundStyle(Palette.ink)
        }
    }
}
