import Foundation

/// The single place a workflow transition and a position capture are joined.
///
/// Keeping this out of both the gateway and the views means the capture policy
/// is stated once: `LocationCaptureEvent.forTransition` decides whether a fix is
/// taken at all, the `LocationService` adapter produces it, and the gateway
/// stores it alongside the status change. A transition the policy does not cover
/// captures nothing — there is no code path that takes a position "just in case".
///
/// The one-shot capture happens because a person tapped a button that moved a
/// job forward. The *travel leg* is opened and closed here too, by the same
/// transitions — `travelling` starts it, every other status stops it — so there
/// is exactly one place in the app where continuous tracking can begin, and it
/// is a place that already has a job id in its hand.
nonisolated enum FieldTransitionCoordinator {
    /// Advances a job, capturing a position first when the workflow event calls
    /// for one.
    ///
    /// The job moves regardless of what location does. A refused permission, a
    /// device with the radio off or a fix that never arrives all leave the
    /// status change intact and the position simply absent — the business rules
    /// decide whether work can proceed, not the GPS.
    ///
    /// - Parameter destination: the site being travelled to, used by the
    ///   simulated adapter to produce a plausible fixture. A production adapter
    ///   ignores it and reads the device.
    /// - Parameter tracker: the travel leg owner. Omitted where a caller has no
    ///   engineer context — an office user moving a job does not start tracking
    ///   their own phone.
    /// - Returns: what became of the capture, so the caller can say so plainly
    ///   instead of quietly recording nothing.
    @discardableResult
    static func advance(
        gateway: DataGateway,
        location: LocationService,
        session: TenantSession,
        jobID: String,
        to status: JobStatus,
        destination: Coordinate?,
        tracker: TravelTracker? = nil
    ) async throws -> LocationCaptureOutcome {
        var fix: LocationFix?
        var outcome: LocationCaptureOutcome = .notRequired

        if let event = LocationCaptureEvent.forTransition(to: status) {
            // Ask at the moment the answer is first needed, rather than
            // ambushing someone with a permission prompt at launch.
            var state = await location.authorizationState
            if state == .notDetermined {
                state = await location.requestAuthorization()
            }

            if state.canCapture {
                fix = await location.captureFix(for: event, near: destination)
                outcome = fix.map { .captured(simulated: $0.simulated) } ?? .unavailable
            } else {
                // No permission means no position. It never means a made-up one.
                outcome = .permissionRefused(state)
            }
        }

        try await gateway.updateJobStatus(
            session: session,
            jobID: jobID,
            to: status,
            locationFix: fix
        )

        // Only after the status is actually persisted. Starting to follow
        // someone because of a transition the database rejected would be
        // tracking a journey that, as far as the office is concerned, never
        // began.
        if let tracker {
            await tracker.sync(
                jobID: jobID,
                status: status,
                location: location,
                gateway: gateway,
                session: session
            )
        }

        return outcome
    }
}
