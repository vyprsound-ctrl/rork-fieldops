import SwiftUI

/// SMS credits: balance, bundles, ledger and message history.
///
/// Credits are a separate commercial system from the Harbour South
/// subscription. Buying credits does not change the subscription, and
/// cancelling the subscription does not destroy credits. The screen says so,
/// because conflating the two is the most likely misunderstanding.
///
/// Every number here comes from the company's own ledger, scoped by RLS. There
/// is no path — in this screen or beneath it — by which one company can read or
/// spend another's balance.
struct SmsCreditsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var viewModel = SmsCreditsViewModel()
    @State private var showAllLedger = false

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .navigationTitle("SMS credits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.userID) { await reload() }
        .refreshable { await reload(showLoading: false) }
        .onChange(of: viewModel.checkoutURL) { _, url in
            if let url { openURL(url); viewModel.checkoutURL = nil }
        }
        .alert(
            "Could not continue",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading credits")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await reload() } }
        case .loaded(let overview):
            loaded(overview)
        }
    }

    private func loaded(_ overview: SmsCreditOverview) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            balanceCard(overview)

            if overview.canPurchase {
                bundlesSection(overview)
            }

            if overview.canReadLedger {
                if !overview.recentMessages.isEmpty {
                    messagesSection(overview)
                }
                if !overview.ledger.isEmpty {
                    ledgerSection(overview)
                }
            }

            Text("SMS credits are separate from your Harbour South subscription. Buying credits does not change your monthly plan, and credits you have bought stay yours.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func balanceCard(_ overview: SmsCreditOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(overview.balance)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(overview.isEmpty ? Theme.amber : Theme.ink)
                Text(overview.balance == 1 ? "credit" : "credits")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Spacer()
            }

            Text(overview.isEmpty
                 ? "You have no credits, so messages cannot be sent. Buy a bundle to start again."
                 : "One credit sends one text segment (up to 160 characters, or 70 with emoji).")
                .font(.footnote)
                .foregroundStyle(overview.isEmpty ? Theme.amber : Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func bundlesSection(_ overview: SmsCreditOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Buy credits")
                .sectionLabelStyle()

            if overview.bundles.isEmpty {
                Text("No credit bundles are available right now.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(overview.bundles) { bundle in
                        Button {
                            Task {
                                guard let session else { return }
                                await viewModel.buy(gateway: env.gateway, session: session, bundle: bundle)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bundle.creditsLabel)
                                    .font(.title3.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.ink)
                                Text("segments")
                                    .font(.caption)
                                    .foregroundStyle(Theme.meta)
                                Divider().padding(.vertical, 2)
                                Text(bundle.priceLabel)
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.primary)
                                Text(bundle.unitLabel)
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.meta)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()
                        }
                        .buttonStyle(PressableTileStyle())
                        .disabled(viewModel.isWorking)
                    }
                }

                // The smallest bundle is 25. Stating it removes the worry that
                // a small business is about to be pushed into a 500-credit
                // minimum it will never use.
                Text("Bundles start at 25 credits — there is no minimum order. Payment opens in your browser, and credits appear here once it completes.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func messagesSection(_ overview: SmsCreditOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent messages")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(overview.recentMessages.prefix(10).enumerated()), id: \.element.id) { index, message in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(message.recipient)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 4)
                            StatusPill(badge: StatusBadge(text: message.state.title, tone: message.state.tone))
                        }

                        Text(message.body)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Text(Formatters.shortDayAndTime(message.sentAt ?? message.createdAt))
                                .font(.caption)
                                .foregroundStyle(Theme.meta)

                            // A returned credit is stated explicitly — a failed
                            // message that silently cost nothing looks like a
                            // billing error.
                            if message.creditsRefunded > 0 {
                                Text("credit returned")
                                    .font(.caption)
                                    .foregroundStyle(Theme.green)
                            }
                        }

                        if let reason = message.failureReason, message.state.isSettled, message.state != .delivered {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(Theme.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if index < min(overview.recentMessages.count, 10) - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func ledgerSection(_ overview: SmsCreditOverview) -> some View {
        let rows = showAllLedger ? overview.ledger : Array(overview.ledger.prefix(8))

        return VStack(alignment: .leading, spacing: 8) {
            Text("Credit history")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.detail)
                                .font(.subheadline)
                                .foregroundStyle(Theme.ink)
                            Text(Formatters.shortDayAndTime(row.at))
                                .font(.caption)
                                .foregroundStyle(Theme.meta)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(row.amountLabel)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(row.amount >= 0 ? Theme.green : Theme.ink)
                            Text("balance \(row.balanceAfter)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.meta)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)

                    if index < rows.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .cardSurface()

            if overview.ledger.count > 8 {
                Button(showAllLedger ? "Show less" : "Show all \(overview.ledger.count)") {
                    withAnimation(.snappy) { showAllLedger.toggle() }
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.primary)
            }
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}
