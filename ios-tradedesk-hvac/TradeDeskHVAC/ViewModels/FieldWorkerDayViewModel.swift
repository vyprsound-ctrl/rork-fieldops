import Foundation
import Observation

@Observable
final class FieldWorkerDayViewModel {
    private(set) var state: LoadState<FieldWorkerDaySnapshot> = .idle
    private(set) var isUpdating: Bool = false
    var actionError: String?

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
