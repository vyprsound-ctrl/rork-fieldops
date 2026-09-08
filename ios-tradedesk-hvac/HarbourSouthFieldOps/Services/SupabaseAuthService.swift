import Foundation
import Supabase

/// The membership row, exactly as RLS is willing to return it.
///
/// `companyID` and `role` are read from the database here — they are never
/// supplied, defaulted or inferred by the client. There is no initialiser that
/// lets a caller choose either one.
private nonisolated struct MembershipRow: Decodable, Sendable {
    let id: UUID
    let companyID: UUID
    let name: String
    let email: String
    let role: Role
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case companyID = "company_id"
        case name
        case email
        case role
        case status
    }
}

private nonisolated struct CompanyRow: Decodable, Sendable {
    let id: UUID
    let name: String
    let trade: Trade
}

/// Arguments for `create_company_and_owner()`.
///
/// The RPC has no `company_id` parameter at all, so founding a company cannot
/// be pointed at an existing tenant. The owner role is assigned inside the
/// function, not requested from here.
private nonisolated struct CreateCompanyParams: Encodable, Sendable {
    let p_name: String
    let p_trade: String
    let p_country_code: String
    let p_currency_code: String
    let p_time_zone_identifier: String
    let p_owner_name: String
}

/// PRODUCTION IMPLEMENTATION — native Supabase Auth (email + password).
///
/// The tenancy chain is resolved entirely server-side on every sign-in and every
/// restore:
///
///     auth.uid() → app_users.id → app_users.company_id → companies → role
///
/// The client contributes only credentials. It never sends a company id or a
/// role, and RLS would reject them if it did.
struct SupabaseAuthService: AuthService {
    let mode: ServiceMode = .production
    private let client: SupabaseClient
    /// Shared by every copy of this struct, so the single-flight guard holds
    /// even though the service itself is a value type.
    private let provisioningGate: CompanyProvisioningGate

    init(client: SupabaseClient) {
        self.client = client
        self.provisioningGate = CompanyProvisioningGate()
    }

    /// `nil` when the build has no Supabase coordinates.
    static func make() -> SupabaseAuthService? {
        guard let client = SupabaseClientProvider.shared else { return nil }
        return SupabaseAuthService(client: client)
    }

    // MARK: - Development-only members

    /// Production never offers an account list — that would enumerate users.
    func availableAccounts() async -> [AuthAccount] { [] }

    func signIn(accountID: String) async throws -> TenantSession {
        throw AuthError.notAvailableInDevelopment
    }

    // MARK: - Sign in

