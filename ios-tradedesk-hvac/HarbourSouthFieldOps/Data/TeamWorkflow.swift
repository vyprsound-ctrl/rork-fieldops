import Foundation

/// One person on the company's team, whatever their role.
///
/// Note what this type does not have: no pay rate, no cost, no revenue and no
/// job value. The team screen is an operational list, so money is not merely
/// hidden from it — it is never assembled into it.
nonisolated struct TeamMember: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let initials: String
    let email: String?
    let phone: String?
    let role: Role
    let roleTitle: String
    let status: UserStatus
    let statusTitle: String
    let statusTone: StatusTone
    let lastActiveLabel: String?
    /// True for the signed-in user's own row. Their own role and status are not
    /// editable here — nobody locks themselves out of their own company.
    let isSelf: Bool

    var isActive: Bool { status == .active }
}

/// An invitation that has been sent and not yet accepted.
nonisolated struct PendingInvitation: Identifiable, Hashable, Sendable {
    let id: String
    let email: String
    let role: Role
    let roleTitle: String
    let sentLabel: String
    let expiresLabel: String
    let isExpired: Bool
}

/// The company's people: who is here, who is on the way in.
nonisolated struct TeamRoster: Hashable, Sendable {
    let members: [TeamMember]
    let invitations: [PendingInvitation]
    let canManage: Bool
    let activeCount: Int
    let inactiveCount: Int
    let fieldWorkerCount: Int

    static let empty = TeamRoster(
        members: [],
        invitations: [],
        canManage: false,
        activeCount: 0,
        inactiveCount: 0,
        fieldWorkerCount: 0
    )

    var isEmpty: Bool { members.isEmpty && invitations.isEmpty }
}

/// What the office fills in to add somebody. No company id: the invitation is
/// stamped with the inviter's own company inside the database.
nonisolated struct TeamInviteDraft: Hashable, Sendable {
    /// Addresses the invitation email and prefills the joiner's own name on the
    /// sign-up form. It is NOT written to the roster from here: the person
    /// confirms or corrects their name when they set up their account, and that
    /// is what the database stores.
    var name: String = ""
    var email: String = ""
    var role: Role = .fieldWorker
    var expiresInDays: Int = 14

    var validationMessage: String? {
        let address = email.tidied
        if name.tidied.isEmpty { return "Enter the person's name." }
        if address.isEmpty { return "Enter the email address to invite." }
        if !address.contains("@") || address.contains(" ") { return "That email address doesn't look right." }
        if role == .owner { return "A company has one owner. Invite an admin instead." }
        return nil
    }
}

/// What genuinely happened to the invitation email.
///
/// Three states rather than a boolean, deliberately. "Nothing was sent because
/// no provider is configured" and "the provider refused it" need different
/// action from the office, and neither may ever be shown as a success.
nonisolated enum InviteDeliveryStatus: Hashable, Sendable {
    case sent(recipient: String)
    case notConfigured
    case failed(detail: String)

    var didSend: Bool {
        if case .sent = self { return true }
        return false
    }
}

/// An invitation that has just been issued.
///
/// The email is dispatched server-side — no email credential exists on the
/// device — and `delivery` reports what actually happened to it. The join code
/// is still returned and shown once, because an email that could not be
/// delivered must still leave the office with a way to get their engineer
/// working.
nonisolated struct TeamInvite: Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let email: String
    let role: Role
    let roleTitle: String
    let token: String
    let expiresLabel: String
    let delivery: InviteDeliveryStatus
}

// MARK: - Gateway surface

extension DataGateway {
    /// Everybody in the company, plus outstanding invitations.
    ///
    /// The development stack has no user directory to manage, so it answers
    /// plainly instead of pretending.
    func teamRoster(session: TenantSession) async throws -> TeamRoster {
        throw DataError.rejected(Self.teamUnavailable)
    }

    func inviteTeamMember(session: TenantSession, draft: TeamInviteDraft) async throws -> TeamInvite {
        throw DataError.rejected(Self.teamUnavailable)
    }

    func revokeInvitation(session: TenantSession, invitationID: String) async throws {
        throw DataError.rejected(Self.teamUnavailable)
    }

    func updateTeamMemberStatus(session: TenantSession, userID: String, status: UserStatus) async throws {
        throw DataError.rejected(Self.teamUnavailable)
    }

    func updateTeamMemberRole(session: TenantSession, userID: String, role: Role) async throws {
        throw DataError.rejected(Self.teamUnavailable)
    }

    func updateTeamMemberDetails(session: TenantSession, userID: String, name: String, phone: String) async throws {
        throw DataError.rejected(Self.teamUnavailable)
    }

    fileprivate static var teamUnavailable: String {
        "Your team is managed against the live database. Sign in with your company account to use this."
    }
}
