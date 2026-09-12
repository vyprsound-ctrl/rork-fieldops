import SwiftUI

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = DashboardViewModel()
    @State private var path = NavigationPath()
    @State private var pendingAction: QuickAction?

    private var session: TenantSession? { env.activeSession }

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
                case .addCustomer:
                    CustomerEditorView { customerID in
                        path.append(AppRoute.customer(customerID))
                    }
                case .newInvoice:
                    NewInvoiceLauncher { invoiceID in
                        path.append(AppRoute.invoice(invoiceID))
                    }
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
                todayProgress(snapshot)
                if !availableActions.isEmpty { actionGrid }
                schedule(snapshot)
                if !snapshot.financialTiles.isEmpty { financials(snapshot) }
                if let balance = snapshot.smsBalance { smsRow(balance) }
                if env.isDevelopmentSession { SimulatedServicesBanner() }
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

    /// Today at a glance: what is done, what is left, who is out and what has
    /// nobody on it. The unassigned count is the one that needs acting on, so it
    /// is the only one that ever changes colour.
    @ViewBuilder
    private func todayProgress(_ snapshot: DashboardSnapshot) -> some View {
        if !snapshot.todayJobs.isEmpty {
            HStack(spacing: 0) {
                progressTile("Done", value: snapshot.completedToday, tone: Theme.green)
                Divider().frame(height: 32)
                progressTile("Left", value: snapshot.remainingToday, tone: Theme.ink)
                Divider().frame(height: 32)
                progressTile("\(env.terms.WorkerPlural) out", value: snapshot.workersOnToday, tone: Theme.ink)

                if snapshot.unassignedToday > 0 {
                    Divider().frame(height: 32)
                    progressTile("Unassigned", value: snapshot.unassignedToday, tone: Theme.amber)
                }
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .cardSurface()
        }
    }

    private func progressTile(_ title: String, value: Int, tone: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tone)
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    /// Only shown to a role that may read the ledger, and only ever the real
    /// balance — an empty account says so rather than showing a cheerful zero.
    private func smsRow(_ balance: Int) -> some View {
        NavigationLink(value: AppRoute.more(.smsCredits)) {
            HStack(spacing: 12) {
                Image(systemName: "message.fill")
                    .font(.footnote)
                    .foregroundStyle(balance > 0 ? Theme.primary : Theme.amber)
                    .frame(width: 32, height: 32)
                    .background(balance > 0 ? Theme.primaryTint : Theme.amber.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(balance == 1 ? "1 SMS credit" : "\(balance) SMS credits")
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                    if balance <= 0 {
                        Text("Messages can't be sent until you top up")
                            .font(.caption)
                            .foregroundStyle(Theme.amber)
                    }
                }

                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: Theme.minTap)
            .contentShape(.rect)
            .cardSurface()
        }
        .buttonStyle(.plain)
    }

    private var actionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(availableActions) { action in
                Button {
                    pendingAction = action
                } label: {
                    VStack(spacing: 10) {
                        // #1 — these four tiles are the office's primary
                        // actions, so they carry the action colour rather than
                        // the structural blue the rest of the card uses.
                        Image(systemName: action.symbolName)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 56, height: 56)
                            .background(Theme.actionTintSoft)
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
