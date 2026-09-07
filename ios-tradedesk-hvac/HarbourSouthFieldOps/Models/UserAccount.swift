import Foundation

nonisolated enum UserStatus: String, Codable, Sendable {
    case active
    case invited
    case suspended

    var title: String {
        switch self {
        case .active: return "Active"
        case .invited: return "Invited"
        case .suspended: return "Suspended"
        }
    }
}

/// A user always belongs to exactly one company and carries exactly one role.
nonisolated struct UserAccount: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    var name: String
    var email: String
    var phone: String
    var role: Role
    var status: UserStatus
    var invitedByUserID: String?
    var lastActiveAt: Date?
    var avatarURL: String?

    var initials: String {
        let parts = name.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }
}
