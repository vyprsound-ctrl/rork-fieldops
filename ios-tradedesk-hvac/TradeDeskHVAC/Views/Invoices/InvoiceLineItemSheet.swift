import SwiftUI

/// Add or edit one invoice line. Amounts are typed as text and parsed into
/// exact decimals — the app never converts money through a binary float.
///
/// Deliberately identical in behaviour to `QuoteLineItemSheet`: a quote line and
/// an invoice line are priced by the same rules, so the two documents can never
/// disagree by a cent.
struct InvoiceLineItemSheet: View {
    let existing: InvoiceLineItemProjection?
    /// The company's current default rate, applied to a **new** line only.
    /// Editing an existing line always starts from the rate stored against it.
    let defaultTaxRate: Decimal
    /// The currency this invoice was issued in — this sheet never assumes one.
    let currencyCode: String
    let onSave: (InvoiceLineItemDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var itemDescription: String = ""
    @State private var quantityText: String = "1"
    @State private var unitPriceText: String = ""
    @State private var taxRateText: String = "0"
    @FocusState private var isDescriptionFocused: Bool

    private var quantity: Decimal { Decimal(string: quantityText.trimmed) ?? 0 }
    private var unitPrice: Decimal { Decimal(string: unitPriceText.trimmed) ?? 0 }
    private var taxRate: Decimal { Money.percent(taxRateText.trimmed.isEmpty ? "0" : taxRateText.trimmed) }

    private var lineTotal: Decimal { Money.lineTotal(quantity: quantity, unitPrice: unitPrice) }
    private var lineTax: Decimal { Money.lineTax(lineTotal: lineTotal, taxRate: taxRate) }

    private var canSave: Bool {
        !itemDescription.trimmed.isEmpty && quantity > 0 && unitPrice >= 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Description") {
                    TextField("What is this line for?", text: $itemDescription, axis: .vertical)
                        .lineLimit(1...3)
                        .focused($isDescriptionFocused)
                }

                Section("Amounts") {
                    LabeledContent("Quantity") {
                        TextField("1", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    LabeledContent("Unit price") {
                        TextField("0.00", text: $unitPriceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    LabeledContent("Tax rate %") {
                        TextField("0", text: $taxRateText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                }

                Section("This line") {
                    LabeledContent("Line total") {
                        Text(Formatters.currency(lineTotal, code: currencyCode))
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(Theme.ink)
                    }
                    LabeledContent("Tax on this line") {
                        Text(Formatters.currency(lineTax, code: currencyCode))
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondary)
                    }
                    Text("Quantity × unit price, rounded to the cent. The tax rate is stored on this line, so a later change to the company default won't alter this invoice.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }
            .navigationTitle(existing == nil ? "Add line item" : "Edit line item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            InvoiceLineItemDraft(
                                id: existing?.id,
                                itemDescription: itemDescription.trimmed,
                                quantity: quantity,
                                unitPrice: unitPrice,
                                taxRate: taxRate
                            )
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear(perform: prime)
        }
        .presentationDetents([.large])
    }

    private func prime() {
        if let existing {
            itemDescription = existing.itemDescription
            quantityText = Money.quantityLabel(existing.quantity)
            if let pricing = existing.pricing {
                unitPriceText = "\(pricing.unitPrice)"
                taxRateText = "\(Money.rounded(pricing.taxRate * 100, scale: 3))"
            }
        } else {
            taxRateText = "\(Money.rounded(defaultTaxRate * 100, scale: 3))"
            isDescriptionFocused = true
        }
    }
}

#Preview {
    InvoiceLineItemSheet(existing: nil, defaultTaxRate: Money.percent("7"), currencyCode: "USD") { _ in }
}
