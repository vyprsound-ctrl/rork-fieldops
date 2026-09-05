import Foundation
import Observation

@Observable
final class FieldWorkerJobViewModel {
    private(set) var state: LoadState<FieldWorkerJobDetail> = .idle
    private(set) var isWorking: Bool = false
    var actionError: String?

    /// What became of the position capture on the last step. Held so the screen
    /// can say a step was recorded without a position, rather than leaving the
    /// worker to assume one was taken.
    private(set) var lastCaptureOutcome: LocationCaptureOutcome?

    func load(gateway: DataGateway, session: TenantSession, jobID: String, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.fieldWorkerJobDetail(session: session, jobID: jobID))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    /// Advances through `FieldTransitionCoordinator` so the status change and the
    /// position capture stay in step.
    func advance(
        gateway: DataGateway,
        location: LocationService,
        session: TenantSession,
        jobID: String,
        to status: JobStatus,
        destination: Coordinate?
    ) async {
        await perform(gateway: gateway, session: session, jobID: jobID) {
            self.lastCaptureOutcome = try await FieldTransitionCoordinator.advance(
                gateway: gateway,
                location: location,
                session: session,
                jobID: jobID,
                to: status,
                destination: destination
            )
        }
    }

    func addNote(gateway: DataGateway, session: TenantSession, jobID: String, body: String) async {
        await perform(gateway: gateway, session: session, jobID: jobID) {
            try await gateway.addJobNote(session: session, jobID: jobID, body: body, visibility: .internalOnly)
        }
    }

    func addPhoto(gateway: DataGateway, session: TenantSession, jobID: String, kind: JobPhotoKind, caption: String?) async {
        await perform(gateway: gateway, session: session, jobID: jobID) {
            try await gateway.addJobPhoto(session: session, jobID: jobID, kind: kind, caption: caption)
        }
    }

    private func perform(
        gateway: DataGateway,
        session: TenantSession,
        jobID: String,
        _ work: () async throws -> Void
    ) async {
        isWorking = true
        actionError = nil
        do {
            try await work()
            await load(gateway: gateway, session: session, jobID: jobID, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
