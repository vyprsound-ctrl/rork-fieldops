import SwiftUI

/// Makes enforcement inspectable: what this role may do, and what the data
/// layer actually allowed or blocked on recent queries.
struct RoleAccessView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var decisions: [AccessDecision] = []

    private var session: TenantSession? { env.session }

    private var groups: [(name: String, permissions: [Permission])] {
        guard let session else { return [] }
        let held = session.permissions
        let grouped = Dictionary(grouping: Permission.allCases, by: \.group)
        return grouped
            .map { (name: $0.key, permissions: $0.value.sorted { $0.title < $1.title }) }
            .sorted { $0.name < $1.name }
            .map { group in
                (name: group.name, permissions: group.permissions.filter { held.contains($0) || !held.contains($0) })
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                explainer

                ForEach(groups, id: \.name) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name)
                            .sectionLabelStyle()

                        VStack(spacing: 0) {
                            ForEach(Array(group.permissions.enumerated()), id: \.element.rawValue) { index, permission in
                                permissionRow(permission)
                                if index < group.permissions.count - 1 {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .cardSurface()
                    }
                }

                if !decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent data-layer decisions")
                            .sectionLabelStyle()

                        VStack(spacing: 0) {
                            ForEach(Array(decisions.prefix(12).enumerated()), id: \.element.id) { index, decision in
                                decisionRow(decision)
                                if index < min(decisions.count, 12) - 1 {
                                    Divider().padding(.leading, 44)
                                }
                            }
                        }
                        .cardSurface()
                    }
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Role & data access")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            guard let session else { return }
            decisions = (try? await env.gateway.recentAccessDecisions(session: session)) ?? []
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(session?.roleTitle ?? "Role")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("Permissions are applied inside the data layer. Rows outside your scope are dropped before the response is built, and restricted fields are never assembled — so hiding them in the interface is not what protects them.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .padding(.top, 4)
    }

    private func permissionRow(_ permission: Permission) -> some View {
        let granted = session?.can(permission) ?? false
        return HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "minus.circle")
                .font(.footnote)
                .foregroundStyle(granted ? Theme.green : Theme.meta)
                .frame(width: 24)
            Text(permission.title(env.terms))
                .font(.subheadline)
                .foregroundStyle(granted ? Theme.ink : Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
    }

    private func decisionRow(_ decision: AccessDecision) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: decision.allowed ? "lock.open.fill" : "lock.fill")
                .font(.caption)
                .foregroundStyle(decision.allowed ? Theme.green : Theme.red)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(decision.query)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(decision.detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(Formatters.time(decision.at))
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

#Preview {
    NavigationStack {
        RoleAccessView()
            .environment(AppEnvironment())
    }
}
