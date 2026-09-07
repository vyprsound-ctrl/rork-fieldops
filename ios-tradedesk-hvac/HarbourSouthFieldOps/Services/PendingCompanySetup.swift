import Foundation
import Supabase

/// The company details captured at sign-up, parked on the auth identity until
/// there is an authenticated session to found the company with.
///
/// WHY THIS EXISTS
/// `create_company_and_owner()` derives the owner from `auth.uid()`, so it can
/// only run once the caller holds a real session. With email confirmation
/// enabled Supabase issues no session at sign-up, so the details have to
/// survive until the user confirms and signs in — potentially on another
/// device, days later, after reinstalling the app.
///
/// They are stored in `auth.users.raw_user_meta_data`, which is part of
/// GoTrue's own schema. That required no migration and no new table, and it
/// travels with the identity rather than with this handset.
///
/// NOTE ON TRUST: nothing here is privileged. The metadata carries a company
/// *name*, not a company *id*, and no role. Even if a user edited it by hand
/// they could only found their own company as its owner — exactly what sign-up
/// already permits. The RPC remains the sole authority on tenancy and role.
nonisolated struct PendingCompanySetup: Sendable, Equatable {
    static let flagKey = "pending_company_setup"

    let companyName: String
    let trade: Trade
    let countryCode: String
    let currencyCode: String
    let timeZoneIdentifier: String
    let ownerName: String

    init(registration: CompanyRegistration) {
        self.companyName = registration.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.trade = registration.trade
        self.countryCode = registration.countryCode.uppercased()
        self.currencyCode = registration.currencyCode.uppercased()
        self.timeZoneIdentifier = registration.timeZoneIdentifier
        self.ownerName = registration.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reads a parked setup back out of the identity's metadata.
    ///
    /// Returns `nil` unless the pending flag is genuinely `true` and the fields
    /// the RPC cannot default are all present. A half-written payload is
    /// treated as absent rather than guessed at — founding a company on
    /// invented details would be worse than reporting no membership.
    init?(metadata: [String: AnyJSON]) {
        guard case .bool(true)? = metadata[Self.flagKey] else { return nil }

        guard
            let companyName = Self.string(metadata["company_name"]),
            !companyName.isEmpty,
            let tradeRaw = Self.string(metadata["trade"]),
            let trade = Trade(rawValue: tradeRaw),
            let countryCode = Self.string(metadata["country_code"]),
            countryCode.count == 2,
            let currencyCode = Self.string(metadata["currency_code"]),
            currencyCode.count == 3
        else { return nil }

        self.companyName = companyName
        self.trade = trade
        self.countryCode = countryCode.uppercased()
        self.currencyCode = currencyCode.uppercased()
        // The RPC has no default for the time zone, so fall back to this
        // device's rather than refusing to provision a real company.
        self.timeZoneIdentifier = Self.string(metadata["time_zone_identifier"])
            ?? TimeZone.current.identifier
        // The RPC defaults an empty owner name to the local part of the email.
        self.ownerName = Self.string(metadata["owner_name"]) ?? ""
    }

    /// Written into `raw_user_meta_data` by `signUp`.
    var signUpMetadata: [String: AnyJSON] {
        [
            Self.flagKey: .bool(true),
            "company_name": .string(companyName),
            "trade": .string(trade.rawValue),
            "country_code": .string(countryCode),
            "currency_code": .string(currencyCode),
            "time_zone_identifier": .string(timeZoneIdentifier),
            "owner_name": .string(ownerName)
        ]
    }

    /// Written once the company exists, so no later sign-in retries provisioning.
    ///
    /// Only the flag is touched. GoTrue merges metadata keys, and leaving the
    /// descriptive fields in place keeps a record of what was requested.
    static var clearedMetadata: [String: AnyJSON] { [flagKey: .bool(false)] }

    private static func string(_ json: AnyJSON?) -> String? {
        guard case .string(let value)? = json else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Serialises company provisioning for a given identity.
///
/// Two paths can discover a pending setup at once — a session restore racing a
/// fresh sign-in on launch, or an impatient double tap. Without this gate both
/// would call `create_company_and_owner()`, and although the database would
/// reject the loser, one of the two callers would surface a raw unique
/// violation to the user. The second caller joins the run already in flight
/// instead of starting another.
///
/// This is a convenience, not the safety guarantee: the one-company-per-user
/// rule is enforced inside the RPC, server-side, and holds across devices where
/// no client-side gate ever could.
actor CompanyProvisioningGate {
    private var inFlight: [String: Task<TenantSession, Error>] = [:]

    func provision(
        userID: String,
        operation: @escaping @Sendable () async throws -> TenantSession
    ) async throws -> TenantSession {
        if let existing = inFlight[userID] {
            return try await existing.value
        }

        let task = Task { try await operation() }
        inFlight[userID] = task
        defer { inFlight[userID] = nil }
        return try await task.value
    }
}
