import Foundation
import Observation

@Observable
final class JobDetailViewModel {
    private(set) var state: LoadState<JobDetailProjection> = .idle
    private(set) var isWorking: Bool = false
    private(set) var options: JobFormOptions = .empty
    var actionError: String?
    var lastConfirmation: String?

    /// A clash this screen has been shown but not yet accepted. Exactly as on
    /// the dispatch board: holding it here is what turns a refusal into
    /// "confirm and retry" instead of an error the user can only dismiss.
    var pendingConflict: PendingAssignment?

    func load(gateway: DataGateway, session: TenantSession, jobID: String, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.jobDetail(session: session, jobID: jobID))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func loadOptions(gateway: DataGateway, session: TenantSession) async {
        options = (try? await gateway.jobFormOptions(session: session)) ?? .empty
    }

    func updateStatus(gateway: DataGateway, session: TenantSession, jobID: String, to status: JobStatus) async {
        await perform(gateway: gateway, session: session, jobID: jobID, confirmation: "Moved to \(status.title(session.terms))") {
            try await gateway.updateJobStatus(session: session, jobID: jobID, to: status)
        }
    }

    /// First attempt, offering no acknowledgement. An overlapping assignment is
    /// refused by the data layer before anything is written, and is surfaced as
    /// a confirmation rather than an error.
    func assign(gateway: DataGateway, session: TenantSession, jobID: String, workerUserID: String?) async {
        isWorking = true
        actionError = nil
        do {
            try await gateway.assignFieldWorker(
                session: session,
                jobID: jobID,
                workerUserID: workerUserID,
                acknowledgesConflict: false
            )
            lastConfirmation = workerUserID == nil ? "\(session.terms.Worker) removed" : "\(session.terms.Worker) assigned"
            await load(gateway: gateway, session: session, jobID: jobID, showLoading: false)
        } catch {
            lastConfirmation = nil

            // Re-run the read-only check so the screen can show exactly what
            // clashes. Anything else is a genuine failure.
            let check = (try? await gateway.checkAssignment(session: session, jobID: jobID, workerUserID: workerUserID)) ?? .clear
            if check.hasConflicts {
                pendingConflict = PendingAssignment(
                    id: jobID,
                    jobID: jobID,
                    jobNumber: state.value?.number ?? "This job",
                    workerUserID: workerUserID,
                    workerName: options.workers.first { $0.id == workerUserID }?.name ?? session.terms.Worker,
                    check: check
                )
            } else {
                actionError = DataError.wrap(error).errorDescription
            }
        }
        isWorking = false
    }

    /// Second attempt, carrying the explicit acknowledgement through the same
    /// assignment path. Only reachable from the confirmation sheet.
    func confirmPendingAssignment(gateway: DataGateway, session: TenantSession) async {
        guard let pending = pendingConflict else { return }
        pendingConflict = nil
        await perform(
            gateway: gateway,
            session: session,
            jobID: pending.jobID,
            confirmation: "\(session.terms.Worker) assigned over an overlap"
        ) {
            try await gateway.assignFieldWorker(
                session: session,
                jobID: pending.jobID,
                workerUserID: pending.workerUserID,
                acknowledgesConflict: true
            )
        }
    }

    func addNote(gateway: DataGateway, session: TenantSession, jobID: String, body: String, visibility: NoteVisibility) async {
        await perform(gateway: gateway, session: session, jobID: jobID, confirmation: "Note saved") {
            try await gateway.addJobNote(session: session, jobID: jobID, body: body, visibility: visibility)
        }
    }

    func addPhoto(gateway: DataGateway, session: TenantSession, jobID: String, kind: JobPhotoKind, caption: String?) async {
        await perform(gateway: gateway, session: session, jobID: jobID, confirmation: "Photo record added") {
            try await gateway.addJobPhoto(session: session, jobID: jobID, kind: kind, caption: caption)
        }
    }

    private func perform(
        gateway: DataGateway,
        session: TenantSession,
        jobID: String,
        confirmation: String,
        _ work: () async throws -> Void
    ) async {
        isWorking = true
        actionError = nil
        do {
            try await work()
            lastConfirmation = confirmation
            await load(gateway: gateway, session: session, jobID: jobID, showLoading: false)
        } catch {
            lastConfirmation = nil
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
