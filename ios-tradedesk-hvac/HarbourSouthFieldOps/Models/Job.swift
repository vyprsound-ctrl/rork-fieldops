import Foundation

/// The approved nine-state job lifecycle.
///
/// "Unscheduled" is deliberately *not* a status: a job is unscheduled when it
/// has no `scheduledStart`, which is a separate fact that can be true of a job
/// in several states. Keeping it out of the enum stops the two ideas drifting.
///
/// Status names are trade-neutral — `workerAssigned` displays as "Engineer
/// assigned", "Plumber assigned" or "Technician assigned" per company.
nonisolated enum JobStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case scheduled
    case workerAssigned
    case travelling
    case arrived
    case inProgress
    case completed
    case invoiced
    case paid
    case cancelled

    var id: String { rawValue }

    /// Trade-neutral title. Use `title(_:)` wherever a company context exists.
    var title: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .workerAssigned: return "Assigned"
        case .travelling: return "Travelling"
        case .arrived: return "Arrived"
        case .inProgress: return "In progress"
        case .completed: return "Completed"
        case .invoiced: return "Invoiced"
        case .paid: return "Paid"
        case .cancelled: return "Cancelled"
        }
    }

    func title(_ terms: Terminology) -> String {
        self == .workerAssigned ? "\(terms.Worker) assigned" : title
    }

    /// Short form for dense rows and filter chips.
    var shortTitle: String { title }

    var symbolName: String {
        switch self {
        case .scheduled: return "calendar"
        case .workerAssigned: return "person.badge.shield.checkmark"
        case .travelling: return "car.fill"
        case .arrived: return "mappin.circle.fill"
        case .inProgress: return "wrench.adjustable.fill"
        case .completed: return "checkmark.circle.fill"
        case .invoiced: return "doc.plaintext.fill"
        case .paid: return "banknote.fill"
        case .cancelled: return "xmark.circle.fill"
        }
    }

    /// Still operationally live — the work isn't finished.
    var isOpen: Bool {
        switch self {
        case .completed, .invoiced, .paid, .cancelled: return false
        default: return true
        }
    }

    /// The field worker is actively working this job on site.
    var isFieldActive: Bool {
        switch self {
        case .travelling, .arrived, .inProgress: return true
        default: return false
        }
    }

    var tone: StatusTone {
        switch self {
        case .scheduled: return .info
        case .workerAssigned: return .info
        case .travelling, .arrived, .inProgress: return .warning
        case .completed, .paid: return .success
        case .invoiced: return .success
        case .cancelled: return .neutral
        }
    }

    /// Position in the operational pipeline, used by the timeline stepper.
    /// Cancelled sits outside the pipeline and returns `nil`.
    var pipelineIndex: Int? {
        switch self {
        case .scheduled: return 0
        case .workerAssigned: return 1
        case .travelling: return 2
        case .arrived: return 3
        case .inProgress: return 4
        case .completed: return 5
        case .invoiced: return 6
        case .paid: return 7
        case .cancelled: return nil
        }
    }

    static let pipeline: [JobStatus] = [
        .scheduled, .workerAssigned, .travelling, .arrived, .inProgress, .completed, .invoiced, .paid
    ]
}

/// Job types common to field-service trades. A trade may later add its own
/// templates on top of these, but the four base kinds apply everywhere.
nonisolated enum JobKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case callOut
    case install
    case maintenance
    case warranty

    var id: String { rawValue }

    var title: String {
        switch self {
        case .callOut: return "Call-out"
        case .install: return "Installation"
        case .maintenance: return "Maintenance"
        case .warranty: return "Warranty"
        }
    }

    var symbolName: String {
        switch self {
        case .callOut: return "exclamationmark.bubble.fill"
        case .install: return "shippingbox.fill"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .warranty: return "checkmark.seal.fill"
        }
    }
}

nonisolated enum JobPriority: String, Codable, CaseIterable, Sendable, Identifiable {
    case standard
    case urgent

    var id: String { rawValue }

    var title: String { self == .urgent ? "Urgent" : "Standard" }
}

/// The work order record. Identical for every trade: what needs doing, for
/// whom, where, on which asset, by whom and when.
nonisolated struct Job: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let customerID: String
    let addressID: String
    var equipmentID: String?
    /// The quote this job was raised from, preserved for the life of the job.
    var quoteID: String?
    var number: String
    var title: String
    var jobDescription: String
    var kind: JobKind
    var priority: JobPriority
    var status: JobStatus
    var scheduledStart: Date?
    var scheduledEnd: Date?
    var actualStart: Date?
    var actualEnd: Date?
    var serviceAgreementID: String?
    var createdAt: Date

    var isUnscheduled: Bool { scheduledStart == nil }
}
