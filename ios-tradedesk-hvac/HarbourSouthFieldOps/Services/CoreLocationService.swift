import CoreLocation
import Foundation

/// PRODUCTION IMPLEMENTATION — real positions from Core Location.
///
/// **Two modes, and only two.**
///
/// 1. *One-shot capture.* `requestLocation()` answers with a single fix and
///    stops. This is what a workflow transition uses.
/// 2. *Travel tracking.* `startUpdatingLocation()` runs for exactly one leg —
///    started when an engineer taps Start Travel, stopped when they arrive,
///    when the job ends, or automatically after `maximumLegDuration`. There is
///    no other caller and no timer that starts it.
///
/// Background delivery is enabled only for the duration of that leg, and only
/// when the worker has granted *always* authorisation. `allowsBackgroundLocation
/// Updates` is switched back off the moment the leg ends, so a suspended app
/// holds no location assertion.
///
/// It knows nothing about the database. It produces `LocationFix` values and
/// hands them back; `FieldTransitionCoordinator` decides when to ask, and the
/// `DataGateway` decides how to store them under the tenant's RLS rules.
@MainActor
final class CoreLocationService: NSObject, LocationService {
    let mode: ServiceMode = .production

    /// This adapter can follow a worker, but only across an active travel leg.
    let performsBackgroundTracking: Bool = true

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

    // MARK: Travel leg state

    /// The job currently being travelled to. Non-nil exactly while updating.
    private var trackedJobID: String?
    private var trackingHandler: (@Sendable (LocationFix) -> Void)?
    private var lastTrackedWrite: Date?
    /// Cancels the automatic stop when a leg ends normally.
    private var legExpiryTask: Task<Void, Never>?

