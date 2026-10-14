import Foundation

/// Why a message is being reported. The raw values are the exact labels the
/// database's `message_reports.reason` check constraint accepts.
nonisolated enum ReportReason: String, CaseIterable, Identifiable, Hashable, Sendable {
    case harassment
    case hate
    case threat
    case sexual
    case spam
    case illegal
    case selfHarm = "self_harm"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .harassment: return "Harassment or bullying"
        case .hate: return "Hate speech or slurs"
        case .threat: return "Threats or violence"
        case .sexual: return "Sexual or inappropriate content"
        case .spam: return "Spam or scam"
        case .illegal: return "Illegal activity"
        case .selfHarm: return "Self-harm or suicide"
        case .other: return "Something else"
        }
    }

    var symbolName: String {
        switch self {
        case .harassment: return "person.fill.xmark"
        case .hate: return "exclamationmark.bubble.fill"
        case .threat: return "exclamationmark.triangle.fill"
        case .sexual: return "eye.slash.fill"
        case .spam: return "envelope.badge.shield.half.filled"
        case .illegal: return "hand.raised.fill"
        case .selfHarm: return "heart.text.square.fill"
        case .other: return "ellipsis.bubble.fill"
        }
    }
}

/// Which kind of message a report is about.
nonisolated enum ReportedMessageKind: Hashable, Sendable {
    /// A message in an engineer ↔ office conversation.
    case office
    /// A text a customer sent to the company's SMS number.
    case sms
}

/// The message a person has chosen to report, as the report sheet needs it.
nonisolated struct ReportTarget: Identifiable, Hashable, Sendable {
    let messageID: String
    let kind: ReportedMessageKind
    /// Shown in the sheet so the reporter can see what they are reporting.
    let excerpt: String
    /// The team member who sent it. `nil` for customer texts, which cannot be
    /// blocked in-app (a moderator removes them instead).
    let senderUserID: String?
    let senderName: String

    var id: String { messageID }
    var canBlockSender: Bool { senderUserID != nil }
}

/// Moderator actions, matching `moderate_message_report(p_action)`.
nonisolated enum ModerationAction: String, Hashable, Sendable {
    case startReview = "start_review"
    case dismiss
    case removeMessage = "remove_message"
    case restrictChat = "restrict_chat"
    case liftChatRestriction = "lift_chat_restriction"
    case suspendAccount = "suspend_account"
}

nonisolated enum ModerationReportStatus: String, Hashable, Sendable {
    case open
    case underReview = "under_review"
    case actioned
    case dismissed

    var title: String {
        switch self {
        case .open: return "Open"
        case .underReview: return "Under review"
        case .actioned: return "Action taken"
        case .dismissed: return "Closed"
        }
    }

    var tone: StatusTone {
        switch self {
        case .open: return .warning
        case .underReview: return .info
        case .actioned: return .success
        case .dismissed: return .neutral
        }
    }

    var isResolved: Bool { self == .actioned || self == .dismissed }
}

/// One report, as the Safety screen lists it. The database decides which
/// rows a caller can see: their own reports, and — for Owners and Admins —
/// every report in the company except reports about themselves.
nonisolated struct ModerationReportRow: Identifiable, Hashable, Sendable {
    let id: String
    let reason: ReportReason
    let status: ModerationReportStatus
    let createdAt: Date
    let isMine: Bool
    let isEscalated: Bool
    /// "office", "sms" or "user" (a block).
    let source: String
    let reporterName: String?
    let reportedName: String?
    let reportedUserID: String?
    let excerpt: String?
    let details: String?
    let resolution: String?

    var isBlock: Bool { source == "user" }
    var canRemoveMessage: Bool { source == "office" || source == "sms" }
    var canActOnPerson: Bool { reportedUserID != nil }

    var sourceTitle: String {
        switch source {
        case "office": return "Team message"
        case "sms": return "Customer text"
        default: return "Blocked person"
        }
    }
}

/// Someone the signed-in person has blocked.
nonisolated struct BlockedChatUser: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let blockedAt: Date
}

/// Everything the Safety screen shows.
nonisolated struct ChatSafetyOverview: Hashable, Sendable {
    let reports: [ModerationReportRow]
    let blocked: [BlockedChatUser]
    let canModerate: Bool

    var reportsToReview: [ModerationReportRow] { reports.filter { !$0.isMine } }
    var myReports: [ModerationReportRow] { reports.filter(\.isMine) }
}
