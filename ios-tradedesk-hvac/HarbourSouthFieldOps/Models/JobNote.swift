import Foundation

nonisolated enum NoteVisibility: String, Codable, Sendable {
    case internalOnly
    case customerVisible

    var title: String { self == .internalOnly ? "Internal" : "Customer visible" }
}

nonisolated struct JobNote: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let jobID: String
    let userID: String
    var body: String
    var visibility: NoteVisibility
    var createdAt: Date
}
