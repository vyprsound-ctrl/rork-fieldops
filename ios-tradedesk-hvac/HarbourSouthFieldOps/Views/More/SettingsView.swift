import SwiftUI

/// Settings shell. Company profile and subscription are read-only in this
/// phase; editing arrives with the management flows.
struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var pendingSection: String?

    private var session: TenantSession? { env.session }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                group(
                    title: "Company",
                    rows: [
                        SettingsRow(title: "Company profile", symbol: "building.2.fill", permission: .companyProfileManage),
                        SettingsRow(title: "Users and roles", symbol: "person.2.badge.gearshape.fill", permission: .usersManage),
                        SettingsRow(title: "Tax and defaults", symbol: "percent", permission: .companyProfileManage),
                        SettingsRow(
                            title: "Online payment link",
                            symbol: "link",
                            permission: .companyProfileRead,
                            route: .paymentLink
                        )
                    ]
                )

                group(
                    title: "Platform subscription",
                    rows: [
                        SettingsRow(title: "Plan and seats", symbol: "creditcard.fill", permission: .saasBillingManage),
                        SettingsRow(title: "SMS credits", symbol: "message.fill", permission: .smsCreditsPurchase)
                    ]
                )

                group(
                    title: "Transparency",
                    rows: [
                        SettingsRow(title: "Role & data access", symbol: "lock.shield.fill", permission: nil, route: .dataAccess),
                        SettingsRow(title: "Integrations", symbol: "app.connected.to.app.below.fill", permission: nil, route: .integrations)
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
        .sheet(item: $pendingSection) { title in
            PhaseTwoSheet(title: title)
        }
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

    @ViewBuilder
    private func rowView(_ row: SettingsRow) -> some View {
        if let route = row.route {
            NavigationLink(value: AppRoute.more(route)) {
                rowLabel(row)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                pendingSection = row.title
            } label: {
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
