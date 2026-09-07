import Foundation

nonisolated enum QuoteStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case draft
    case sent
    case viewed
    case accepted
    case declined
    case expired

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .viewed: return "Viewed"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        case .expired: return "Expired"
        }
    }

    var symbolName: String {
        switch self {
        case .draft: return "pencil.line"
        case .sent: return "paperplane.fill"
        case .viewed: return "eye.fill"
        case .accepted: return "checkmark.seal.fill"
        case .declined: return "hand.thumbsdown.fill"
        case .expired: return "clock.badge.xmark.fill"
        }
    }

    var tone: StatusTone {
        switch self {
        case .draft: return .neutral
        case .sent: return .info
        case .viewed: return .info
        case .accepted: return .success
        case .declined: return .danger
        case .expired: return .warning
        }
    }

    /// A quote may still be edited only while it is a draft.
    var isEditable: Bool { self == .draft }
}

nonisolated struct Quote: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let customerID: String
    let addressID: String
    var number: String
    var title: String
    /// The agreed scope of works, carried onto the job when the quote is accepted.
    var scopeOfWork: String
    var status: QuoteStatus
    /// Derived from the line items by `Money.totals` — never edited directly.
    var subtotal: Decimal
    var tax: Decimal
    var total: Decimal
    var validUntil: Date?
    var createdAt: Date
    var sentAt: Date?
    var viewedAt: Date?
    var acceptedAt: Date?
    var declinedAt: Date?
    /// Set once when the accepted quote is converted. The quote itself is never
    /// otherwise altered by conversion.
    var convertedJobID: String?
}

/// Allowed quote status moves, with the permission the data layer enforces.
nonisolated enum QuoteWorkflow {
    static func nextStatuses(from status: QuoteStatus) -> [QuoteStatus] {
        switch status {
        case .draft: return [.sent]
        case .sent: return [.viewed, .accepted, .declined, .expired]
        case .viewed: return [.accepted, .declined, .expired]
        case .accepted: return []
        case .declined: return []
        case .expired: return [.sent]
        }
    }

    static func actionTitle(for status: QuoteStatus) -> String {
        switch status {
        case .draft: return "Back to draft"
        case .sent: return "Mark as sent"
        case .viewed: return "Mark as viewed"
        case .accepted: return "Mark accepted"
        case .declined: return "Mark declined"
        case .expired: return "Mark expired"
        }
    }
}
