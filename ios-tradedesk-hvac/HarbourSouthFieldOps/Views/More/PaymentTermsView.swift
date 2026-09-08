import SwiftUI

/// The company's default payment terms.
///
/// Two things matter here and both are easy to get wrong:
///
/// 1. "Due on completion" is a *rule*, not a horizon. The invoice is due the
///    day the work finished, not a number of days after it was raised. Every
///    other option counts days from the issue date.
/// 2. This is only a **default**. An individual invoice can still override it,
///    because a commercial customer on 60-day terms does not change what the
///    rest of the book is on.
struct PaymentTermsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<PaymentTermsSettings> = .idle
    @State private var option: PaymentTermOption = .net30
    @State private var customDays: Int = 30
    @State private var isSaving = false
    @State private var actionError: String?
    @State private var confirmation: String?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .navigationTitle("Payment terms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.userID) { await load() }
        .alert(
            "Could not save",
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingStateView(message: "Loading terms")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await load() } }
        case .loaded(let settings):
            loaded(settings)
        }
    }

    private func loaded(_ settings: PaymentTermsSettings) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let confirmation {
                banner(confirmation)
            }

            currentCard

            VStack(alignment: .leading, spacing: 8) {
                Text("Default for new invoices")
                    .sectionLabelStyle()

                VStack(spacing: 0) {
                    ForEach(Array(PaymentTermOption.allCases.enumerated()), id: \.element.rawValue) { index, term in
                        Button {
                            guard settings.canManage else { return }
                            option = term
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: option == term ? "largecircle.fill.circle" : "circle")
                                    .font(.footnote)
                                    .foregroundStyle(option == term ? Theme.primary : Theme.meta)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(term.label)
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.ink)
                                    if term == .onCompletion {
                                        Text("Due the day the job is finished")
                                            .font(.caption)
                                            .foregroundStyle(Theme.meta)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: 48)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(!settings.canManage)

                        if index < PaymentTermOption.allCases.count - 1 {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
                .cardSurface()

                if option == .custom {
                    Stepper(value: $customDays, in: 0...365) {
                        Text(customDays == 0 ? "Due on receipt" : "Due in \(customDays) days")
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    }
                    .padding(14)
                    .cardSurface()
                    .disabled(!settings.canManage)
                }
            }

            if settings.canManage {
                saveButton
            } else {
                Text("Your role can see the company's terms but not change them.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }

            Text("This is the starting point for new invoices. Any single invoice can still be set to different terms when it is raised.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Currently")
                .font(.caption)
                .foregroundStyle(Theme.meta)
            Text(option == .custom ? PaymentTermOption.custom.storedLabel(customDays: customDays) : option.label)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(exampleLine)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// A worked example beats a definition. It also makes the "on completion"
    /// rule obvious without a paragraph explaining it.
    private var exampleLine: String {
        let reference = Date()
        let due = option.dueDate(from: reference, customDays: customDays)
        if option == .onCompletion {
            return "A job finished today would be due today."
        }
        return "An invoice raised today would be due \(Formatters.shortDate(due))."
    }

    private var saveButton: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving { ProgressView().controlSize(.small).tint(.white) }
                Text(isSaving ? "Saving" : "Save default")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
            .background(Theme.primary)
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(PressableTileStyle())
        .disabled(isSaving)
    }

    private func banner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.green)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.green.opacity(0.10))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func load() async {
        guard let session else { return }
        state = .loading
        do {
            let settings = try await env.gateway.paymentTermsSettings(session: session)
            option = settings.option
            customDays = settings.customDays
            state = .loaded(settings)
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    private func save() async {
        guard let session else { return }
        isSaving = true
        actionError = nil
        do {
            try await env.gateway.updatePaymentTerms(
                session: session,
                option: option,
                customDays: customDays
            )
            confirmation = "Default payment terms updated."
            await load()
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isSaving = false
    }
}
