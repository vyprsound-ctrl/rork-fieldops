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
    @Environment(\.scenePhase) private var scenePhase

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
                // No active subscription = no working workspace.
                switch env.workspaceGate {
                case .checking:
                    ZStack {
                        Theme.canvas.ignoresSafeArea()
                        LoadingStateView(message: "Opening your workspace")
                    }
                case .memberLocked:
                    WorkspaceLockedView()
                case .memberSeatResolution:
                    WorkspaceLockedView(reason: .seatResolution)
                case .ownerReadOnly:
                    OwnerReadOnlyShellView()
                case .ownerSeatResolution:
                    OwnerReadOnlyShellView(reason: .seatResolution)
                case .open:
                    if session.role.usesFieldShell {
                        EngineerShellView()
                    } else {
                        OwnerShellView()
                    }
                }
            } else {
                SignInView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: env.session)
        .animation(.easeInOut(duration: 0.25), value: env.productionSession)
        .animation(.easeInOut(duration: 0.25), value: env.pendingPasswordReset)
        .animation(.easeInOut(duration: 0.25), value: env.workspaceGate)
        .sheet(item: $deepLinkRoute) { route in
            NavigationStack {
                RouteDestinationView(route: route)
                    // A destination opened from a notification can push
                    // further — a conversation about a job offers to open that
                    // job. Without these the link renders as a dead row inside
                    // the sheet, because the presented stack knows none of the
                    // route types the tab stacks register.
                    .navigationDestination(for: FieldJobRoute.self) { field in
                        FieldWorkerJobView(jobID: field.jobID)
                    }
                    .navigationDestination(for: OfficeThreadRoute.self) { thread in
                        OfficeConversationView(threadID: thread.threadID)
                    }
                    .navigationDestination(for: AppRoute.self) { next in
                        RouteDestinationView(route: next)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { deepLinkRoute = nil }
                        }
                    }
            }
        }
        .task {
            env.startStoreListener()
            await env.restoreProductionSession()
            consumePendingDeepLink()
        }
        .task(id: env.productionSession?.userID) {
            await env.syncStoreEntitlements()
        }
        .task(id: env.signedInSession?.userID) {
            await env.refreshWorkspaceAccess()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, env.signedInSession != nil else { return }
            Task { await env.refreshWorkspaceAccess() }
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
        guard env.activeSession != nil, !env.workspaceGate.isMemberLocked else { return }
        guard let route = PushDeepLinkInbox.shared.consume() else { return }
        deepLinkRoute = route
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment())
}
