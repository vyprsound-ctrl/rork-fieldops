import SwiftUI

/// The owner's workspace while it is not open for normal work.
///
/// Two reasons, one shape:
///   * no active subscription — "Choose a plan" is presented straight away,
///     with Restore purchases and Redeem code on the same screen;
///   * seat resolution — Apple applied a smaller plan and the company has more
///     active people than it allows. The owner chooses who to deactivate.
///
/// Company data stays readable either way. The session is read-only, so
/// create and edit controls are withheld and the data layer refuses writes;
/// managing people and the subscription stay available.
struct OwnerReadOnlyShellView: View {
    @Environment(AppEnvironment.self) private var env
    var reason: WorkspaceLockReason = .noSubscription
    @State private var isResolving: Bool = true

    var body: some View {
        OwnerShellView()
            .safeAreaInset(edge: .top, spacing: 0) {
                banner
            }
            .sheet(isPresented: $isResolving) {
                NavigationStack {
                    Group {
                        if reason == .seatResolution {
                            SeatResolutionView()
                        } else {
                            SubscriptionView()
                        }
                    }
                    .navigationDestination(for: AppRoute.self) { route in
                        RouteDestinationView(route: route)
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("View data") { isResolving = false }
                                .accessibilityIdentifier("workspace.readOnly.browse")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Sign out", role: .destructive) {
                                isResolving = false
                                Task { await env.signOutOfCurrentSession() }
                            }
                        }
                    }
                }
            }
    }

    private var bannerTitle: String {
        reason == .seatResolution ? "Too many active users · read-only" : "No active subscription · read-only"
    }

    private var bannerDetail: String {
        reason == .seatResolution ? "Choose who stays active to continue." : "Choose a plan to start working again."
    }

    private var bannerAction: String {
        reason == .seatResolution ? "Resolve" : "Choose a plan"
    }

    private var banner: some View {
        Button {
            isResolving = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: reason == .seatResolution ? "person.2.slash" : "lock.fill")
                    .font(.footnote.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(bannerTitle)
                        .font(.footnote.weight(.semibold))
                    Text(bannerDetail)
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 8)
                Text(bannerAction)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.18))
                    .clipShape(.capsule)
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.brandNavy)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workspace.readOnly.banner")
    }
}

#Preview {
    OwnerReadOnlyShellView()
        .environment(AppEnvironment())
}
