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

    init(client: SupabaseClient) {
        self.client = client
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
            return try await resolveSession(for: response.user.id)
        } catch let error as AuthError {
            throw error
        } catch {
            throw Self.translate(error)
        }
    }

    // MARK: - Sign up

    /// Creates the auth identity, then founds the company through the
    /// SECURITY DEFINER RPC. The client never inserts into `companies` or
    /// `app_users` — both tables refuse direct inserts by policy.
    func signUp(_ registration: CompanyRegistration) async throws -> TenantSession {
        let normalised = registration.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            let response = try await client.auth.signUp(email: normalised, password: registration.password)

            // With email confirmation enabled there is no session yet, so the
            // RPC would run unauthenticated. Stop and tell the user instead.
            guard response.session != nil else {
                throw AuthError.emailConfirmationRequired
            }

            let params = CreateCompanyParams(
                p_name: registration.companyName,
                p_trade: registration.trade.rawValue,
                p_country_code: registration.countryCode,
                p_currency_code: registration.currencyCode,
                p_time_zone_identifier: registration.timeZoneIdentifier,
                p_owner_name: registration.ownerName
            )

            try await client.rpc("create_company_and_owner", params: params).execute()

            return try await resolveSession(for: response.user.id)
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
            return try await resolveSession(for: session.user.id)
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
