import CoreLocation
import Foundation

/// PRODUCTION IMPLEMENTATION — real positions from Core Location.
///
/// **This adapter never starts continuous updates.** Every reading comes from
/// `requestLocation()`, which Core Location answers with a single fix and then
/// stops. There is no `startUpdatingLocation`, no significant-change monitoring,
/// no region monitoring, no heading stream and no timer anywhere in this file.
/// Background location is not requested and the app declares no location
/// background mode, so iOS itself would refuse to deliver updates while
/// suspended even if this class asked for them.
///
/// It also knows nothing about the database. It produces a `LocationFix` and
/// hands it back; `FieldTransitionCoordinator` decides whether to ask for one
/// and the `DataGateway` decides how to store it under the tenant's RLS rules.
/// That separation is what keeps this testable and the security model in one
/// place.
@MainActor
final class CoreLocationService: NSObject, LocationService {
    let mode: ServiceMode = .production

    /// Core Location is perfectly capable of following someone around. This
    /// adapter deliberately does not, and says so.
    let performsBackgroundTracking: Bool = false

    private let manager: CLLocationManager

    /// A one-shot read is abandoned after this long so a workflow transition
    /// can never hang behind a fix that is not coming — indoors, in a lift, or
    /// with no sky in view.
    private static let fixTimeout: Duration = .seconds(10)

    /// The prompt is modal, but a backgrounded app can leave it unanswered.
    /// Rather than suspend the caller forever, give up and report where things
    /// stand.
    private static let promptTimeout: Duration = .seconds(45)

    /// A fix this fresh is reused instead of waking the GPS again.
    private static let reuseWindow: TimeInterval = 120

    private var fixWaiters: [CheckedContinuation<CLLocation?, Never>] = []
    private var authorizationWaiters: [CheckedContinuation<LocationAuthorizationState, Never>] = []
    private var isAwaitingFix: Bool = false
    private var requestGeneration: Int = 0
    private var lastLocation: CLLocation?

    /// Set when the system reports a refusal while the app itself is
    /// authorised, which is how "location services are off device-wide" arrives.
    /// Checking `locationServicesEnabled()` directly would block the main actor.
    private var servicesReportedOff: Bool = false

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        // Ten metres is ample for "were they at the site": it is a job record,
        // not a navigation trace, and asking for best-possible accuracy would
        // cost battery for precision nobody uses.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        // No distanceFilter, no allowsBackgroundLocationUpdates and no
        // pausesLocationUpdatesAutomatically: all three only matter for
        // continuous updates, which this adapter never starts.
    }

    // MARK: - Authorisation

    var authorizationState: LocationAuthorizationState {
        get async { currentState }
    }

    private var currentState: LocationAuthorizationState {
        switch manager.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .authorizedWhenInUse, .authorizedAlways:
            // Authorised for the app, but the device-wide switch may still be
            // off — the system tells us that by refusing the request.
            return servicesReportedOff ? .unavailable : .authorized
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> LocationAuthorizationState {
        // Only ever prompt once. Afterwards the answer lives in Settings, and
        // asking again does nothing but waste the caller's time.
        guard manager.authorizationStatus == .notDetermined else { return currentState }

        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)

            guard authorizationWaiters.count == 1 else { return }

            // When in use only. This app has no reason to know where anyone is
            // while they are not using it.
            manager.requestWhenInUseAuthorization()

            Task { [weak self] in
                try? await Task.sleep(for: Self.promptTimeout)
                self?.deliverAuthorization()
            }
        }
    }

    private func deliverAuthorization() {
        guard !authorizationWaiters.isEmpty else { return }
        let waiters = authorizationWaiters
        authorizationWaiters = []
        let state = currentState
        for waiter in waiters { waiter.resume(returning: state) }
    }

    // MARK: - Capture

    func captureFix(for event: LocationCaptureEvent, near destination: Coordinate?) async -> LocationFix? {
        // `destination` is deliberately ignored. It exists so the simulated
        // adapter can produce a plausible fixture; a real device reports where
        // it actually is, and nudging that toward the expected answer would be
        // fabricating a position.
        _ = destination

        guard currentState.canCapture else { return nil }
        guard let location = await requestOneShotFix() else { return nil }
        return Self.fix(from: location)
    }

    func currentLocation() async -> Coordinate? {
        guard currentState.canCapture else { return nil }

        // Reuse a recent reading rather than waking the GPS for an ETA refresh.
        if let last = lastLocation, Date().timeIntervalSince(last.timestamp) < Self.reuseWindow {
            return Coordinate(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        }
        guard let location = await requestOneShotFix() else { return nil }
        return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    /// One reading, then silence. Concurrent callers share a single request
    /// instead of stacking up radio work.
    private func requestOneShotFix() async -> CLLocation? {
        await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)

            guard !isAwaitingFix else { return }
            isAwaitingFix = true
            requestGeneration &+= 1
            let generation = requestGeneration

            manager.requestLocation()

            Task { [weak self] in
                try? await Task.sleep(for: Self.fixTimeout)
                self?.abandonFix(generation: generation)
            }
        }
    }

    private func abandonFix(generation: Int) {
        guard isAwaitingFix, generation == requestGeneration else { return }
        deliverFix(nil)
    }

    private func deliverFix(_ location: CLLocation?) {
        guard isAwaitingFix else { return }
        isAwaitingFix = false
        if let location { lastLocation = location }

        let waiters = fixWaiters
        fixWaiters = []
        for waiter in waiters { waiter.resume(returning: location) }
    }

    /// Translates a Core Location reading into the app's own fix.
    ///
    /// `course` and `speed` are only meaningful when Core Location says so —
    /// both come back negative when unknown, and passing that straight through
    /// would record a worker travelling at minus one metre per second.
    private static func fix(from location: CLLocation) -> LocationFix {
        LocationFix(
            coordinate: Coordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ),
            accuracyMeters: location.horizontalAccuracy,
            heading: location.course >= 0 ? location.course : nil,
            speedMetersPerSecond: location.speed >= 0 ? location.speed : nil,
            capturedAt: location.timestamp,
            // The whole point: a real reading is never marked simulated, and a
            // failure produces no reading at all rather than a plausible one.
            simulated: false
        )
    }
}

// MARK: - CLLocationManagerDelegate

extension CoreLocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let newest = locations.last
        Task { @MainActor [weak self] in
            self?.servicesReportedOff = false
            self?.deliverFix(newest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let isRefusal = (error as? CLError)?.code == .denied
        Task { @MainActor [weak self] in
            guard let self else { return }
            // A refusal while the app is authorised means the device-wide
            // switch is off. Recorded so the UI can say the right thing.
            if isRefusal { self.servicesReportedOff = true }
            // No fix, so no position. The transition still goes through.
            self.deliverFix(nil)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.manager.authorizationStatus != .denied { self.servicesReportedOff = false }
            self.deliverAuthorization()
        }
    }
}
