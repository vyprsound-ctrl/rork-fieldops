import Foundation

/// One person on the company's field-worker roster.
///
/// Note what this type does not have: no pay rate, no cost, no revenue, no
/// job value of any kind. The roster is an operational list, so money is not
/// merely hidden from it — it is never assembled into it, exactly as
/// `FieldWorkerStop` withholds money from a field worker's own screens.
nonisolated struct RosterMember: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let initials: String
    /// The company's own word for the role ("Engineer", "Plumber").
    let roleTitle: String
    let statusTitle: String
    let statusTone: StatusTone
    let isActive: Bool
    /// Only populated where the record carries one.
    let phone: String?
}

/// The company's field workers, active and otherwise.
nonisolated struct FieldWorkerRoster: Hashable, Sendable {
    let members: [RosterMember]
    let activeCount: Int
    let inactiveCount: Int

    static let empty = FieldWorkerRoster(members: [], activeCount: 0, inactiveCount: 0)

    var isEmpty: Bool { members.isEmpty }
}

extension DataGateway {
    /// Derives a roster from the assignable-worker list every gateway already
    /// serves.
    ///
    /// This is the fallback the development stack uses. `jobFormOptions` returns
    /// the workers who can currently be assigned — active field workers — so
    /// describing them as active is accurate rather than assumed. A gateway that
    /// can read the underlying user records overrides this with the real thing,
    /// including people who are invited or suspended.
    func fieldWorkerRoster(session: TenantSession) async throws -> FieldWorkerRoster {
        guard session.can(.usersRead) else { throw DataError.notPermitted(.usersRead) }

        let workers = try await jobFormOptions(session: session).workers
        let members = workers.map { worker in
            RosterMember(
                id: worker.id,
                name: worker.name,
                initials: worker.initials,
                roleTitle: Role.fieldWorker.title(session.terms),
                statusTitle: UserStatus.active.title,
                statusTone: .success,
                isActive: true,
                phone: nil
            )
        }

        return FieldWorkerRoster(
            members: members,
            activeCount: members.count,
            inactiveCount: 0
        )
    }
}
