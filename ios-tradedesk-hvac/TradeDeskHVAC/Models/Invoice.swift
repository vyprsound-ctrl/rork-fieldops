import Foundation

nonisolated enum InvoiceStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case draft
    case sent
    case viewed
    case partPaid
    case paid
    case overdue
    case void

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .viewed: return "Viewed"
        case .partPaid: return "Part paid"
        case .paid: return "Paid"
        case .overdue: return "Overdue"
        case .void: return "Void"
        }
    }

    var symbolName: String {
        switch self {
        case .draft: return "pencil.line"
        case .sent: return "paperplane.fill"
        case .viewed: return "eye.fill"
        case .partPaid: return "circle.lefthalf.filled"
        case .paid: return "checkmark.seal.fill"
        case .overdue: return "exclamationmark.triangle.fill"
        case .void: return "slash.circle.fill"
        }
    }

    var tone: StatusTone {
        switch self {
        case .draft: return .neutral
        case .sent, .viewed: return .info
        case .partPaid: return .warning
        case .paid: return .success
        case .overdue: return .danger
        case .void: return .neutral
        }
    }

    /// Line items may only be changed while the invoice is still a draft. Once
    /// it has been issued it is a financial document, not a working sheet.
    var isEditable: Bool { self == .draft }

    /// The invoice has been issued to the customer.
    var isIssued: Bool {
        switch self {
        case .draft, .void: return false
        default: return true
        }
    }

    /// Nothing further is owed on it.
    var isSettled: Bool { self == .paid || self == .void }

    /// Unknown values decode to `draft` rather than failing, so a status added
    /// server-side can never break an older client into showing money as paid.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InvoiceStatus(rawValue: raw) ?? .draft
    }
}

/// Allowed invoice status moves that a person may make directly.
///
/// Part paid, paid and overdue are deliberately absent: those are *derived*
/// from payments and the due date, never chosen by hand, so the money on the
/// document can't disagree with the payments recorded against it.
nonisolated enum InvoiceWorkflow {
    static func nextStatuses(from status: InvoiceStatus) -> [InvoiceStatus] {
        switch status {
        case .draft: return [.sent, .void]
        case .sent: return [.viewed, .void]
        case .viewed: return [.void]
        case .partPaid, .overdue: return []
        case .paid: return []
        case .void: return []
        }
    }

    static func actionTitle(for status: InvoiceStatus) -> String {
        switch status {
        case .draft: return "Back to draft"
        case .sent: return "Mark as sent"
        case .viewed: return "Mark as viewed"
        case .partPaid: return "Mark part paid"
        case .paid: return "Mark paid"
        case .overdue: return "Mark overdue"
        case .void: return "Void invoice"
        }
    }

    /// The status an invoice settles at for a given amount paid.
    ///
    /// Derived, never typed in: the payments decide. `void` is absorbing — a
    /// voided invoice is not dragged back to life by an old payment row.
    static func settledStatus(current: InvoiceStatus, total: Decimal, amountPaid: Decimal) -> InvoiceStatus {
        if current == .void { return .void }
        if total > 0, amountPaid >= total { return .paid }
        if amountPaid > 0 { return .partPaid }
        // Back to the issued state it was in before any payment landed.
        switch current {
        case .draft: return .draft
        case .viewed: return .viewed
        default: return .sent
        }
    }
}

/// A financial document: what the customer owes, as agreed at the moment it was
/// issued.
///
/// Everything needed to reproduce the document is stored **on** the invoice —
/// its currency, its payment terms, its line items and their tax rates. The
/// company record supplies the defaults when the invoice is raised and is never
/// consulted again, so changing the company's currency, tax rate or a
/// customer's terms later cannot alter a document that has already been issued.
///
/// The model is trade-neutral: an HVAC condenser replacement, a rewire, a roof
/// repair and a pest treatment are all just line items on this one shape.
nonisolated struct Invoice: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let customerID: String
    /// The contact the invoice is billed to, captured when it was raised.
    var billingContactID: String?
    /// Where the work was done. Optional — not every invoice has a site.
    var addressID: String?
    /// The job this invoice bills for, if it came from one.
    var jobID: String?
    /// The quote this invoice was priced from, if any. Retained even when the
    /// invoice was raised from a job that itself originated from that quote.
    var quoteID: String?
    var number: String
    var title: String
    /// The agreed work, snapshotted from the job or quote it came from.
    var scopeOfWork: String
    var status: InvoiceStatus

    /// The currency this invoice was **issued in**, snapshotted from the
    /// company. If the company later changes currency, this document keeps the
    /// one the customer agreed to.
    var currencyCode: String
    /// The agreed terms as free text ("Net 30", "Due on receipt", "50% on
    /// completion"). Snapshotted from the customer so later changes to their
    /// default terms don't rewrite an issued invoice.
    var paymentTermsLabel: String

    var issueDate: Date
    var dueDate: Date

    /// Derived from the line items by `Money.totals` — never edited directly.
    var subtotal: Decimal
    var tax: Decimal
    var total: Decimal
    /// Sum of succeeded payments. Never allowed to exceed `total`.
    var amountPaid: Decimal
    /// Always `total - amountPaid`.
    var balance: Decimal

    var createdByUserID: String?
    var sentAt: Date?
    var viewedAt: Date?
    var paidAt: Date?
    var voidedAt: Date?

    /// Past its due date with money still owed. Draft and settled invoices are
    /// never overdue.
    func isOverdue(asOf now: Date = Date()) -> Bool {
        guard status.isIssued, !status.isSettled else { return false }
        return balance > 0 && dueDate < now
    }

    /// The status to show. Overdue is computed from the due date rather than
    /// stored, so an invoice becomes overdue by the clock alone — no job needs
    /// to run — and a part payment still reads as part paid underneath.
    func effectiveStatus(asOf now: Date = Date()) -> InvoiceStatus {
        isOverdue(asOf: now) ? .overdue : status
    }

    /// Counts toward accounts receivable: issued, not settled, money still owed.
    func isReceivable(asOf now: Date = Date()) -> Bool {
        status.isIssued && !status.isSettled && balance > 0
    }
}
