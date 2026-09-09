import Foundation
import MapKit

/// PRODUCTION IMPLEMENTATION — travel time from Apple's own routing engine.
///
/// `MKDirections.calculateETA` is a real network call to Apple Maps. It follows
/// roads, respects one-way systems and — because `departureDate` is now —
/// accounts for current traffic where Apple has it. No API key, no account and
/// no server-side dependency: the entitlement to use it comes with the platform.
///
/// **What happens when it fails.** A routing request can fail for honest
/// reasons: no network in a plant room, a destination Apple cannot route to, or
/// a rate limit. When it does, this falls back to straight-line distance and
/// marks the result `simulated: true`. The flag rides on the estimate, so the
/// screen showing it says "estimated" rather than presenting a guess as a
/// routed arrival time. It never returns a routed-looking estimate it did not
/// route.
struct MapKitRouteService: RouteService {
    let mode: ServiceMode = .production
    let providerName: String = "Apple Maps"

    /// Apple's routing occasionally takes its time. A worker staring at a
    /// spinner is worse than an honest straight-line estimate, so the request
    /// is abandoned after this long.
    private static let timeout: Duration = .seconds(8)

    func estimate(from origin: Coordinate, to destination: Coordinate) async -> RouteEstimate {
        if let routed = await routedEstimate(from: origin, to: destination) {
            return routed
        }
        // Routing was not available. The estimate is still useful, and it is
        // labelled for what it is.
        return await MockRouteService().estimate(from: origin, to: destination)
    }

    /// A real route, or nil when Apple could not provide one.
    private func routedEstimate(from origin: Coordinate, to destination: Coordinate) async -> RouteEstimate? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.clCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.clCoordinate))
        request.transportType = .automobile
        // "Now", which is what makes the traffic figure meaningful.
        request.departureDate = Date()

        let directions = MKDirections(request: request)

        return await withTaskGroup(of: RouteEstimate?.self) { group in
            group.addTask {
                do {
                    let response = try await directions.calculateETA()
                    return RouteEstimate(
                        distanceMeters: response.distance,
                        durationSeconds: response.expectedTravelTime,
                        arrivalTime: response.expectedArrivalDate,
                        routeSummary: nil,
                        // Apple applies traffic to an automobile ETA departing
                        // now. Stated rather than assumed.
                        usesLiveTraffic: true,
                        simulated: false
                    )
                } catch {
                    // Not an app failure — a routing failure. The caller falls
                    // back and the user is told the estimate is approximate.
                    print("[routing] Apple Maps could not route this leg: \(error.localizedDescription)")
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: Self.timeout)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            directions.cancel()
            return first
        }
    }
}

/// PRODUCTION IMPLEMENTATION — hands a destination to Apple Maps.
///
/// This app deliberately does not implement turn-by-turn navigation. It draws
/// the route on an in-app map so the worker can see where they are going, and
/// when they want guidance it opens Apple Maps, which already does that job
/// properly. `behaviourNote` says exactly that before the worker leaves.
struct MapKitMapService: MapService {
    let mode: ServiceMode = .production
    let providerName: String = "Apple Maps"

    func prepareNavigation(to destination: Coordinate, label: String, addressLine: String?) -> NavigationHandoff {
        var components = URLComponents(string: "http://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(destination.latitude),\(destination.longitude)"),
            URLQueryItem(name: "q", value: label),
            // Driving directions, which is what a van needs.
            URLQueryItem(name: "dirflg", value: "d")
        ]

        return NavigationHandoff(
            destination: destination,
            label: label,
            addressLine: addressLine,
            url: components?.url,
            simulated: false,
            behaviourNote: "Opens Apple Maps with driving directions to this site. Harbour South does not give turn-by-turn guidance itself."
        )
    }
}

extension Coordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Whether this is a usable position rather than the null island a missing
    /// latitude/longitude pair decodes to.
    var isPlottable: Bool {
        CLLocationCoordinate2DIsValid(clCoordinate) && !(latitude == 0 && longitude == 0)
    }
}
