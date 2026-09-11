import SwiftUI

/// Settings → Business → Email & Invoicing.
///
/// THE PROBLEM THIS SOLVES: a customer who receives an invoice should see their
/// contractor, not the software their contractor uses. One address fixes that —
/// the one the business already gives out, `invoices@…` or `office@…`.
///
/// WHAT IT IS: a customer-facing reply identity. The invoice email is sent with
/// the business's name as the visible sender and this address as `Reply-To`, so
/// a customer's reply reaches the business directly.
///
/// WHAT IT IS DELIBERATELY NOT: an email-infrastructure setting. There is no
/// DNS record to add, no SPF or DKIM to configure, no SMTP host, no API key,
/// and no custom domain required to start using Harbour South. Delivery still
/// travels over Harbour South's own verified sending domain, because that is
/// the only domain whose authentication this product controls — sending as an
/// unverified domain would put invoices in spam folders.
///
/// The screen says all of that plainly rather than implying the business has
/// configured something it has not.
struct BusinessEmailView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = BusinessEmailViewModel()
    @FocusState private var isFieldFocused: Bool

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.margin)
                .padding(.top, 4)
                .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Email & Invoicing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFieldFocused = false }
            }
        }
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
            LoadingStateView(message: "Loading email settings")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await reload() } }
        case .loaded(let settings):
            loaded(settings)
        }
    }

    private func loaded(_ settings: BusinessEmailSettings) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            previewCard(settings)

            if settings.canManage {
                editor(settings)
            } else {
                readOnly(settings)
            }

            explainerCard
        }
    }

    /// What the customer will actually see at the top of their inbox. More
    /// convincing than a paragraph about reply identities.
    private func previewCard(_ settings: BusinessEmailSettings) -> some View {
        let name = settings.companyName.isEmpty ? "Your business" : settings.companyName
        let initial = String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()

        return VStack(alignment: .leading, spacing: 10) {
            Text("What your customer sees").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 11) {
                    Text(initial)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 42, height: 42)
                        .background(Theme.primary)
                        .clipShape(.rect(cornerRadius: 11))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Text(viewModel.draft.tidied.isEmpty
                             ? "Replies have no return address yet"
                             : "Reply to \(viewModel.draft.tidied)")
                            .font(.caption)
                            .foregroundStyle(
                                viewModel.draft.tidied.isEmpty ? Theme.amber : Theme.secondary
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 0)
                }

                Divider()

                VStack(alignment: .leading, spacing: 3) {
                    Text("Invoice INV-1042 from \(name) — $486.00 due")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                    Text("Your invoice, your logo, your contact details and a pay button.")
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

    private func editor(_ settings: BusinessEmailSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your customer-facing address").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 10) {
                TextField("invoices@yourbusiness.com", text: $viewModel.draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .focused($isFieldFocused)
                    .padding(12)
                    .background(Theme.canvas)
                    .clipShape(.rect(cornerRadius: 10))

                if let problem = viewModel.draftProblem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                } else if viewModel.draft.tidied.isEmpty {
                    Text("Leave it empty and your invoices are still sent — customers just won't have an address to reply to.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label("Replies go straight to you", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                }

                if let notice = viewModel.savedNotice {
                    Label(notice, systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .cardSurface()

            HStack(spacing: 10) {
                Button {
                    isFieldFocused = false
                    Task { await save() }
                } label: {
                    BrandButtonLabel(
                        title: viewModel.isWorking ? "Saving" : "Save address",
                        isEnabled: canSave,
                        isWorking: viewModel.isWorking
                    )
                }
                .buttonStyle(PressableTileStyle())
                .disabled(!canSave)

                if settings.isConfigured {
                    Button {
                        isFieldFocused = false
                        Task { await clear() }
                    } label: {
                        Text("Remove")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.red)
                            .frame(minWidth: 96, minHeight: Theme.minTap)
                            .cardSurface()
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(viewModel.isWorking)
                }
            }
        }
    }

    private var canSave: Bool {
        viewModel.isDirty && viewModel.draftProblem == nil && !viewModel.isWorking
    }

    private func readOnly(_ settings: BusinessEmailSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your customer-facing address").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 6) {
                Text(settings.email ?? "No address set")
                    .font(.footnote)
                    .foregroundStyle(settings.isConfigured ? Theme.ink : Theme.meta)
                    .lineLimit(2)
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

    /// The honest account of what is and is not configured here.
    private var explainerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How invoice email works").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 9) {
                row("checkmark.circle.fill", Theme.green,
                    "Your invoices are branded as your business — your name, your contact details, your invoice.")
                row("checkmark.circle.fill", Theme.green,
                    "Customers reply to your address, not to Harbour South.")
                row("info.circle.fill", Theme.primary,
                    "Delivery travels over Harbour South's verified sending domain, so your invoices arrive reliably from day one.")
                row("xmark.circle.fill", Theme.meta,
                    "No DNS, SPF, DKIM, SMTP or API keys to set up — and no custom domain needed to start.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            Text("Sending from your own authenticated domain is a later addition. When it arrives, this is the address it will use — nothing you set up now is wasted.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ symbol: String, _ tint: Color, _ text: String) -> some View {
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

    private func reload() async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session)
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
        BusinessEmailView()
            .environment(AppEnvironment())
    }
}
