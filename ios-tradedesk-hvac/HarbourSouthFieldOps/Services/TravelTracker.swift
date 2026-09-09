import Foundation
import Observation

/// Owns the one travel leg an engineer can be on, and writes its pings.
///
/// **Why this exists as a separate object.** `LocationService` knows how to read
/// a device and nothing else; `DataGateway` knows how to write a row and nothing
/// else. Something has to decide *when* a leg starts, *when* it stops and *what*
/// gets stored in between, and putting that in a view would mean the leg ended
/// whenever the worker navigated away. It lives on `AppEnvironment` so it
/// survives navigation, and `state` is what the UI shows — never more optimistic
/// than what Core Location actually reported.
///
/// **The bounds are the point.** A leg is opened by `Start travel`, closed by
/// `Arrived`, `Complete`, sign-out, or the adapter's own expiry. There is no
/// path that opens one without a job id, so this cannot become all-day tracking
/// by accident.
///
/// It deliberately holds no gateway, session or adapter of its own: they are
/// passed in at each call, so the tracker can never keep writing against a
/// session that has since been signed out.
@MainActor
@Observable
final class TravelTracker {
    private(set) var state: TravelTrackingState = .off
    /// Pings written during the current leg. Reset when a leg starts, shown so
    /// a worker can see the app is doing what it said it would.
    private(set) var pingsThisLeg: Int = 0
    /// The last thing that went wrong, in the worker's terms. Nil when fine.
    private(set) var lastError: String?
    /// Whether updates survive the phone being locked, as last read.
    private(set) var backgroundState: LocationBackgroundState = .foregroundOnly

    /// The adapter currently running the leg, so it can be stopped by whoever
    /// closes it — including a sign-out that no longer has a session to pass.
    private var activeLocation: LocationService?

    /// Serialises writes so two fixes arriving together cannot interleave.
    private var writeTask: Task<Void, Never>?

    var isTracking: Bool { state.isTracking }

    /// Brings tracking in line with a job's status.
    ///
    /// This is the single rule: *travelling* opens a leg, anything else closes
    /// it. Arrival, completion, cancellation and a job put back on hold all
    /// stop the radio through the same path, which is why there is no status
    /// that can leave tracking running.
    func sync(
        jobID: String,
        status: JobStatus,
        location: LocationService,
        gateway: DataGateway,
        session: TenantSession
    ) async {
        if status == .travelling {
            await start(jobID: jobID, location: location, gateway: gateway, session: session)
        } else if state.jobID == jobID || state.isTracking {
            await stop()
        }
    }

    /// Opens a leg for this job.
    ///
    /// Calling it for a job already being tracked is a no-op rather than a
    /// restart, so a screen reappearing cannot reset the ping count or re-prompt.
    func start(
        jobID: String,
        location: LocationService,
        gateway: DataGateway,
        session: TenantSession
    ) async {
        guard state.jobID != jobID else { return }

        pingsThisLeg = 0
        lastError = nil
        activeLocation = location

        // Core Location calls the handler from its own context, so the hop back
        // onto the main actor happens here rather than being assumed.
        state = await location.startTravelTracking(jobID: jobID) { [weak self] fix in
            Task { @MainActor [weak self] in
                self?.record(fix: fix, jobID: jobID, gateway: gateway, session: session)
            }
        }
        backgroundState = await location.backgroundAuthorizationState
    }

    /// Closes the leg. Safe to call when nothing is running.
    func stop() async {
        writeTask?.cancel()
        writeTask = nil
        await activeLocation?.stopTravelTracking()
        activeLocation = nil
        state = .off
    }

    /// Reads the background permission without prompting.
    func refreshBackgroundState(location: LocationService) async {
        backgroundState = await location.backgroundAuthorizationState
    }

    /// Asks for the always-authorisation upgrade. Only meaningful once
    /// while-in-use exists, which the adapter enforces.
    @discardableResult
    func requestBackgroundPermission(location: LocationService) async -> LocationBackgroundState {
        let result = await location.requestBackgroundAuthorization()
        backgroundState = result
        // The leg may have been foreground-only when it started. Re-reading the
        // state here is what lets the badge become "Sharing location" without
        // the worker having to restart travel.
        if case .tracking(let jobID, false) = state, result == .granted {
            state = .tracking(jobID: jobID, background: true)
        }
        return result
    }

    /// Stores one ping.
    ///
    /// The write carries no company id — the gateway takes it from the session,
    /// exactly as every other write in this app does, so a tracked position
    /// cannot be filed against another tenant.
    private func record(
        fix: LocationFix,
        jobID: String,
        gateway: DataGateway,
        session: TenantSession
    ) {
        // A late fix arriving after the leg closed is discarded rather than
        // written, so a stored trail never extends past the arrival it belongs
        // to.
        guard state.jobID == jobID else { return }

        let previous = writeTask
        writeTask = Task { [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            do {
                // Filed under `travelStarted`: every ping in this leg belongs
                // to the drive that event opened, so the office reads one
                // continuous approach rather than a second category of point.
                try await gateway.recordLocationFix(
                    session: session,
                    jobID: jobID,
                    event: .travelStarted,
                    fix: fix
                )
                self.pingsThisLeg += 1
                self.lastError = nil
            } catch {
                // A failed ping is not a failed journey. The worker is told,
                // the leg continues, and the next fix tries again.
                self.lastError = (error as? DataError)?.errorDescription
                    ?? "A position could not be sent to the office."
            }
        }
    }
}
