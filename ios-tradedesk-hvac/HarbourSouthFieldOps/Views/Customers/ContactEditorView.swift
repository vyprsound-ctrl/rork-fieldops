import SwiftUI

/// Add or edit one person at a customer.
struct ContactEditorView: View {
    @State var draft: ContactDraft
    let onSave: (ContactDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { draft.id != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact") {
                    TextField("Name", text: $draft.name)
                        .textContentType(.name)
                    TextField("Role (optional)", text: $draft.contactRole)
                    TextField("Phone", text: $draft.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Email", text: $draft.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                }

                Section {
                    Toggle("Main contact", isOn: $draft.isPrimary)
                        .tint(Theme.primary)
                    Toggle("Billing contact", isOn: $draft.isBillingContact)
                        .tint(Theme.primary)
                } footer: {
                    Text("The main contact is who your field workers call from the doorstep. The billing contact is who invoices go to.")
                }
            }
            .navigationTitle(isEditing ? "Edit contact" : "New contact")
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
        }
        .presentationDetents([.large])
    }
}

#Preview {
    ContactEditorView(draft: ContactDraft()) { _ in }
}
