import SwiftUI

/// Register or edit a serviceable asset at one of the customer's sites.
///
/// The vocabulary follows the company's trade — "unit" for HVAC, "appliance",
/// "board" — so nothing here assumes a condenser.
struct EquipmentEditorView: View {
    @State var draft: EquipmentDraft
    let addresses: [CustomerAddressProjection]
    let assetTerm: String
    let onSave: (EquipmentDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { draft.id != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Site") {
                    Picker("Installed at", selection: $draft.addressID) {
                        ForEach(addresses) { address in
                            Text(address.line1).tag(address.id)
                        }
                    }
                    TextField("Where on site (optional)", text: $draft.location)
                }

                Section(assetTerm.capitalizedFirst) {
                    TextField("Type — condenser, boiler, board…", text: $draft.category)
                    TextField("Manufacturer", text: $draft.make)
                    TextField("Model", text: $draft.model)
                    TextField("Serial number", text: $draft.serialNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }

                Section("Dates") {
                    DatePicker("Installed", selection: $draft.installedOn, displayedComponents: .date)
                    Toggle("Under warranty", isOn: $draft.hasWarranty)
                        .tint(Theme.primary)
                    if draft.hasWarranty {
                        DatePicker("Warranty ends", selection: $draft.warrantyExpiresOn, displayedComponents: .date)
                    }
                }

                Section {
                    TextField("System notes", text: $draft.systemNotes, axis: .vertical)
                        .lineLimit(2...5)
                    Toggle("In service", isOn: $draft.isActive)
                        .tint(Theme.primary)
                } footer: {
                    Text("Turn this off when the unit is decommissioned. Its service history stays on the site.")
                }
            }
            .navigationTitle(isEditing ? "Edit \(assetTerm)" : "New \(assetTerm)")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.validationMessage != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let problem = draft.validationMessage {
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
}

#Preview {
    EquipmentEditorView(
        draft: EquipmentDraft(addressID: "adr_1"),
        addresses: [],
        assetTerm: "unit"
    ) { _ in }
}
