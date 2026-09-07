import Foundation

nonisolated struct QuoteLineItem: Identifiable, Codable, Hashable, Sendable, MoneyLine {
    let id: String
    let companyID: String
    let quoteID: String
    var itemDescription: String
    var quantity: Decimal
    var unitPrice: Decimal
    /// Stored as a decimal fraction (0.07 == 7%), never as a binary float.
    var taxRate: Decimal
    /// Always `Money.lineTotal(quantity:unitPrice:)`; stored so historical
    /// documents keep the figure they were sent with.
    var lineTotal: Decimal
    var sortOrder: Int
}
