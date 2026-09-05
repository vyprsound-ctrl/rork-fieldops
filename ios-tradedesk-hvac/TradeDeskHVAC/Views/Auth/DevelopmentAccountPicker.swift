import SwiftUI

/// DEVELOPMENT SIGN-IN — the seeded account picker.
///
/// Unchanged behaviour: credentials are not verified, and every seeded role and
/// both tenants can be exercised. Extracted from `SignInView` so the production
/// form could sit beside it without altering this path.
struct DevelopmentAccountPicker: View {
    @Environment(AppEnvironment.self) private var env
    @State private var accounts: [AuthAccount] = []
    @State private var isLoading: Bool = true
    @State private var selectedAccountID: String?

    private var groupedAccounts: [(company: String, trade: Trade, accounts: [AuthAccount])] {
        Dictionary(grouping: accounts, by: \.companyName)
            .map { (company: $0.key, trade: $0.value.first?.trade ?? .other, accounts: $0.value) }
            .sorted { $0.company < $1.company }
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingStateView(message: "Preparing accounts")
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    SimulatedServicesBanner()

                    ForEach(groupedAccounts, id: \.company) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Text(group.company)
                                    .sectionLabelStyle()
                                Text(group.trade.title)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Theme.primaryTint)
                                    .clipShape(.capsule)
                            }

                            VStack(spacing: 0) {
                                ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                                    Button {
                                        selectedAccountID = account.id
                                        Task { await env.signIn(accountID: account.id) }
                                    } label: {
                                        accountRow(account)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(env.isSigningIn)

                                    if index < group.accounts.count - 1 {
                                        Divider().padding(.leading, 62)
                                    }
                                }
                            }
                            .cardSurface()
                        }
                    }

                    if let error = env.signInError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tenant isolation check: signing in as a Northline Plumbing user must never surface Gulf Coast Air records.")
                        Text("Trade check: the two companies run different trades on the same schema — the field role reads as Engineer for one and Plumber for the other.")
                    }
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                }
            }
        }
        .task {
            accounts = await env.auth.availableAccounts()
            isLoading = false
        }
    }

    private func accountRow(_ account: AuthAccount) -> some View {
        HStack(spacing: 12) {
            Text(initials(for: account.name))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38)
                .background(Theme.primaryTint)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(account.roleSummary)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if env.isSigningIn, selectedAccountID == account.id {
                ProgressView()
            } else {
                Text(account.roleTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.canvas)
                    .clipShape(.rect(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .contentShape(.rect)
    }

    private func initials(for name: String) -> String {
        let parts = name.split(separator: " ")
        return String(parts.prefix(2).compactMap(\.first)).uppercased()
    }
}
