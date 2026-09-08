import SwiftUI

/// The company's Harbour South subscription.
///
/// The whole point of this screen is that the owner can see *why* the bill is
/// what it is. A total on its own invites suspicion; the arithmetic, the head
/// count and the tier they sit in do not.
///
/// This is FLOW A money — the trade business paying Harbour South. The card
/// payments their own customers make live on a different screen and a different
/// Stripe account entirely, and the two are labelled so they cannot be
/// confused.
struct SubscriptionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var viewModel = SubscriptionViewModel()
    /// The "what if we hired someone" slider. A projection, never a charge.
    @State private var projectedUsers: Int = 0

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.userID) { await reload() }
        .refreshable { await reload(showLoading: false) }
        .onChange(of: viewModel.pendingLink) { _, link in
            if let link { openURL(link); viewModel.pendingLink = nil }
        }
        .alert(
            "Something went wrong",
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
            LoadingStateView(message: "Loading subscription")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await reload() } }
        case .loaded(let overview):
            loaded(overview)
        }
    }

    private func loaded(_ overview: SubscriptionOverview) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let alert = overview.alert {
                alertCard(alert)
            }

            priceCard(overview)
            breakdownCard(overview)
            seatCard(overview)
            projectionCard(overview)
            tierListCard(overview)
            connectCard()

            if !overview.pricing.isLive {
                Text("These prices could not be read from the server and are the built-in defaults. Reconnect to confirm the current price list.")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Cards

    private func alertCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.amber)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.10))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func priceCard(_ overview: SubscriptionOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(overview.quote.monthlyLabel)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                Text("/month")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Spacer()
                if let subscription = overview.subscription {
                    StatusPill(badge: StatusBadge(
                        text: subscription.status.title,
                        tone: tone(for: subscription.status)
                    ))
                }
            }

            Text("\(overview.quote.tierName) · \(overview.quote.activePaidUsers) active \(overview.quote.activePaidUsers == 1 ? "person" : "people")")
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)

            if let subscription = overview.subscription {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                    Text(subscription.status == .cancelled
                         ? "Ends \(Formatters.shortDate(subscription.currentPeriodEnd))"
                         : "Renews \(Formatters.shortDate(subscription.renewalDate))")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// The arithmetic, spelled out. This is the answer to "why am I paying
    /// this?" and it is deliberately the most prominent thing after the total.
    private func breakdownCard(_ overview: SubscriptionOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How this is calculated")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                breakdownRow(
                    "First user",
                    detail: "Included in every plan",
                    amount: SubscriptionQuote.money(overview.quote.baseCents)
                )

                if overview.quote.additionalUsers > 0 {
                    Divider().padding(.leading, 14)
                    breakdownRow(
                        "\(overview.quote.additionalUsers) more \(overview.quote.additionalUsers == 1 ? "user" : "users")",
                        detail: "\(SubscriptionQuote.money(overview.quote.additionalUserCents)) each on the \(overview.quote.tierName) rate",
                        amount: SubscriptionQuote.money(overview.quote.additionalCents)
                    )
                }

                Divider().padding(.leading, 14)
                breakdownRow(
                    "Total each month",
                    detail: nil,
                    amount: overview.quote.monthlyLabel,
                    emphasised: true
                )
            }
            .cardSurface()

            // The rule that is most often got wrong, stated plainly.
            Text("Every user after the first is charged at the same rate — the one for your total head count. It is not banded, so growing into a bigger tier lowers the rate on all of your users, not just the new one.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func breakdownRow(
        _ title: String,
        detail: String?,
        amount: String,
        emphasised: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(emphasised ? .subheadline.weight(.semibold) : .subheadline)
                    .foregroundStyle(Theme.ink)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(amount)
                .font(emphasised ? .subheadline.weight(.bold) : .subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func seatCard(_ overview: SubscriptionOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                seatRow("Active — billed", value: overview.activeUsers, tone: Theme.ink)
                Divider().padding(.leading, 14)
                seatRow("Invited — not yet billed", value: overview.invitedUsers, tone: Theme.secondary)
                Divider().padding(.leading, 14)
                seatRow("Suspended — not billed", value: overview.suspendedUsers, tone: Theme.secondary)

                if let next = overview.quote.nextUserCents {
                    Divider().padding(.leading, 14)
                    HStack {
                        Text(next >= 0 ? "Adding one more person" : "Adding one more person saves")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text(SubscriptionQuote.money(abs(next)))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(next >= 0 ? Theme.ink : Theme.green)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .cardSurface()

            Text(overview.quote.isAtCapacity
                 ? "This company is at the supported maximum of \(overview.quote.maxUsers) active people."
                 : "Only active people are billed. Suspending somebody removes their seat from the next bill; inviting somebody does not add one until they accept.")
                .font(.caption)
                .foregroundStyle(overview.quote.isAtCapacity ? Theme.amber : Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func seatRow(_ title: String, value: Int, tone: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(tone)
            Spacer()
            Text("\(value)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tone)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Lets an owner price a hire before making it.
    private func projectionCard(_ overview: SubscriptionOverview) -> some View {
        let users = projectedUsers == 0 ? overview.quote.activePaidUsers : projectedUsers
        let projected = viewModel.projection(overview, users: users)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Plan ahead")
                .sectionLabelStyle()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("\(users) \(users == 1 ? "person" : "people")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(projected.monthlyLabel)/mo")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primary)
                }

                Stepper(
                    value: Binding(
                        get: { users },
                        set: { projectedUsers = $0 }
                    ),
                    in: 1...overview.pricing.maxUsers
                ) {
                    Text(projected.breakdownLine)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                }

                if users != overview.quote.activePaidUsers {
                    Text("This is an estimate only. Your bill changes when someone is actually activated.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func tierListCard(_ overview: SubscriptionOverview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Price list")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(overview.pricing.tiers.enumerated()), id: \.element.id) { index, tier in
                    let isCurrent = tier.id == overview.quote.tierID

                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(tier.displayName)
                                    .font(.subheadline.weight(isCurrent ? .bold : .regular))
                                    .foregroundStyle(Theme.ink)
                                if isCurrent {
                                    Text("Current")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.primary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Theme.primaryTint)
                                        .clipShape(.rect(cornerRadius: 5))
                                }
                            }
                            Text(tier.minUsers == tier.maxUsers
                                 ? "\(tier.minUsers) user"
                                 : "\(tier.minUsers)–\(tier.maxUsers) users")
                                .font(.caption)
                                .foregroundStyle(Theme.meta)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(SubscriptionQuote.money(tier.baseCents))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(Theme.ink)
                            if tier.additionalUserCents > 0 {
                                Text("+ \(SubscriptionQuote.money(tier.additionalUserCents))/user")
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.meta)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(isCurrent ? Theme.primaryTint.opacity(0.4) : Color.clear)

                    if index < overview.pricing.tiers.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .cardSurface()
        }
    }

    /// FLOW B, kept visually and verbally distinct from everything above.
    @ViewBuilder
    private func connectCard() -> some View {
        if case .loaded(let connect) = viewModel.connectState {
            VStack(alignment: .leading, spacing: 8) {
                Text("Taking customer payments")
                    .sectionLabelStyle()

                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: connect.acceptsCards ? "checkmark.seal.fill" : "creditcard")
                            .font(.footnote)
                            .foregroundStyle(connect.acceptsCards ? Theme.green : Theme.secondary)
                        Text(connect.readiness.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Spacer()
                    }

                    Text(connectDetail(connect))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !connect.requirementsDue.isEmpty {
                        Text("Stripe still needs: \(connect.requirementsDue.prefix(4).joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if connect.canManage, connect.readiness != .notConfigured {
                        Button {
                            Task {
                                guard let session else { return }
                                if connect.readiness == .ready {
                                    await viewModel.openStripeDashboard(gateway: env.gateway, session: session)
                                } else {
                                    await viewModel.startOnboarding(gateway: env.gateway, session: session)
                                }
                            }
                        } label: {
                            HStack {
                                Text(connect.readiness == .ready ? "Open Stripe dashboard" : "Continue setup")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                if viewModel.isWorking {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.footnote)
                                }
                            }
                            .foregroundStyle(Theme.primary)
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isWorking)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()

                Text("This is separate from your Harbour South subscription above. Customer payments go straight to your own Stripe account.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func connectDetail(_ connect: ConnectAccountStatus) -> String {
        switch connect.readiness {
        case .notConfigured:
            return connect.disabledReason
                ?? "Card payments are not switched on for this deployment yet."
        case .notConnected:
            return "Connect a Stripe account to let customers pay their invoices by card. Money goes to you, not to Harbour South."
        case .pending:
            return "Stripe needs a little more information before you can take payments."
        case .ready:
            return "You can take card payments. Funds settle into your own Stripe account."
        case .restricted:
            return connect.disabledReason ?? "Stripe has restricted this account. Open the dashboard for details."
        }
    }

    private func tone(for status: SubscriptionStatus) -> StatusTone {
        switch status {
        case .active: return .success
        case .trialing: return .info
        case .pastDue: return .warning
        case .cancelled, .expired: return .danger
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}
