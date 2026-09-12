import SwiftUI

/// Creates or edits one recurring service arrangement.
///
/// Deliberately small. A maintenance contract in a trades business is "this
/// customer, this site, this often, starting then" — anything more elaborate is
/// a scheduling product, not a field-service app.
struct RecurringServiceEditorView: View {
    @State var draft: RecurringServiceDraft
    let options: JobFormOptions
    /// Returns true when the save succeeded, so the sheet only closes on success.
    let onSave: (RecurringServiceDraft) async -> Bool

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

    private var terms: Terminology { env.terms }

    private var selectedCustomer: CustomerOption? {
        options.customers.first { $0.id == draft.customerID }
    }

    private var sites: [CustomerSiteOption] {
        selectedCustomer?.selectableSites ?? []
    }

    private var equipmentOptions: [EquipmentOption] {
        selectedCustomer?.site(draft.addressID)?.equipment ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                if options.customers.isEmpty {
                    Section {
                        Text("Add a customer first. A recurring visit has to belong to somebody.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                } else {
                    customerSection
                    scheduleSection
                    detailSection
                    statusSection
                }

                if let message = draft.validationMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Theme.amber)
                    }
                }
            }
            .navigationTitle(draft.id == nil ? "New recurring visit" : "Edit recurring visit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(draft.validationMessage != nil)
                    }
                }
            }
        }
    }

    private var customerSection: some View {
        Section("Customer and site") {
            Picker("Customer", selection: $draft.customerID) {
                Text("Choose").tag("")
                ForEach(options.customers) { customer in
                    Text(customer.name).tag(customer.id)
                }
            }
            .onChange(of: draft.customerID) { _, _ in
                // A site belongs to exactly one customer, so changing the
                // customer must invalidate the site and anything under it —
                // otherwise a visit gets booked at the previous customer's
                // address.
                draft.addressID = sites.first?.id ?? ""
                draft.equipmentID = nil
            }

            if !sites.isEmpty {
                Picker("Site", selection: $draft.addressID) {
                    Text("Choose").tag("")
                    ForEach(sites) { site in
                        Text(site.line).tag(site.id)
                    }
                }
                .onChange(of: draft.addressID) { _, _ in
                    draft.equipmentID = nil
                }
            }

            if !equipmentOptions.isEmpty {
                Picker(terms.Asset, selection: Binding(
                    get: { draft.equipmentID ?? "" },
                    set: { draft.equipmentID = $0.isEmpty ? nil : $0 }
                )) {
                    Text("Not specific").tag("")
                    ForEach(equipmentOptions) { item in
                        Text(item.name).tag(item.id)
                    }
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section("How often") {
            Picker("Frequency", selection: $draft.frequency) {
                ForEach(ServiceFrequency.allCases, id: \.rawValue) { frequency in
                    Text(frequency.title).tag(frequency)
                }
            }

            if draft.frequency == .custom {
                Stepper(value: $draft.intervalDays, in: 1...730) {
                    Text("Every \(draft.intervalDays) days")
                        .monospacedDigit()
                }
            }

            DatePicker(
                "First visit due",
                selection: $draft.nextDueDate,
                displayedComponents: .date
            )
        }
    }

    private var detailSection: some View {
        Section("What happens") {
            TextField("Name, e.g. Annual service", text: $draft.title)
                .textInputAutocapitalization(.sentences)

            Picker("Job type", selection: $draft.kind) {
                ForEach(JobKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }

            TextField("Notes for the field worker", text: $draft.description, axis: .vertical)
                .lineLimit(2...5)
                .textInputAutocapitalization(.sentences)
        }
    }

    private var statusSection: some View {
        Section {
            Toggle("Active", isOn: $draft.isActive)
        } footer: {
            Text(draft.isActive
                 ? "Visits are booked automatically as each one falls due."
                 : "Paused. Nothing will be booked until this is switched back on.")
        }
    }

    private func save() async {
        isSaving = true
        let ok = await onSave(draft)
        isSaving = false
        if ok { dismiss() }
    }
}
