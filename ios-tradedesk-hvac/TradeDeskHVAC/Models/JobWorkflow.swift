import Foundation

/// What a caller must hold to perform a transition.
nonisolated enum TransitionRequirement: Hashable, Sendable {
    /// Field work: allowed for a field worker assigned to this job
    /// (`jobStatusUpdateOwn` + a matching `FieldWorkerAssignment`), or for
    /// office roles holding `jobsManage`.
    case fieldWork
    /// Office-only transition requiring a specific permission.
    case office(Permission)

    var permissionForDisplay: Permission {
        switch self {
        case .fieldWork: return .jobStatusUpdateOwn
        case .office(let permission): return permission
        }
    }
}

nonisolated struct JobTransition: Hashable, Sendable, Identifiable {
    let from: JobStatus
    let to: JobStatus
    /// May contain `{worker}` tokens, resolved against the company's trade.
    let actionTemplate: String
    let requirement: TransitionRequirement
    /// Field transitions stamp the worker's last known position onto the
    /// history row; office transitions deliberately do not.
    let capturesLocation: Bool
    let isDestructive: Bool

    var id: String { "\(from.rawValue)->\(to.rawValue)" }

    func actionTitle(_ terms: Terminology) -> String {
        terms.resolve(actionTemplate).capitalizedFirst
    }
}

/// The approved status workflow, in one place.
///
/// The gateway validates every write against this table, so an invalid or
/// out-of-order transition is rejected by the data layer rather than merely
/// being absent from a screen. The workflow is trade-neutral.
nonisolated enum JobWorkflow {
    static let all: [JobTransition] = [
        JobTransition(from: .scheduled, to: .workerAssigned, actionTemplate: "Assign {worker}", requirement: .office(.assignmentsManage), capturesLocation: false, isDestructive: false),
        JobTransition(from: .workerAssigned, to: .travelling, actionTemplate: "Start travel", requirement: .fieldWork, capturesLocation: true, isDestructive: false),
        JobTransition(from: .travelling, to: .arrived, actionTemplate: "Arrived on site", requirement: .fieldWork, capturesLocation: true, isDestructive: false),
        JobTransition(from: .arrived, to: .inProgress, actionTemplate: "Start work", requirement: .fieldWork, capturesLocation: true, isDestructive: false),
        JobTransition(from: .inProgress, to: .completed, actionTemplate: "Complete job", requirement: .fieldWork, capturesLocation: true, isDestructive: false),
        JobTransition(from: .completed, to: .invoiced, actionTemplate: "Mark invoiced", requirement: .office(.invoicesManage), capturesLocation: false, isDestructive: false),
        JobTransition(from: .invoiced, to: .paid, actionTemplate: "Mark paid", requirement: .office(.paymentsManage), capturesLocation: false, isDestructive: false),
        // Recovery paths for the office.
        JobTransition(from: .workerAssigned, to: .scheduled, actionTemplate: "Unassign {worker}", requirement: .office(.assignmentsManage), capturesLocation: false, isDestructive: false),
        JobTransition(from: .travelling, to: .workerAssigned, actionTemplate: "Send back to assigned", requirement: .office(.jobsManage), capturesLocation: false, isDestructive: false),
        // Cancellation from any live state.
        JobTransition(from: .scheduled, to: .cancelled, actionTemplate: "Cancel job", requirement: .office(.jobsManage), capturesLocation: false, isDestructive: true),
        JobTransition(from: .workerAssigned, to: .cancelled, actionTemplate: "Cancel job", requirement: .office(.jobsManage), capturesLocation: false, isDestructive: true),
        JobTransition(from: .travelling, to: .cancelled, actionTemplate: "Cancel job", requirement: .office(.jobsManage), capturesLocation: false, isDestructive: true),
        JobTransition(from: .arrived, to: .cancelled, actionTemplate: "Cancel job", requirement: .office(.jobsManage), capturesLocation: false, isDestructive: true)
    ]

    static func transitions(from status: JobStatus) -> [JobTransition] {
        all.filter { $0.from == status }
    }

    static func transition(from: JobStatus, to: JobStatus) -> JobTransition? {
        all.first { $0.from == from && $0.to == to }
    }

    /// The single forward step a field worker takes next, if any.
    static func fieldAdvance(from status: JobStatus) -> JobTransition? {
        transitions(from: status).first { $0.requirement == .fieldWork && !$0.isDestructive }
    }
}
