import SwiftUI

/// Job alerts for this device, and the alerts already addressed to this person.
///
/// This is the new home of the notification controls that used to sit on the
/// production landing screen. Nothing about the push architecture changed: the
/// same two components are reused, and `AppEnvironment.enablePushNotifications`
/// is still the only place in the app that can show the system prompt — reached
/// only from a control the person deliberately tapped.
struct NotificationsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    @State private var alerts: [PushNotificationRecord] = []
    @State private var isLoadingAlerts: Bool = false
    @State private var hasLoadedOnce: Bool = false

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if session != nil {
                    PushPermissionCard(
                        state: env.pushAuthorization,
                        isRegistered: env.isPushRegistered,
                        isWorking: env.isRegisteringForPush,
                        detail: env.pushStatusDetail,
                        worker: env.terms.worker
                    ) {
                        Task {
                            await env.enablePushNotifications()
                            await loadAlerts()
                        }
                    }

                    if isLoadingAlerts, !hasLoadedOnce {
                        LoadingStateView(message: "Loading your alerts")
                    } else {
                        PushAlertsSection(alerts: alerts) { _ in }
                    }

                    Text("Alerts are sent to the devices you have signed in on. Signing out removes this device, so a shared handset stops receiving your jobs.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Job alerts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await loadAlerts() }
        .task {
            // Reads permission; deliberately does not ask for it.
            await env.refreshPushAuthorization()
            // Re-registers a device whose permission was granted in an earlier
            // session, because iOS can reissue the token at any time.
            await env.restorePushRegistration()
            await loadAlerts()
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from Settings is the moment a refusal may have become
            // a grant, so the card stops being wrong as soon as they return.
            guard phase == .active else { return }
            Task {
                await env.refreshPushAuthorization()
                await loadAlerts()
            }
        }
    }

    private func loadAlerts() async {
        guard let session else { return }
        isLoadingAlerts = true
        defer {
            isLoadingAlerts = false
            hasLoadedOnce = true
        }
        alerts = (try? await env.gateway.pushInbox(session: session, limit: 20)) ?? []
    }
}

#Preview {
    NavigationStack {
        NotificationsView()
            .environment(AppEnvironment())
    }
}
