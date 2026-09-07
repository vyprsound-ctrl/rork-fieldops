import Foundation

// Rows for the document and money surfaces.
//
// Every `numeric` column is requested as `::text` and parsed with
// `SupabaseCoding.decimal`, so money never round-trips through a binary double.
// `company_id` is deliberately never selected: RLS has already proved each row
// belongs to the caller's company, and the value used by the app comes from the
// authenticated session instead of the payload.

/// The priced quote row, from the base table. Reachable only with
/// `quoteFinancialsRead` — every other role gets zero rows from RLS.
nonisolated struct QuoteRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let addressID: UUID
    let number: String
    let title: String
    let scopeOfWork: String?
    let status: QuoteStatus
    let subtotal: String?
    let tax: String?
    let total: String?
    let validUntil: Date?
    let createdAt: Date
    let sentAt: Date?
    let viewedAt: Date?
    let acceptedAt: Date?
    let declinedAt: Date?
    let convertedJobID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, number, title, status, subtotal, tax, total
        case customerID = "customer_id"
        case addressID = "address_id"
        case scopeOfWork = "scope_of_work"
        case validUntil = "valid_until"
        case createdAt = "created_at"
        case sentAt = "sent_at"
        case viewedAt = "viewed_at"
        case acceptedAt = "accepted_at"
        case declinedAt = "declined_at"
        case convertedJobID = "converted_job_id"
    }

    static let columns = """
    id,customer_id,address_id,number,title,scope_of_work,status,subtotal::text,tax::text,total::text,\
    valid_until,created_at,sent_at,viewed_at,accepted_at,declined_at,converted_job_id
    """

    /// The same row from `quotes_operational`, which has no subtotal, tax or
    /// total column at all. The money properties decode as absent, so a role
    /// reading this surface cannot be handed a quote total by accident.
    static let operationalColumns = """
    id,customer_id,address_id,number,title,scope_of_work,status,\
    valid_until,created_at,sent_at,viewed_at,accepted_at,declined_at,converted_job_id
    """

    func model(companyID: String) -> Quote {
        Quote(
            id: id.uuidString,
            companyID: companyID,
            customerID: customerID.uuidString,
            addressID: addressID.uuidString,
            number: number,
            title: title,
            scopeOfWork: scopeOfWork ?? "",
            status: status,
            subtotal: SupabaseCoding.decimal(subtotal),
            tax: SupabaseCoding.decimal(tax),
            total: SupabaseCoding.decimal(total),
            validUntil: validUntil,
            createdAt: createdAt,
            sentAt: sentAt,
            viewedAt: viewedAt,
            acceptedAt: acceptedAt,
            declinedAt: declinedAt,
            convertedJobID: convertedJobID?.uuidString
        )
    }
}

nonisolated struct QuoteLineItemRecord: Decodable, Sendable {
    let id: UUID
    let quoteID: UUID
    let itemDescription: String
    let quantity: String?
    let unitPrice: String?
    let taxRate: String?
    let lineTotal: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case quoteID = "quote_id"
        case itemDescription = "item_description"
        case unitPrice = "unit_price"
        case taxRate = "tax_rate"
        case lineTotal = "line_total"
        case sortOrder = "sort_order"
    }

    static let columns = """
    id,quote_id,item_description,quantity::text,unit_price::text,tax_rate::text,line_total::text,sort_order
    """

    func model(companyID: String) -> QuoteLineItem {
        QuoteLineItem(
            id: id.uuidString,
            companyID: companyID,
            quoteID: quoteID.uuidString,
            itemDescription: itemDescription,
            quantity: SupabaseCoding.decimal(quantity),
            unitPrice: SupabaseCoding.decimal(unitPrice),
            taxRate: SupabaseCoding.decimal(taxRate),
            lineTotal: SupabaseCoding.decimal(lineTotal),
            sortOrder: sortOrder
        )
    }
}

