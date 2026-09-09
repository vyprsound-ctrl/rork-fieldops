import Foundation

nonisolated struct Coordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// A position fix, whatever produced it.
///
/// `simulated` travels with the reading itself rather than being inferred from
/// which build is running, so a fixture can never be presented as a real fix.
nonisolated struct LocationFix: Hashable, Sendable {
    let coordinate: Coordinate
    let accuracyMeters: Double
    /// Degrees from true north. Absent when the device isn't moving.
    let heading: Double?
    let speedMetersPerSecond: Double?
    let capturedAt: Date
    let simulated: Bool
}

/// The workflow moments at which a position is worth recording.
///
/// **Location policy.** A fix is always taken at these three events. Between
/// *travel started* and *arrived* — and only between those two — the production
/// adapter additionally follows the vehicle so the office can watch an engineer
/// approach. Outside that leg there is no timer, no stream and no background
/// updates of any kind: the tracking is bounded by the job's own status, not by
/// the working day.
nonisolated enum LocationCaptureEvent: String, CaseIterable, Sendable, Identifiable {
    case travelStarted
    case arrived
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .travelStarted: return "Travel started"
        case .arrived: return "Arrived on site"
        case .completed: return "Work completed"
        }
    }

    /// The workflow transition this event corresponds to. Anything not listed
    /// here captures nothing at all.
    static func forTransition(to status: JobStatus) -> LocationCaptureEvent? {
        switch status {
        case .travelling: return .travelStarted
        case .arrived: return .arrived
        case .completed: return .completed
        default: return nil
        }
    }
}

/// Whether an active travel leg is being followed, and why not when it isn't.
///
/// This is deliberately a *state*, not a boolean: "not tracking" and "tracking
/// is impossible because the worker only granted while-in-use" are different
/// answers, and the office is shown which one applies rather than an empty map.
nonisolated enum TravelTrackingState: Hashable, Sendable {
    /// No travel leg is in progress. The radio is idle.
    case off
    /// Following the vehicle for exactly this job.
    case tracking(jobID: String, background: Bool)
    /// A leg is in progress but the device will not report — permission,
    /// hardware or policy. The job still advances; the map simply says so.
    case unavailable(LocationAuthorizationState)

    var isTracking: Bool {
        if case .tracking = self { return true }
        return false
    }

    var jobID: String? {
        if case .tracking(let jobID, _) = self { return jobID }
        return nil
    }

    /// True when updates will keep arriving with the phone locked or the app
    /// in the background. False means foreground-only, which is honest to say.
    var continuesInBackground: Bool {
        if case .tracking(_, let background) = self { return background }
        return false
    }

    var title: String {
        switch self {
        case .off: return "Not travelling"
        case .tracking(_, let background): return background ? "Sharing location" : "Sharing while app is open"
        case .unavailable: return "Location unavailable"
        }
    }
}

/// Whether the worker has granted the *always* authorisation that lets updates
/// continue with the phone locked.
///
/// Separate from `LocationAuthorizationState` because the answers are different
/// questions: one asks whether a position can be read at all, this one asks
/// whether it can be read while the app is not on screen.
nonisolated enum LocationBackgroundState: String, Sendable, Hashable {
    /// While-in-use only. Travel updates stop when the app leaves the screen.
    case foregroundOnly
    /// Always. Updates continue with the phone locked, while a leg is active.
    case granted
    /// No location permission at all, so the question does not arise.
    case noLocationPermission

    var title: String {
        switch self {
        case .foregroundOnly: return "While using the app"
        case .granted: return "Always, while travelling"
        case .noLocationPermission: return "Not allowed"
        }
    }

    /// What the worker needs to know, in their terms.
    var explanation: String {
        switch self {
        case .granted:
            return "Your position is shared while you are travelling to a job, including when your phone is locked. It stops the moment you mark yourself arrived."
        case .foregroundOnly:
            return "Your position is shared while you are travelling and this screen is open. Lock your phone and the office stops seeing you move until you open the app again. Allow \"Always\" in Settings to keep it running with the phone locked."
        case .noLocationPermission:
            return "Location is off for this app, so the office cannot see your progress. Your job steps are still recorded."
        }
    }
}

