import Foundation

/// Every status transition is recorded with who changed it, when, and where
/// (location captured only for field transitions such as en route / on site).
nonisolated struct JobStatusHistory: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let jobID: String
    var fromStatus: JobStatus?
    var toStatus: JobStatus
    var changedByUserID: String
    var changedAt: Date
    var latitude: Double?
    var longitude: Double?
}