    /// True only when the bundle actually declares the location background
    /// mode. Setting `allowsBackgroundLocationUpdates` without it is a hard
    /// crash, so this is checked rather than assumed.
    private static let bundleAllowsBackgroundLocation: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }()

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
        // Deliberately left at their defaults here. `distanceFilter`,
        // `allowsBackgroundLocationUpdates` and `activityType` are configured
        // when a travel leg starts and unwound when it ends, so an idle app
        // holds no continuous-update configuration at all.
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

    var backgroundAuthorizationState: LocationBackgroundState {
        get async {
            switch manager.authorizationStatus {
            case .authorizedAlways:
                // Always is only useful if the app may actually run in the
                // background. Without the background mode it is foreground-only
                // in practice, and saying otherwise would overpromise.
                return Self.bundleAllowsBackgroundLocation ? .granted : .foregroundOnly
            case .authorizedWhenInUse:
                return .foregroundOnly
            default:
                return .noLocationPermission
            }
        }
    }

    /// Asks to upgrade while-in-use to always.
    ///
    /// iOS shows this prompt at most once per install and only after
    /// while-in-use exists, so this is a request rather than a guarantee. The
    /// answer is read back afterwards rather than assumed.
    func requestBackgroundAuthorization() async -> LocationBackgroundState {
        guard manager.authorizationStatus == .authorizedWhenInUse else {
            return await backgroundAuthorizationState
        }

        return await withCheckedContinuation { continuation in
            authorizationWaiters.append(continuation)
            if authorizationWaiters.count == 1 {
                manager.requestAlwaysAuthorization()
                Task { [weak self] in
                    try? await Task.sleep(for: Self.promptTimeout)
                    self?.deliverAuthorization()
                }
            }
        }.asBackgroundState(bundleAllowsBackground: Self.bundleAllowsBackgroundLocation, status: manager.authorizationStatus)
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

    // MARK: - Travel leg

    /// Starts following one leg.
    ///
    /// Background delivery is switched on only when *always* has been granted
    /// **and** the bundle declares the location background mode. With only
    /// while-in-use the leg still runs, but iOS suspends it when the app leaves
    /// the screen — which is reported back as `background: false` rather than
    /// being papered over.
    func startTravelTracking(
        jobID: String,
        onFix: @escaping @Sendable (LocationFix) -> Void
    ) async -> TravelTrackingState {
        var state = currentState
        if state == .notDetermined { state = await requestAuthorization() }
        guard state.canCapture else {
            await stopTravelTracking()
            return .unavailable(state)
        }

        // Replacing a leg rather than stacking one on top of another.
        legExpiryTask?.cancel()

        trackedJobID = jobID
        trackingHandler = onFix
        lastTrackedWrite = nil

        let background = await backgroundAuthorizationState == .granted
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = TravelTrackingPolicy.distanceFilterMeters
        manager.activityType = .automotiveNavigation
        // iOS may pause updates when the device stops moving for a long time.
        // That is exactly the behaviour we want for a van parked on site.
        manager.pausesLocationUpdatesAutomatically = true
        if Self.bundleAllowsBackgroundLocation {
            manager.allowsBackgroundLocationUpdates = background
            // The blue bar is not optional here: a worker must be able to see
            // that the app is reading their position.
            manager.showsBackgroundLocationIndicator = background
        }
        manager.startUpdatingLocation()

        // A leg nobody closed must not follow someone home. This is the
        // backstop for a forgotten "Start travel".
        legExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(TravelTrackingPolicy.maximumLegDuration))
            guard !Task.isCancelled else { return }
            await self?.stopTravelTracking()
        }

        return .tracking(jobID: jobID, background: background)
    }

    func stopTravelTracking() async {
        legExpiryTask?.cancel()
        legExpiryTask = nil
        guard trackedJobID != nil else { return }

        trackedJobID = nil
        trackingHandler = nil
        lastTrackedWrite = nil

        manager.stopUpdatingLocation()
        if Self.bundleAllowsBackgroundLocation {
            // Released immediately. A suspended app must not hold a location
            // assertion just because a leg happened earlier in the day.
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
        }
        manager.distanceFilter = kCLDistanceFilterNone
    }

    /// Applies the write policy to a tracked reading.
    ///
    /// Core Location's `distanceFilter` already limits movement; this adds the
    /// time floor, so a vehicle crawling through traffic cannot produce a ping
    /// every few seconds.
    private func forwardTrackedFix(_ location: CLLocation) {
        guard trackedJobID != nil, let handler = trackingHandler else { return }

        // A stale cached reading delivered on start-up is not evidence of
        // movement now.
        guard abs(location.timestamp.timeIntervalSinceNow) < 120 else { return }
        // Core Location reports −1 for an invalid fix.
        guard location.horizontalAccuracy >= 0 else { return }

        if let last = lastTrackedWrite,
           Date().timeIntervalSince(last) < TravelTrackingPolicy.minimumWriteInterval {
            return
        }
        lastTrackedWrite = Date()
        handler(Self.fix(from: location))
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
            guard let self else { return }
            self.servicesReportedOff = false
            // A tracked leg and a one-shot request can be in flight at the same
            // time — the same reading legitimately serves both.
            if let newest { self.forwardTrackedFix(newest) }
            self.deliverFix(newest)
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
            // Permission revoked mid-leg: stop rather than keep a dead
            // subscription open and a background assertion held.
            if !self.currentState.canCapture, self.trackedJobID != nil {
                await self.stopTravelTracking()
            }
            self.deliverAuthorization()
        }
    }
}

private extension LocationAuthorizationState {
    /// Re-reads the background answer after an authorisation prompt settles.
    /// The prompt result arrives as a `LocationAuthorizationState`, but the
    /// caller asked a narrower question.
    func asBackgroundState(bundleAllowsBackground: Bool, status: CLAuthorizationStatus) -> LocationBackgroundState {
        switch status {
        case .authorizedAlways: return bundleAllowsBackground ? .granted : .foregroundOnly
        case .authorizedWhenInUse: return .foregroundOnly
        default: return .noLocationPermission
        }
    }
}
