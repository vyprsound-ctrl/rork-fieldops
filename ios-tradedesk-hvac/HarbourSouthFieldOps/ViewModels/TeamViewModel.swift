import Foundation
import Observation

/// Drives the team screen: who is in the company, and every change made to them.
@Observable
final class TeamViewModel {
    private(set) var state: LoadState<TeamRoster> = .idle
    private(set) var isWorking: Bool = false
    var actionError: String?
    /// The code from the invitation just issued, shown once so the office can
    /// pass it on. Never persisted on the device.
    var issuedInvite: TeamInvite?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.teamRoster(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func invite(gateway: DataGateway, session: TenantSession, draft: TeamInviteDraft) async {
        isWorking = true
        actionError = nil
        do {
            issuedInvite = try await gateway.inviteTeamMember(session: session, draft: draft)
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }

    func revoke(gateway: DataGateway, session: TenantSession, invitationID: String) async {
        await perform(gateway: gateway, session: session) {
            try await gateway.revokeInvitation(session: session, invitationID: invitationID)
        }
    }

    func setStatus(gateway: DataGateway, session: TenantSession, userID: String, status: UserStatus) async {
        await perform(gateway: gateway, session: session) {
            try await gateway.updateTeamMemberStatus(session: session, userID: userID, status: status)
        }
    }

    func setRole(gateway: DataGateway, session: TenantSession, userID: String, role: Role) async {
        await perform(gateway: gateway, session: session) {
            try await gateway.updateTeamMemberRole(session: session, userID: userID, role: role)
        }
    }

    func setDetails(
        gateway: DataGateway,
        session: TenantSession,
        userID: String,
        name: String,
        phone: String
    ) async {
        await perform(gateway: gateway, session: session) {
            try await gateway.updateTeamMemberDetails(session: session, userID: userID, name: name, phone: phone)
        }
    }

    private func perform(
        gateway: DataGateway,
        session: TenantSession,
        _ work: () async throws -> Void
    ) async {
        isWorking = true
        actionError = nil
        do {
            try await work()
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
