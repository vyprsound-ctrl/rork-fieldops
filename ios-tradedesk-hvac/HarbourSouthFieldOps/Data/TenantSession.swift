import Foundation

/// The authenticated context every data query is scoped by.
///
/// `companyID` is derived from the authenticated session, never from client
/// input, so a caller cannot ask for another company's rows. `trade` rides
/// along purely so responses can be labelled in the company's own vocabulary —
/// it never affects which rows or fields are returned.
nonisolated struct TenantSession: Hashable, Sendable {
    let userID: String
    let companyID: String
    let role: Role
    let displayName: String
    let email: String
    let trade: Trade
    /// The company has no active subscription (or has more active people than
    /// its plan allows) and this is its owner: company data stays readable,
    /// and only what is needed to put that right (plan, restore, Offer Codes,
    /// deactivating people) remains available. Every other create, update or
    /// delete is refused by the data layer. The role and the permission matrix
    /// themselves are unchanged.
    var isWorkspaceReadOnly: Bool = false

    var permissions: Set<Permission> {
        let granted = PermissionMatrix.permissions(for: role)
        return isWorkspaceReadOnly ? granted.intersection(Self.availableWithoutSubscription) : granted
    }

    /// What an owner keeps while the company has no active subscription.
    static let availableWithoutSubscription: Set<Permission> = [
        .companyProfileRead, .companyDelete,
        .usersRead, .usersManage,
        .saasBillingRead, .saasBillingManage,
        .customersReadAll, .customersReadAssignedSiteOnly, .customerBillingDetailsRead,
        .jobsReadAll, .jobsReadAssignedOnly, .jobStatusHistoryReadAll,
        .calendarReadAll, .calendarReadOwnOnly,
        .jobNotesRead, .jobPhotosRead, .equipmentRead,
        .fieldWorkerLocationReadAll,
        .quotesRead, .quoteFinancialsRead,
        .invoicesRead, .paymentsRead,
        .smsLedgerRead,
        .reportsOperational, .reportsFinancial
    ]

    /// This session with the company's workspace in read-only mode.
    func readOnlyWorkspace() -> TenantSession {
        var copy = self
        copy.isWorkspaceReadOnly = true
        return copy
    }

    func can(_ permission: Permission) -> Bool { permissions.contains(permission) }

    /// False while the workspace is read-only. Operational writes that are not
    /// tied to a single permission (messages, job status, availability,
    /// location) check this.
    var canMutateWorkspace: Bool { !isWorkspaceReadOnly }

    /// The sentence a refused workspace write shows.
    static let readOnlyRefusal = "Your company's Harbour South workspace is read-only right now. Open Subscription to restore normal work."

    var terms: Terminology { trade.terminology }

    var roleTitle: String { role.title(terms) }
}