nonisolated struct InvoiceRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let billingContactID: UUID?
    let addressID: UUID?
    let jobID: UUID?
    let quoteID: UUID?
    let number: String
    let title: String
    let scopeOfWork: String?
    let status: InvoiceStatus
    let currencyCode: String
    let paymentTermsLabel: String
    let issueDate: Date
    let dueDate: Date
    let subtotal: String?
    let tax: String?
    let total: String?
    let amountPaid: String?
    let balance: String?
    let createdByUserID: UUID?
    let sentAt: Date?
    let viewedAt: Date?
    let paidAt: Date?
    let voidedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, number, title, status, subtotal, tax, total, balance
        case customerID = "customer_id"
        case billingContactID = "billing_contact_id"
        case addressID = "address_id"
        case jobID = "job_id"
        case quoteID = "quote_id"
        case scopeOfWork = "scope_of_work"
        case currencyCode = "currency_code"
        case paymentTermsLabel = "payment_terms_label"
        case issueDate = "issue_date"
        case dueDate = "due_date"
        case amountPaid = "amount_paid"
        case createdByUserID = "created_by_user_id"
        case sentAt = "sent_at"
        case viewedAt = "viewed_at"
        case paidAt = "paid_at"
        case voidedAt = "voided_at"
    }

    static let columns = """
    id,customer_id,billing_contact_id,address_id,job_id,quote_id,number,title,scope_of_work,status,\
    currency_code,payment_terms_label,issue_date,due_date,subtotal::text,tax::text,total::text,\
    amount_paid::text,balance::text,created_by_user_id,sent_at,viewed_at,paid_at,voided_at
    """

    func model(companyID: String) -> Invoice {
        Invoice(
            id: id.uuidString,
            companyID: companyID,
            customerID: customerID.uuidString,
            billingContactID: billingContactID?.uuidString,
            addressID: addressID?.uuidString,
            jobID: jobID?.uuidString,
            quoteID: quoteID?.uuidString,
            number: number,
            title: title,
            scopeOfWork: scopeOfWork ?? "",
            status: status,
            currencyCode: currencyCode.trimmingCharacters(in: .whitespaces),
            paymentTermsLabel: paymentTermsLabel,
            issueDate: issueDate,
            dueDate: dueDate,
            subtotal: SupabaseCoding.decimal(subtotal),
            tax: SupabaseCoding.decimal(tax),
            total: SupabaseCoding.decimal(total),
            amountPaid: SupabaseCoding.decimal(amountPaid),
            balance: SupabaseCoding.decimal(balance),
            createdByUserID: createdByUserID?.uuidString,
            sentAt: sentAt,
            viewedAt: viewedAt,
            paidAt: paidAt,
            voidedAt: voidedAt
        )
    }
}

nonisolated struct InvoiceLineItemRecord: Decodable, Sendable {
    let id: UUID
    let invoiceID: UUID
    let itemDescription: String
    let quantity: String?
    let unitPrice: String?
    let taxRate: String?
    let lineTotal: String?
    let sortOrder: Int
    let sourceQuoteLineItemID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, quantity
        case invoiceID = "invoice_id"
        case itemDescription = "item_description"
        case unitPrice = "unit_price"
        case taxRate = "tax_rate"
        case lineTotal = "line_total"
        case sortOrder = "sort_order"
        case sourceQuoteLineItemID = "source_quote_line_item_id"
    }

    static let columns = """
    id,invoice_id,item_description,quantity::text,unit_price::text,tax_rate::text,line_total::text,\
    sort_order,source_quote_line_item_id
    """

    func model(companyID: String) -> InvoiceLineItem {
        InvoiceLineItem(
            id: id.uuidString,
            companyID: companyID,
            invoiceID: invoiceID.uuidString,
            itemDescription: itemDescription,
            quantity: SupabaseCoding.decimal(quantity),
            unitPrice: SupabaseCoding.decimal(unitPrice),
            taxRate: SupabaseCoding.decimal(taxRate),
            lineTotal: SupabaseCoding.decimal(lineTotal),
            sortOrder: sortOrder,
            sourceQuoteLineItemID: sourceQuoteLineItemID?.uuidString
        )
    }
}

nonisolated struct PaymentRecord: Decodable, Sendable {
    let id: UUID
    let invoiceID: UUID
    let amount: String?
    let method: PaymentMethod
    let status: PaymentStatus
    let reference: String?
    let note: String?
    let receivedAt: Date
    let recordedByUserID: UUID?
    let isSimulated: Bool

    enum CodingKeys: String, CodingKey {
        case id, amount, method, status, reference, note
        case invoiceID = "invoice_id"
        case receivedAt = "received_at"
        case recordedByUserID = "recorded_by_user_id"
        case isSimulated = "is_simulated"
    }

    static let columns = """
    id,invoice_id,amount::text,method,status,reference,note,\
    received_at,recorded_by_user_id,is_simulated
    """
}

/// A customer's billing details, for raising and presenting invoices. Reachable
/// only with `customerBillingDetailsRead`; `billing_terms` is the field the
/// invoice's terms are snapshotted from.
nonisolated struct CustomerBillingRecord: Decodable, Sendable {
    let id: UUID
    let name: String
    let type: CustomerType
    let billingTerms: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type
        case billingTerms = "billing_terms"
    }

    static let columns = "id,name,type,billing_terms"
}

/// The billing contact on the invoice, including email — unlike the operational
/// contact view, which carries neither an email nor the billing flag.
nonisolated struct BillingContactRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let name: String
    let contactRole: String?
    let phone: String?
    let email: String?
    let isPrimary: Bool
    let isBillingContact: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, phone, email
        case customerID = "customer_id"
        case contactRole = "contact_role"
        case isPrimary = "is_primary"
        case isBillingContact = "is_billing_contact"
    }

    static let columns = "id,customer_id,name,contact_role,phone,email,is_primary,is_billing_contact"
}
