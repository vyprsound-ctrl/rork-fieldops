import SwiftUI

/// MODEL B — the company's own payment provider.
///
/// Reached from Settings → Integrations → Payments, not from the top level:
/// supplying a link is one of two payment models now, and no longer the
/// headline way to take money. `PaymentsIntegrationView` is where the choice
/// between this and Harbour South Payments is made.
///
/// This screen sets one thing: a URL. There is no processor to connect, no
/// account to authorise and no credential to store, because with this model
/// Harbour South is never a party to the customer's payment — the money goes
/// straight from their customer to them, through whatever provider they
/// already use, and Harbour South takes no transaction fee on it.
struct PaymentLinkView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = PaymentLinkViewModel()
    @FocusState private var isFieldFocused: Bool

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("My payment link")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.userID) { await reload() }
        .alert(
            "Couldn't save that",
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
            LoadingStateView(message: "Loading payment settings")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let settings):
            loaded(settings)
        }
    }

    private func loaded(_ settings: PaymentLinkSettings) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explainer

                if settings.canManage {
                    editor(settings)
                } else {
                    readOnly(settings)
                }

                boundary
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.footnote)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 34, height: 34)
                    .background(Theme.primaryTint)
                    .clipShape(.rect(cornerRadius: 9))
                Text("Where your customers pay you")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            Text("Using your own payment provider? Paste its payment page link — Square, PayPal, your bank, your own portal. It's shown as a Pay online button on the invoice your customer opens, and Harbour South charges no transaction fee on it.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func editor(_ settings: PaymentLinkSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment link").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 10) {
                TextField("https://…", text: $viewModel.draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .font(.subheadline)
                    .focused($isFieldFocused)
                    .padding(12)
                    .background(Theme.canvas)
                    .clipShape(.rect(cornerRadius: 10))

                if let problem = viewModel.draftProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let host = OnlinePaymentLink.displayHost(viewModel.draft.trimmed) {
                    Label("Customers will be sent to \(host)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                } else {
                    Text("Must start with https://. Leave it empty and no payment button is shown at all.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let notice = viewModel.savedNotice {
                    Label(notice, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.green)
                }
            }
            .padding(14)
            .cardSurface()

            HStack(spacing: 10) {
                Button {
                    isFieldFocused = false
                    Task { await save() }
                } label: {
                    Text(viewModel.isWorking ? "Saving…" : "Save link")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .background(canSave ? Theme.primary : Theme.meta.opacity(0.4))
                        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)

                if settings.isConfigured {
                    Button {
                        isFieldFocused = false
                        Task { await clear() }
                    } label: {
                        Text("Clear")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.red)
                            .frame(minWidth: 92, minHeight: Theme.minTap)
                            .cardSurface()
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isWorking)
                }
            }
        }
    }

    private var canSave: Bool {
        viewModel.isDirty && viewModel.draftProblem == nil && !viewModel.isWorking
    }

    private func readOnly(_ settings: PaymentLinkSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment link").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.url ?? "No payment link configured")
                    .font(.footnote)
                    .monospaced()
                    .foregroundStyle(settings.isConfigured ? Theme.ink : Theme.meta)
                    .lineLimit(3)
                    .truncationMode(.middle)

                Text("Only an owner or admin can change this.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private var boundary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What Harbour South does with it").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 9) {
                boundaryRow("checkmark.circle.fill", Theme.green, "Shows it as a button on the invoice your customer opens.")
                boundaryRow("checkmark.circle.fill", Theme.green, "Charges no Harbour South transaction fee on these payments.")
                boundaryRow("xmark.circle.fill", Theme.meta, "Doesn't take, hold, route or refund the payment.")
                boundaryRow("xmark.circle.fill", Theme.meta, "Doesn't connect to your payment provider, and stores no keys or account details.")
                boundaryRow("xmark.circle.fill", Theme.meta, "Doesn't know whether your customer paid. Record the payment here when the money reaches you.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            // The alternative, stated once so this screen is not a dead end
            // for somebody who would rather take cards through Harbour South.
            Text("Prefer customers to pay by card and have it settle itself? Connect Stripe under Settings → Integrations → Payments.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Actions

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }

    private func save() async {
        guard let session else { return }
        await viewModel.save(gateway: env.gateway, session: session)
    }

    private func clear() async {
        guard let session else { return }
        await viewModel.clear(gateway: env.gateway, session: session)
    }
}

#Preview {
    NavigationStack {
        PaymentLinkView()
            .environment(AppEnvironment())
    }
}