/// How much movement, and how much time, is worth another stored ping.
///
/// Tuned for battery rather than for a perfect trace: an engineer driving
/// across a city produces a readable line, and one stuck at a light produces
/// nothing at all.
nonisolated enum TravelTrackingPolicy {
    /// Core Location will not report movement smaller than this, in metres.
    static let distanceFilterMeters: Double = 120
    /// Nor will a ping be written more often than this, in seconds, however
    /// far the vehicle has moved.
    static let minimumWriteInterval: TimeInterval = 60
    /// A leg longer than this stops tracking on its own. A forgotten "start
    /// travel" must not follow somebody home.
    static let maximumLegDuration: TimeInterval = 4 * 60 * 60

    static var summary: String {
        "Between start travel and arrival only · at most one point per \(Int(minimumWriteInterval))s · \(Int(distanceFilterMeters))m of movement required · stops automatically after \(Int(maximumLegDuration / 3600))h"
    }
}

/// How long position history is kept, and how much of it.
///
/// Retention is bounded by policy rather than by whatever the database happens
/// to accumulate: pings are operational evidence for a job, not a movement
/// archive. The gateway trims to these limits as it writes.
nonisolated enum LocationRetentionPolicy {
    /// Days of history kept per company.
    static let days: Int = 30
    /// Hard cap on stored pings per field worker, whichever bites first.
    static let maximumPingsPerWorker: Int = 200
    /// A fix older than this is "last known" rather than "recent".
    static let recentThresholdMinutes: Int = 15

    static var summary: String {
        "Captured at job workflow events only · kept \(days) days · max \(maximumPingsPerWorker) points per worker · never continuous"
    }
}

/// Whether this device will give us a position, and why not when it won't.
///
/// Kept separate from `CLAuthorizationStatus` so the rest of the app never
/// imports Core Location, and so the simulated adapter can answer the same
/// question without one.
nonisolated enum LocationAuthorizationState: String, Sendable, Hashable {
    /// Never asked. The prompt has not been shown yet.
    case notDetermined
    case authorized
    /// The person said no, or turned it off later.
    case denied
    /// Blocked by device policy — parental controls or an MDM profile. The
    /// person cannot grant it themselves, so "open Settings" is not the answer.
    case restricted
    /// Location services are off device-wide, or there is no hardware.
    case unavailable

    /// Whether asking for a fix could actually produce one.
    var canCapture: Bool { self == .authorized }

    /// Whether the person can fix this themselves in Settings.
    var isResolvableInSettings: Bool { self == .denied || self == .unavailable }

    var title: String {
        switch self {
        case .notDetermined: return "Not asked yet"
        case .authorized: return "Allowed"
        case .denied: return "Not allowed"
        case .restricted: return "Restricted"
        case .unavailable: return "Unavailable"
        }
    }

    /// What to tell the worker, in their terms, when a capture could not happen.
    func explanation(worker: String) -> String {
        switch self {
        case .notDetermined:
            return "Your position is recorded when you start travel, arrive and finish a job, so the office can see progress without calling you."
        case .authorized:
            return "Your position is recorded at those three moments and at no other time."
        case .denied:
            return "Location is off for this app, so your job steps are being recorded without a position. You can turn it back on in Settings."
        case .restricted:
            return "Location is blocked by a restriction on this device, so your job steps are being recorded without a position. A device administrator controls this."
        case .unavailable:
            return "Location services are switched off on this device, so your job steps are being recorded without a position."
        }
    }
}

/// What happened to the position capture on a workflow transition.
///
/// The job always moves. This says whether a position rode along with it, so
/// the screen can be honest instead of silently recording nothing.
nonisolated enum LocationCaptureOutcome: Hashable, Sendable {
    /// This transition is not a capture point — the common case.
    case notRequired
    case captured(simulated: Bool)
    /// Permission was refused, so nothing was recorded. Never a fake position.
    case permissionRefused(LocationAuthorizationState)
    /// Permitted, but the device could not produce a fix in time.
    case unavailable

    var didCapture: Bool {
        if case .captured = self { return true }
        return false
    }

    /// The state to explain to the worker, when there is something to explain.
    var refusedState: LocationAuthorizationState? {
        if case .permissionRefused(let state) = self { return state }
        return nil
    }
}