    func signIn(email: String, password: String) async throws -> TenantSession {
        let normalised = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let response = try await client.auth.signIn(email: normalised, password: password)
            // This is the path a founder takes after confirming by email: the
            // company is founded here, on their first real session.
            return try await resolveSessionCompletingPendingSetup(for: response.user.id)
        } catch let error as AuthError {
            throw error
        } catch {
            throw Self.translate(error)
        }
    }

    // MARK: - Sign up

    /// Creates the auth identity and founds the company through the SECURITY
    /// DEFINER RPC. The client never inserts into `companies` or `app_users` —
    /// both tables refuse direct inserts by policy.
    ///
    /// The RPC needs an authenticated caller, because it takes the owner from
    /// `auth.uid()`. When email confirmation is enabled there is no session at
    /// this point, so the company details are parked on the identity and the
    /// company is founded on the first authenticated session instead — whether
    /// that arrives moments later or on another device next week.
    func signUp(_ registration: CompanyRegistration) async throws -> SignUpOutcome {
        let normalised = registration.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let setup = PendingCompanySetup(registration: registration)
        do {
            let response = try await client.auth.signUp(
                email: normalised,
                password: registration.password,
                data: setup.signUpMetadata,
                // Without this the confirmation email points at the project's
                // Site URL (localhost), which a phone cannot open.
                redirectTo: AuthCallback.url
            )

            guard response.session != nil else {
                // Confirmation required. This is a success, not a failure: the
                // identity exists and the company details are safely parked.
                return .confirmationSent(email: normalised)
            }

            let session = try await provisionCompany(setup, for: response.user.id)
            return .signedIn(session)
        } catch let error as AuthError {
            throw error
        } catch {
            throw Self.translate(error)
        }
    }

    // MARK: - Joining an existing company

    /// Joins a company that already exists, using an invitation code.
    ///
    /// Three shapes of caller arrive here and all three end in the same place:
    /// a brand new person, a person whose address is already registered, and a
    /// person who has to confirm by email first. The membership row itself is
    /// always created by `accept_invitation()` inside the database, from the
    /// invitation's own company and role — this app never writes it and could
    /// not choose either value if it tried.
    func joinCompany(_ redemption: InvitationRedemption) async throws -> JoinOutcome {
        let normalised = redemption.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let token = redemption.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw AuthError.invitationUnusable }

        let setup = PendingInvitationSetup(token: token, name: redemption.name)

        do {
            let response = try await client.auth.signUp(
                email: normalised,
                password: redemption.password,
                data: setup.signUpMetadata,
                redirectTo: AuthCallback.url
            )

            guard response.session != nil else {
                // Confirmation required. The code is parked on the identity and
                // redeemed on the first authenticated session.
                return .confirmationSent(email: normalised)
            }
            return .joined(try await redeem(setup, for: response.user.id))
        } catch let error as AuthError {
            throw error
        } catch {
            // An address that already has an account is not a failure here: the
            // person may have been invited after signing up, or be moving
            // between companies. Authenticate them and redeem the code.
            guard Self.isAlreadyRegistered(error) else { throw Self.translate(error) }
            let response = try await client.auth.signIn(email: normalised, password: redemption.password)
            return .joined(try await redeem(setup, for: response.user.id))
        }
    }

    /// Redeems the invitation, then resolves the resulting membership.
    private func redeem(_ setup: PendingInvitationSetup, for userID: UUID) async throws -> TenantSession {
        do {
            try await client.rpc("accept_invitation", params: ["p_token": setup.token]).execute()
        } catch {
            // Already a member of the company this invitation points at — the
            // code was redeemed by an earlier attempt. Resolve rather than fail.
            guard Self.isAlreadyProvisioned(error) else {
                print("[auth] invitation could not be redeemed: \(error.localizedDescription)")
                throw AuthError.invitationUnusable
            }
        }

        await clearPendingInvitationFlag()
        try await applyInvitedName(setup.name, for: userID)
        return try await resolveSession(for: userID)
    }

    /// Puts the joiner's own name on their membership row.
    ///
    /// The invitation carries an email address and a role, not a name, so
    /// without this every invited person would appear on the roster as whatever
    /// the database defaulted them to. Deliberately cannot fail the join.
    private func applyInvitedName(_ name: String, for userID: UUID) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await client
                .from("app_users")
                .update(["name": trimmed])
                .eq("id", value: userID)
                .execute()
        } catch {
            print("[auth] joined, but the display name could not be set: \(error.localizedDescription)")
        }
    }

    private func clearPendingInvitationFlag() async {
        do {
            _ = try await client.auth.update(
                user: UserAttributes(data: PendingInvitationSetup.clearedMetadata)
            )
        } catch {
            print("[auth] joined, but the pending invitation flag could not be cleared: \(error.localizedDescription)")
        }
    }

    private static func isAlreadyRegistered(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("already registered")
            || text.contains("already been registered")
            || text.contains("user already exists")
    }

    // MARK: - Session lifecycle

    /// Restores a persisted session on launch. Returns `nil` when signed out.
    ///
    /// A stored token that the server no longer honours is treated as signed
    /// out, not as an error, so a stale keychain entry can never strand the app
    /// on a failure screen.
    func restoreSession() async throws -> TenantSession? {
        do {
            let session = try await client.auth.session
            return try await resolveSessionCompletingPendingSetup(for: session.user.id)
        } catch let error as AuthError {
            switch error {
            case .noMembership, .suspended, .identityMismatch:
                // A real, reportable condition — surface it.
                throw error
            default:
                try? await client.auth.signOut()
                return nil
            }
        } catch {
            return nil
        }
    }

    func signOut() async throws {
        do {
            try await client.auth.signOut()
        } catch {
            // The local session is already discarded by the SDK even when the
            // server call fails, so this is not worth failing the sign-out over.
            print("[auth] sign-out completed locally with a server error: \(error.localizedDescription)")
        }
    }

    func requestPasswordReset(email: String) async throws {
        let normalised = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalised.isEmpty else { throw AuthError.passwordResetFailed }
        do {
            // Same reasoning as sign-up: the reset link has to return to the
            // app, not to the Site URL.
            try await client.auth.resetPasswordForEmail(normalised, redirectTo: AuthCallback.url)
        } catch {
            print("[auth] password reset request failed: \(error.localizedDescription)")
            throw AuthError.passwordResetFailed
        }
    }

    /// Sets a new password for whoever the recovery link just authenticated.
    ///
    /// A reset link signs the user in with a short-lived recovery session, and
    /// this is the only thing that session is good for. Without this call the
    /// flow reached the app and then stopped, which is a dead end: the user had
    /// a valid session and no way to choose a password with it.
    ///
    /// The user is NOT identified from anything passed in. Supabase applies the
    /// change to the session's own identity, so this cannot set somebody else's
    /// password even if the caller wanted to.
    func updatePassword(_ newPassword: String) async throws {
        guard newPassword.count >= 8 else { throw AuthError.passwordTooWeak }

        // A recovery session that has already lapsed produces a confusing
        // provider error, so check for it first and say what actually happened.
        guard (try? await client.auth.session) != nil else {
            throw AuthError.recoverySessionExpired
        }

        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
        } catch {
            let text = error.localizedDescription.lowercased()
            if text.contains("weak") || text.contains("at least") || text.contains("characters") {
                throw AuthError.passwordTooWeak
            }
            if text.contains("expired") || text.contains("session") || text.contains("jwt") {
                throw AuthError.recoverySessionExpired
            }
            print("[auth] password update failed: \(error.localizedDescription)")
            throw AuthError.server("We couldn't change your password. Try the reset link again.")
        }
    }

    // MARK: - Email link callback

    /// Completes an email link that reopened the app.
    ///
    /// This is the direct return path: tapping Confirm in the email hands the
    /// app an authorization code, which is exchanged here for a real session.
    /// Tenancy then resolves through exactly the same code as a password
    /// sign-in, so a company still pending from sign-up is founded now.
    ///
    /// The indirect path still works unchanged. If the exchange cannot happen —
    /// the link was opened on another device, or the code was already spent —
    /// this reports a failure that tells the user to sign in normally, and
    /// `signIn` provisions the company at that point instead.
    func completeAuthCallback(url: URL) async throws -> TenantSession {
        guard AuthCallback.matches(url) else { throw AuthError.confirmationLinkUnusable }

        // An expired or already-used link still redirects here successfully,
        // reporting the failure in the URL rather than as a network error.
        if let reported = AuthCallback.reportedFailure(in: url) { throw reported }

        do {
            let session = try await client.auth.session(from: url)
            return try await resolveSessionCompletingPendingSetup(for: session.user.id)
        } catch let error as AuthError {
            throw error
        } catch {
            throw Self.translateCallback(error)
        }
    }

    /// Maps a failed code exchange onto advice the user can act on.
    ///
    /// Nothing here signs the user out. A link that cannot be exchanged says
    /// nothing about the session already on this device, and discarding it
    /// would turn a stale email into an unexpected sign-out.
    private static func translateCallback(_ error: Error) -> AuthError {
        let text = error.localizedDescription.lowercased()

        if text.contains("expired") || text.contains("already been used") || text.contains("invalid") {
            return .confirmationLinkExpired
        }

        print("[auth] email link could not be completed: \(error)")
        return .confirmationLinkUnusable
    }

    // MARK: - Deferred company provisioning

    /// Resolves the session, founding the company first if one is still owed.
    ///
    /// Provisioning is only attempted when the account genuinely has no
    /// membership AND the identity carries a pending setup. An account that
    /// simply has not been invited anywhere still gets `.noMembership`.
    private func resolveSessionCompletingPendingSetup(for userID: UUID) async throws -> TenantSession {
        do {
            return try await resolveSession(for: userID)
        } catch AuthError.noMembership {
            let metadata = try await identityMetadata()

            // An invitation is checked first: somebody joining a company that
            // already exists never has company details parked, and a person who
            // has both is joining, not founding.
            if let invitation = PendingInvitationSetup(metadata: metadata) {
                return try await redeem(invitation, for: userID)
            }

            guard let setup = PendingCompanySetup(metadata: metadata) else { throw AuthError.noMembership }
            return try await provisionCompany(setup, for: userID)
        }
    }

    /// Reads the parked sign-up details off the authenticated identity.
    private func identityMetadata() async throws -> [String: AnyJSON] {
        let session = try await client.auth.session
        return session.user.userMetadata
    }

    /// Founds the company through the RPC, then resolves the owner session.
    ///
    /// Duplicate protection has four layers, only the first of which is a
    /// guarantee:
    ///   1. The RPC refuses a caller who already has an `app_users` row. That
    ///      check is server-side and holds across every device and process.
    ///   2. This runs only after a resolve returned no membership.
    ///   3. The single-flight gate stops one client racing itself.
    ///   4. An "already belongs" or unique-violation answer is treated as
    ///      already-provisioned and re-resolved, so a half-finished earlier
    ///      attempt converges instead of erroring.
    private func provisionCompany(
        _ setup: PendingCompanySetup,
        for userID: UUID
    ) async throws -> TenantSession {
        try await provisioningGate.provision(userID: userID.uuidString) {
            let params = CreateCompanyParams(
                p_name: setup.companyName,
                p_trade: setup.trade.rawValue,
                p_country_code: setup.countryCode,
                p_currency_code: setup.currencyCode,
                p_time_zone_identifier: setup.timeZoneIdentifier,
                p_owner_name: setup.ownerName
            )

            do {
                try await client.rpc("create_company_and_owner", params: params).execute()
            } catch {
                // Someone — an earlier attempt, or a concurrent one that won —
                // already founded this company. Fall through and resolve it
                // rather than reporting a failure or founding a second one.
                guard Self.isAlreadyProvisioned(error) else { throw Self.translate(error) }
                print("[auth] company already provisioned for this account; resolving the existing one")
            }

            await clearPendingSetupFlag()
            return try await resolveSession(for: userID)
        }
    }

    /// Marks the setup done so no later sign-in retries it.
    ///
    /// Deliberately cannot fail the provisioning it follows: the company now
    /// exists, and refusing the session over a metadata write would be worse
    /// than a redundant retry. If this does fail, the next sign-in attempts
    /// provisioning again, the RPC answers "already belongs to a company", and
    /// the flow self-heals through the already-provisioned path above.
    private func clearPendingSetupFlag() async {
        do {
            _ = try await client.auth.update(
                user: UserAttributes(data: PendingCompanySetup.clearedMetadata)
            )
        } catch {
            print("[auth] company provisioned, but the pending flag could not be cleared: \(error.localizedDescription)")
        }
    }

    /// True when the database is telling us this account already has a company.
    ///
    /// `P0001` is the RPC's own one-company-per-user guard. `23505` is the
    /// unique violation a concurrent caller hits when it loses the race to
    /// insert `app_users.id` — surfacing that raw would show the user a
    /// Postgres constraint name for what is really a success.
    private static func isAlreadyProvisioned(_ error: Error) -> Bool {
        if let postgrest = error as? PostgrestError {
            if postgrest.code == "23505" { return true }
            if postgrest.message.lowercased().contains("already belongs to a company") { return true }
        }

        let text = error.localizedDescription.lowercased()
        if text.contains("already belongs to a company") { return true }
        return text.contains("duplicate key") && text.contains("app_users")
    }

    // MARK: - Tenancy resolution

    /// Turns a verified `auth.uid()` into a `TenantSession`.
    ///
    /// Filtering by the authenticated id is a precision filter, not the security
    /// boundary: an owner's RLS policy can return every membership in their
    /// company, so without it the wrong row could be picked. RLS independently
    /// guarantees no row from another company is reachable at all.
    private func resolveSession(for userID: UUID) async throws -> TenantSession {
        let memberships: [MembershipRow] = try await client
            .from("app_users")
            .select("id, company_id, name, email, role, status")
            .eq("id", value: userID)
            .limit(1)
            .execute()
            .value

        guard let membership = memberships.first else {
            throw AuthError.noMembership
        }

        // The row must belong to the account that just authenticated.
        guard membership.id == userID else {
            try? await client.auth.signOut()
            throw AuthError.identityMismatch
        }

        guard membership.status == "active" else {
            try? await client.auth.signOut()
            throw AuthError.suspended
        }

        let companies: [CompanyRow] = try await client
            .from("companies")
            .select("id, name, trade")
            .eq("id", value: membership.companyID)
            .limit(1)
            .execute()
            .value

        guard let company = companies.first else {
            // RLS returned a membership but not its company — refuse rather than
            // guess a tenant.
            throw AuthError.noMembership
        }

        return TenantSession(
            userID: membership.id.uuidString,
            companyID: membership.companyID.uuidString,
            role: membership.role,
            displayName: membership.name,
            email: membership.email,
            trade: company.trade
        )
    }

    // MARK: - Error mapping

    /// Maps SDK/Postgres errors onto the app's vocabulary without leaking
    /// internals into the UI.
    private static func translate(_ error: Error) -> AuthError {
        let text = error.localizedDescription.lowercased()

        if text.contains("invalid login") || text.contains("invalid credentials") || text.contains("bad_credential") {
            return .invalidCredentials
        }
        if text.contains("email not confirmed") || text.contains("confirm") {
            return .emailConfirmationRequired
        }
        if text.contains("already registered") || text.contains("already been registered") {
            return .server("That email already has an account. Sign in instead.")
        }
        if text.contains("already belongs to a company") {
            return .server("This account already belongs to a company.")
        }
        if text.contains("jwt") || text.contains("expired") {
            return .sessionExpired
        }
        if text.contains("password") && text.contains("short") {
            return .server("Choose a password of at least 6 characters.")
        }

        print("[auth] unmapped error: \(error)")
        return .server("Sign-in failed. Please try again.")
    }
}
