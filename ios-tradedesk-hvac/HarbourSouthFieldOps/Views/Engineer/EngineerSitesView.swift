import SwiftUI

/// Sites the engineer works at.
///
/// Deliberately not the company's CRM. The list is built from the jobs this
/// engineer is assigned to, and the database narrows those to their own
/// assignments before this screen sees a row — so a site they have never been
/// sent to simply does not exist here. No account balance, no payment terms,
/// no pricing and no customer notes appear anywhere on this surface, because
/// the field-worker site view has no such columns to give.
struct EngineerSitesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = EngineerSitesViewModel()

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("Sites & \(terms.assetPlural)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $viewModel.searchText, prompt: "Customer or address")
        .task(id: session?.userID) { await reload() }
        .onChange(of: viewModel.searchText) { _, _ in
            Task { await reload(showLoading: false) }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading your sites")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let sites):
            loaded(sites)
        }
    }

    @ViewBuilder
    private func loaded(_ sites: [EngineerSiteRow]) -> some View {
        if sites.isEmpty {
            ScrollView {
                EmptyStateView(
                    symbolName: viewModel.searchText.isEmpty ? "building.2" : "magnifyingglass",
                    title: viewModel.searchText.isEmpty ? "No sites yet" : "Nothing matches",
                    message: viewModel.searchText.isEmpty
                        ? "Sites appear here once you've been assigned work at them."
                        : "Try a different customer name or street."
                )
                .cardSurface()
                .padding(Theme.margin)
            }
            .refreshable { await reload(showLoading: false) }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(sites.count == 1 ? "1 site" : "\(sites.count) sites")
                        .sectionLabelStyle()

                    VStack(spacing: 0) {
                        ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                            NavigationLink(value: EngineerSiteRoute(addressID: site.id)) {
                                row(site)
                            }
                            .buttonStyle(.plain)

                            if index < sites.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .cardSurface()

                    Text("These are the sites you've been assigned work at. Anything you add here — notes, photos, \(terms.asset) details — goes on the record the whole team reads.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .refreshable { await reload(showLoading: false) }
        }
    }

    private func row(_ site: EngineerSiteRow) -> some View {
        HStack(spacing: 12) {
            Text(site.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 34, height: 34)
                .background(Theme.primaryTint)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(site.customerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if site.hasOpenWork {
                        Text("Open work")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.amber.opacity(0.14))
                            .clipShape(.capsule)
                    }
                }

                Text(site.addressLine)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    if site.equipmentCount > 0 {
                        Label(
                            site.equipmentCount == 1
                                ? "1 \(terms.asset)"
                                : "\(site.equipmentCount) \(terms.assetPlural)",
                            systemImage: "shippingbox"
                        )
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                    }
                    Label(
                        site.visitCount == 1 ? "1 visit" : "\(site.visitCount) visits",
                        systemImage: "clock.arrow.circlepath"
                    )
                    .font(.caption2)
                    .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

/// Route value for the engineer's site stack.
nonisolated struct EngineerSiteRoute: Hashable, Sendable {
    let addressID: String
}

#Preview {
    NavigationStack {
        EngineerSitesView()
            .environment(AppEnvironment())
    }
}
