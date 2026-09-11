import SwiftUI

/// Settings shell.
///
/// Every row here goes to a real screen. There are no placeholder rows left:
/// company profile and the tax default now have their own screens, so nothing
/// in Settings opens a sheet explaining that it does not work yet.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group(
                    title: "Business",
                    rows: [
                        SettingsRow(
                            title: "Company profile",
                            symbol: "building.2.fill",
                            permission: .companyProfileRead,
                            route: .companyProfile
                        ),
                        // The business's customer-facing email identity, so
                        // invoices read as the trade business rather than as
                        // the software it runs on.
                        SettingsRow(
                            title: "Email & Invoicing",
                            symbol: "envelope.fill",
                            permission: .companyProfileRead,
                            route: .businessEmail
                        ),
                        SettingsRow(
                            title: "Users and roles",
                            symbol: "person.2.badge.gearshape.fill",
                            permission: .usersManage,
                            route: .fieldWorkers
                        ),
                        SettingsRow(
                            title: "Payment terms",
                            symbol: "calendar.badge.clock",
                            permission: .companyProfileRead,
                            route: .paymentTerms
                        )
                    ]
                )

                // Integrations → Payments → Stripe. The payment link is no
                // longer a top-level row: it is one of the two models offered
                // inside the Payments screen, not the headline way to take
                // money.
                group(
                    title: "Integrations",
                    rows: [
                        SettingsRow(
                            title: "Payments",
                            symbol: "creditcard.and.123",
                            permission: .saasBillingRead,
                            route: .payments_integration
                        ),
                        SettingsRow(
                            title: "SMS credits",
                            symbol: "message.fill",
                            permission: .smsLedgerRead,
                            route: .smsCredits
                        )
                    ]
                )

                group(
                    title: "Subscription",
                    rows: [
                        SettingsRow(
                            title: "Plan and users",
                            symbol: "creditcard.fill",
                            permission: .saasBillingRead,
                            route: .subscription
                        ),
                        SettingsRow(
                            title: "Recurring service",
                            symbol: "arrow.triangle.2.circlepath",
                            permission: .jobsReadAll,
                            route: .recurring
                        )
                    ]
                )

                group(
                    title: "Transparency",
                    rows: [
                        SettingsRow(title: "Role & data access", symbol: "lock.shield.fill", permission: nil, route: .dataAccess),
                        SettingsRow(title: "Integration status", symbol: "app.connected.to.app.below.fill", permission: nil, route: .integrations)
                    ]
                )
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private struct SettingsRow: Identifiable {
        let title: String
        let symbol: String
        let permission: Permission?
        var route: MoreSection?
        var id: String { title }
    }

    private func group(title: String, rows: [SettingsRow]) -> some View {
        let visible = rows.filter { row in
            guard let permission = row.permission else { return true }
            return session?.can(permission) ?? false
        }

        return Group {
            if visible.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .sectionLabelStyle()

                    VStack(spacing: 0) {
                        ForEach(Array(visible.enumerated()), id: \.element.id) { index, row in
                            rowView(row)
                            if index < visible.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .cardSurface()
                }
            }
        }
    }

    /// Every row has a destination. The optional `route` is kept so the type
    /// still describes a row that has not been built — but there are none, and
    /// a row without one is simply not rendered rather than opening a dead end.
    @ViewBuilder
    private func rowView(_ row: SettingsRow) -> some View {
        if let route = row.route {
            NavigationLink(value: AppRoute.more(route)) {
                rowLabel(row)
            }
            .buttonStyle(.plain)
        }
    }

    private func rowLabel(_ row: SettingsRow) -> some View {
        HStack(spacing: 12) {
            Image(systemName: row.symbol)
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 8))
            Text(row.title)
                .font(.body)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }
}

extension String: @retroactive Identifiable {
    public var id: String { self }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppEnvironment())
    }
}