/// Field worker positioning.
///
/// Two distinct capabilities, kept apart on purpose:
///
/// 1. **Event capture** — one fix, taken because a person tapped a button that
///    moved a job forward. Always available.
/// 2. **Travel tracking** — a bounded stream, running only between *start
///    travel* and *arrived*. Opt-in per adapter, and impossible to start
///    without a job id, which is what keeps it tied to a real leg of work.
///
/// An adapter produces `LocationFix` values and nothing else. Persistence,
/// tenancy and retention belong to the gateway, which is why no implementation
/// of this protocol knows the database exists.
protocol LocationService: Sendable {
    var mode: ServiceMode { get }
    /// Whether this adapter can follow a worker during an active travel leg.
    /// False means event capture only — surfaced so the UI can say which.
    var performsBackgroundTracking: Bool { get }

    /// Current permission, without prompting.
    var authorizationState: LocationAuthorizationState { get async }

    /// Whether updates would survive the app leaving the screen.
    var backgroundAuthorizationState: LocationBackgroundState { get async }

    /// Shows the system prompt if it has never been shown, and reports where
    /// things stand afterwards. Safe to call repeatedly.
    func requestAuthorization() async -> LocationAuthorizationState

    /// Asks to upgrade while-in-use to always. iOS shows this at most once, and
    /// only after while-in-use has already been granted.
    func requestBackgroundAuthorization() async -> LocationBackgroundState

    /// A one-shot fix taken because a workflow event just happened.
    func captureFix(for event: LocationCaptureEvent, near destination: Coordinate?) async -> LocationFix?
    func currentLocation() async -> Coordinate?

    /// Begins following one travel leg. The handler receives every fix that
    /// clears `TravelTrackingPolicy`; the caller decides what to store.
    ///
    /// Starting a second leg replaces the first — there is no way to track two
    /// jobs, or two workers, at once.
    func startTravelTracking(
        jobID: String,
        onFix: @escaping @Sendable (LocationFix) -> Void
    ) async -> TravelTrackingState

    /// Ends the leg and powers the radio down. Safe to call when not tracking.
    func stopTravelTracking() async
}

extension LocationService {
    /// Simulated adapters need no permission and must never prompt, so they
    /// inherit an "already allowed" answer and are left otherwise untouched.
    var authorizationState: LocationAuthorizationState { get async { .authorized } }

    func requestAuthorization() async -> LocationAuthorizationState { .authorized }

    /// An adapter that does not track cannot be running in the background, and
    /// says so rather than implying a permission it never asked for.
    var backgroundAuthorizationState: LocationBackgroundState { get async { .foregroundOnly } }

    func requestBackgroundAuthorization() async -> LocationBackgroundState {
        await backgroundAuthorizationState
    }

    /// Default: this adapter does not follow anyone. Reporting `.off` rather
    /// than a fake `.tracking` is what stops a non-tracking stack from drawing
    /// a live badge it cannot back up.
    func startTravelTracking(
        jobID: String,
        onFix: @escaping @Sendable (LocationFix) -> Void
    ) async -> TravelTrackingState {
        .off
    }

    func stopTravelTracking() async {}
}

/// DEVELOPMENT IMPLEMENTATION — deterministic fixtures, no Core Location, no
/// authorisation prompt and no background updates. Every fix it returns is
/// marked `simulated` so nothing downstream can mistake it for a real position.
struct MockLocationService: LocationService {
    let mode: ServiceMode = .simulated
    let performsBackgroundTracking: Bool = false

    /// Roughly central Tampa, matching the seeded company's operating area.
    private static let base = Coordinate(latitude: 27.9772, longitude: -82.4680)

    func currentLocation() async -> Coordinate? { Self.base }

    func captureFix(for event: LocationCaptureEvent, near destination: Coordinate?) async -> LocationFix? {
        // The fixture is positioned to make the reading plausible for the event:
        // setting off is away from site, arriving and finishing are at it.
        let coordinate: Coordinate
        let speed: Double?
        let heading: Double?

        switch event {
        case .travelStarted:
            coordinate = Self.base
            speed = 11.2
            heading = 74
        case .arrived, .completed:
            coordinate = destination ?? Self.base
            speed = 0
            heading = nil
        }

        return LocationFix(
            coordinate: coordinate,
            accuracyMeters: event == .travelStarted ? 12 : 8,
            heading: heading,
            speedMetersPerSecond: speed,
            capturedAt: Date(),
            simulated: true
        )
    }
}
