import Foundation

/// A device registered to receive job alerts.
///
/// Tenancy is not a field the client chooses: `companyID` and `userID` are
/// written by the database from the authenticated session. They appear here
/// only because the development store has to model what the database records.
nonisolated struct PushDeviceRecord: Identifiable, Hashable, Sendable {
    let id: String
    let companyID: String
    let userID: String
    /// The APNs address. Never rendered in full and never logged.
    let token: String
    let environment: PushEnvironment
    var appVersion: String
    var deviceModel: String
    var lastRegisteredAt: Date
    /// Nil while the token is deliverable.
    var revokedAt: Date?
    var revokedReason: String?

    var isLive: Bool { revokedAt == nil }

    var masked: String { "•••• \(token.suffix(6))" }
}

/// The operational events that raise a push notification.
///
/// Each case corresponds to a real change in the workflow — an assignment row
/// written, a job's slot moved, a status transition recorded. Nothing here can
/// be raised on its own; the event is a consequence of the write.
nonisolated enum PushEvent: String, CaseIterable, Sendable {
    case jobAssigned = "job.assigned"
    case jobReassigned = "job.reassigned"
    case jobUnassigned = "job.unassigned"
    case jobRescheduled = "job.rescheduled"
    case jobCancelled = "job.cancelled"
    case jobUpdated = "job.updated"
    case jobNote = "job.note"
    /// Field progress travelling the other way: the office hears that an
    /// engineer has moved a job on.
    case jobFieldUpdate = "job.fieldUpdate"
    /// A message in an engineer ↔ office conversation. Travels in both
    /// directions: the office is alerted when an engineer writes, and the
    /// engineer is alerted when the office replies.
    case officeMessage = "office.message"

    var title: String {
        switch self {
        case .jobAssigned: return "New job assigned"
        case .jobReassigned: return "Job reassigned to you"
        case .jobUnassigned: return "Removed from a job"
        case .jobRescheduled: return "Job time changed"
        case .jobCancelled: return "Job cancelled"
        case .jobUpdated: return "Job details updated"
        case .jobNote: return "New note on your job"
        case .jobFieldUpdate: return "Job progress"
        case .officeMessage: return "New message"
        }
    }

    var symbolName: String {
        switch self {
        case .jobAssigned, .jobReassigned: return "person.badge.plus"
        case .jobUnassigned: return "person.badge.minus"
        case .jobRescheduled: return "clock.arrow.circlepath"
        case .jobCancelled: return "xmark.octagon.fill"
        case .jobUpdated: return "pencil"
        case .jobNote: return "text.bubble"
        case .jobFieldUpdate: return "figure.walk"
        case .officeMessage: return "bubble.left.and.bubble.right.fill"
        }
    }

    /// Which permission an office recipient must hold to be told. Engineer
    /// events are addressed by assignment instead, which is stricter.
    ///
    /// A message needs no entry here: `send_office_message()` resolves its
    /// recipients individually from the company's own role grants, so the
    /// addressing is done before a notification row is ever written.
    var officePermission: Permission? {
        self == .jobFieldUpdate ? .assignmentsManage : nil
    }
}

/// One push attempt, read back from the shared notifications ledger.
///
/// This is the same ledger that records customer SMS and email. There is no
/// separate push table, so a delivery outcome means the same thing whichever
/// channel produced it.
nonisolated struct PushNotificationRecord: Identifiable, Hashable, Sendable {
    let id: String
    let event: String
    let title: String
    let body: String
    let status: NotificationStatus
    let jobID: String?
    let deepLink: String?
    let failureReason: String?
    let createdAt: Date
    let sentAt: Date?

    var pushEvent: PushEvent? { PushEvent(rawValue: event) }

    var symbolName: String { pushEvent?.symbolName ?? "bell" }

    /// Where tapping this notification takes the person.
    var route: AppRoute? { PushDeepLink.route(fromLink: deepLink) }

    var statusTitle: String { status.title }

    /// Delivery is only ever claimed when the provider confirmed it.
    var wasDelivered: Bool { status == .sent || status == .delivered }
}
