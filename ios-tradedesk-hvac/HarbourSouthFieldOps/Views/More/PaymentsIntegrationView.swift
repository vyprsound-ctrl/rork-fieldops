import SwiftUI

/// More → Connect Stripe, and Settings → Integrations → Payments.
///
/// Both entries open this one screen; there is no second Stripe surface.
/// The one place an owner manages how their customers pay them, and what that
/// costs. It replaces the old "Online payment link" screen, whose copy framed a
/// pasted URL as the primary way to take money — which is no longer the Harbour
/// South architecture.
///
/// TWO MODELS, BOTH LEGITIMATE:
///
///   Harbour South Payments  the company's OWN connected Stripe account. Money
///                           goes to the trade business; Harbour South takes a
///                           platform fee and is never the merchant of record.
///   My own payment provider the company keeps whatever it already uses and
///                           supplies its customer-facing link. No Harbour
///                           South transaction fee at all.
///
/// NOTHING ON THIS SCREEN DECIDES ANYTHING COMMERCIAL. The Stripe state and
/// the platform fee arrive already decided from `company_commercial_state()`.
/// The Harbour South subscription is a separate concept on its own screen. Stripe onboarding is the existing Connect
/// flow — no API key is ever asked for, and no credential reaches this app.
struct PaymentsIntegrationView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var viewModel = CommercialViewModel()
    @State private var isConfirmingExternal = false

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.margin)
                .padding(.top, 4)
                .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .navigationTitle("Payments")
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
        .confirmationDialog(
            "Keep using your own payment provider?",
            isPresented: $isConfirmingExternal,
            titleVisibility: .visible
        ) {
            Button("Use my own provider") {
                Task {
                    guard let session else { return }
                    await viewModel.chooseExternalProvider(gateway: env.gateway, session: session)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your customers will pay through your existing provider's link. Those payments carry a \(PlatformFeeCopy.zeroPhrase), and your normal subscription applies.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading payment settings")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await reload() } }
        case .loaded(let commercial):
            loaded(commercial)
        }
    }

    private func loaded(_ commercial: CommercialState) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let confirmation = viewModel.confirmation {
                successBanner(confirmation)
            }

            stripeSection(commercial)
            externalSection(commercial)
            boundaryCard
        }
    }

    // MARK: - Stripe

    private func stripeSection(_ commercial: CommercialState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Harbour South Payments").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: commercial.stripeState))
                        .font(.footnote)
                        .foregroundStyle(Color.white)
                        .frame(width: 34, height: 34)
                        .background(tintColor(for: commercial.stripeState))
                        .clipShape(.rect(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(commercial.stripeState.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .accessibilityIdentifier("stripe-state-title")
                        Text("Stripe")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }

                    Spacer(minLength: 0)

                    StatusPill(badge: StatusBadge(
                        text: commercial.stripeState.shortLabel,
                        tone: commercial.stripeState.tone
                    ))
                }

                Text(commercial.stripeState.message)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if commercial.stripeConnected {
                    connectedDetail(commercial)
                }

                if !commercial.stripeNeeds.isEmpty, !commercial.stripeState.isConnected {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Stripe still needs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.amber)
                        Text(commercial.stripeNeeds.prefix(5).joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // The business structure question used to live here, in UK
                // terms ("Sole trader" / "Limited company") that do not fit a
                // US market. It has been removed rather than translated:
                // Stripe's hosted onboarding collects and *verifies* the
                // structure itself, so asking first duplicated the question and
                // could only ever disagree with the answer Stripe accepted.
                if commercial.canManageBilling, commercial.stripeState == .notConnected {
                    Text("Stripe will ask about your business and verify it during setup.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if commercial.canManageBilling {
                    let action = commercial.stripeState.actionTitle
                    Button {
                        Task { await runStripeAction(commercial) }
                    } label: {
                        // The accent is reserved for the step that actually
                        // needs taking. Managing a healthy account is routine,
                        // so it is the quieter primary blue.
                        BrandButtonLabel(
                            title: action,
                            role: commercial.stripeState.isConnected ? .primary : .accent,
                            isEnabled: !viewModel.isWorking,
                            isWorking: viewModel.isWorking
                        )
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(viewModel.isWorking)
                } else if !commercial.canManageBilling {
                    Text("Only the account owner can connect or manage Stripe.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    /// The commercial position of a connected company, itemised.
    private func connectedDetail(_ commercial: CommercialState) -> some View {
        VStack(spacing: 0) {
            detailRow(
                "Payments",
                commercial.chargesEnabled ? "Enabled" : "Not enabled",
                tone: commercial.chargesEnabled ? Theme.green : Theme.amber
            )
            Divider()
            detailRow(
                "Payouts",
                commercial.payoutsEnabled ? "Enabled" : "Not enabled",
                tone: commercial.payoutsEnabled ? Theme.green : Theme.amber
            )

            if let account = commercial.stripeAccountID {
                Divider()
                detailRow("Stripe account", account, tone: Theme.secondary, monospaced: true)
            }

            Divider()
            detailRow(PlatformFeeCopy.rowTitle, commercial.platformFeeLabel, tone: Theme.ink)
        }
        .padding(.vertical, 2)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: 10))
    }

    private func detailRow(
        _ title: String,
        _ value: String,
        tone: Color,
        monospaced: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.footnote.weight(.semibold))
                .monospaced(monospaced)
                .foregroundStyle(tone)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
    }

    // MARK: - External provider

    private func externalSection(_ commercial: CommercialState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Or use your own provider").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "link")
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                        .frame(width: 34, height: 34)
                        .background(Theme.primaryTint)
                        .clipShape(.rect(cornerRadius: 9))

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Use my existing payment provider")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(commercial.paymentModel == .externalProvider
                             ? "This is your current choice"
                             : "Square, PayPal, your bank, your own portal")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }

                    Spacer(minLength: 0)

                    if commercial.paymentModel == .externalProvider {
                        StatusPill(badge: StatusBadge(text: "Selected", tone: .info))
                    }
                }

                Text("Keep using your existing payment provider and payment link. Your invoices show a Pay online button that sends your customer to your own payment page.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 0) {
                    detailRow(PlatformFeeCopy.rowTitle, "0%", tone: Theme.green)
                    Divider()
                    detailRow(
                        "Your payment link",
                        OnlinePaymentLink.displayHost(commercial.externalPaymentURL) ?? "Not set",
                        tone: commercial.externalPaymentURL == nil ? Theme.meta : Theme.ink
                    )
                }
                .padding(.vertical, 2)
                .background(Theme.canvas)
                .clipShape(.rect(cornerRadius: 10))

                if commercial.canManageBilling {
                    NavigationLink(value: AppRoute.more(.paymentLink)) {
                        BrandOutlineLabel(
                            title: commercial.externalPaymentURL == nil
                                ? "Add my payment link"
                                : "Edit my payment link",
                            symbol: "link"
                        )
                    }
                    .buttonStyle(PressableTileStyle())

                    if commercial.paymentModel != .externalProvider {
                        Button {
                            isConfirmingExternal = true
                        } label: {
                            BrandOutlineLabel(
                                title: "Use my own provider",
                                symbol: "checkmark.circle",
                                tint: Theme.secondary
                            )
                        }
                        .buttonStyle(PressableTileStyle())
                        .disabled(viewModel.isWorking)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    /// Where the money actually goes. Stated because it is the question a trade
    /// business most wants answered before connecting a bank account.
    private var boundaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Where the money goes").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 9) {
                boundaryRow(
                    "checkmark.circle.fill", Theme.green,
                    "Your customers' payments land in your own Stripe account, not in a Harbour South account."
                )
                boundaryRow(
                    "checkmark.circle.fill", Theme.green,
                    "Harbour South is never the merchant of record for your invoices."
                )
                boundaryRow(
                    "info.circle.fill", Theme.primary,
                    "Stripe's normal processing fees are charged to your connected account by Stripe."
                )
                boundaryRow(
                    "xmark.circle.fill", Theme.meta,
                    "Harbour South never asks for your Stripe keys, and stores no payment credentials."
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func boundaryRow(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tint)
                .padding(.top, 2)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func successBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(Theme.green)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.green.opacity(0.10))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Copy and colour

    private func symbol(for state: StripeConnectionState) -> String {
        switch state {
        case .notConnected: return "creditcard"
        case .setupIncomplete: return "list.bullet.clipboard"
        case .connected: return "checkmark.seal.fill"
        case .underReview: return "hourglass"
        case .restricted: return "exclamationmark.triangle.fill"
        }
    }

    private func tintColor(for state: StripeConnectionState) -> Color {
        switch state {
        case .notConnected: return Theme.primary
        case .setupIncomplete: return Theme.amber
        case .connected: return Theme.green
        case .underReview: return Theme.primary
        case .restricted: return Theme.red
        }
    }

    // MARK: - Actions

    private func runStripeAction(_ commercial: CommercialState) async {
        guard let session else { return }
        // Connected (or submitted and under review / restricted) opens the
        // account's own Stripe dashboard; otherwise Stripe's hosted setup is
        // resumed, which is the only thing that can move it forward.
        if commercial.stripeState.actionOpensDashboard(detailsSubmitted: commercial.detailsSubmitted) {
            await viewModel.openStripeDashboard(gateway: env.gateway, session: session)
        } else {
            await viewModel.startOnboarding(gateway: env.gateway, session: session)
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    NavigationStack {
        PaymentsIntegrationView()
            .environment(AppEnvironment())
    }
}
