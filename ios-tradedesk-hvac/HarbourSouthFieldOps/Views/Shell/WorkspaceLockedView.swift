import SwiftUI

/// What every company member other than the owner sees while the company has
/// no active subscription. Nothing is deleted: the moment the owner renews,
/// the workspace opens again.
struct WorkspaceLockedView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isChecking: Bool = false

    static let message = "Your company's subscription has ended. Please ask the account owner to renew the subscription."

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 24)

                Image(systemName: "lock.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(width: 76, height: 76)
                    .background(Theme.primaryTint)
                    .clipShape(.circle)
                    .accessibilityHidden(true)

                VStack(spacing: 10) {
                    Text("Workspace paused")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(Self.message)
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
                }
            }
            .padding(Theme.margin)
            .frame(maxWidth: 520)
        }
        .sensoryFeedback(.warning, trigger: isChecking)
    }
}

#Preview {
    WorkspaceLockedView()
        .environment(AppEnvironment())
}
