import Foundation

/// How a company classifies a customer relationship.
///
/// This is a *starting set*, not a platform assumption. Field-service
/// businesses do not all sell to households and offices: a roofer works for
/// property managers, a locksmith for landlords and letting agents, a pest
/// controller for housing associations. `other` is the deliberate escape hatch
/// so no company is forced into a wrong label, and the raw value is stored as a
/// string so a company-defined classification list can be layered on later
/// without a migration or a schema change.
nonisolated enum CustomerType: String, Codable, CaseIterable, Sendable, Identifiable {
    case residential
    case commercial
    case propertyManagement
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .residential: return "Residential"
        case .commercial: return "Commercial"
        case .propertyManagement: return "Property management"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .residential: return "house.fill"
        case .commercial: return "building.2.fill"
        case .propertyManagement: return "building.columns.fill"
        case .other: return "person.2.fill"
        }
    }

    /// Unknown values decode to `other` rather than failing, so a classification
    /// added server-side can never break an older client.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CustomerType(rawValue: raw) ?? .other
    }
}

nonisolated struct Customer: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    var name: String
    var type: CustomerType
    var billingTerms: String
    var notes: String?
    var createdAt: Date

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
