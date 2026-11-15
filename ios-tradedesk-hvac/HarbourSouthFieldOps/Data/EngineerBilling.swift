import Foundation

/// The two per-engineer financial grants an owner or admin can switch on.
///
/// They are stored in their own table and written only by a database function
/// that requires `usersManage` and refuses a self-edit, so an engineer can
/// never grant themselves either one.
nonisolated struct FinancialPermissions: Hashable, Sendable {
    var canInvoice: Bool
    var canCollectPayments: Bool

    static let none = FinancialPermissions(canInvoice: false, canCollectPayments: false)
}

/// One line on an invoice, as the engineer's billing card shows it.
nonisolated struct EngineerInvoiceLine: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let description: String
    let quantity: Decimal
    let unitPrice: Decimal
    let taxRate: Decimal
    let lineTotal: Decimal

    enum CodingKeys: String, CodingKey {
        case id, description, quantity
        case unitPrice = "unit_price"
        case taxRate = "tax_rate"
        case lineTotal = "line_total"
    }
}

/// The invoice raised against one of the engineer's own assigned jobs.
nonisolated struct EngineerInvoice: Identifiable, Hashable, Sendable, Decodable {
    let id: String
    let number: String
    let title: String?
    let status: InvoiceStatus
    let currencyCode: String
    let issueDate: String?
    let dueDate: String?
    let subtotal: Decimal
    let tax: Decimal
    let total: Decimal
    let amountPaid: Decimal
    let balance: Decimal
    let billingEmail: String
    let lines: [EngineerInvoiceLine]

    enum CodingKeys: String, CodingKey {
        case id, number, title, status, subtotal, tax, total, balance, lines
        case currencyCode = "currency_code"
        case issueDate = "issue_date"
        case dueDate = "due_date"
        case amountPaid = "amount_paid"
        case billingEmail = "billing_email"
    }

    var isDraft: Bool { status == .draft }

    /// Matches the server's own rule for handing out a payment link.
    var isOpenForPayment: Bool {
        [.sent, .viewed, .partPaid, .overdue].contains(status) && balance > 0
    }

    func money(_ value: Decimal) -> String {
        Formatters.currency(value, code: currencyCode.isEmpty ? "USD" : currencyCode)
    }
}

/// What an engineer may do with money on one job, and the invoice if there is
/// one. With neither grant the server returns both flags false and no invoice,
/// and the card simply isn't shown.
nonisolated struct EngineerJobBilling: Hashable, Sendable, Decodable {
    let canInvoice: Bool
    let canCollect: Bool
    let jobStatus: JobStatus?
    let invoice: EngineerInvoice?

    enum CodingKeys: String, CodingKey {
        case invoice
        case canInvoice = "can_invoice"
        case canCollect = "can_collect"
        case jobStatus = "job_status"
    }

    init(canInvoice: Bool, canCollect: Bool, jobStatus: JobStatus?, invoice: EngineerInvoice?) {
        self.canInvoice = canInvoice
        self.canCollect = canCollect
        self.jobStatus = jobStatus
        self.invoice = invoice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canInvoice = try container.decodeIfPresent(Bool.self, forKey: .canInvoice) ?? false
        canCollect = try container.decodeIfPresent(Bool.self, forKey: .canCollect) ?? false
        jobStatus = (try? container.decodeIfPresent(JobStatus.self, forKey: .jobStatus)) ?? nil
        invoice = try container.decodeIfPresent(EngineerInvoice.self, forKey: .invoice)
    }

    static let hidden = EngineerJobBilling(canInvoice: false, canCollect: false, jobStatus: nil, invoice: nil)

    var isVisible: Bool { canInvoice || canCollect }
}

// MARK: - Gateway surface

/// The development stack has no engineer billing; it answers plainly rather
/// than pretending, and the card stays hidden.
extension DataGateway {
    func setFinancialPermissions(
        session: TenantSession,
        userID: String,
        permissions: FinancialPermissions
    ) async throws {
        throw DataError.rejected(Self.billingUnavailable)
    }

    func engineerJobBilling(session: TenantSession, jobID: String) async throws -> EngineerJobBilling {
        .hidden
    }

    func engineerCreateInvoice(session: TenantSession, jobID: String) async throws -> String {
        throw DataError.rejected(Self.billingUnavailable)
    }

    func engineerSaveInvoiceLine(
        session: TenantSession,
        invoiceID: String,
        lineID: String?,
        description: String,
        quantity: Decimal,
        unitPrice: Decimal
    ) async throws {
        throw DataError.rejected(Self.billingUnavailable)
    }

    func engineerDeleteInvoiceLine(session: TenantSession, invoiceID: String, lineID: String) async throws {
        throw DataError.rejected(Self.billingUnavailable)
    }

    func engineerIssueInvoice(session: TenantSession, invoiceID: String) async throws {
        throw DataError.rejected(Self.billingUnavailable)
    }

    func engineerEmailInvoice(
        session: TenantSession,
        invoiceID: String,
        recipient: String
    ) async throws -> InvoiceSendOutcome {
        throw DataError.rejected(Self.billingUnavailable)
    }

    func engineerPaymentLink(session: TenantSession, invoiceID: String) async throws -> String {
        throw DataError.rejected(Self.billingUnavailable)
    }

    fileprivate static var billingUnavailable: String {
        "Invoicing from the field works against the live database. Sign in with your company account to use this."
    }
}
