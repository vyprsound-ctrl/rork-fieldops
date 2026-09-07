import SwiftUI

/// Confirms a navigation hand-off before leaving the app.
///
/// This exists so the app never implies it is navigating. It states plainly
/// what is about to happen — the destination is passed to the device's maps
/// app — and it says so while the mock adapter is in place. There is no in-app
/// route line, no guidance and no progress tracking anywhere in this build.
struct NavigationHandoffSheet: View {
    let handoff: NavigationHandoff
    /// Simulated travel estimate, when one has been worked out.
    var estimate: RouteEstimate?
    var countryCode: String = "US"

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    destinationCard

                    if let estimate {
                        estimateCard(estimate)
                    }

                    behaviourCard

                    Spacer(minLength: 0)

                    Button {
                        if let url = handoff.url { openURL(url) }
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.forward.app.fill")
                            Text("Open in Maps")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .background(handoff.canOpen ? Theme.primary : Theme.meta)
                        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(!handoff.canOpen)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .navigationTitle("Navigate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Destination").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 6) {
                Text(handoff.label)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                if let addressLine = handoff.addressLine {
                    Text(addressLine)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(Formatters.coordinateLabel(
                    latitude: handoff.destination.latitude,
                    longitude: handoff.destination.longitude
                ))
                .font(.caption)
                .monospaced()
                .foregroundStyle(Theme.meta)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func estimateCard(_ estimate: RouteEstimate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Estimated travel").sectionLabelStyle()
                if estimate.simulated { SimulatedBadge() }
            }

            HStack(spacing: 0) {
                estimateColumn("Distance", estimate.distanceLabel(countryCode: countryCode))
                Divider().frame(height: 34)
                estimateColumn("Drive", estimate.durationLabel)
                Divider().frame(height: 34)
                estimateColumn("Arrive", estimate.arrivalLabel)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }

    private func estimateColumn(_ caption: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.meta)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private var behaviourCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.amber)
            Text(handoff.behaviourNote)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }
}

#Preview {
    NavigationHandoffSheet(
        handoff: NavigationHandoff(
            destination: Coordinate(latitude: 27.9506, longitude: -82.4572),
            label: "Coastal Storage",
            addressLine: "44 Harbour Point Dr, Tampa FL 33602",
            url: URL(string: "http://maps.apple.com/?daddr=27.95,-82.45"),
            simulated: true,
            behaviourNote: "Hands the destination to your maps app. This build has no in-app routing or turn-by-turn guidance."
        ),
        estimate: RouteEstimate(
            distanceMeters: 4800,
            durationSeconds: 660,
            arrivalTime: Date().addingTimeInterval(660),
            routeSummary: nil,
            usesLiveTraffic: false,
            simulated: true
        )
    )
}
