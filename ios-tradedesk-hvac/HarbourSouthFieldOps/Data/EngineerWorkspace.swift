import Foundation

// MARK: - Availability

/// The part of an engineer's availability the job lifecycle cannot express.
///
/// Deliberately only three values. Travelling, on site and working are already
/// facts about a job — they live in `JobStatus` and are derived from it — so
/// storing them again here would create two sources of truth that could
/// disagree. This enum matches `public.worker_duty_state` in the database
/// exactly, and nothing else.
nonisolated enum DutyState: String, Codable, CaseIterable, Sendable, Identifiable {
    case available
    case onBreak
    case offDuty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .available: return "Available"
        case .onBreak: return "On a break"
        case .offDuty: return "Off duty"
        }
    }

    var symbolName: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .onBreak: return "cup.and.saucer.fill"
        case .offDuty: return "moon.zzz.fill"
        }
    }

    var detail: String {
        switch self {
        case .available: return "Dispatch can send you the next call-out."
        case .onBreak: return "Dispatch can see you're on a break."
        case .offDuty: return "Dispatch won't count on you for new work."
        }
    }
}

/// What the office actually sees: the duty state the engineer set, unless a job
/// is live, in which case the job says where they are.
///
/// This is a *presentation* of two existing facts, not a third stored state.
nonisolated enum EngineerAvailability: String, Hashable, Sendable {
    case available
    case travelling
    case onSite
    case working
    case onBreak
    case offDuty

    /// Derives the shown status. The live job always wins: an engineer who is
    /// mid-repair is not "available" merely because they never changed a
    /// picker, and the office must not be told otherwise.
    static func resolve(duty: DutyState, activeJobStatus: JobStatus?) -> EngineerAvailability {
        switch activeJobStatus {
        case .travelling: return .travelling
        case .arrived: return .onSite
        case .inProgress: return .working
        default:
            switch duty {
            case .available: return .available
            case .onBreak: return .onBreak
            case .offDuty: return .offDuty
            }
        }
    }

    var title: String {
        switch self {
        case .available: return "Available"
        case .travelling: return "Travelling"
        case .onSite: return "On site"
        case .working: return "Working"
        case .onBreak: return "On a break"
        case .offDuty: return "Off duty"
        }
    }

    var symbolName: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .travelling: return "car.fill"
        case .onSite: return "mappin.circle.fill"
        case .working: return "wrench.adjustable.fill"
        case .onBreak: return "cup.and.saucer.fill"
        case .offDuty: return "moon.zzz.fill"
        }
    }

    var tone: StatusTone {
        switch self {
        case .available: return .success
        case .travelling, .onSite, .working: return .warning
        case .onBreak: return .info
        case .offDuty: return .neutral
        }
    }

    /// True when the status comes from a live job rather than the picker, so
    /// the UI can explain why the control is showing something else.
    var isDerivedFromJob: Bool {
        switch self {
        case .travelling, .onSite, .working: return true
        default: return false
        }
    }
}

// MARK: - Schedule

/// One assigned stop as the schedule shows it.
///
/// Like every other engineer-facing type in this app, it carries no price,
/// total or balance field at all — the restriction is structural.
nonisolated struct EngineerScheduleStop: Identifiable, Hashable, Sendable {
    let jobID: String
    let number: String
    let timeLabel: String
    let durationLabel: String?
    let customerName: String
    let addressLine: String
    let jobTitle: String
    let kindTitle: String
    let status: JobStatus
    let badge: StatusBadge
    let isUrgent: Bool

    var id: String { jobID }
}

nonisolated struct EngineerScheduleDay: Identifiable, Hashable, Sendable {
    let id: String
    let date: Date
    let title: String
    let subtitle: String
    let stops: [EngineerScheduleStop]
}

/// The engineer's own forward schedule. Read-only by construction: there is no
/// reschedule, reassign or delete anywhere on this type or its gateway call.
nonisolated struct EngineerSchedule: Hashable, Sendable {
    let days: [EngineerScheduleDay]
    let headline: String
    let subline: String

    var isEmpty: Bool { days.allSatisfy(\.stops.isEmpty) }
    var totalStops: Int { days.reduce(0) { $0 + $1.stops.count } }
}

// MARK: - Sites

/// A site the engineer has legitimate work at. Keyed by address, because an
/// engineer services a *place*, not an account.
nonisolated struct EngineerSiteRow: Identifiable, Hashable, Sendable {
    let id: String
    let customerID: String
    let customerName: String
    let initials: String
    let addressLine: String
    let equipmentCount: Int
    let visitCount: Int
    let lastVisitLabel: String?
    let hasOpenWork: Bool
}

nonisolated struct EngineerSiteContact: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let roleTitle: String?
    let phone: String?
}

/// One visit to a site, in the engineer's history. No money, by construction.
nonisolated struct EngineerVisitRow: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let dateLabel: String
    let kindTitle: String
    let badge: StatusBadge
    let isMine: Bool
}

