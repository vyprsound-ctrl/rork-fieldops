import SwiftUI

/// Add or edit a customer.
///
/// A new customer needs a first service address, because a field-service
/// customer with nowhere to send anybody is not a customer yet — it is a name.
/// Editing does not ask for one again; sites are managed from the customer's
/// own screen, where they can have as many as they like.
struct CustomerEditorView: View {
    var existing: CustomerProfile?
    let onSaved: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CustomerEditorViewModel

    init(existing: CustomerProfile? = nil, onSaved: @escaping (String) -> Void) {
        self.existing = existing
        self.onSaved = onSaved
        _viewModel = State(
            initialValue: CustomerEditorViewModel(
                customerID: existing?.id,
                draft: existing?.draft ?? CustomerDraft()
            )
        )
    }

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    TextField("Name or business", text: $viewModel.draft.name)
                        .textContentType(.organizationName)

                    Picker("Type", selection: $viewModel.draft.type) {
                        ForEach(CustomerType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                }

                Section {
                    TextField("First name", text: $viewModel.draft.firstName)
                        .textContentType(.givenName)
                    TextField("Last name", text: $viewModel.draft.lastName)
                        .textContentType(.familyName)
                    TextField("Role on site (optional)", text: $viewModel.draft.contactRole)
                    TextField("Phone", text: $viewModel.draft.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Email", text: $viewModel.draft.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                } header: {
                    Text("Main contact")
                } footer: {
                    Text("Who your field workers call when they're outside. You can add more contacts from the customer's screen.")
                }

                if !viewModel.isEditing {
                    Section {
                        TextField("Street address", text: $viewModel.draft.line1)
                            .textContentType(.streetAddressLine1)
                        TextField("Apt, suite, unit (optional)", text: $viewModel.draft.line2)
                            .textContentType(.streetAddressLine2)
                        TextField("City", text: $viewModel.draft.city)
                            .textContentType(.addressCity)
                        HStack {
                            TextField("State", text: $viewModel.draft.state)
                                .textContentType(.addressState)
                                .textInputAutocapitalization(.characters)
                            Divider()
                            TextField("ZIP", text: $viewModel.draft.postalCode)
                                .keyboardType(.numbersAndPunctuation)
                                .textContentType(.postalCode)
                        }
                        TextField("Site access notes (optional)", text: $viewModel.draft.accessNotes, axis: .vertical)
                            .lineLimit(1...3)
                    } header: {
                        Text("First service address")
                    } footer: {
                        Text("Gate codes, parking, where the unit is — anything that saves a field worker ten minutes.")
                    }
                }

                Section {
                    TextField("Billing terms", text: $viewModel.draft.billingTerms)
                    TextField("Notes (optional)", text: $viewModel.draft.notes, axis: .vertical)
                        .lineLimit(1...5)
                } header: {
                    Text("Account")
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                    }
                }
            }
            .navigationTitle(viewModel.isEditing ? "Edit customer" : "New customer")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button(viewModel.isEditing ? "Save" : "Create") { save() }
                            .disabled(!viewModel.canSave)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let problem = viewModel.validationMessage {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Theme.margin)
                        .padding(.vertical, 10)
                        .background(.bar)
                }
            }
        }
    }

    private func save() {
        guard let session else { return }
        Task {
            let saved = await viewModel.save(gateway: env.gateway, session: session)
            if saved, let id = viewModel.savedCustomerID {
                onSaved(id)
                dismiss()
            }
        }
    }
}

#Preview {
    CustomerEditorView { _ in }
        .environment(AppEnvironment())
}
