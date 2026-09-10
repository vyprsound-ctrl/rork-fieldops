import Foundation
import Supabase

/// The full user record the team screen needs — the narrower `AppUserRecord`
/// carries no email and no last-active stamp.
nonisolated struct TeamUserRecord: Decodable, Sendable {
    let id: UUID
    let name: String
    let email: String?
    let phone: String?
    let role: Role
    let status: UserStatus
    let lastActiveAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, email, phone, role, status
        case lastActiveAt = "last_active_at"
    }

    static let columns = "id,name,email,phone,role,status,last_active_at"
}

nonisolated struct InvitationRecord: Decodable, Sendable {
    let id: UUID
    let email: String
    let role: Role
    let createdAt: Date
    let expiresAt: Date
    let acceptedAt: Date?
    let revokedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, role
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case acceptedAt = "accepted_at"
        case revokedAt = "revoked_at"
    }

    static let columns = "id,email,role,created_at,expires_at,accepted_at,revoked_at"
}

/// What `create_invitation()` hands back.
private nonisolated struct InvitationResult: Decodable, Sendable {
    let invitationID: UUID
    let invitationToken: String

    enum CodingKeys: String, CodingKey {
        case invitationID = "invitation_id"
        case invitationToken = "invitation_token"
    }
}

/// What the invitation dispatcher is asked to send.
///
/// Note what is absent: no company id, no role, no recipient address. The
/// dispatcher re-reads all three from the invitation row using the caller's own
/// token, so this payload cannot redirect an invitation anywhere.
private nonisolated struct InviteDispatchRequest: Encodable, Sendable {
    let invitationId: String
    let token: String
    let name: String
}

private nonisolated struct InviteDispatchResponse: Decodable, Sendable {
    let delivered: Bool?
    let configured: Bool?
    let recipient: String?
    let detail: String?
    let error: String?
}

private nonisolated struct UserStatusPayload: Encodable, Sendable {
    let status: String
    let updated_at: String
}

private nonisolated struct UserRolePayload: Encodable, Sendable {
    let role: String
    let updated_at: String
}

private nonisolated struct UserDetailsPayload: Encodable, Sendable {
    let name: String
    let phone: String
    let updated_at: String
}

/// Team management against Supabase.
///
/// Adding somebody is an invitation, never a direct insert: `app_users` refuses
/// client inserts by policy, and the row is created by `accept_invitation()`
/// when the invited person authenticates. That is what stops this app from
/// writing a user into a company it does not belong to — the company on the
/// invitation comes from the inviter's own session, resolved inside the
/// database.
///
/// Status and role changes are ordinary updates governed by the `usersManage`
/// policy on `app_users`. The checks here make a refusal legible; they are not
/// the boundary.
extension SupabaseDataGateway {

