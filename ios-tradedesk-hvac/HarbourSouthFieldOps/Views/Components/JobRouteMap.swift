import MapKit
import SwiftUI

/// The site, the engineer, and the road between them.
///
/// A real MapKit map — Apple's tiles, Apple's route line, the system's own blue
/// user dot. It is not a navigation view: there is no guidance, no re-routing
/// and no voice. It exists so a worker can see where they are going before they
/// set off, and so the office can see where somebody actually is.
///
/// The route line is drawn only when Apple returns one. When routing fails the
/// map still shows both points and simply has no line, which is honest — a
/// straight line between two pins would look like a route and be nothing of the
/// kind.
struct JobRouteMap: View {
    let destination: Coordinate
    let destinationLabel: String
    /// The engineer's position, when one is known. Nil hides the route.
    var origin: Coordinate?
    /// Whether the system's live user dot should be shown. Only true where the
    /// person looking at the map is the person being located.
    var showsUserLocation: Bool = false
    var height: CGFloat = 220

    @State private var route: MKRoute?
    @State private var position: MapCameraPosition = .automatic
    @State private var isRouting: Bool = false

    var body: some View {
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            // A site pin, not a tool. The wrench-and-screwdriver belonged to
            // the previous product identity.
            Marker(destinationLabel, systemImage: "mappin.and.ellipse", coordinate: destination.clCoordinate)
                .tint(Theme.primary)

            if showsUserLocation {
                UserAnnotation()
            } else if let origin, origin.isPlottable {
                Marker("Last reported", systemImage: "figure.walk", coordinate: origin.clCoordinate)
                    .tint(Theme.amber)
            }

            if let route {
                MapPolyline(route.polyline)
                    .stroke(Theme.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .frame(height: height)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay(alignment: .topTrailing) {
            if isRouting {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.thinMaterial, in: .rect(cornerRadius: 8))
                    .padding(8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let route {
                Text(Formatters.relativeDuration(minutes: max(Int((route.expectedTravelTime / 60).rounded()), 1)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: .capsule)
                    .padding(10)
            }
        }
        .accessibilityLabel("Map showing the route to \(destinationLabel)")
        .task(id: routeKey) { await loadRoute() }
    }

    /// Recomputes only when an endpoint actually moves, so panning the map or a
    /// list refreshing does not fire a routing request.
    private var routeKey: String {
        let originPart = origin.map { String(format: "%.3f,%.3f", $0.latitude, $0.longitude) } ?? "-"
        return "\(originPart)|\(String(format: "%.4f,%.4f", destination.latitude, destination.longitude))"
    }

    private func loadRoute() async {
        guard destination.isPlottable else { return }

        // Frame the destination immediately. The route, if it arrives, widens
        // this — but a map that shows nothing while routing is worse than one
        // that shows the site.
        position = .region(
            MKCoordinateRegion(
                center: destination.clCoordinate,
                latitudinalMeters: 1_200,
                longitudinalMeters: 1_200
            )
        )

        guard let origin, origin.isPlottable else {
            route = nil
            return
        }

        isRouting = true
        defer { isRouting = false }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.clCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.clCoordinate))
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard let best = response.routes.first else { return }
            route = best
            // Fit the whole leg with room for the pins.
            position = .rect(best.polyline.boundingMapRect.insetBy(dx: -2_000, dy: -2_000))
        } catch {
            // No line rather than a fabricated one. The pins still tell the
            // truth about where both ends are.
            route = nil
            print("[map] no route available for this leg: \(error.localizedDescription)")
        }
    }
}

/// Where the field team was last seen, on Apple's map.
///
/// Pin colour carries the one thing that matters: green for a position recent
/// enough to act on, amber for one that is merely the last thing recorded. A
/// stale pin is never drawn as if it were live, because a dispatcher deciding
/// who is nearest needs to know the difference.
struct FieldTeamMap: View {
    let locations: [FieldWorkerLocationProjection]
    var height: CGFloat = 240

    @State private var position: MapCameraPosition = .automatic

    /// Null-island rows are excluded rather than plotted off the coast of
    /// Africa, which is what an unset latitude/longitude pair looks like.
    private var plottable: [FieldWorkerLocationProjection] {
        locations.filter {
            Coordinate(latitude: $0.latitude, longitude: $0.longitude).isPlottable
        }
    }

    var body: some View {
        Group {
            if plottable.isEmpty {
                EmptyView()
            } else {
                Map(position: $position, interactionModes: [.pan, .zoom]) {
                    ForEach(plottable) { location in
                        Marker(
                            location.workerName,
                            systemImage: location.freshness == .recent ? "location.fill" : "clock.arrow.circlepath",
                            coordinate: CLLocationCoordinate2D(
                                latitude: location.latitude,
                                longitude: location.longitude
                            )
                        )
                        .tint(location.freshness == .recent ? Theme.green : Theme.amber)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: height)
                .clipShape(.rect(cornerRadius: Theme.cardRadius))
                .accessibilityLabel("Map of the last reported positions of \(plottable.count) team members")
                .task(id: plottable.map(\.id).joined()) { frame() }
            }
        }
    }

    /// Fits every pin with a margin, rather than leaving `.automatic` to guess
    /// and cut the outliers off.
    private func frame() {
        let coordinates = plottable.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard let first = coordinates.first else { return }

        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for point in coordinates {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }

        position = .region(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: (minLat + maxLat) / 2,
                    longitude: (minLon + maxLon) / 2
                ),
                span: MKCoordinateSpan(
                    // A single pin has no span at all, so a floor is applied
                    // rather than zooming to the maximum level on one worker.
                    latitudeDelta: max((maxLat - minLat) * 1.5, 0.02),
                    longitudeDelta: max((maxLon - minLon) * 1.5, 0.02)
                )
            )
        )
    }
}

/// The live badge shown while a travel leg is being followed.
///
/// It reports what is actually happening — including the difference between
/// "sharing with the phone locked" and "sharing only while this screen is open",
/// which is the difference the office cares about and the worker is entitled to
/// know.
struct TravelTrackingBadge: View {
    let state: TravelTrackingState
    let pings: Int
    /// ISSUE #14 — the company's own word for the role. This badge previously
    /// hard-coded "engineer" in its permission explanation, which is the one
    /// place in this file that reaches a real user rather than a preview.
    /// Defaulted so existing call sites and previews are unaffected.
    var worker: String = Terminology.generic.worker

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .symbolEffect(.pulse, options: .repeating, isActive: state.isTracking)

            VStack(alignment: .leading, spacing: 1) {
                Text(state.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }

    private var symbol: String {
        switch state {
        case .tracking: return "location.fill"
        case .off: return "location.slash"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .tracking(_, let background): return background ? Theme.green : Theme.amber
        case .off: return Theme.meta
        case .unavailable: return Theme.red
        }
    }

    private var detail: String {
        switch state {
        case .tracking(_, let background):
            let sent = pings == 1 ? "1 position sent" : "\(pings) positions sent"
            return background
                ? "\(sent) · continues with your phone locked · stops when you arrive"
                : "\(sent) · pauses when you leave this app · stops when you arrive"
        case .off:
            return "Your position is only shared while you are travelling to a job."
        case .unavailable(let authorization):
            return authorization.explanation(worker: worker)
        }
    }
}
