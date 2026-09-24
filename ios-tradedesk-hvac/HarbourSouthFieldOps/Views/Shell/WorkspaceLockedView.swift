import SwiftUI

/// Why a workspace is not open for normal work.
nonisolated enum WorkspaceLockReason: Equatable, Sendable {
    /// The company holds no entitled Harbour South subscription.
    case noSubscription
    /// Apple applied a smaller plan and the company has more active people
    /// than it allows; the owner is choosing who to deactivate.
    case seatResolution
}

/// What every company member other than the owner sees while the company has
/// no active subscription, or while the owner resolves seats after a
/// downgrade. Nothing is deleted and nobody is suspended by this: the moment
/// the owner renews (or resolves seats), the workspace opens again.
struct WorkspaceLockedView: View {
    @Environment(AppEnvironment.self) private var env
    var reason: WorkspaceLockReason = .noSubscription
    @State private var isChecking: Bool = false

    static let message = "Your company's subscription has ended. Please ask the account owner to renew the subscription."
    static let seatMessage = "Your company's Harbour South plan now allows fewer active users than your company has. The account owner needs to choose who stays active before work continues."

    private var title: String {
        reason == .seatResolution ? "Waiting for the owner" : "Workspace paused"
    }

    private var bodyText: String {
        reason == .seatResolution ? Self.seatMessage : Self.message
    }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 24)

                Image(systemName: reason == .seatResolution ? "person.2.slash" : "lock.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 76, height: 76)
                    .background(Theme.primaryTint)
                    .clipShape(.circle)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(bodyText)
                        .font(.body)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("workspace.locked.message")
                }

                Spacer(minLength: 24)

                VStack(spacing: 10) {
                    Button {
                        Task {
                            isChecking = true
                            await env.refreshWorkspaceAccess()
                            isChecking = false
                        }
                    } label: {
                        BrandButtonLabel(title: isChecking ? "Checking…" : "Check again", isWorking: isChecking)
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(isChecking)

                    Button {
                        Task { await env.signOutOfCurrentSession() }
                    } label: {
                        BrandOutlineLabel(title: "Sign out", symbol: "rectangle.portrait.and.arrow.right", tint: Theme.red)
                    }
                    .buttonStyle(PressableTileStyle())

                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        Text("Delete account")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.meta)
                            .frame(minHeight: Theme.minTap)
                    }
                    .accessibilityIdentifier("workspace.locked.deleteAccount")
                }
            }
            .padding(Theme.margin)
            .frame(maxWidth: 520)
        }
        .sensoryFeedback(.warning, trigger: isChecking)
    }
}

#Preview {
    NavigationStack {
        WorkspaceLockedView()
    }
    .environment(AppEnvironment())
}
