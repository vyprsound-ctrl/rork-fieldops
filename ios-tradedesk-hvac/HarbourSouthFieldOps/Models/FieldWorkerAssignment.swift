import Foundation

/// Links a field worker to a job. This row is the sole basis on which a field
/// worker's data queries are allowed to return a job.
nonisolated struct FieldWorkerAssignment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let jobID: String
    let userID: String
    var assignedByUserID: String
    var assignedAt: Date
    var isPrimary: Bool
    var acceptedAt: Date?
    var sortOrder: Int
}
