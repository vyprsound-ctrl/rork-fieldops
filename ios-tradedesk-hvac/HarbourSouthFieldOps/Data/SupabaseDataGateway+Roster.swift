import Foundation
import Supabase

/// The field-worker roster, read from the company's own user records.
///
/// This overrides the derived default in `FieldWorkerRoster.swift`. The
/// difference matters: the default can only see workers who are currently
/// assignable, whereas this reads the user records themselves and therefore
/// also shows people who are invited or suspended.
///
/// No company identifier is sent. The policy on `app_users` resolves the
/// caller's company from `auth.uid()`, so the rows that come back are this
/// company's and no filtering here is what makes that true.
extension SupabaseDataGateway {
    func fieldWorkerRoster(session: TenantSession) async throws -> FieldWorkerRoster {
        try require(.usersRead, session, query: "users.roster")

        let rows = try await fetch(
            AppUserRecord.self,
            client.from("app_users")
                .select(AppUserRecord.columns)
                .eq("role", value: Role.fieldWorker.rawValue)
        )

        // Active first, then by name, so the people who can take work today are
        // at the top without hiding the ones who cannot.
        let members = rows
            .sorted { lhs, rhs in
                let lhsActive = lhs.status == .active
                let rhsActive = rhs.status == .active
                if lhsActive != rhsActive { return lhsActive }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { row in
                RosterMember(
                    id: row.id.uuidString,
                    name: row.name,
                    initials: Self.rosterInitials(of: row.name),
                    roleTitle: row.role.title(session.terms),
                    statusTitle: row.status.title,
                    statusTone: Self.tone(for: row.status),
                    isActive: row.status == .active,
                    phone: row.phone
                )
            }

        let activeCount = members.filter(\.isActive).count
        record(
            "users.roster",
            session,
            allowed: true,
            "\(members.count) \(session.terms.workerPlural) returned by RLS in company scope"
        )

        return FieldWorkerRoster(
            members: members,
            activeCount: activeCount,
            inactiveCount: members.count - activeCount
        )
    }

    /// Mirrors the gateway's own initials rule. Declared here because that one
    /// is file-private to the main gateway file.
    private nonisolated static func rosterInitials(of name: String) -> String {
        let parts = name
            .split(separator: " ")
            .compactMap(\.first)
            .map(String.init)
        return parts.prefix(2).joined().uppercased()
    }

    private nonisolated static func tone(for status: UserStatus) -> StatusTone {
        switch status {
        case .active: return .success
        case .invited: return .info
        case .suspended: return .danger
        }
    }
}
