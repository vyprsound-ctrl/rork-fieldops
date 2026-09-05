import Foundation

/// Quick filter chips for the invoice list. Each maps to a rule the gateway
/// applies *after* the tenant and role gates, never instead of them.
nonisolated enum InvoiceListFilter: String, CaseIterable, Sendable, Identifiable {
    case outstanding
    case overdue
    case dueThisWeek
    case draft
    case paid
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .outstanding: return "Outstanding"
        case .overdue: return "Overdue"
        case .dueThisWeek: return "Due this week"
        case .draft: return "Drafts"
        case .paid: return "Paid"
        case .all: return "All"
        }
    }

    func matches(_ invoice: Invoice, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .outstanding:
            return invoice.isReceivable(asOf: now)
        case .overdue:
            return invoice.isOverdue(asOf: now)
        case .dueThisWeek:
            return invoice.isReceivable(asOf: now) && Self.isDueWithinAWeek(invoice, now: now, calendar: calendar)
        case .draft:
            return invoice.status == .draft
        case .paid:
            return invoice.status == .paid
        }
    }

    /// Due from now up to seven days out. Already-overdue invoices are counted
    /// under "overdue" instead, so the two figures never double-count.
    static func isDueWithinAWeek(_ invoice: Invoice, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let horizon = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) else { return false }
        return invoice.dueDate >= now && invoice.dueDate <= horizon
    }
}

/// Date scope for invoice lists and the receivables view, applied to the issue
/// date.
nonisolated enum InvoiceDateScope: String, CaseIterable, Sendable, Identifiable {
    case last30Days
    case last90Days
    case thisYear
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .last30Days: return "Last 30 days"
        case .last90Days: return "Last 90 days"
        case .thisYear: return "This year"
        case .all: return "All time"
        }
    }

    func matches(_ invoice: Invoice, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .last30Days:
            guard let from = calendar.date(byAdding: .day, value: -30, to: now) else { return true }
            return invoice.issueDate >= from
        case .last90Days:
            guard let from = calendar.date(byAdding: .day, value: -90, to: now) else { return true }
            return invoice.issueDate >= from
        case .thisYear:
            return calendar.component(.year, from: invoice.issueDate) == calendar.component(.year, from: now)
        }
    }
}

/// Everything the invoice list and the receivables screen can be narrowed by.
nonisolated struct InvoiceQuery: Hashable, Sendable {
    var filter: InvoiceListFilter = .outstanding
    var dateScope: InvoiceDateScope = .all
    var customerID: String?
    /// Matches invoice number, customer name or invoice title.
    var searchText: String = ""

    static let outstanding = InvoiceQuery()

    var refinementCount: Int {
        var count = 0
        if customerID != nil { count += 1 }
        if dateScope != .all { count += 1 }
        return count
    }

    var hasRefinements: Bool { refinementCount > 0 }

    mutating func clearRefinements() {
        customerID = nil
        dateScope = .all
    }
}

// MARK: - Write payloads

/// A line item to add or update on an invoice. Mirrors `QuoteLineItemDraft` so
/// both documents are priced by exactly the same code path.
nonisolated struct InvoiceLineItemDraft: Hashable, Sendable, MoneyLine {
    /// `nil` creates a new line; an existing id edits that line in place.
    var id: String?
    var itemDescription: String
    var quantity: Decimal
    var unitPrice: Decimal
    var taxRate: Decimal
}

/// Payload for raising an invoice from scratch. `companyID` is absent on
/// purpose — the gateway takes it from the session.
nonisolated struct NewInvoiceInput: Hashable, Sendable {
    var customerID: String
    var addressID: String?
    var title: String
    var scopeOfWork: String = ""
    /// Nil lets the gateway fall back to the customer's own billing terms.
    var paymentTermsLabel: String?
    var issueDate: Date = Date()
    /// Nil lets the gateway derive the due date from the payment terms.
    var dueDate: Date?
}

/// Options chosen when raising an invoice from a completed job or an accepted
/// quote.
nonisolated struct InvoiceConversionInput: Hashable, Sendable {
    var paymentTermsLabel: String?
    var issueDate: Date = Date()
    var dueDate: Date?
    /// Copy the source document's priced lines onto the invoice. When false the
    /// invoice is raised empty and priced by hand.
    var copyLineItems: Bool = true
    /// Advance the linked job to "Invoiced" as a recorded workflow transition.
    var advanceJobStatus: Bool = true
}

/// A payment being recorded against an invoice.
nonisolated struct PaymentDraft: Hashable, Sendable {
    var amount: Decimal
    var method: PaymentMethod = .card
    var receivedAt: Date = Date()
    var reference: String?
    var note: String?
}

// MARK: - Source pickers

/// A completed job or accepted quote that can still be turned into an invoice.
/// Already-invoiced sources are excluded by the gateway, which is what stops
/// the same source being billed twice from the UI.
nonisolated struct InvoiceSourceOption: Identifiable, Hashable, Sendable {
    let id: String
    let number: String
    let title: String
    let customerName: String
    let dateLabel: String
    /// Nil for roles that may raise invoices but not read the source's money.
    let valueLabel: String?
    let lineItemCount: Int
}

nonisolated struct InvoiceSourceOptions: Hashable, Sendable {
    let completedJobs: [InvoiceSourceOption]
    let acceptedQuotes: [InvoiceSourceOption]
    let canCreate: Bool

    static let empty = InvoiceSourceOptions(completedJobs: [], acceptedQuotes: [], canCreate: false)

    var isEmpty: Bool { completedJobs.isEmpty && acceptedQuotes.isEmpty }
}