nonisolated struct EngineerSiteDetail: Identifiable, Hashable, Sendable {
    let id: String
    let customerID: String
    let customerName: String
    let typeTitle: String
    let addressLine: String
    let latitude: Double
    let longitude: Double
    let accessNotes: String?
    let siteNotes: String?
    let contacts: [EngineerSiteContact]
    let equipment: [EquipmentProjection]
    let openVisits: [EngineerVisitRow]
    let pastVisits: [EngineerVisitRow]
    /// Whether this engineer may add technical detail to the asset register.
    let canUpdateEquipment: Bool
}

// MARK: - Completed work

nonisolated struct EngineerWorkRecord: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let customerName: String
    let addressLine: String
    let kindTitle: String
    let completedAt: Date
    let completedLabel: String
    let noteCount: Int
    let photoCount: Int
    let hasSignature: Bool
}

// MARK: - Profile

nonisolated struct EngineerProfile: Hashable, Sendable {
    let userID: String
    let name: String
    let initials: String
    let email: String
    let phone: String?
    let roleTitle: String
    let companyName: String
    let tradeTitle: String

    let dutyState: DutyState
    let availability: EngineerAvailability
    let dutyChangedLabel: String?
    /// The job driving a derived status, so the screen can name it.
    let activeJobNumber: String?

    let jobsToday: Int
    let completedToday: Int
    let upcomingCount: Int
    let completedAllTime: Int
}

// MARK: - Office messaging

nonisolated struct OfficeThreadRow: Identifiable, Hashable, Sendable {
    let id: String
    let subject: String
    let preview: String
    let timeLabel: String
    let lastMessageAt: Date
    let counterpartyName: String
    let jobID: String?
    let jobNumber: String?
    let customerName: String?
    let isUnread: Bool
}

/// The engineer's conversations with the office.
///
/// `isAvailable` exists so the development stack, which has no messaging behind
/// it, says so plainly instead of presenting an empty inbox that would never
/// fill — the same honesty rule the rest of this app follows.
nonisolated struct OfficeInbox: Hashable, Sendable {
    let threads: [OfficeThreadRow]
    let unreadCount: Int
    let isAvailable: Bool
    let unavailableReason: String?

    static func unavailable(_ reason: String) -> OfficeInbox {
        OfficeInbox(threads: [], unreadCount: 0, isAvailable: false, unavailableReason: reason)
    }
}

nonisolated struct OfficeMessageRow: Identifiable, Hashable, Sendable {
    let id: String
    let body: String
    let senderName: String
    let senderInitials: String
    let timeLabel: String
    let isMine: Bool
    /// `job_photos.storage_reference` values, resolved by the same thumbnail
    /// component the job screens use. No separate media pipeline.
    let photoReferences: [String]
}

nonisolated struct OfficeConversation: Identifiable, Hashable, Sendable {
    let id: String
    let subject: String
    let jobID: String?
    let jobNumber: String?
    let customerName: String?
    let messages: [OfficeMessageRow]
    let canReply: Bool
}

/// What the composer sends. Carries no company and no sender: the database
/// takes both from the authenticated session, so this app cannot post as
/// somebody else or into another company.
nonisolated struct OfficeMessageDraft: Hashable, Sendable {
    /// Continuing an existing conversation.
    var threadID: String?
    /// Starting one about a specific job.
    var jobID: String?
    var subject: String = ""
    var body: String = ""
    /// Photos already attached to `jobID`, referenced by id.
    var photoIDs: [String] = []

    var isSendable: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The reasons an engineer usually needs the office, offered as starting points
/// so a message is a two-tap job on a cold morning rather than a blank box.
nonisolated enum OfficeMessageTopic: String, CaseIterable, Identifiable, Sendable {
    case partRequired
    case partAvailability
    case needsApproval
    case runningLate
    case accessProblem
    case identifyEquipment
    case contactCustomer
    case somethingElse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .partRequired: return "Part required"
        case .partAvailability: return "Is this part in stock?"
        case .needsApproval: return "Need approval"
        case .runningLate: return "Running late"
        case .accessProblem: return "Can't get access"
        case .identifyEquipment: return "Help identifying a part"
        case .contactCustomer: return "Please call the customer"
        case .somethingElse: return "Something else"
        }
    }

    var symbolName: String {
        switch self {
        case .partRequired: return "shippingbox"
        case .partAvailability: return "magnifyingglass"
        case .needsApproval: return "checkmark.seal"
        case .runningLate: return "clock"
        case .accessProblem: return "lock.trianglebadge.exclamationmark"
        case .identifyEquipment: return "camera.viewfinder"
        case .contactCustomer: return "phone"
        case .somethingElse: return "bubble.left"
        }
    }

    /// A first line, not a canned message. The engineer still writes what is
    /// actually wrong — this only saves them typing the subject.
    var prompt: String {
        switch self {
        case .partRequired: return "Which part, and what's it for?"
        case .partAvailability: return "Which part are you checking on?"
        case .needsApproval: return "What needs approving before you carry on?"
        case .runningLate: return "How late, and what's holding you up?"
        case .accessProblem: return "What's stopping you getting in?"
        case .identifyEquipment: return "Describe what you're looking at."
        case .contactCustomer: return "What should the office tell them?"
        case .somethingElse: return "What do you need the office to know?"
        }
    }
}