    func teamRoster(session: TenantSession) async throws -> TeamRoster {
        try require(.usersRead, session, query: "team.roster")

        let people = try await fetch(
            TeamUserRecord.self,
            client.from("app_users").select(TeamUserRecord.columns)
        )

        let canManage = session.can(.usersManage)
        var invitations: [PendingInvitation] = []

        if canManage {
            // An invitation carries an email address, so it is only read for a
            // role that may manage users. The policy on the table says the same.
            let rows = try await fetch(
                InvitationRecord.self,
                client.from("invitations").select(InvitationRecord.columns)
            )
            invitations = rows
                .filter { $0.acceptedAt == nil && $0.revokedAt == nil }
                .sorted { $0.createdAt > $1.createdAt }
                .map { row in
                    let expired = row.expiresAt < Date()
                    return PendingInvitation(
                        id: row.id.uuidString,
                        email: row.email,
                        role: row.role,
                        roleTitle: row.role.title(session.terms),
                        sentLabel: "Invited \(Formatters.shortDate(row.createdAt))",
                        expiresLabel: expired
                            ? "Expired \(Formatters.shortDate(row.expiresAt))"
                            : "Expires \(Formatters.shortDate(row.expiresAt))",
                        isExpired: expired
                    )
                }
        }

        let members = people
            .sorted { lhs, rhs in
                if lhs.status != rhs.status { return lhs.status == .active }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map { row -> TeamMember in
                let key = row.id.uuidString
                return TeamMember(
                    id: key,
                    name: row.name,
                    initials: Self.crmInitials(row.name),
                    email: row.email?.nilIfBlank,
                    phone: row.phone?.nilIfBlank,
                    role: row.role,
                    roleTitle: row.role.title(session.terms),
                    status: row.status,
                    statusTitle: row.status.title,
                    statusTone: Self.tone(for: row.status),
                    lastActiveLabel: row.lastActiveAt.map { "Last active \(Formatters.shortDayAndTime($0))" },
                    isSelf: key == session.userID
                )
            }

        record(
            "team.roster",
            session,
            allowed: true,
            "\(members.count) member(s) and \(invitations.count) open invitation(s) returned by RLS in company scope"
        )

        return TeamRoster(
            members: members,
            invitations: invitations,
            canManage: canManage,
            activeCount: members.filter(\.isActive).count,
            inactiveCount: members.filter { !$0.isActive }.count,
            fieldWorkerCount: members.filter { $0.role == .fieldWorker && $0.isActive }.count
        )
    }

    /// Issues an invitation. The token is returned once, to the person who
    /// created it, and is never stored on the device.
    func inviteTeamMember(session: TenantSession, draft: TeamInviteDraft) async throws -> TeamInvite {
        try require(.usersManage, session, query: "team.invite")
        if let problem = draft.validationMessage { throw DataError.rejected(problem) }

        let address = draft.email.tidied.lowercased()

        let data: Data
        do {
            let response: PostgrestResponse<Void> = try await client
                .rpc(
                    "create_invitation",
                    params: [
                        "p_email": AnyJSON.string(address),
                        "p_role": AnyJSON.string(draft.role.rawValue),
                        "p_expires_in_days": AnyJSON.integer(max(1, min(draft.expiresInDays, 90)))
                    ]
                )
                .execute()
            data = response.data
        } catch let error as PostgrestError {
            record("team.invite", session, allowed: false, "Refused by the database — \(error.message)")
            throw Self.inviteError(error)
        } catch {
            throw DataError.unexpected("The invitation couldn't be created. Try again in a moment.")
        }

        // The function returns a one-row table.
        let results = (try? SupabaseCoding.decoder.decode([InvitationResult].self, from: data)) ?? []
        guard let result = results.first else {
            throw DataError.unexpected("The invitation was created but the server didn't return its code.")
        }

        let expiry = Calendar.current.date(byAdding: .day, value: draft.expiresInDays, to: Date()) ?? Date()

        // The invitation now exists and is valid. Delivery is attempted next
        // and reported honestly — a failure here never invalidates the
        // invitation, and never presents itself as a success.
        let delivery = await dispatchInvitationEmail(
            invitationID: result.invitationID.uuidString,
            token: result.invitationToken,
            name: draft.name.tidied,
            fallbackRecipient: address
        )

        record(
            "team.invite",
            session,
            allowed: true,
            delivery.didSend
                ? "\(draft.role.title(session.terms)) invitation issued and emailed; company came from the caller's own session"
                : "\(draft.role.title(session.terms)) invitation issued; email not delivered — code must be passed on by hand"
        )

        return TeamInvite(
            id: result.invitationID.uuidString,
            name: draft.name.tidied,
            email: address,
            role: draft.role,
            roleTitle: draft.role.title(session.terms),
            token: result.invitationToken,
            expiresLabel: "Expires \(Formatters.shortDate(expiry))",
            delivery: delivery
        )
    }

    /// Hands the invitation to the server-side dispatcher, which is the only
    /// place in the stack that holds an email credential.
    ///
    /// The caller's own access token travels with the request and is what the
    /// dispatcher authenticates and authorises against — it re-reads the
    /// invitation through Row Level Security rather than trusting this call.
    ///
    /// Deliberately cannot throw. The invitation is already created; turning a
    /// delivery problem into a thrown error would tell the office the whole
    /// operation failed when it did not, and would hide the code they need.
    private func dispatchInvitationEmail(
        invitationID: String,
        token: String,
        name: String,
        fallbackRecipient: String
    ) async -> InviteDeliveryStatus {
        guard let base = BackendConfiguration.invoicePageBase,
              let endpoint = URL(string: "\(base)/invite") else {
            return .notConfigured
        }

        let accessToken: String
        do {
            accessToken = try await client.auth.session.accessToken
        } catch {
            print("[team] no access token available to dispatch the invitation")
            return .failed(detail: "Your session needs refreshing before an invitation can be emailed.")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(
                InviteDispatchRequest(invitationId: invitationID, token: token, name: name)
            )
        } catch {
            return .failed(detail: "The invitation couldn't be prepared for sending.")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let decoded = try? JSONDecoder().decode(InviteDispatchResponse.self, from: data)

            guard status == 200 else {
                print("[team] invitation dispatch refused: \(status) \(decoded?.error ?? "-")")
                return .failed(detail: "The invitation was created but couldn't be emailed.")
            }
            if decoded?.configured == false { return .notConfigured }
            if decoded?.delivered == true {
                return .sent(recipient: decoded?.recipient ?? fallbackRecipient)
            }
            return .failed(detail: decoded?.detail ?? "The invitation was created but couldn't be emailed.")
        } catch {
            print("[team] invitation dispatch failed: \(error.localizedDescription)")
            return .failed(detail: "Couldn't reach the mail service. The invitation is still valid.")
        }
    }

    func revokeInvitation(session: TenantSession, invitationID: String) async throws {
        try require(.usersManage, session, query: "team.revokeInvitation")
        try await perform("revoke_invitation", ["p_invitation_id": .string(invitationID)])
        record("team.revokeInvitation", session, allowed: true, "Invitation revoked; the code no longer works")
    }

    func updateTeamMemberStatus(session: TenantSession, userID: String, status: UserStatus) async throws {
        try require(.usersManage, session, query: "team.updateStatus")
        guard userID != session.userID else {
            throw DataError.rejected("You can't change your own status.")
        }
        guard status != .invited else {
            throw DataError.rejected("Invited is set by the invitation, not by hand.")
        }

        try await performWrite(
            client.from("app_users")
                .update(UserStatusPayload(status: status.rawValue, updated_at: SupabaseCoding.timestamp(Date())))
                .eq("id", value: userID)
        )
        record(
            "team.updateStatus",
            session,
            allowed: true,
            status == .active
                ? "Member reactivated — they can sign in and take work again"
                : "Member suspended — their next sign-in is refused and they take no new work"
        )
    }

    func updateTeamMemberRole(session: TenantSession, userID: String, role: Role) async throws {
        try require(.usersManage, session, query: "team.updateRole")
        guard userID != session.userID else {
            throw DataError.rejected("You can't change your own role.")
        }
        guard role != .owner else {
            throw DataError.rejected("A company has one owner, and that isn't set from here.")
        }

        try await performWrite(
            client.from("app_users")
                .update(UserRolePayload(role: role.rawValue, updated_at: SupabaseCoding.timestamp(Date())))
                .eq("id", value: userID)
        )
        record("team.updateRole", session, allowed: true, "Role changed to \(role.title(session.terms))")
    }

    func updateTeamMemberDetails(session: TenantSession, userID: String, name: String, phone: String) async throws {
        try require(.usersManage, session, query: "team.updateDetails")
        guard !name.tidied.isEmpty else { throw DataError.rejected("Give this person a name.") }

        try await performWrite(
            client.from("app_users")
                .update(
                    UserDetailsPayload(
                        name: name.tidied,
                        phone: phone.tidied,
                        updated_at: SupabaseCoding.timestamp(Date())
                    )
                )
                .eq("id", value: userID)
        )
        record("team.updateDetails", session, allowed: true, "Member details updated in company scope")
    }

    // MARK: - Helpers

    private nonisolated static func tone(for status: UserStatus) -> StatusTone {
        switch status {
        case .active: return .success
        case .invited: return .info
        case .suspended: return .warning
        }
    }

    /// Turns the database's own refusal into a sentence the office can act on.
    private nonisolated static func inviteError(_ error: PostgrestError) -> DataError {
        let text = error.message.lowercased()
        if text.contains("already") && text.contains("member") {
            return .rejected("That email already belongs to somebody in your company.")
        }
        if error.code == "23505" {
            return .rejected("There's already an open invitation for that address.")
        }
        if error.code == "42501" || text.contains("permission") {
            return .notPermitted(.usersManage)
        }
        return .rejected(error.message)
    }
}
