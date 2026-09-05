import SwiftUI

/// Create a quote header. Line items are added on the quote itself, so the
/// totals are always derived from real lines rather than typed in.
struct QuoteEditorView: View {
    let onCreated: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var options: JobFormOptions = .empty
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    @State private var customerID: String = ""
    @State private var title: String = ""
    @State private var scopeOfWork: String = ""
    @State private var hasExpiry: Bool = true
    @State private var validUntil: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    private var session: TenantSession? { env.session }

    private var selectedCustomer: CustomerOption? {
        options.customers.first { $0.id == customerID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingStateView(message: "Loading customers")
                } else if options.customers.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbolName: "person.2.slash",
                            title: "No customers available",
                            message: "Quotes need a customer record to attach to."
                        )
                    }
                } else {
                    Form {
                        Section("Customer") {
                            Picker("Customer", selection: $customerID) {
                                ForEach(options.customers) { customer in
                                    Text(customer.name).tag(customer.id)
                                }
                            }
                            if let customer = selectedCustomer {
                                Text(customer.addressLine)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.secondary)
                            }
                        }

                        Section("Quote") {
                            TextField("Title", text: $title)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Scope of work")
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondary)
                                TextEditor(text: $scopeOfWork)
                                    .frame(minHeight: 100)
                                    .font(.subheadline)
                            }
                        }

                        Section("Validity") {
                            Toggle("Set a valid-until date", isOn: $hasExpiry)
                                .tint(Theme.primary)
                            if hasExpiry {
                                DatePicker("Valid until", selection: $validUntil, displayedComponents: .date)
                            }
                        }

                        Section {
                            Text("The quote is created as a draft. Add line items next — the subtotal, tax and total are calculated from them.")
                                .font(.footnote)
                                .foregroundStyle(Theme.meta)
                        }

                        if let errorMessage {
                            Section {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.red)
                            }
                        }
                    }
                }
            }
            .background(Theme.canvas)
            .navigationTitle("New quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
        }
        .task {
            guard let session else { return }
            options = (try? await env.gateway.jobFormOptions(session: session)) ?? .empty
            if customerID.isEmpty, let first = options.customers.first { customerID = first.id }
            isLoading = false
        }
    }

    private var canSave: Bool {
        selectedCustomer != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard let session, let customer = selectedCustomer else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let id = try await env.gateway.createQuote(
                    session: session,
                    input: NewQuoteInput(
                        customerID: customer.id,
                        addressID: customer.addressID,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        scopeOfWork: scopeOfWork.trimmingCharacters(in: .whitespacesAndNewlines),
                        validUntil: hasExpiry ? validUntil : nil
                    )
                )
                onCreated(id)
                dismiss()
            } catch {
                errorMessage = DataError.wrap(error).errorDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    QuoteEditorView { _ in }
        .environment(AppEnvironment())
}
