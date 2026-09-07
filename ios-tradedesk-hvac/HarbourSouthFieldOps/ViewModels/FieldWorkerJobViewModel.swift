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

    /// Attaches real images. Each one reports its own outcome, so "three of
    /// four went up" is said out loud rather than hidden behind a refresh.
    func attachPhotos(
        gateway: DataGateway,
        session: TenantSession,
        jobID: String,
        uploads: [JobMediaUpload]
    ) async {
        guard !uploads.isEmpty else { return }
        await perform(gateway: gateway, session: session, jobID: jobID) {
            var failures = 0
            for upload in uploads {
                let result = try await gateway.attachJobMedia(session: session, jobID: jobID, upload: upload)
                if !result.stored { failures += 1 }
            }
            if failures > 0 {
                throw DataError.unexpected(
                    failures == 1
                        ? "One photo couldn't be attached. Try it again."
                        : "\(failures) photos couldn't be attached. Try them again."
                )
            }
        }
    }

    /// Refreshes after the completion sheet has done its own writing.
    func reload(gateway: DataGateway, session: TenantSession, jobID: String) async {
        await load(gateway: gateway, session: session, jobID: jobID, showLoading: false)
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
