import SwiftUI

/// Add or edit one service address.
struct AddressEditorView: View {
    @State var draft: AddressDraft
    let onSave: (AddressDraft) -> Void

    @Environment(\.dismiss) private var dismiss

    private var isEditing: Bool { draft.id != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Address") {
                    TextField("Street address", text: $draft.line1)
                        .textContentType(.streetAddressLine1)
                    TextField("Apt, suite, unit (optional)", text: $draft.line2)
                        .textContentType(.streetAddressLine2)
                    TextField("City", text: $draft.city)
                        .textContentType(.addressCity)
                    HStack {
                        TextField("State", text: $draft.state)
                            .textContentType(.addressState)
                            .textInputAutocapitalization(.characters)
                        Divider()
                        TextField("ZIP", text: $draft.postalCode)
                            .keyboardType(.numbersAndPunctuation)
                            .textContentType(.postalCode)
                    }
                }

                Section {
                    TextField("Access notes", text: $draft.accessNotes, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("On site")
                } footer: {
                    Text("Gate codes, parking, key safe, which door — whatever the engineer needs before they arrive.")
                }
            }
            .navigationTitle(isEditing ? "Edit site" : "New site")
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
    AddressEditorView(draft: AddressDraft()) { _ in }
}
