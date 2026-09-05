import Foundation
import Observation

@Observable
final class TravelViewModel {
    private(set) var state: LoadState<TravelSnapshot> = .idle
    private(set) var isWorking: Bool = false
    /// Simulated in this phase. The flag rides on the estimate itself, so the
    /// view labels it honestly without knowing which adapter produced it.
    private(set) var estimate: RouteEstimate?
    var actionError: String?

    /// What became of the position capture on the last step. Held so the screen
    /// can say a step was recorded without a position, rather than leaving the
    /// worker to assume one was taken.
    private(set) var lastCaptureOutcome: LocationCaptureOutcome?

    func load(
        gateway: DataGateway,
        location: LocationService,
        routes: RouteService,
        session: TenantSession,
        jobID: String,
        showLoading: Bool = true
    ) async {
        if showLoading { state = .loading }
        do {
            let snapshot = try await gateway.travelSnapshot(session: session, jobID: jobID)
            state = .loaded(snapshot)
            await refreshEstimate(location: location, routes: routes, snapshot: snapshot)
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    /// Re-runs the estimate on demand. There is no polling: the worker asks, or
    /// the screen loads.
    func refreshEstimate(location: LocationService, routes: RouteService, snapshot: TravelSnapshot) async {
        guard let origin = await location.currentLocation() else {
            estimate = nil
            return
        }
        estimate = await routes.estimate(
            from: origin,
            to: Coordinate(latitude: snapshot.latitude, longitude: snapshot.longitude)
        )
    }

    /// Advances through the coordinator so the position capture and the status
    /// change stay in step.
    func advance(
        gateway: DataGateway,
        location: LocationService,
        routes: RouteService,
        session: TenantSession,
        jobID: String,
        to status: JobStatus,
        destination: Coordinate?
    ) async {
        isWorking = true
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
            await load(gateway: gateway, location: location, routes: routes, session: session, jobID: jobID, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
