import Foundation

nonisolated enum ServiceFrequency: String, CaseIterable, Codable, Hashable, Sendable {
    case monthly
    case quarterly
    case semiAnnual
    case annual
    /// An interval the four fixed options cannot express — every 45 days, every
    /// 18 months. The interval itself lives on the agreement, not here, because
    /// two custom agreements rarely share one.
    case custom

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .quarterly: return "Quarterly"
        case .semiAnnual: return "Twice a year"
        case .annual: return "Annual"
        case .custom: return "Custom interval"
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
    /// Only meaningful when `frequency` is `.custom`.
    var intervalDays: Int?
    var nextDueDate: Date
    var templateJobKind: JobKind
    var templateTitle: String
    var isActive: Bool
}
