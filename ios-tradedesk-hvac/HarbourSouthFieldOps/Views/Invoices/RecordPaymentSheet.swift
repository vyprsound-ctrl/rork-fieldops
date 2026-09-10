import SwiftUI

/// Records money the contractor has already received against an invoice.
///
/// Harbour South takes no payment here: this is a manual record, and `reference` is
/// whatever the person recording it writes down. The record the gateway writes
/// is flagged as simulated on the row itself in development builds — a
/// simulated payment is never presented as a real one.
struct RecordPaymentSheet: View {
    let invoiceNumber: String
    let currencyCode: String
    /// The most this payment may be for. Enforced by the data layer too.
    let outstanding: Decimal
    let outstandingLabel: String
    let onSave: (PaymentDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String = ""
    @State private var method: PaymentMethod = .card
    @State private var receivedAt: Date = Date()
    @State private var reference: String = ""
    @State private var note: String = ""
    @FocusState private var isAmountFocused: Bool

    private var amount: Decimal { Decimal(string: amountText.trimmed) ?? 0 }
    private var isOverPayment: Bool { amount > outstanding }
    private var remainingAfter: Decimal { Money.rounded(outstanding - amount) }

    private var canSave: Bool { amount > 0 && !isOverPayment }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Amount") {
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .focused($isAmountFocused)
                    }
                    Button("Pay the full \(outstandingLabel)") {
                        amountText = "\(outstanding)"
                    }
                    .font(.subheadline)
                    .tint(Theme.primary)
                } header: {
                    Text("Amount received")
                } footer: {
                    if isOverPayment {
                        Text("That's more than the \(outstandingLabel) outstanding on \(invoiceNumber). Record that amount or less — there's no refund or credit note in this build.")
                            .foregroundStyle(Theme.red)
                    } else if amount > 0 {
                        Text(remainingAfter > 0
                             ? "\(Formatters.currency(remainingAfter, code: currencyCode)) will still be outstanding."
                             : "This settles \(invoiceNumber) in full.")
                    } else {
                        Text("\(outstandingLabel) outstanding on \(invoiceNumber).")
                    }
                }

                Section("Method") {
                    Picker("Method", selection: $method) {
                        ForEach(PaymentMethod.allCases) { option in
                            Label(option.title, systemImage: option.symbolName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    DatePicker("Received", selection: $receivedAt, displayedComponents: .date)

                    LabeledContent("Reference") {
                        TextField(method.referencePrompt, text: $reference)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section("Note") {
                    TextField("Anything worth recording (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section {
                    HStack(spacing: 8) {
                        SimulatedBadge()
                        Text("Recorded by hand. Harbour South doesn't take the payment — it records that you received it, so the balance and status follow your own books.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }
            .navigationTitle("Record payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Record") {
                        onSave(
                            PaymentDraft(
                                amount: amount,
                                method: method,
                                receivedAt: receivedAt,
                                reference: reference.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                                note: note.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear { isAmountFocused = true }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    RecordPaymentSheet(
        invoiceNumber: "INV-1176",
        currencyCode: "USD",
        outstanding: Money.dec("477.98"),
        outstandingLabel: "$477.98"
    ) { _ in }
}
