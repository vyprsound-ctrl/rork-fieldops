import SwiftUI

struct MoreView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = MoreViewModel()
    @State private var path = NavigationPath()

    private var session: TenantSession? { env.session }
    private var terms: Terminology { env.terms }

    /// Sections in the approved order, filtered by what the data layer will
    /// actually serve this role.
    private var visibleSections: [MoreSection] {
        guard let session else { return [] }
        return [.dispatch, .workerLocations, .fieldWorkers, .quotes, .invoices, .payments, .reports, .settings, .dataAccess, .integrations]
            .filter { section in
                guard let permission = section.requiredPermission else { return true }
                return session.can(permission)
            }
    }

    /// Development-only tooling, kept in its own labelled group so it is easy to
    /// find and obviously not part of the customer-facing product surface.
    private var developmentSections: [MoreSection] {
        session == nil ? [] : [.developmentTests]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: AppRoute.self) { route in
                RouteDestinationView(route: route)
            }
        }
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let overview):
            loaded(overview)
        }
    }

    private func loaded(_ overview: MoreOverview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityCard(overview)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sections")
                        .sectionLabelStyle()

                    VStack(spacing: 0) {
                        ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
                            NavigationLink(value: AppRoute.more(section)) {
                                sectionRow(section, overview: overview)
                            }
                            .buttonStyle(.plain)

                            if index < visibleSections.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .cardSurface()
                }

                if !developmentSections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Development")
                            .sectionLabelStyle()

                        VStack(spacing: 0) {
                            ForEach(Array(developmentSections.enumerated()), id: \.element.id) { index, section in
                                NavigationLink(value: AppRoute.more(section)) {
                                    sectionRow(section, overview: overview)
                                }
                                .buttonStyle(.plain)

                                if index < developmentSections.count - 1 {
                                    Divider().padding(.leading, 58)
                                }
                            }
                        }
                        .cardSurface()

                        Text("Runs the full acceptance suite against a freshly seeded store. Development build only.")
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    env.signOut()
                } label: {
                    Text("Sign out")
                        .font(.headline)
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .cardSurface()
                }
                .buttonStyle(PressableTileStyle())

                SimulatedServicesBanner()
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private func identityCard(_ overview: MoreOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(overview.companyName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 8) {
                Text(session?.displayName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Text(overview.roleTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.primaryTint)
                    .clipShape(.rect(cornerRadius: 6))
                Text(overview.tradeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.canvas)
                    .clipShape(.rect(cornerRadius: 6))
            }

            if let subscription = overview.subscriptionSummary {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                    Text(subscription)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                    SimulatedBadge()
                }
            }

            if let sms = overview.smsBalance {
                HStack(spacing: 8) {
                    Image(systemName: "message")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                    Text("\(sms) SMS credits")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .padding(.top, 4)
    }

    private func sectionRow(_ section: MoreSection, overview: MoreOverview) -> some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbolName)
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 8))

            Text(section.title(terms))
                .font(.body)
                .foregroundStyle(Theme.ink)

            Spacer(minLength: 4)

            if let detail = detailText(for: section, overview: overview) {
                Text(detail)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.meta)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    private func detailText(for section: MoreSection, overview: MoreOverview) -> String? {
        switch section {
        case .fieldWorkers: return overview.workerCount.map(String.init)
        case .quotes: return overview.quoteCount.map(String.init)
        case .invoices: return overview.outstandingLabel
        case .payments: return overview.paymentCount.map(String.init)
        default: return nil
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    MoreView()
        .environment(AppEnvironment())
}
