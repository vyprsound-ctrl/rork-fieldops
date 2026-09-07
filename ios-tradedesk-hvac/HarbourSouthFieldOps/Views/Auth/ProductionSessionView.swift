import SwiftUI

/// What a production-authenticated user sees.
///
/// The office and field shells are still wired to `MockDataGateway`, whose
/// records belong to seeded demo companies, so this screen deliberately does
/// not open them. What it does open is the one production surface that is fully
/// wired end to end: the job a notification refers to, read through the
/// Supabase gateway under this user's own RLS.
///
/// Notification permission is asked for here and nowhere else, from a control
/// the person taps after reading what the alerts are for.
struct ProductionSessionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    @State private var path = NavigationPath()
    @State private var alerts: [PushNotificationRecord] = []
    @State private var isLoadingAlerts: Bool = false

    private var session: TenantSession? { env.productionSession }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        if let session {
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

                            PushAlertsSection(alerts: alerts) { route in
                                path.append(route)
                            }

                            identityCard(session)
                            permissionsCard(session)
                        }

                        pendingCard

                        Button {
                            Task { await env.signOutOfProduction() }
                        } label: {
                            Text("Sign out")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: Theme.minTap)
                                .background(Theme.surface)
                                .foregroundStyle(Theme.red)
                                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                                .overlay {
                                    RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                        .stroke(Theme.border, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(Theme.margin)
                }
                .refreshable { await loadAlerts() }
            }
            .navigationDestination(for: AppRoute.self) { route in
                // Push events only ever address a job, but routing the rest
                // keeps a future event from landing nowhere.
                RouteDestinationView(route: route)
            }
        }
        .task {
            // Reads permission; deliberately does not ask for it.
            await env.refreshPushAuthorization()
            // Re-registers a device whose permission was granted in an earlier
            // session, because iOS can reissue the token at any time.
            await env.restorePushRegistration()
            await loadAlerts()
            consumePendingDeepLink()
        }
        .onChange(of: PushDeepLinkInbox.shared.pending) { _, _ in
            consumePendingDeepLink()
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

    /// A tap that arrived while the app was launching, or while the session was
    /// still being restored, is held until there is somewhere safe to send it.
    private func consumePendingDeepLink() {
        guard session != nil else { return }
        guard let route = PushDeepLinkInbox.shared.consume() else { return }
        path.append(route)
    }

    private func loadAlerts() async {
        guard let session else { return }
        isLoadingAlerts = true
        defer { isLoadingAlerts = false }
        alerts = (try? await env.gateway.pushInbox(session: session, limit: 20)) ?? []
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.green)
                Text("Signed in")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Theme.ink)
            }

            Text("Authenticated against the live database.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .padding(.top, 12)
    }

    private func identityCard(_ session: TenantSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resolved by the server")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                row("Name", session.displayName)
                Divider().padding(.leading, 14)
                row("Email", session.email)
                Divider().padding(.leading, 14)
                row("Company", session.companyID)
                Divider().padding(.leading, 14)
                row("Trade", session.trade.title)
                Divider().padding(.leading, 14)
                row("Role", session.roleTitle)
            }
            .cardSurface()

            Text("Company and role were read from your membership record via auth.uid(). This app never sends either value.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionsCard(_ session: TenantSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(session.permissions.count) permissions")
                .sectionLabelStyle()

            Text(session.permissions
                .map(\.rawValue)
                .sorted()
                .joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
        }
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(Theme.amber)
                Text("Production data not fully connected yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            Text("Authentication and job alerts are live. The customer, quote, invoice and payment screens still run on simulated data, so they stay closed rather than showing you another company's demo records. Opening a job from an alert reads your real data.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Use Development sign-in to explore the full app with simulated data.")
                .font(.footnote)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF8EB))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(Theme.amber.opacity(0.3), lineWidth: 1)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
    }
}
