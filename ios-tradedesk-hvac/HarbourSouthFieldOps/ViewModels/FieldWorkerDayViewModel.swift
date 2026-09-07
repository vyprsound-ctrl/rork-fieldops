import Foundation
import Observation

@Observable
final class FieldWorkerDayViewModel {
    private(set) var state: LoadState<FieldWorkerDaySnapshot> = .idle
    private(set) var isUpdating: Bool = false
    var actionError: String?
    /// Plain confirmation of the last thing that was sent, so a message to the
    /// office is visibly received rather than silently swallowed.
    private(set) var lastConfirmation: String?

    /// What became of the position capture on the last step. Held so the day
    /// screen can say a step was recorded without a position, rather than
    /// leaving the worker to assume one was taken.
    private(set) var lastCaptureOutcome: LocationCaptureOutcome?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.fieldWorkerDay(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    /// Tells the office something about the stop currently in hand.
    ///
    /// This is an internal note on the job, not a parallel messaging system:
    /// the office reads it where they read everything else about that job, and
    /// it stays on the record afterwards.
    func notifyDispatch(
        gateway: DataGateway,
        session: TenantSession,
        jobID: String,
        body: String
    ) async {
        isUpdating = true
        actionError = nil
        lastConfirmation = nil
        do {
            try await gateway.addJobNote(
                session: session,
                jobID: jobID,
                body: body,
                visibility: .internalOnly
            )
            lastConfirmation = "Sent to the office and saved on the job."
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isUpdating = false
    }

    /// Advances through `FieldTransitionCoordinator`, so a position is captured
    /// at exactly the workflow events the policy covers and at no others.
    func advance(
        gateway: DataGateway,
        location: LocationService,
        session: TenantSession,
        jobID: String,
        to status: JobStatus,
        destination: Coordinate?
    ) async {
        isUpdating = true
        actionError = nil
        lastConfirmation = nil
        do {
            lastCaptureOutcome = try await FieldTransitionCoordinator.advance(
                gateway: gateway,
                location: location,
                session: session,
                jobID: jobID,
                to: status,
                destination: destination
            )
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isUpdating = false
    }
}
