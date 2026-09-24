import SwiftUI

/// The owner's workspace while the company has no active subscription.
///
/// Company data stays readable (the session is read-only, so create and edit
/// controls are withheld and the data layer refuses writes), a banner says
/// why, and "Choose a plan" is presented straight away — with Restore
/// purchases and Redeem code on the same screen.
struct OwnerReadOnlyShellView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var isChoosingPlan: Bool = true

    var body: some View {
        OwnerShellView()
            .safeAreaInset(edge: .top, spacing: 0) {
                banner
            }
            .sheet(isPresented: $isChoosingPlan) {
                NavigationStack {
                    SubscriptionView()
                        .navigationDestination(for: AppRoute.self) { route in
                            RouteDestinationView(route: route)
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("View data") { isChoosingPlan = false }
                                    .accessibilityIdentifier("workspace.readOnly.browse")
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Sign out", role: .destructive) {
                                    isChoosingPlan = false
                                    Task { await env.signOutOfCurrentSession() }
                                }
                            }
                        }
                }
            }
    }

    private var banner: some View {
        Button {
            isChoosingPlan = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.footnote.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("No active subscription · read-only")
                        .font(.footnote.weight(.semibold))
                    Text("Choose a plan to start working again.")
                        .font(.caption)
                        .opacity(0.85)
                }
                Spacer(minLength: 8)
                Text("Choose a plan")
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
