import Foundation

/// One priced line on an invoice.
///
/// Identical in shape to `QuoteLineItem` and calculated by exactly the same
/// `Money` helpers, so a quote and the invoice raised from it can never
/// disagree by a cent. `taxRate` is stored per line: the company's default rate
/// seeds a new line and is never applied retrospectively to an existing one.
///
/// Descriptions are free text, which is what keeps the model trade-neutral —
/// "Condenser fan motor", "Consumer unit upgrade", "Ridge tile re-bed" and
/// "Rodent bait stations" are all just lines.
nonisolated struct InvoiceLineItem: Identifiable, Codable, Hashable, Sendable, MoneyLine {
    let id: String
    let companyID: String
    let invoiceID: String
    var itemDescription: String
    var quantity: Decimal
    var unitPrice: Decimal
    var taxRate: Decimal
    /// `quantity × unitPrice`, rounded to the cent.
    var lineTotal: Decimal
    var sortOrder: Int
    /// The quote line this was copied from, when the invoice was raised from a
    /// quote. A provenance record only — this line is an independent snapshot
    /// and is never re-read from the quote afterwards.
    var sourceQuoteLineItemID: String?

    init(
        id: String,
        companyID: String,
        invoiceID: String,
        itemDescription: String,
        quantity: Decimal,
        unitPrice: Decimal,
        taxRate: Decimal,
        lineTotal: Decimal,
        sortOrder: Int,
        sourceQuoteLineItemID: String? = nil
    ) {
        self.id = id
        self.companyID = companyID
        self.invoiceID = invoiceID
        self.itemDescription = itemDescription
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.taxRate = taxRate
        self.lineTotal = lineTotal
        self.sortOrder = sortOrder
        self.sourceQuoteLineItemID = sourceQuoteLineItemID
    }
}
