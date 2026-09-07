import Foundation

/// What a routing provider returns for one origin/destination pair.
///
/// Shaped for a real provider — distance, duration, arrival time and an optional
/// route summary are exactly what MapKit, Google Directions and Mapbox all
/// return — so swapping the mock for production is an adapter change, not a
/// model change.
///
/// `simulated` is part of the estimate itself. Anything displaying an ETA can
/// therefore label it honestly without knowing which adapter produced it.
nonisolated struct RouteEstimate: Hashable, Sendable {
    let distanceMeters: Double
    let durationSeconds: Double
    let arrivalTime: Date
    /// Provider-supplied summary, e.g. "I-275 N". Nil when unavailable.
    let routeSummary: String?
    /// Where traffic was taken into account. Always false while simulated.
    let usesLiveTraffic: Bool
    let simulated: Bool

    var minutesAway: Int { max(Int((durationSeconds / 60).rounded()), 1) }

    /// Distance in the units the company's country would expect. Miles for the
    /// US, kilometres elsewhere — read from configuration, never assumed.
    func distanceLabel(countryCode: String) -> String {
        let usesMiles = ["US", "GB", "LR", "MM"].contains(countryCode.uppercased())
        if usesMiles {
            let miles = distanceMeters / 1609.344
            return miles < 0.2
                ? "\(Int((distanceMeters / 0.9144).rounded())) yd"
                : String(format: "%.1f mi", miles)
        }
        let km = distanceMeters / 1000
        return km < 0.5
            ? "\(Int(distanceMeters.rounded())) m"
            : String(format: "%.1f km", km)
    }

    var durationLabel: String { Formatters.relativeDuration(minutes: minutesAway) }

    var arrivalLabel: String { Formatters.time(arrivalTime) }
}

/// Travel time and distance between two points.
///
/// Deliberately separate from `LocationService`: knowing where someone is and
/// working out how long they'll take are different providers in production
/// (Core Location vs MapKit Directions), and separating them now means neither
/// has to be rewritten when the other is connected.
protocol RouteService: Sendable {
    var mode: ServiceMode { get }
    /// The provider this adapter stands in for, shown in Settings.
    var providerName: String { get }

    func estimate(from origin: Coordinate, to destination: Coordinate) async -> RouteEstimate
}

/// DEVELOPMENT IMPLEMENTATION.
///
/// Straight-line distance and a flat assumed speed. It contacts no routing
/// service, knows nothing about roads and accounts for no traffic. Every
/// estimate is flagged `simulated` so it is always presented as an illustration
/// rather than a real arrival time.
struct MockRouteService: RouteService {
    let mode: ServiceMode = .simulated
    let providerName: String = "MapKit Directions"

    /// Assumed average including junctions — a stand-in for real routing, not a
    /// model of it.
    private static let assumedMetresPerSecond: Double = 11.0

    func estimate(from origin: Coordinate, to destination: Coordinate) async -> RouteEstimate {
        let metres = Self.haversineMetres(origin, destination)
        // Roads are never straight: a rough multiplier keeps the fixture from
        // looking implausibly fast without pretending to be a route.
        let travelMetres = metres * 1.3
        let seconds = max(travelMetres / Self.assumedMetresPerSecond, 120)

        return RouteEstimate(
            distanceMeters: travelMetres,
            durationSeconds: seconds,
            arrivalTime: Date().addingTimeInterval(seconds),
            routeSummary: nil,
            usesLiveTraffic: false,
            simulated: true
        )
    }

    /// Great-circle distance in metres.
    private static func haversineMetres(_ a: Coordinate, _ b: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLat = (b.latitude - a.latitude) * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180

        let h = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(1 - h))
    }
}

/// Everything needed to hand a destination to a maps application.
///
/// The app builds this and passes it on. It does not draw a route, does not
/// speak directions and does not track progress — turn-by-turn belongs to the
/// maps app, and this platform is not implementing one.
nonisolated struct NavigationHandoff: Identifiable, Hashable, Sendable {
    var id: String { "\(destination.latitude),\(destination.longitude)|\(label)" }
    let destination: Coordinate
    let label: String
    /// Street address, so the maps app can show something human.
    let addressLine: String?
    let url: URL?
    /// True while the hand-off is prepared by a simulated adapter.
    let simulated: Bool
    /// Plain-language statement of what will actually happen, shown to the user
    /// before they leave the app.
    let behaviourNote: String

    var canOpen: Bool { url != nil }
}

/// Map presentation and navigation hand-off.
protocol MapService: Sendable {
    var mode: ServiceMode { get }
    var providerName: String { get }

    /// Prepares a destination for hand-off. Returns the payload rather than
    /// opening anything, so the caller decides and the data layer stays
    /// testable.
    func prepareNavigation(to destination: Coordinate, label: String, addressLine: String?) -> NavigationHandoff
}

/// DEVELOPMENT IMPLEMENTATION.
///
/// Builds an Apple Maps URL and stops there. There is no in-app map, no route
/// line, no live traffic and no turn-by-turn guidance — opening the URL hands
/// the destination to whichever maps app the device has. A production adapter
/// replaces this without any caller changing.
struct MockMapService: MapService {
    let mode: ServiceMode = .simulated
    let providerName: String = "MapKit"

    func prepareNavigation(to destination: Coordinate, label: String, addressLine: String?) -> NavigationHandoff {
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "q", value: label)
        ]

        return NavigationHandoff(
            destination: destination,
            label: label,
            addressLine: addressLine,
            url: components?.url,
            simulated: true,
            behaviourNote: "Hands the destination to your maps app. This build has no in-app routing or turn-by-turn guidance."
        )
    }
}
