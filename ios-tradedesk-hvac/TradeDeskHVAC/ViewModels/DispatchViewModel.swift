import Foundation
import Observation

@Observable
final class DispatchViewModel {
    private(set) var state: LoadState<DispatchBoard> = .idle
    private(set) var isWorking: Bool = false
    var query: DispatchQuery = .today
    var actionError: String?

    /// A clash the dispatcher has been shown but not yet accepted. Holding it
    /// here is what turns "refused" into "confirm and retry" without the view
    /// having to re-derive anything.
    var pendingConflict: PendingAssignment?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.dispatchBoard(session: session, query: query))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    /// First attempt. An overlapping assignment is refused by the data layer and
    /// surfaced as a confirmation rather than an error.
    func assign(
        gateway: DataGateway,
        session: TenantSession,
        jobID: String,
        jobNumber: String,
        workerUserID: String?,
        workerName: String
    ) async {
        isWorking = true
        actionError = nil
        do {
            _ = try await gateway.assignJob(
                session: session,
                jobID: jobID,
                input: AssignmentInput(workerUserID: workerUserID, acknowledgesConflict: false)
            )
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            // Re-run the read-only check so the view can show exactly what clashes.
            let check = (try? await gateway.checkAssignment(session: session, jobID: jobID, workerUserID: workerUserID)) ?? .clear
            if check.hasConflicts {
                pendingConflict = PendingAssignment(
                    id: jobID,
                    jobID: jobID,
                    jobNumber: jobNumber,
                    workerUserID: workerUserID,
                    workerName: workerName,
                    check: check
                )
            } else {
                actionError = DataError.wrap(error).errorDescription
            }
        }
        isWorking = false
    }

    /// Second attempt, carrying the dispatcher's explicit acknowledgement.
    func confirmPendingAssignment(gateway: DataGateway, session: TenantSession) async {
        guard let pending = pendingConflict else { return }
        pendingConflict = nil
        isWorking = true
        actionError = nil
        do {
            _ = try await gateway.assignJob(
                session: session,
                jobID: pending.jobID,
                input: AssignmentInput(workerUserID: pending.workerUserID, acknowledgesConflict: true)
            )
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
