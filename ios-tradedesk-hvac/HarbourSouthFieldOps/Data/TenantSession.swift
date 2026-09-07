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

    var permissions: Set<Permission> { PermissionMatrix.permissions(for: role) }

    func can(_ permission: Permission) -> Bool { permissions.contains(permission) }

    var terms: Terminology { trade.terminology }

    var roleTitle: String { role.title(terms) }
}
