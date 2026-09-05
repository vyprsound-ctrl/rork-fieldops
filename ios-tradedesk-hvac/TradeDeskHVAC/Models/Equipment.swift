import Foundation

/// A trade-specific detail recorded against an asset.
///
/// Trades need different facts about their equipment — refrigerant for HVAC,
/// pressure rating for plumbing, circuit rating for electrical. Rather than
/// adding a column per trade, those live here as configured name/value pairs.
nonisolated struct EquipmentAttribute: Identifiable, Codable, Hashable, Sendable {
    let name: String
    let value: String

    var id: String { name }
}

/// A serviceable asset at a customer site.
///
/// Deliberately generic: a condenser, a boiler, a consumer unit, a roof section
/// and a commercial oven are all the same record. `category` is free text
/// supplied by the company rather than a fixed enum, so a new trade needs no
/// schema change.
nonisolated struct Equipment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let addressID: String
    var make: String
    var model: String
    var serialNumber: String
    /// e.g. "Condenser", "Water heater", "Consumer unit", "Flat roof".
    var category: String
    var installedOn: Date
    var warrantyExpiresOn: Date?
    var attributes: [EquipmentAttribute]
    var photoURL: String?

    var displayName: String { "\(make) \(model)" }
}

/// A single service event recorded against an asset.
nonisolated struct EquipmentHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let equipmentID: String
    var jobID: String?
    var summary: String
    var occurredAt: Date
}
