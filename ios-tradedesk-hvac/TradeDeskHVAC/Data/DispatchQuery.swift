import Foundation

/// How the dispatch board is narrowed. Applied by the gateway *after* the
/// tenant and role gates, never instead of them.
nonisolated struct DispatchQuery: Hashable, Sendable {
    var date: Date = Date()
    /// Show one worker's column only. Nil means everybody.
    var fieldWorkerUserID: String?
    /// Only jobs with nobody assigned.
    var unassignedOnly: Bool = false
    var searchText: String = ""

    static let today = DispatchQuery()

    var refinementCount: Int {
        var count = 0
        if fieldWorkerUserID != nil { count += 1 }
        if unassignedOnly { count += 1 }
        return count
    }

    var hasRefinements: Bool { refinementCount > 0 }

    mutating func clearRefinements() {
        fieldWorkerUserID = nil
        unassignedOnly = false
    }
}

/// Day or week. The calendar reads the same `Job.scheduledStart`/`scheduledEnd`
/// either way — the span only changes how many days are fetched.
nonisolated enum CalendarSpan: String, CaseIterable, Sendable, Identifiable {
    case day
    case week

    var id: String { rawValue }
    var title: String { self == .day ? "Day" : "Week" }
    var dayCount: Int { self == .day ? 1 : 7 }
}

/// What the calendar is showing and how it is filtered.
nonisolated struct CalendarQuery: Hashable, Sendable {
    var span: CalendarSpan = .day
    var anchorDate: Date = Date()
    var fieldWorkerUserID: String?
    var unassignedOnly: Bool = false

    var hasRefinements: Bool { fieldWorkerUserID != nil || unassignedOnly }

    mutating func clearRefinements() {
        fieldWorkerUserID = nil
        unassignedOnly = false
    }
}

/// A request to move a job to a new slot.
nonisolated struct RescheduleInput: Hashable, Sendable {
    var scheduledStart: Date?
    var scheduledEnd: Date?
    /// Set once a dispatcher has seen the conflict warning and chosen to go
    /// ahead anyway. The data layer refuses an overlapping change until this is
    /// true, so an overlap can never be created silently.
    var acknowledgesConflict: Bool = false
}

/// A request to assign, reassign or clear a job's field worker.
nonisolated struct AssignmentInput: Hashable, Sendable {
    /// Nil clears the assignment.
    var workerUserID: String?
    /// As with rescheduling: an overlap must be seen and accepted first.
    var acknowledgesConflict: Bool = false
}

// MARK: - Conflicts

/// Why a scheduling change is contentious.
///
/// A conflict is never an error on its own. Dispatch is a human job and there
/// are good reasons to double-book — two workers on one site, a quick call-out
/// squeezed between visits. The rule is only that it can't happen *silently*.
nonisolated enum SchedulingConflictKind: String, Sendable {
    /// The same worker is already booked over this time.
    case workerDoubleBooked
    /// The job has no slot, so nothing can be checked.
    case unscheduled

    var title: String {
        switch self {
        case .workerDoubleBooked: return "Overlapping jobs"
        case .unscheduled: return "No time slot"
        }
    }
}

/// One overlap the dispatcher needs to see before committing.
nonisolated struct SchedulingConflict: Identifiable, Hashable, Sendable {
    let id: String
    let kind: SchedulingConflictKind
    /// The job being moved or assigned.
    let jobID: String
    let jobNumber: String
    /// The job it clashes with.
    let clashingJobID: String
    let clashingJobNumber: String
    let clashingJobTitle: String
    let workerUserID: String
    let workerName: String
    /// "Marcus Hale is already on J-1042, 10:30 – 12:00"
    let detail: String
    let overlapLabel: String
}

/// The answer to "can this change go ahead?".
nonisolated struct SchedulingCheck: Hashable, Sendable {
    let conflicts: [SchedulingConflict]

    var hasConflicts: Bool { !conflicts.isEmpty }

    static let clear = SchedulingCheck(conflicts: [])

    var summary: String {
        guard let first = conflicts.first else { return "No clashes." }
        return conflicts.count == 1
            ? first.detail
            : "\(first.detail) and \(conflicts.count - 1) more."
    }
}
