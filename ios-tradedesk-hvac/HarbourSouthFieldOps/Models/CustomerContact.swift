import Foundation

/// Multiple contacts can sit under one customer within one company.
nonisolated struct CustomerContact: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let customerID: String
    var name: String
    var contactRole: String
    var phone: String
    var email: String?
    var isPrimary: Bool
    var isBillingContact: Bool
}
