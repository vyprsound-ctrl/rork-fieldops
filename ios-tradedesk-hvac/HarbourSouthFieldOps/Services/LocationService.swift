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
/// **Location policy.** This platform does not follow field workers around. A
/// fix is taken at these events and at no other time: there is no timer, no
/// background tracking and no continuous stream. Each case exists because the
/// business genuinely needs the answer — when did they set off, when did they
/// get there, where were they when they said the work was done.
///
/// Production background tracking, if it is ever enabled, will be an explicit
/// opt-in tied to a production provider, not a side effect of this enum.
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
/// The protocol deliberately exposes *event-driven* capture only — there is no
/// `startTracking()`, no delegate stream and no timer — so background tracking
/// cannot be switched on without a deliberate change to this contract.
///
/// An adapter produces a `LocationFix` and nothing else. Persistence, tenancy
/// and retention belong to the gateway, which is why no implementation of this
/// protocol knows the database exists.
protocol LocationService: Sendable {
    var mode: ServiceMode { get }
    /// Whether this adapter follows the worker continuously. Always false;
    /// surfaced so the UI can state the policy honestly.
    var performsBackgroundTracking: Bool { get }

    /// Current permission, without prompting.
    var authorizationState: LocationAuthorizationState { get async }

    /// Shows the system prompt if it has never been shown, and reports where
    /// things stand afterwards. Safe to call repeatedly.
    func requestAuthorization() async -> LocationAuthorizationState

    /// A one-shot fix taken because a workflow event just happened.
    func captureFix(for event: LocationCaptureEvent, near destination: Coordinate?) async -> LocationFix?
    func currentLocation() async -> Coordinate?
}

extension LocationService {
    /// Simulated adapters need no permission and must never prompt, so they
    /// inherit an "already allowed" answer and are left otherwise untouched.
    var authorizationState: LocationAuthorizationState { get async { .authorized } }

    func requestAuthorization() async -> LocationAuthorizationState { .authorized }
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
