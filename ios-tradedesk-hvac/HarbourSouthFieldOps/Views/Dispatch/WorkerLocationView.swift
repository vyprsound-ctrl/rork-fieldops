import SwiftUI

/// Where the field team was last seen.
///
/// Two things this screen is careful about. First, it distinguishes a *recent*
/// fix from a *last known* one — a position from four minutes ago is worth
/// acting on, one from yesterday is a historical record, and presenting the
/// second as the first would be a lie; the map carries that same distinction in
/// its pin colour. Second, it states the capture policy plainly: positions are
/// taken at job workflow events and, while somebody is actually driving to a
/// job, across that leg — never all day, and never on a timer.
struct WorkerLocationView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = WorkerLocationViewModel()

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("\(terms.Worker) locations")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading locations")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let board):
            loaded(board)
        }
    }

    private func loaded(_ board: FieldWorkerLocationBoard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if board.isSimulated { simulatedBanner }

                summary(board)

                if board.locations.isEmpty {
                    EmptyStateView(
                        symbolName: "location.slash",
                        title: "No positions recorded",
                        message: "A position is captured when a \(terms.worker) starts travel, arrives or completes a job."
                    )
                    .cardSurface()
                } else {
                    FieldTeamMap(locations: board.locations)
                    locationList(board)
                }

                if !board.withoutLocation.isEmpty {
                    missingSection(board)
                }

                policyCard(board)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
            .padding(.top, 4)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private var simulatedBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Theme.amber)
            Text("These are development fixtures, not real positions. No device is being tracked and no location permission has been requested.")
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.1))
        .clipShape(.rect(cornerRadius: 10))
    }

    private func summary(_ board: FieldWorkerLocationBoard) -> some View {
        HStack(spacing: 10) {
            summaryTile("\(board.recentCount)", "Recent", tone: .success)
            summaryTile("\(board.lastKnownCount)", "Last known", tone: .neutral)
            summaryTile("\(board.withoutLocation.count)", "No fix", tone: .neutral)
        }
    }

    private func summaryTile(_ value: String, _ caption: String, tone: StatusTone) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint(tone))
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardSurface()
    }

    private func locationList(_ board: FieldWorkerLocationBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last reported").sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(board.locations.enumerated()), id: \.element.id) { index, location in
                    locationRow(location)
                    if index < board.locations.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func locationRow(_ location: FieldWorkerLocationProjection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint(location.freshness.tone).opacity(0.12))
                    .frame(width: 38, height: 38)
                Image(systemName: location.freshness == .recent ? "location.fill" : "location.slash")
                    .font(.footnote)
                    .foregroundStyle(tint(location.freshness.tone))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(location.workerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    StatusPill(badge: StatusBadge(text: location.freshness.title, tone: location.freshness.tone))
                }

                Text(location.recordedAtLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)

                if let number = location.jobNumber {
                    Text("On \(number)\(location.jobStatusTitle.map { " · \($0)" } ?? "")")
                        .font(.caption)
                        .foregroundStyle(Theme.primary)
                }

                HStack(spacing: 8) {
                    Text(location.coordinateLabel)
                        .font(.caption2)
                        .monospaced()
                    Text(location.accuracyLabel)
                        .font(.caption2)
                }
                .foregroundStyle(Theme.meta)

                if location.headingLabel != nil || location.speedLabel != nil {
                    HStack(spacing: 8) {
                        if let heading = location.headingLabel {
                            Label(heading, systemImage: "location.north.line")
                                .font(.caption2)
                        }
                        if let speed = location.speedLabel {
                            Label(speed, systemImage: "speedometer")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 0)

            if location.isSimulated { SimulatedBadge() }
        }
        .padding(14)
    }

    private func missingSection(_ board: FieldWorkerLocationBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing reported yet").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 6) {
                ForEach(board.withoutLocation, id: \.self) { name in
                    HStack(spacing: 8) {
                        Image(systemName: "person.fill.questionmark")
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                        Text(name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                        Spacer(minLength: 0)
                    }
                }
                Text("A position appears once they start travel, arrive or complete a job.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func policyCard(_ board: FieldWorkerLocationBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How location works here").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 8) {
                policyLine("checkmark.circle.fill", "Captured at job events — start travel, arrive, complete.", Theme.green)
                policyLine("car.fill", "Followed while actually driving to a job, between start travel and arrival.", Theme.primary)
                policyLine("xmark.circle.fill", "Never outside that leg. No all-day tracking and no timer.", Theme.red)
                policyLine("clock.arrow.circlepath", "History is capped at \(LocationRetentionPolicy.days) days and \(LocationRetentionPolicy.maximumPingsPerWorker) points per \(terms.worker).", Theme.secondary)
                policyLine("building.2.fill", "Positions never leave the company they were recorded in.", Theme.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            Text(board.policySummary)
                .font(.caption2)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func policyLine(_ symbol: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private func tint(_ tone: StatusTone) -> Color {
        switch tone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    NavigationStack {
        WorkerLocationView()
            .environment(AppEnvironment())
    }
}
