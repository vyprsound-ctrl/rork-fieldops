import Foundation

nonisolated enum JobPhotoKind: String, Codable, Sendable {
    case before
    case after
    case part
    case proof

    var title: String {
        switch self {
        case .before: return "Before"
        case .after: return "After"
        case .part: return "Part"
        case .proof: return "Proof"
        }
    }
}

nonisolated struct JobPhoto: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let jobID: String
    let userID: String
    var storageReference: String
    var caption: String?
    var kind: JobPhotoKind
    var capturedAt: Date
}
