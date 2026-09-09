import SwiftUI

/// Travel mode: the screen a field worker sees once they're on their way.
///
/// Big type, few controls, nothing to read. Where they're going, how to get
/// there, roughly how long it'll take, and the one button that moves the job
/// forward when they arrive.
///
/// The map and the ETA come from Apple Maps on the production stack. This app
/// still does not give turn-by-turn guidance — it shows the route, then hands
/// the destination to Apple Maps when the worker wants directions. Where a
/// route could not be fetched the estimate falls back to straight-line distance
/// and says so on screen rather than passing a guess off as a routed arrival.
struct TravelModeView: View {
    let jobID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = TravelViewModel()
    @State private var navigationHandoff: NavigationHandoff?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.state.value?.number ?? "On the way")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: jobID) { await reload() }
        .sheet(item: $navigationHandoff) { handoff in
            NavigationHandoffSheet(
                handoff: handoff,
                estimate: viewModel.estimate,
                countryCode: viewModel.state.value?.countryCode ?? "US"
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading route")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let trip):
            loaded(trip)
        }
    }

    private func loaded(_ trip: TravelSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusHeader(trip)

                if env.travelTracker.state.isTracking || env.travelTracker.state.jobID == jobID {
                    TravelTrackingBadge(
                        state: env.travelTracker.state,
                        pings: env.travelTracker.pingsThisLeg
                    )

                    // Offered only when it would actually change something:
                    // a leg already running foreground-only.
                    if env.travelTracker.state.isTracking,
                       !env.travelTracker.state.continuesInBackground,
                       env.travelTracker.backgroundState == .foregroundOnly {
                        backgroundUpgradeButton
                    }

                    if let error = env.travelTracker.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                etaCard(trip)

                JobRouteMap(
                    destination: Coordinate(latitude: trip.latitude, longitude: trip.longitude),
                    destinationLabel: trip.customerName,
                    origin: viewModel.origin,
                    showsUserLocation: env.isProductionSession
                )

                destinationCard(trip)

                if let error = viewModel.actionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.red.opacity(0.08))
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))
                }

                // Only appears when a step genuinely could not record a
                // position. Nothing is invented in its place.
                if let refused = viewModel.lastCaptureOutcome?.refusedState {
                    LocationPermissionNotice(state: refused, worker: env.terms.worker)
                }

                locationNote
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
            .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar(trip)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private func statusHeader(_ trip: TravelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusPill(badge: trip.badge)
                if trip.isUrgent {
                    Text("Urgent")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.red.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 6))
                }
                Spacer(minLength: 0)
            }

            Text(trip.customerName)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(trip.scheduleLabel)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func etaCard(_ trip: TravelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Travel").sectionLabelStyle()
                if viewModel.estimate?.simulated == true {
                    SimulatedBadge(text: "Estimated")
                } else if viewModel.estimate?.usesLiveTraffic == true {
                    Text("Apple Maps · with traffic")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.green)
                }
            }

            if let estimate = viewModel.estimate {
                VStack(spacing: 12) {
                    HStack(spacing: 0) {
                        etaColumn("Arrive", estimate.arrivalLabel, emphasis: true)
                        Divider().frame(height: 40)
                        etaColumn("Drive", estimate.durationLabel)
                        Divider().frame(height: 40)
                        etaColumn("Distance", estimate.distanceLabel(countryCode: trip.countryCode))
                    }

                    Button {
                        Task { await refreshEstimate(trip) }
                    } label: {
                        Label("Update estimate", systemImage: "arrow.clockwise")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .cardSurface()
            } else {
                Text("No estimate available.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
            }

            Text(etaCaption)
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// States which of the two things actually produced the number on screen.
    private var etaCaption: String {
        guard let estimate = viewModel.estimate else {
            return "An estimate needs your current position. Allow location to see one."
        }
        return estimate.simulated
            ? "A route wasn't available, so this is straight-line distance at an assumed speed. It knows nothing about roads or traffic."
            : "Driving time from Apple Maps, following roads and current traffic. It updates when you ask it to, not continuously."
    }

    private var backgroundUpgradeButton: some View {
        Button {
            Task { await env.travelTracker.requestBackgroundPermission(location: env.location) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "lock.iphone")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep sharing when my phone is locked")
                        .font(.subheadline.weight(.semibold))
                    Text("Otherwise the office stops seeing you move once you put the phone away.")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.primary)
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
            .background(Theme.primaryTint)
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(PressableTileStyle())
    }

    private func etaColumn(_ caption: String, _ value: String, emphasis: Bool = false) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(emphasis ? .title3.weight(.bold) : .subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(emphasis ? Theme.primary : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.meta)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
    }

    private func destinationCard(_ trip: TravelSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.footnote)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(Theme.primaryTint)
                    .clipShape(.circle)

                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.addressLine)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let access = trip.accessNotes {
                        Text(access)
                            .font(.footnote)
                            .foregroundStyle(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if let name = trip.siteContactName, let phone = trip.siteContactPhone {
                Divider()
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle")
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                        .frame(width: 32, height: 32)
                        .background(Theme.primaryTint)
                        .clipShape(.circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Text("Site contact")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer(minLength: 0)

                    if let url = URL(string: "tel://\(phone.filter(\.isNumber))") {
                        Link(destination: url) {
                            Text("Call")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Theme.primaryTint)
                                .clipShape(.capsule)
                        }
                    }
                }
            }

            Button {
                prepareNavigation(trip)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                    Text("Navigate")
                }
                .font(.headline)
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(PressableTileStyle())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var locationNote: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.meta)
            Text("Your position is shared while you are on your way, and recorded when you start travel, arrive and finish. Sharing stops the moment you mark yourself arrived.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(radius: 10)
    }

    @ViewBuilder
    private func actionBar(_ trip: TravelSnapshot) -> some View {
        if let next = trip.nextStatus, let title = trip.nextActionTitle {
            VStack(spacing: 0) {
                Divider()
                Button {
                    Task { await advance(trip, to: next) }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.isWorking { ProgressView().tint(.white) }
                        Text(title)
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(next == .completed ? Theme.green : Theme.primary)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                }
                .buttonStyle(PressableTileStyle())
                .disabled(viewModel.isWorking)
                .padding(.horizontal, Theme.margin)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .background(.bar)
        }
    }

    // MARK: - Actions

    private func prepareNavigation(_ trip: TravelSnapshot) {
        navigationHandoff = env.maps.prepareNavigation(
            to: Coordinate(latitude: trip.latitude, longitude: trip.longitude),
            label: trip.customerName,
            addressLine: trip.addressLine
        )
    }

    private func refreshEstimate(_ trip: TravelSnapshot) async {
        await viewModel.refreshEstimate(location: env.location, routes: env.routes, snapshot: trip)
    }

    private func advance(_ trip: TravelSnapshot, to status: JobStatus) async {
        guard let session else { return }
        await viewModel.advance(
            gateway: env.gateway,
            location: env.location,
            routes: env.routes,
            session: session,
            jobID: jobID,
            to: status,
            destination: Coordinate(latitude: trip.latitude, longitude: trip.longitude),
            tracker: env.travelTracker
        )
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(
            gateway: env.gateway,
            location: env.location,
            routes: env.routes,
            session: session,
            jobID: jobID,
            showLoading: showLoading
        )
    }
}

#Preview {
    NavigationStack {
        TravelModeView(jobID: "job_1042")
            .environment(AppEnvironment())
    }
}
