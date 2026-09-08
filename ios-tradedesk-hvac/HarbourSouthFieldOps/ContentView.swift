import SwiftUI

/// Root router.
///
/// Both stacks route by role into the same two shells. Which data a shell
/// receives is decided by the data layer, not here: `AppEnvironment.gateway`
/// resolves to Supabase for a production session and to the seeded store for a
/// development one, so a shell never needs to know which stack it is on.
///
/// A production session still takes precedence over a development one, and a
/// field worker never receives the office shell.
struct ContentView: View {
    @Environment(AppEnvironment.self) private var env

    /// A destination a notification tap asked for.
    ///
    /// Presented from the root rather than pushed onto one tab's stack: the tap
    /// has to open the job from wherever the person already was, and the office
    /// shell has five independent stacks.
    @State private var deepLinkRoute: AppRoute?

    var body: some View {
        Group {
            if env.authPhase == .restoring {
                ZStack {
                    Theme.canvas.ignoresSafeArea()
                    LoadingStateView(message: "Restoring your session")
                }
            } else if env.pendingPasswordReset != nil {
                // A recovery link authenticated somebody who has not chosen a
                // password yet. This takes precedence over every other signed-in
                // state: the session exists but is deliberately withheld until
                // the reset finishes, so nobody lands in the shell mid-flow.
                ChooseNewPasswordView()
            } else if let session = env.activeSession {
                if session.role.usesFieldShell {
                    FieldWorkerDayView()
                } else {
                    OwnerShellView()
                }
            } else {
                SignInView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: env.session)
        .animation(.easeInOut(duration: 0.25), value: env.productionSession)
        .animation(.easeInOut(duration: 0.25), value: env.pendingPasswordReset)
        .sheet(item: $deepLinkRoute) { route in
            NavigationStack {
                RouteDestinationView(route: route)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { deepLinkRoute = nil }
                        }
                    }
            }
        }
        .task {
            await env.restoreProductionSession()
            consumePendingDeepLink()
        }
        .onChange(of: PushDeepLinkInbox.shared.pending) { _, _ in
            consumePendingDeepLink()
        }
    }

    /// A tap that arrived while the app was launching, or while the session was
    /// still being restored, is held until there is somewhere safe to send it.
    ///
    /// The session check is the important part: a parked route must never
    /// navigate a signed-out user into a tenant screen.
    private func consumePendingDeepLink() {
        guard env.activeSession != nil else { return }
        guard let route = PushDeepLinkInbox.shared.consume() else { return }
        deepLinkRoute = route
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment())
}
