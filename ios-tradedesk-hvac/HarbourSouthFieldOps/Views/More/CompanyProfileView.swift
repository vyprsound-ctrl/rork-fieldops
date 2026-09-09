import SwiftUI

/// The company's own details, as customers see them.
///
/// Everything here appears on a quote or an invoice, which is why it is worth a
/// screen rather than a settings row that does nothing. Three fields are shown
/// but deliberately not editable — trade, country and currency — because each
/// one reaches backwards: trade decides what a field worker is called
/// throughout the app, country decides address shape and distance units, and
/// currency formats every money label ever written. Changing them after
/// documents exist would silently re-label history, so they are stated and
/// left alone.
///
/// The tax rate is a **default** for new line items. Existing quotes and
/// invoices keep the rate that applied when they were raised.
struct CompanyProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<CompanyProfileSettings> = .idle
    @State private var draft: CompanyProfileSettings?
    @State private var isSaving = false
    @State private var actionError: String?
    @State private var confirmation: String?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, phone, addressLine, city, state, postalCode, taxRate
    }

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Company profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
            }
        }
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
            LoadingStateView(message: "Loading company details")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await load() } }
        case .loaded(let settings):
            if draft != nil {
                loaded(settings)
            } else {
                LoadingStateView(message: "Loading company details")
            }
        }
    }

    @ViewBuilder
    private func loaded(_ settings: CompanyProfileSettings) -> some View {
        let binding = Binding<CompanyProfileSettings>(
            get: { draft ?? settings },
            set: { draft = $0 }
        )

        VStack(alignment: .leading, spacing: 20) {
            if let confirmation {
                banner(confirmation)
            }

            headerCard(binding.wrappedValue)

            fieldGroup(
                title: "Business details",
                footnote: "This name and number appear at the top of every quote and invoice you send."
            ) {
                labelledField("Company name", text: binding.name, field: .name)
                    .textInputAutocapitalization(.words)
                Divider().padding(.leading, 14)
                labelledField("Phone", text: binding.phone, field: .phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }

            fieldGroup(
                title: "Address",
                footnote: "Where your business is based. Shown on documents, not used for scheduling."
            ) {
                labelledField("Street", text: binding.addressLine, field: .addressLine)
                    .textContentType(.streetAddressLine1)
                Divider().padding(.leading, 14)
                labelledField("City", text: binding.city, field: .city)
                    .textContentType(.addressCity)
                Divider().padding(.leading, 14)
                HStack(spacing: 0) {
                    labelledField("State", text: binding.state, field: .state)
                        .textContentType(.addressState)
                        .frame(maxWidth: .infinity)
                    Divider().frame(height: 30)
                    labelledField("ZIP", text: binding.postalCode, field: .postalCode)
                        .keyboardType(.numbersAndPunctuation)
                        .textContentType(.postalCode)
                        .frame(maxWidth: .infinity)
                }
            }

            taxSection(binding)

            fixedFactsCard(settings)

            if settings.canManage {
                saveButton(binding.wrappedValue)
            } else {
                Text("Your role can see the company profile but not change it. Ask an owner or admin to update these details.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 4)
        .disabled(!settings.canManage)
    }

    private func headerCard(_ profile: CompanyProfileSettings) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("As it appears on documents")
                .font(.caption)
                .foregroundStyle(Theme.meta)
            Text(profile.name.isEmpty ? "Unnamed company" : profile.name)
                .font(.title3.weight(.bold))
                .foregroundStyle(profile.name.isEmpty ? Theme.meta : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !profile.addressSummary.isEmpty {
                Text(profile.addressSummary)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !profile.phone.isEmpty {
                Text(profile.phone)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func taxSection(_ binding: Binding<CompanyProfileSettings>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Default tax rate").sectionLabelStyle()

            HStack(spacing: 12) {
                TextField(
                    "0",
                    value: binding.defaultTaxRatePercent,
                    format: .number.precision(.fractionLength(0...3))
                )
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: .taxRate)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)

                Text("%")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.secondary)

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            Text("Applied to new quote and invoice lines. Every line already written keeps the rate it was raised with, so changing this never alters an existing document.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The three settings that cannot be edited, and why.
    private func fixedFactsCard(_ settings: CompanyProfileSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Set when the company was created").sectionLabelStyle()

            VStack(spacing: 0) {
                factRow("Trade", settings.trade.title, "Decides what your field staff are called throughout the app.")
                Divider().padding(.leading, 14)
                factRow("Country", settings.countryCode, "Sets address format and distance units.")
                Divider().padding(.leading, 14)
                factRow("Currency", settings.currencyCode, "Formats every amount in the app and on your documents.")
            }
            .cardSurface()

            Text("These are fixed because changing them would re-label quotes and invoices you have already sent. Contact support if one of them is genuinely wrong.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func factRow(_ title: String, _ value: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondary)
        }
        .padding(14)
    }

    private func fieldGroup<Content: View>(
        title: String,
        footnote: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).sectionLabelStyle()
            VStack(spacing: 0) { content() }
                .cardSurface()
            Text(footnote)
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func labelledField(_ label: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.meta)
                .textCase(.uppercase)
            TextField(label, text: text)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .focused($focusedField, equals: field)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: Theme.minTap, alignment: .leading)
    }

    private func saveButton(_ profile: CompanyProfileSettings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // The reason a save would be refused is shown before it is
            // attempted, rather than as an error after the fact.
            if let problem = profile.validationError {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await save(profile) }
            } label: {
                HStack(spacing: 8) {
                    if isSaving { ProgressView().controlSize(.small).tint(.white) }
                    Text(isSaving ? "Saving" : "Save company details")
                        .font(.headline)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(profile.validationError == nil ? Theme.primary : Theme.meta)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(PressableTileStyle())
            .disabled(isSaving || profile.validationError != nil)
        }
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
            let settings = try await env.gateway.companyProfile(session: session)
            draft = settings
            state = .loaded(settings)
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    private func save(_ profile: CompanyProfileSettings) async {
        guard let session else { return }
        focusedField = nil
        isSaving = true
        actionError = nil
        confirmation = nil
        do {
            try await env.gateway.updateCompanyProfile(session: session, profile: profile)
            confirmation = "Company details updated."
            await load()
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isSaving = false
    }
}

#Preview {
    NavigationStack {
        CompanyProfileView()
            .environment(AppEnvironment())
    }
}
