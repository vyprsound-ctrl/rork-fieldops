import Foundation

nonisolated struct AuthAccount: Identifiable, Hashable, Sendable {
    let id: String
    let companyID: String
    let companyName: String
    let trade: Trade
    let name: String
    let email: String
    let role: Role

    /// Role name in this company's own vocabulary.
    var roleTitle: String { role.title(trade.terminology) }
    var roleSummary: String { role.summary(trade.terminology) }
}

/// Everything the client is allowed to supply when founding a company.
///
/// Note what is absent: no company id, no role, no user id. The owner role and
/// the company id are both minted by `create_company_and_owner()` inside the
/// database. There is deliberately no field here a caller could use to choose
/// its own tenancy.
nonisolated struct CompanyRegistration: Sendable {
    let email: String
    let password: String
    let ownerName: String
    let companyName: String
    let trade: Trade
    let countryCode: String
    let currencyCode: String
    let timeZoneIdentifier: String

    init(
        email: String,
        password: String,
        ownerName: String,
        companyName: String,
        trade: Trade,
        countryCode: String,
        currencyCode: String,
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.email = email
        self.password = password
        self.ownerName = ownerName
        self.companyName = companyName
        self.trade = trade
        self.countryCode = countryCode
        self.currencyCode = currencyCode
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// How a sign-up ended.
///
/// Email confirmation being enabled is a normal, successful outcome — not a
/// failure. Modelling it as an error was what previously aborted sign-up before
/// the company could be founded.
nonisolated enum SignUpOutcome: Sendable {
    /// Confirmation is disabled: the company exists and the owner is signed in.
    case signedIn(TenantSession)
    /// Confirmation is required. The company details are parked on the identity
    /// and provisioned on the first authenticated session.
    case confirmationSent(email: String)
}

nonisolated enum AuthError: LocalizedError, Equatable {
    case unknownAccount
    case suspended
    case notConfigured
    case invalidCredentials
    case emailConfirmationRequired
    case noMembership
    case sessionExpired
    case identityMismatch
    case passwordResetFailed
    /// Signed in and confirmed, but the parked company details are missing or
    /// unreadable, so there is nothing to found a company from.
    case companyDetailsUnavailable
    case notAvailableInDevelopment
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unknownAccount:
            return "We couldn't find that account."
        case .suspended:
            return "This account is suspended. Contact your owner."
        case .notConfigured:
            return "This build has no Supabase configuration, so production sign-in is unavailable."
        case .invalidCredentials:
            return "That email and password don't match an account."
        case .emailConfirmationRequired:
            return "Check your email to confirm the address, then sign in."
        case .companyDetailsUnavailable:
            return "We couldn't find the company details from your sign-up. Create the company again with this same email to finish setting it up."
        case .noMembership:
            return "This account isn't a member of any company yet. Ask an owner or admin for an invitation."
        case .sessionExpired:
            return "Your session has expired. Please sign in again."
        case .identityMismatch:
            return "The account record didn't match the signed-in user. You've been signed out."
        case .passwordResetFailed:
            return "We couldn't send a reset email. Check the address and try again."
        case .notAvailableInDevelopment:
            return "That action needs the production backend. Switch to Production sign-in."
        case .server(let message):
            return message
        }
    }
}

/// Authentication surface.
///
/// The development picker and production Supabase Auth both satisfy this. The
/// production-only members have defaults that refuse, so `MockAuthService` keeps
/// exactly the behaviour it has always had without implementing any of them.
protocol AuthService: Sendable {
    var mode: ServiceMode { get }

    /// Development only — the seeded account list behind the picker.
    func availableAccounts() async -> [AuthAccount]

    /// Development only — sign in as a seeded account without verifying anything.
    func signIn(accountID: String) async throws -> TenantSession

    func signIn(email: String, password: String) async throws -> TenantSession
    func signUp(_ registration: CompanyRegistration) async throws -> SignUpOutcome
    /// Returns the restored session, or `nil` when nobody is signed in.
    func restoreSession() async throws -> TenantSession?
    func signOut() async throws
    func requestPasswordReset(email: String) async throws
}

extension AuthService {
    func signIn(email: String, password: String) async throws -> TenantSession {
        throw AuthError.notAvailableInDevelopment
    }

    func signUp(_ registration: CompanyRegistration) async throws -> SignUpOutcome {
        throw AuthError.notAvailableInDevelopment
    }

    func restoreSession() async throws -> TenantSession? { nil }

    func signOut() async throws {}

    func requestPasswordReset(email: String) async throws {
        throw AuthError.notAvailableInDevelopment
    }
}

/// DEVELOPMENT IMPLEMENTATION — verifies nothing, issues a local session.
struct MockAuthService: AuthService {
    let mode: ServiceMode = .simulated
    private let store: MockDataStore

    init(store: MockDataStore = .seeded()) {
        self.store = store
    }

    func availableAccounts() async -> [AuthAccount] {
        store.users
            .filter { $0.status == .active }
            .map { user in
                let company = store.companies.first { $0.id == user.companyID }
                return AuthAccount(
                    id: user.id,
                    companyID: user.companyID,
                    companyName: company?.name ?? "Company",
                    trade: company?.trade ?? .other,
                    name: user.name,
                    email: user.email,
                    role: user.role
                )
            }
            .sorted { lhs, rhs in
                if lhs.companyName != rhs.companyName { return lhs.companyName < rhs.companyName }
                return lhs.role.rawValue < rhs.role.rawValue
            }
    }

    func signIn(accountID: String) async throws -> TenantSession {
        try? await Task.sleep(for: .milliseconds(420))
        guard let user = store.users.first(where: { $0.id == accountID }) else {
            throw AuthError.unknownAccount
        }
        guard user.status == .active else { throw AuthError.suspended }
        let company = store.companies.first { $0.id == user.companyID }

        // company_id comes from the account record, never from caller input.
        // The trade rides along so responses can be labelled in the company's
        // own vocabulary; it never widens or narrows access.
        return TenantSession(
            userID: user.id,
            companyID: user.companyID,
            role: user.role,
            displayName: user.name,
            email: user.email,
            trade: company?.trade ?? .other
        )
    }
}
