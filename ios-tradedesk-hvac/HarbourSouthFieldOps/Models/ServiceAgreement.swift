import Foundation

nonisolated enum ServiceFrequency: String, Codable, Sendable {
    case monthly
    case quarterly
    case semiAnnual
    case annual

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .semiAnnual: return "Twice a year"
        case .annual: return "Annual"
        }
    }
}

/// A recurring commitment to service a customer's asset — an HVAC maintenance
/// contract, a quarterly pest treatment, an annual boiler service. Same record
/// for every trade.
nonisolated struct ServiceAgreement: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let customerID: String
    let addressID: String
    var equipmentID: String?
    var frequency: ServiceFrequency
    var nextDueDate: Date
    var templateJobKind: JobKind
    var templateTitle: String
    var isActive: Bool
}
