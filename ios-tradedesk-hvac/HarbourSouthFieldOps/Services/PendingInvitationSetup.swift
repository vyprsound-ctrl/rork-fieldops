import Foundation
import Supabase

/// The invitation code captured when somebody joins an existing company, parked
/// on the auth identity until there is an authenticated session to redeem it
/// with.
///
/// WHY THIS EXISTS
/// `accept_invitation()` derives the joiner from `auth.uid()`, so it can only
/// run once the caller holds a real session. With email confirmation enabled
/// Supabase issues no session at sign-up, so the code has to survive until the
/// person confirms and signs in — possibly on another device, days later.
///
/// This mirrors `PendingCompanySetup` exactly, and for the same reason.
///
/// NOTE ON TRUST: nothing here is privileged. The metadata carries an
/// invitation *token*, which the database matches against a live, unexpired,
/// unrevoked invitation row; the company and the role come off that row. A user
/// editing this by hand could only fail to match an invitation.
nonisolated struct PendingInvitationSetup: Sendable, Equatable {
    static let flagKey = "pending_invitation"

    let token: String
    let name: String

    init(token: String, name: String) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads a parked code back out of the identity's metadata. A missing or
    /// blank token is treated as absent rather than guessed at.
    init?(metadata: [String: AnyJSON]) {
        guard case .bool(true)? = metadata[Self.flagKey] else { return nil }
        guard let token = Self.string(metadata["invitation_token"]) else { return nil }
        self.token = token
        self.name = Self.string(metadata["invited_name"]) ?? ""
    }

    var signUpMetadata: [String: AnyJSON] {
        [
            Self.flagKey: .bool(true),
            "invitation_token": .string(token),
            "invited_name": .string(name)
        ]
    }

    /// Written once the membership exists, so no later sign-in retries it.
    static var clearedMetadata: [String: AnyJSON] { [flagKey: .bool(false)] }

    private static func string(_ json: AnyJSON?) -> String? {
        guard case .string(let value)? = json else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
