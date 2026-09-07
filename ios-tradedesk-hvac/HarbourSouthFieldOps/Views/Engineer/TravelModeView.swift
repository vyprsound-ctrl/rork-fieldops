import SwiftUI

/// Travel mode: the screen a field worker sees once they're on their way.
///
/// Big type, few controls, nothing to read. Where they're going, how to get
/// there, roughly how long it'll take, and the one button that moves the job
/// forward when they arrive.
///
/// The ETA is a simulation and says so. This app does not navigate — it hands
/// the destination to the device's maps app and stops there.
struct TravelModeView: View {
    let jobID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = TravelViewModel()
    @State private var navigationHandoff: NavigationHandoff?

    private var session: TenantSession? { env.session }

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
                etaCard(trip)
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
                SimulatedBadge(text: "Simulated ETA")
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

            Text("Worked out from straight-line distance at an assumed speed. It knows nothing about roads or traffic and is not a real arrival time.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            Text("Your position is recorded when you start travel, arrive and finish — not in between, and never in the background.")
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
            destination: Coordinate(latitude: trip.latitude, longitude: trip.longitude)
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
