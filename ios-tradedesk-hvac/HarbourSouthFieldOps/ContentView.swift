import SwiftUI

/// Root router.
///
/// A production session takes precedence and routes to its own screen: the
/// office and field shells read from `MockDataGateway`, so a real authenticated
/// user must not be sent into them. The signed-in role decides which simulated
/// shell loads in development — field workers never receive the office shell.
struct ContentView: View {
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if env.authPhase == .restoring {
                ZStack {
                    Theme.canvas.ignoresSafeArea()
                    LoadingStateView(message: "Restoring your session")
                }
            } else if env.productionSession != nil {
                ProductionSessionView()
            } else if let session = env.session {
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
        .task {
            await env.restoreProductionSession()
        }
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment())
}
