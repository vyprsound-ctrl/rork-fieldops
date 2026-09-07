import Foundation

/// The customer-facing link for one invoice.
///
/// The token *is* the address. Nothing identifying is in the URL — no company,
/// customer or invoice id, and no invoice number — so the page cannot be found
/// by guessing, walking a sequence, or reading the link over someone's
/// shoulder and editing it.
///
/// A link can be revoked (the URL stops working immediately) or rotated
/// (the old URL dies, a new one is issued). Revoked rows are kept so the
/// history of who could see what stays intact.
nonisolated struct InvoiceShareToken: Identifiable, Hashable, Sendable {
    let id: String
    let companyID: String
    let invoiceID: String
    let token: String
    let createdByUserID: String
    let createdAt: Date
    var revokedAt: Date?
    var lastViewedAt: Date?
    var viewCount: Int

    var isActive: Bool { revokedAt == nil }
}
