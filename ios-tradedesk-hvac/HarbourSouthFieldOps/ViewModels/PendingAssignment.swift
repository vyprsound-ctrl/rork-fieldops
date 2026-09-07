import Foundation

/// An assignment that was refused because it would double-book a worker, held
/// until the person doing it has seen the clash and accepted it.
///
/// Shared by every screen that can assign — the dispatch board and a job's own
/// screen — so the warning, the wording and the acknowledgement are the same
/// wherever the assignment is made from.
struct PendingAssignment: Identifiable, Hashable {
    let id: String
    let jobID: String
    let jobNumber: String
    let workerUserID: String?
    let workerName: String
    let check: SchedulingCheck

    /// Names what is about to happen, so the sheet states the job and the worker
    /// as well as the clash they would collide with.
    var contextLine: String {
        "Assigning \(jobNumber) to \(workerName)"
    }
}
