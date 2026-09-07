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
                data: setup.signUpMetadata
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
            try await client.auth.resetPasswordForEmail(normalised)
        } catch {
            print("[auth] password reset request failed: \(error.localizedDescription)")
            throw AuthError.passwordResetFailed
        }
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
            guard let setup = try await pendingSetup() else { throw AuthError.noMembership }
            return try await provisionCompany(setup, for: userID)
        }
    }

    /// Reads the parked company details off the authenticated identity.
    private func pendingSetup() async throws -> PendingCompanySetup? {
        let session = try await client.auth.session
        return PendingCompanySetup(metadata: session.user.userMetadata)
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
