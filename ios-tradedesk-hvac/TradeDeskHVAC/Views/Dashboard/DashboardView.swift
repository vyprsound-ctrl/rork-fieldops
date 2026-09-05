import SwiftUI

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = DashboardViewModel()
    @State private var path = NavigationPath()
    @State private var pendingAction: QuickAction?

    private var session: TenantSession? { env.session }

    private var availableActions: [QuickAction] {
        guard let session else { return [] }
        return QuickAction.allCases.filter { session.can($0.requiredPermission) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationDestination(for: AppRoute.self) { route in
                RouteDestinationView(route: route)
            }
            .sheet(item: $pendingAction) { action in
                switch action {
                case .newJob:
                    JobEditorView { jobID in
                        path.append(AppRoute.job(jobID))
                    }
                case .newQuote:
                    QuoteEditorView { quoteID in
                        path.append(AppRoute.quote(quoteID))
                    }
                default:
                    PhaseTwoSheet(title: action.title, permission: action.requiredPermission)
                }
            }
        }
        .task(id: session?.userID) {
            guard let session else { return }
            await viewModel.load(gateway: env.gateway, session: session)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading today")
        case .failed(let error):
            ErrorStateView(error: error) {
                guard let session else { return }
                Task { await viewModel.load(gateway: env.gateway, session: session) }
            }
        case .loaded(let snapshot):
            loaded(snapshot)
        }
    }

    private func loaded(_ snapshot: DashboardSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(snapshot)
                if !availableActions.isEmpty { actionGrid }
                schedule(snapshot)
                if !snapshot.financialTiles.isEmpty { financials(snapshot) }
                SimulatedServicesBanner()
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .refreshable {
            guard let session else { return }
            await viewModel.load(gateway: env.gateway, session: session, showLoading: false)
        }
    }

    private func header(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.headline)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(snapshot.subline)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(availableActions) { action in
                Button {
                    pendingAction = action
                } label: {
                    VStack(spacing: 10) {
                        Image(systemName: action.symbolName)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 56, height: 56)
                            .background(Theme.primaryTint)
                            .clipShape(.circle)
                        Text(action.title)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .cardSurface()
                }
                .buttonStyle(PressableTileStyle())
            }
        }
    }

    private func schedule(_ snapshot: DashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's schedule")
                .sectionLabelStyle()

            if snapshot.todayJobs.isEmpty {
                EmptyStateView(
                    symbolName: "calendar",
                    title: "Nothing booked today",
                    message: "Jobs scheduled for today will appear here."
                )
                .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.todayJobs.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: AppRoute.job(row.id)) {
                            JobRowView(row: row)
                        }
                        .buttonStyle(.plain)

                        if index < snapshot.todayJobs.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private func financials(_ snapshot: DashboardSnapshot) -> some View {
        HStack(spacing: 12) {
            ForEach(snapshot.financialTiles) { tile in
                VStack(alignment: .leading, spacing: 8) {
                    Text(tile.caption)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                    Text(tile.amount)
                        .font(.system(size: 27, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    HStack {
                        Spacer()
                        Image(systemName: tile.symbolName)
                            .font(.footnote)
                            .foregroundStyle(Theme.primary)
                            .frame(width: 30, height: 30)
                            .background(Theme.primaryTint)
                            .clipShape(.rect(cornerRadius: 8))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }
}

/// Subtle press feedback on the large home tiles.
struct PressableTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed)
    }
}

#Preview {
    DashboardView()
        .environment(AppEnvironment())
}
