import Foundation
import Supabase

/// Quote, invoice, payment and receivables reads against Supabase.
///
/// The enforcement model is the same as the rest of the production gateway:
/// nothing here decides which rows a caller may see. Requests are issued with
/// the caller's own JWT and Row Level Security answers with whatever that role
/// is entitled to. The permission checks make a refusal legible instead of an
/// empty screen, and stop a payload that carries money from being requested at
/// all for a role that must not have it.
extension SupabaseDataGateway {

    // MARK: - Money formatting

    /// An amount in the company's configured currency.
    func money(_ amount: Decimal, _ session: TenantSession) async throws -> String {
        Formatters.currency(amount, code: try await currencyCode(session))
    }

    /// An amount in the currency the invoice was **issued** in, which is stored
    /// on the invoice itself and is not re-read from the company.
    nonisolated func invoiceMoney(_ amount: Decimal, _ invoice: Invoice) -> String {
        Formatters.currency(amount, code: invoice.currencyCode)
    }

    func defaultTaxRate(_ session: TenantSession) async throws -> Decimal {
        SupabaseCoding.decimal(try await companyRecord(session)?.defaultTaxRate)
    }

    // MARK: - Quote rows

    /// Quotes, on the surface the caller's role permits.
    ///
    /// These are two genuinely different data surfaces, not one surface with a
    /// filter: `quotes` carries subtotal, tax and total, while
    /// `quotes_operational` is a view with no money columns in it at all. A
    /// dispatcher reads the view, so a quote total isn't merely hidden from
    /// them — it is not in the response.
    private func quoteRecords(_ session: TenantSession, query: String) async throws -> [Quote] {
        try require(.quotesRead, session, query: query)

        if session.can(.quoteFinancialsRead) {
            let rows = try await fetch(QuoteRecord.self, client.from("quotes").select(QuoteRecord.columns))
            record(query, session, allowed: true, "\(rows.count) priced quote rows returned by RLS")
            return rows.map { $0.model(companyID: session.companyID) }
        }

        let rows = try await fetch(
            QuoteRecord.self,
            client.from("quotes_operational").select(QuoteRecord.operationalColumns)
        )
        record(
            query,
            session,
            allowed: true,
            "\(rows.count) quote rows from quotes_operational — the view has no subtotal, tax or total column"
        )
        return rows.map { $0.model(companyID: session.companyID) }
    }

    private func requireQuote(_ quoteID: String, _ session: TenantSession, query: String) async throws -> Quote {
        try require(.quotesRead, session, query: query)
        guard UUID(uuidString: quoteID) != nil else { throw DataError.notFound }

        let table = session.can(.quoteFinancialsRead) ? "quotes" : "quotes_operational"
        let columns = session.can(.quoteFinancialsRead) ? QuoteRecord.columns : QuoteRecord.operationalColumns
        let rows = try await fetch(
            QuoteRecord.self,
            client.from(table).select(columns).eq("id", value: quoteID).limit(1)
        )
        guard let row = rows.first else {
            record(query, session, allowed: false, "Row outside scope — answered notFound")
            throw DataError.notFound
        }
        return row.model(companyID: session.companyID)
    }

    /// Quote lines, as RLS returns them. Every column on this table is priced,
    /// so a role without the financial permission receives no rows — which is
    /// recorded rather than passed off as an empty quote.
    private func quoteLines(_ quoteIDs: [String], _ session: TenantSession, query: String) async throws -> [String: [QuoteLineItem]] {
        guard !quoteIDs.isEmpty else { return [:] }
        guard session.can(.quoteFinancialsRead) else {
            record(query, session, allowed: false, "Line pricing not requested — missing quoteFinancialsRead")
            return [:]
        }
        let rows = try await fetch(
            QuoteLineItemRecord.self,
            client.from("quote_line_items").select(QuoteLineItemRecord.columns).in("quote_id", values: quoteIDs)
        )
        let lines = rows.map { $0.model(companyID: session.companyID) }
        return Dictionary(grouping: lines, by: \.quoteID).mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }
    }

    private nonisolated func quoteBadge(_ quote: Quote) -> StatusBadge {
        StatusBadge(text: quote.status.title, tone: quote.status.tone)
    }

    /// Customer names and site lines for a set of documents.
    private func documentReference(
        customerIDs: [String],
        addressIDs: [String]
    ) async throws -> (customers: [String: CustomerRecord], addresses: [String: AddressRecord]) {
        var customers: [String: CustomerRecord] = [:]
        var addresses: [String: AddressRecord] = [:]

        if !customerIDs.isEmpty {
            let rows = try await fetch(
                CustomerRecord.self,
                client.from("customers").select(CustomerRecord.columns).in("id", values: customerIDs)
            )
            customers = Dictionary(rows.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        }
        if !addressIDs.isEmpty {
            let rows = try await fetch(
                AddressRecord.self,
                client.from("addresses").select(AddressRecord.columns).in("id", values: addressIDs)
            )
            addresses = Dictionary(rows.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return (customers, addresses)
    }

    private nonisolated func singleLine(_ address: AddressRecord?) -> String {
        guard let address else { return "" }
        return "\(address.line1), \(address.city) \(address.state) \(address.postalCode)"
    }

    // MARK: - Quotes

    func quotes(session: TenantSession, filter: QuoteListFilter, query: String) async throws -> [QuoteRow] {
        let all = try await quoteRecords(session, query: "quotes.list")
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let mayReadMoney = session.can(.quoteFinancialsRead)

        let reference = try await documentReference(
            customerIDs: Array(Set(all.map(\.customerID))),
            addressIDs: Array(Set(all.map(\.addressID)))
        )

        let matching = all
            .filter { filter.matches($0) }
            .filter { quote in
                guard !trimmed.isEmpty else { return true }
                let name = reference.customers[quote.customerID]?.name ?? ""
                return quote.number.localizedStandardContains(trimmed)
                    || quote.title.localizedStandardContains(trimmed)
                    || name.localizedStandardContains(trimmed)
            }
            .sorted { $0.createdAt > $1.createdAt }

        let lines = try await quoteLines(matching.map(\.id), session, query: "quotes.list.lines")

        // Only the converted jobs are looked up, and only for their number: an
        // operational back-reference, never a second job payload.
        var jobNumbers: [String: String] = [:]
        let convertedIDs = Array(Set(matching.compactMap(\.convertedJobID)))
        if !convertedIDs.isEmpty, session.can(.jobsReadAll) || session.can(.jobsReadAssignedOnly) {
            let rows = try await fetch(
                JobNumberRecord.self,
                client.from("jobs").select(JobNumberRecord.columns).in("id", values: convertedIDs)
            )
            jobNumbers = Dictionary(rows.map { ($0.id.uuidString, $0.number) }, uniquingKeysWith: { first, _ in first })
        }

        let code = try await currencyCode(session)

        record(
            "quotes.list",
            session,
            allowed: true,
            "\(matching.count) of \(all.count) after the \(filter.title.lowercased()) filter\(mayReadMoney ? "" : " · totals absent from the payload")"
        )

        return matching.map { quote in
            let items = lines[quote.id] ?? []
            return QuoteRow(
                id: quote.id,
                number: quote.number,
                title: quote.title,
                customerName: reference.customers[quote.customerID]?.name ?? "Customer",
                addressShort: reference.addresses[quote.addressID]?.line1 ?? "",
                badge: quoteBadge(quote),
                status: quote.status,
                dateLabel: Formatters.shortDate(quote.createdAt),
                validityLabel: quote.validUntil.map { Formatters.validityLabel($0) },
                itemCountLabel: items.count == 1 ? "1 line item" : "\(items.count) line items",
                totalLabel: mayReadMoney ? Formatters.currency(quote.total, code: code) : nil,
                convertedJobNumber: quote.convertedJobID.flatMap { jobNumbers[$0] }
            )
        }
    }

    func quoteDetail(session: TenantSession, quoteID: String) async throws -> QuoteDetailProjection {
        let quote = try await requireQuote(quoteID, session, query: "quotes.detail")
        let mayReadMoney = session.can(.quoteFinancialsRead)
        let items = try await quoteLines([quote.id], session, query: "quotes.detail.financials")[quote.id] ?? []

        let reference = try await documentReference(
            customerIDs: [quote.customerID],
            addressIDs: [quote.addressID]
        )
        let code = try await currencyCode(session)

        let lineProjections = items.map { item -> QuoteLineItemProjection in
            var pricing: QuoteLinePricing?
            if mayReadMoney {
                pricing = QuoteLinePricing(
                    unitPrice: item.unitPrice,
                    taxRate: item.taxRate,
                    lineTotal: item.lineTotal,
                    unitPriceLabel: Formatters.currency(item.unitPrice, code: code),
                    taxRateLabel: Money.percentLabel(item.taxRate),
                    lineTotalLabel: Formatters.currency(item.lineTotal, code: code)
                )
            }
            return QuoteLineItemProjection(
                id: item.id,
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                quantityLabel: Money.quantityLabel(item.quantity),
                sortOrder: item.sortOrder,
                pricing: pricing
            )
        }

        // Derived from the stored lines every time, so the printed lines always
        // reconcile with the printed subtotal, tax and total.
        var totals: QuoteTotalsProjection?
        if mayReadMoney {
            let computed = Money.totals(for: items)
            totals = QuoteTotalsProjection(
                subtotal: computed.subtotal,
                tax: computed.tax,
                total: computed.total,
                subtotalLabel: Formatters.currency(computed.subtotal, code: code),
                taxLabel: Formatters.currency(computed.tax, code: code),
                totalLabel: Formatters.currency(computed.total, code: code)
            )
        }

        let canManage = session.can(.quotesManage)
        let statusActions: [QuoteStatusAction] = canManage
            ? QuoteWorkflow.nextStatuses(from: quote.status).map {
                QuoteStatusAction(
                    id: $0.rawValue,
                    title: QuoteWorkflow.actionTitle(for: $0),
                    status: $0,
                    isDestructive: $0 == .declined || $0 == .expired
                )
            }
            : []

        var convertedNumber: String?
        if let jobID = quote.convertedJobID, session.can(.jobsReadAll) || session.can(.jobsReadAssignedOnly) {
            let rows = try await fetch(
                JobNumberRecord.self,
                client.from("jobs").select(JobNumberRecord.columns).eq("id", value: jobID).limit(1)
            )
            convertedNumber = rows.first?.number
        }

        // Operational reference to any invoice already raised from this quote.
        // Gated on `invoicesRead` and deliberately money-free, so a dispatcher
        // still never learns a figure from it.
        var raisedInvoice: Invoice?
        if session.can(.invoicesRead) {
            let rows = try await fetch(
                InvoiceRecord.self,
                client.from("invoices")
                    .select(InvoiceRecord.columns)
                    .eq("quote_id", value: quote.id)
                    .neq("status", value: InvoiceStatus.void.rawValue)
                    .limit(1)
            )
            raisedInvoice = rows.first?.model(companyID: session.companyID)
        }

        let contacts = try await fetch(
            SiteContactRecord.self,
            client.from("site_contacts_operational")
                .select(SiteContactRecord.columns)
                .eq("customer_id", value: quote.customerID)
        )
        let contact = contacts.first

        record(
            "quotes.detail",
            session,
            allowed: true,
            mayReadMoney
                ? "\(quote.number) served with \(items.count) priced lines"
                : "\(quote.number) served without pricing — line and total columns not requested"
        )

        return QuoteDetailProjection(
            id: quote.id,
            number: quote.number,
            title: quote.title,
            scopeOfWork: quote.scopeOfWork,
            status: quote.status,
            badge: quoteBadge(quote),
            customerID: quote.customerID,
            customerName: reference.customers[quote.customerID]?.name ?? "Customer",
            contactLabel: contact.map { "\($0.name) · \($0.phone ?? "no phone")" },
            addressLine: singleLine(reference.addresses[quote.addressID]),
            createdLabel: Formatters.shortDate(quote.createdAt),
            sentLabel: quote.sentAt.map { Formatters.shortDate($0) },
            viewedLabel: quote.viewedAt.map { Formatters.shortDate($0) },
            acceptedLabel: quote.acceptedAt.map { Formatters.shortDate($0) },
            declinedLabel: quote.declinedAt.map { Formatters.shortDate($0) },
            validUntilLabel: quote.validUntil.map { Formatters.validityLabel($0) },
            isExpiringSoon: quote.validUntil.map { Formatters.daysUntil($0) <= 5 } ?? false,
            lineItems: lineProjections,
            totals: totals,
            currencyCode: code,
            defaultTaxRate: mayReadMoney ? try await defaultTaxRate(session) : nil,
            statusActions: statusActions,
            canManage: canManage,
            canEditLineItems: canManage && mayReadMoney && quote.status.isEditable,
            canConvert: quote.status == .accepted
                && quote.convertedJobID == nil
                && canManage
                && session.can(.jobsManage),
            convertedJobID: quote.convertedJobID,
            convertedJobNumber: convertedNumber,
            invoicedReference: raisedInvoice.map { "\($0.number) · \($0.effectiveStatus().title)" },
            invoiceID: raisedInvoice?.id,
            canRaiseInvoice: quote.status == .accepted
                && raisedInvoice == nil
                && session.can(.invoicesManage)
        )
    }

    // MARK: - Invoice rows

    /// Unlike quotes there is no "see the document but not the money" tier: an
    /// invoice *is* money. A role without `invoicesRead` is refused here and no
    /// row is assembled at all.
    private func invoiceRecords(_ session: TenantSession, query: String) async throws -> [Invoice] {
        try require(.invoicesRead, session, query: query)
        let rows = try await fetch(InvoiceRecord.self, client.from("invoices").select(InvoiceRecord.columns))
        record(query, session, allowed: true, "\(rows.count) invoice rows returned by RLS in company scope")
        return rows.map { $0.model(companyID: session.companyID) }
    }

    func requireInvoice(_ invoiceID: String, _ session: TenantSession, query: String) async throws -> Invoice {
        try require(.invoicesRead, session, query: query)
        guard UUID(uuidString: invoiceID) != nil else { throw DataError.notFound }
        let rows = try await fetch(
            InvoiceRecord.self,
            client.from("invoices").select(InvoiceRecord.columns).eq("id", value: invoiceID).limit(1)
        )
        guard let row = rows.first else {
            record(query, session, allowed: false, "Row outside scope — answered notFound")
            throw DataError.notFound
        }
        return row.model(companyID: session.companyID)
    }

    private func invoiceLines(_ invoiceIDs: [String], _ session: TenantSession) async throws -> [String: [InvoiceLineItem]] {
        guard !invoiceIDs.isEmpty else { return [:] }
        let rows = try await fetch(
            InvoiceLineItemRecord.self,
            client.from("invoice_line_items").select(InvoiceLineItemRecord.columns).in("invoice_id", values: invoiceIDs)
        )
        let lines = rows.map { $0.model(companyID: session.companyID) }
        return Dictionary(grouping: lines, by: \.invoiceID).mapValues { $0.sorted { $0.sortOrder < $1.sortOrder } }
    }

    private func paymentRecords(_ session: TenantSession, invoiceIDs: [String]?, query: String) async throws -> [PaymentRecord] {
        guard session.can(.paymentsRead) else {
            record(query, session, allowed: false, "Payment rows not requested — missing paymentsRead")
            return []
        }
        var builder = client.from("payments").select(PaymentRecord.columns)
        if let invoiceIDs {
            guard !invoiceIDs.isEmpty else { return [] }
            builder = builder.in("invoice_id", values: invoiceIDs)
        }
        return try await fetch(PaymentRecord.self, builder)
    }

    private nonisolated func invoiceBadge(_ invoice: Invoice) -> StatusBadge {
        let shown = invoice.effectiveStatus()
        return StatusBadge(text: shown.title, tone: shown.tone)
    }

    private nonisolated func invoiceRow(
        _ invoice: Invoice,
        customerName: String,
        jobNumbers: [String: String],
        quoteNumbers: [String: String]
    ) -> InvoiceRow {
        InvoiceRow(
            id: invoice.id,
            number: invoice.number,
            title: invoice.title,
            customerID: invoice.customerID,
            customerName: customerName,
            badge: invoiceBadge(invoice),
            status: invoice.effectiveStatus(),
            issuedLabel: "Issued \(Formatters.shortDate(invoice.issueDate))",
            dueLabel: invoice.status.isSettled
                ? "Due \(Formatters.shortDate(invoice.dueDate))"
                : Formatters.dueLabel(invoice.dueDate),
            isOverdue: invoice.isOverdue(),
            daysOverdue: invoice.isOverdue() ? abs(Formatters.daysUntil(invoice.dueDate)) : nil,
            totalLabel: invoiceMoney(invoice.total, invoice),
            balanceLabel: invoiceMoney(invoice.balance, invoice),
            amountPaidLabel: invoice.amountPaid > 0 ? invoiceMoney(invoice.amountPaid, invoice) : nil,
            jobReference: invoice.jobID.flatMap { jobNumbers[$0] },
            quoteReference: invoice.quoteID.flatMap { quoteNumbers[$0] }
        )
    }

    /// Job and quote numbers for a set of invoices: operational references only,
    /// never a second document payload.
    private func documentNumbers(
        for invoices: [Invoice],
        _ session: TenantSession
    ) async throws -> (jobs: [String: String], quotes: [String: String]) {
        var jobNumbers: [String: String] = [:]
        var quoteNumbers: [String: String] = [:]

        let jobIDs = Array(Set(invoices.compactMap(\.jobID)))
        if !jobIDs.isEmpty, session.can(.jobsReadAll) || session.can(.jobsReadAssignedOnly) {
            let rows = try await fetch(
                JobNumberRecord.self,
                client.from("jobs").select(JobNumberRecord.columns).in("id", values: jobIDs)
            )
            jobNumbers = Dictionary(rows.map { ($0.id.uuidString, $0.number) }, uniquingKeysWith: { first, _ in first })
        }

        let quoteIDs = Array(Set(invoices.compactMap(\.quoteID)))
        if !quoteIDs.isEmpty, session.can(.quotesRead) {
            let rows = try await fetch(
                QuoteOperationalRecord.self,
                client.from("quotes_operational").select(QuoteOperationalRecord.columns).in("id", values: quoteIDs)
            )
            quoteNumbers = Dictionary(rows.map { ($0.id.uuidString, $0.number) }, uniquingKeysWith: { first, _ in first })
        }
        return (jobNumbers, quoteNumbers)
    }

    private func customerNames(_ ids: [String]) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        let rows = try await fetch(
            CustomerRecord.self,
            client.from("customers").select(CustomerRecord.columns).in("id", values: ids)
        )
        return Dictionary(rows.map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: - Invoices

    func invoices(session: TenantSession, query: InvoiceQuery) async throws -> [InvoiceRow] {
        let all = try await invoiceRecords(session, query: "invoices.list")
        let names = try await customerNames(Array(Set(all.map(\.customerID))))
        let trimmed = query.searchText.trimmingCharacters(in: .whitespaces)

        let filtered = all.filter { invoice in
            guard query.filter.matches(invoice) else { return false }
            guard query.dateScope.matches(invoice) else { return false }
            if let customerID = query.customerID, invoice.customerID != customerID { return false }
            if !trimmed.isEmpty {
                let name = names[invoice.customerID] ?? ""
                let matches = invoice.number.localizedStandardContains(trimmed)
                    || invoice.title.localizedStandardContains(trimmed)
                    || name.localizedStandardContains(trimmed)
                if !matches { return false }
            }
            return true
        }

        let references = try await documentNumbers(for: filtered, session)

        record(
            "invoices.list",
            session,
            allowed: true,
            "\(filtered.count) of \(all.count) after the \(query.filter.title.lowercased()) filter"
        )

        return filtered
            .sorted { lhs, rhs in
                // Most urgent money first: overdue, then by due date.
                if lhs.isOverdue() != rhs.isOverdue() { return lhs.isOverdue() }
                if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                return lhs.number > rhs.number
            }
            .map {
                invoiceRow(
                    $0,
                    customerName: names[$0.customerID] ?? "Customer",
                    jobNumbers: references.jobs,
                    quoteNumbers: references.quotes
                )
            }
    }

    private func paymentProjection(
        _ payment: PaymentRecord,
        _ invoice: Invoice,
        authors: [String: AppUserRecord],
        customerName: String?,
        includeContext: Bool
    ) -> PaymentProjection {
        let amount = SupabaseCoding.decimal(payment.amount)
        return PaymentProjection(
            id: payment.id.uuidString,
            amountLabel: invoiceMoney(amount, invoice),
            amount: amount,
            methodTitle: payment.method.title,
            methodSymbol: payment.method.symbolName,
            statusTitle: payment.status.title,
            statusTone: payment.status.tone,
            receivedLabel: Formatters.shortDate(payment.receivedAt),
            recordedByName: payment.recordedByUserID.flatMap { authors[$0.uuidString]?.name } ?? "Team member",
            reference: payment.reference,
            note: payment.note,
            isSimulated: payment.isSimulated,
            invoiceNumber: includeContext ? invoice.number : nil,
            customerName: includeContext ? customerName : nil
        )
    }

    func invoiceDetail(session: TenantSession, invoiceID: String) async throws -> InvoiceDetailProjection {
        let invoice = try await requireInvoice(invoiceID, session, query: "invoices.detail")
        let lines = try await invoiceLines([invoice.id], session)[invoice.id] ?? []

        let lineProjections = lines.map { item -> InvoiceLineItemProjection in
            let lineTax = Money.lineTax(lineTotal: item.lineTotal, taxRate: item.taxRate)
            return InvoiceLineItemProjection(
                id: item.id,
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                quantityLabel: Money.quantityLabel(item.quantity),
                sortOrder: item.sortOrder,
                pricing: InvoiceLinePricing(
                    unitPrice: item.unitPrice,
                    taxRate: item.taxRate,
                    lineTotal: item.lineTotal,
                    lineTax: lineTax,
                    unitPriceLabel: invoiceMoney(item.unitPrice, invoice),
                    taxRateLabel: Money.percentLabel(item.taxRate),
                    lineTotalLabel: invoiceMoney(item.lineTotal, invoice),
                    lineTaxLabel: invoiceMoney(lineTax, invoice)
                ),
                isFromQuote: item.sourceQuoteLineItemID != nil
            )
        }

        // Derived from the stored lines every time, so the printed lines always
        // reconcile with the printed subtotal, tax and total.
        let computed = Money.totals(for: lines)
        let outstanding = Money.rounded(computed.total - invoice.amountPaid)
        let totals = InvoiceTotalsProjection(
            subtotal: computed.subtotal,
            tax: computed.tax,
            total: computed.total,
            amountPaid: invoice.amountPaid,
            balance: outstanding,
            subtotalLabel: invoiceMoney(computed.subtotal, invoice),
            taxLabel: invoiceMoney(computed.tax, invoice),
            totalLabel: invoiceMoney(computed.total, invoice),
            amountPaidLabel: invoiceMoney(invoice.amountPaid, invoice),
            balanceLabel: invoiceMoney(outstanding, invoice)
        )

        let payments = try await paymentRecords(session, invoiceIDs: [invoice.id], query: "invoices.detail.payments")
        let authors = try await users(ids: Array(Set(payments.compactMap { $0.recordedByUserID?.uuidString })))
        let paymentRows = payments
            .sorted { $0.receivedAt > $1.receivedAt }
            .map { paymentProjection($0, invoice, authors: authors, customerName: nil, includeContext: false) }

        let canManage = session.can(.invoicesManage)
        let statusActions: [InvoiceStatusAction] = canManage
            ? InvoiceWorkflow.nextStatuses(from: invoice.status).map {
                InvoiceStatusAction(
                    id: $0.rawValue,
                    title: InvoiceWorkflow.actionTitle(for: $0),
                    status: $0,
                    isDestructive: $0 == .void
                )
            }
            : []

        let references = try await documentNumbers(for: [invoice], session)
        var jobStatusTitle: String?
        if let jobID = invoice.jobID, session.can(.jobsReadAll) {
            let rows = try await fetch(
                JobRecord.self,
                client.from("jobs").select(JobRecord.columns).eq("id", value: jobID).limit(1)
            )
            jobStatusTitle = rows.first.map { $0.status.title(session.terms) }
        }
        var quoteStatusTitle: String?
        if let quoteID = invoice.quoteID, session.can(.quotesRead) {
            let rows = try await fetch(
                QuoteOperationalRecord.self,
                client.from("quotes_operational").select(QuoteOperationalRecord.columns).eq("id", value: quoteID).limit(1)
            )
            quoteStatusTitle = rows.first?.status.title
        }

        // Customer, billing contact and site, as captured on the document.
        var customer: CustomerBillingRecord?
        if session.can(.customersReadAll) {
            let rows = try await fetch(
                CustomerBillingRecord.self,
                client.from("customers")
                    .select(session.can(.customerBillingDetailsRead) ? CustomerBillingRecord.columns : CustomerRecord.columns)
                    .eq("id", value: invoice.customerID)
                    .limit(1)
            )
            customer = rows.first
        }

        var contact: BillingContactRecord?
        let contactRows = try await fetch(
            BillingContactRecord.self,
            client.from("customer_contacts")
                .select(BillingContactRecord.columns)
                .eq("customer_id", value: invoice.customerID)
        )
        contact = invoice.billingContactID.flatMap { id in contactRows.first { $0.id.uuidString == id } }
            ?? contactRows.first { $0.isBillingContact }
            ?? contactRows.first { $0.isPrimary }

        var addressLine: String?
        if let addressID = invoice.addressID {
            let rows = try await fetch(
                AddressRecord.self,
                client.from("addresses").select(AddressRecord.columns).eq("id", value: addressID).limit(1)
            )
            addressLine = rows.first.map { singleLine($0) }
        }

        record(
            "invoices.detail",
            session,
            allowed: true,
            "\(invoice.number): \(lines.count) lines, \(paymentRows.count) payments, balance \(invoiceMoney(outstanding, invoice))"
        )

        return InvoiceDetailProjection(
            id: invoice.id,
            number: invoice.number,
            title: invoice.title,
            scopeOfWork: invoice.scopeOfWork,
            status: invoice.effectiveStatus(),
            badge: invoiceBadge(invoice),
            customerID: invoice.customerID,
            customerName: customer?.name ?? "Customer",
            customerTypeTitle: customer?.type.title ?? "",
            billingContactName: contact?.name,
            billingContactRole: contact?.contactRole,
            billingContactPhone: contact?.phone,
            billingContactEmail: contact?.email,
            addressLine: addressLine,
            issuedLabel: Formatters.shortDate(invoice.issueDate),
            dueLabel: Formatters.shortDate(invoice.dueDate),
            paymentTermsLabel: invoice.paymentTermsLabel,
            isOverdue: invoice.isOverdue(),
            daysOverdue: invoice.isOverdue() ? abs(Formatters.daysUntil(invoice.dueDate)) : nil,
            sentLabel: invoice.sentAt.map { Formatters.shortDate($0) },
            viewedLabel: invoice.viewedAt.map { Formatters.shortDate($0) },
            paidLabel: invoice.paidAt.map { Formatters.shortDate($0) },
            voidedLabel: invoice.voidedAt.map { Formatters.shortDate($0) },
            jobReference: invoice.jobID.flatMap { id in
                references.jobs[id].map { number in jobStatusTitle.map { "\(number) · \($0)" } ?? number }
            },
            jobID: session.can(.jobsReadAll) ? invoice.jobID : nil,
            quoteReference: invoice.quoteID.flatMap { id in
                references.quotes[id].map { number in quoteStatusTitle.map { "\(number) · \($0)" } ?? number }
            },
            quoteID: session.can(.quotesRead) ? invoice.quoteID : nil,
            lineItems: lineProjections,
            totals: totals,
            payments: paymentRows,
            currencyCode: invoice.currencyCode,
            defaultTaxRate: canManage ? try await defaultTaxRate(session) : nil,
            statusActions: statusActions,
            canManage: canManage,
            canEditLineItems: canManage && invoice.status.isEditable,
            canRecordPayment: session.can(.paymentsManage) && invoice.status.isIssued && outstanding > 0,
            maximumPayment: outstanding,
            maximumPaymentLabel: invoiceMoney(outstanding, invoice)
        )
    }

    func invoiceSources(session: TenantSession) async throws -> InvoiceSourceOptions {
        guard session.can(.invoicesManage) else {
            record("invoices.sources", session, allowed: false, "Reference data withheld — missing invoicesManage")
            return .empty
        }

        let invoices = try await invoiceRecords(session, query: "invoices.sources.invoices")
        let liveJobIDs = Set(invoices.filter { $0.status != .void }.compactMap(\.jobID))
        let liveQuoteIDs = Set(invoices.filter { $0.status != .void }.compactMap(\.quoteID))

        let jobs = try await jobRecords(session, query: "invoices.sources.jobs")
        let quotes = try await quoteRecords(session, query: "invoices.sources.quotes")
        let mayReadQuoteMoney = session.can(.quoteFinancialsRead)

        let quotesByID = Dictionary(quotes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let lines = try await quoteLines(quotes.map(\.id), session, query: "invoices.sources.lines")

        let names = try await customerNames(
            Array(Set(jobs.map(\.customerID)).union(quotes.map(\.customerID)))
        )
        let code = try await currencyCode(session)

        // Completed jobs that have not already produced a live invoice.
        // Filtering the source list is a convenience; the write path refuses
        // duplicates regardless of what the UI offered.
        let completed = jobs
            .filter { $0.status == .completed && !liveJobIDs.contains($0.id) }
            .sorted { ($0.actualEnd ?? $0.createdAt) > ($1.actualEnd ?? $1.createdAt) }
            .map { job -> InvoiceSourceOption in
                let quote = job.quoteID.flatMap { quotesByID[$0] }
                return InvoiceSourceOption(
                    id: job.id,
                    number: job.number,
                    title: job.title,
                    customerName: names[job.customerID] ?? "Customer",
                    dateLabel: job.actualEnd.map { "Completed \(Formatters.shortDate($0))" } ?? Formatters.shortDate(job.createdAt),
                    valueLabel: mayReadQuoteMoney ? quote.map { Formatters.currency($0.total, code: code) } : nil,
                    lineItemCount: quote.map { lines[$0.id]?.count ?? 0 } ?? 0
                )
            }

        let acceptedQuotes = quotes
            .filter { $0.status == .accepted && !liveQuoteIDs.contains($0.id) }
            .sorted { ($0.acceptedAt ?? $0.createdAt) > ($1.acceptedAt ?? $1.createdAt) }
            .map { quote -> InvoiceSourceOption in
                InvoiceSourceOption(
                    id: quote.id,
                    number: quote.number,
                    title: quote.title,
                    customerName: names[quote.customerID] ?? "Customer",
                    dateLabel: quote.acceptedAt.map { "Accepted \(Formatters.shortDate($0))" } ?? Formatters.shortDate(quote.createdAt),
                    valueLabel: mayReadQuoteMoney ? Formatters.currency(quote.total, code: code) : nil,
                    lineItemCount: lines[quote.id]?.count ?? 0
                )
            }

        record(
            "invoices.sources",
            session,
            allowed: true,
            "\(completed.count) uninvoiced completed jobs, \(acceptedQuotes.count) uninvoiced accepted quotes"
        )
        return InvoiceSourceOptions(completedJobs: completed, acceptedQuotes: acceptedQuotes, canCreate: true)
    }

    // MARK: - Payments

    func payments(session: TenantSession, query: InvoiceQuery) async throws -> [PaymentProjection] {
        try require(.paymentsRead, session, query: "payments.list")

        let invoices = try await invoiceRecords(session, query: "payments.list.invoices")
        let byID = Dictionary(invoices.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let names = try await customerNames(Array(Set(invoices.map(\.customerID))))
        let rows = try await paymentRecords(session, invoiceIDs: nil, query: "payments.list")
        let authors = try await users(ids: Array(Set(rows.compactMap { $0.recordedByUserID?.uuidString })))
        let trimmed = query.searchText.trimmingCharacters(in: .whitespaces)

        let projections = rows
            .sorted { $0.receivedAt > $1.receivedAt }
            .compactMap { payment -> PaymentProjection? in
                // A payment is only reachable through an invoice inside the
                // tenant, so an orphaned row can never be served.
                guard let invoice = byID[payment.invoiceID.uuidString] else { return nil }
                if let customerID = query.customerID, invoice.customerID != customerID { return nil }
                guard query.dateScope.matches(invoice) else { return nil }
                let name = names[invoice.customerID]
                if !trimmed.isEmpty {
                    let matches = invoice.number.localizedStandardContains(trimmed)
                        || (name ?? "").localizedStandardContains(trimmed)
                        || (payment.reference?.localizedStandardContains(trimmed) ?? false)
                    if !matches { return nil }
                }
                return paymentProjection(payment, invoice, authors: authors, customerName: name, includeContext: true)
            }

        record("payments.list", session, allowed: true, "\(projections.count) payment rows in company scope")
        return projections
    }

    // MARK: - Accounts receivable

    func receivables(session: TenantSession, query: InvoiceQuery) async throws -> ReceivablesSnapshot {
        let all = try await invoiceRecords(session, query: "receivables")
        let now = Date()

        // Headline figures are computed over the whole book, narrowed only by
        // the customer and date filters — not by the status chip — so they
        // don't move when the list below is re-filtered.
        let book = all.filter { invoice in
            guard query.dateScope.matches(invoice, now: now) else { return false }
            if let customerID = query.customerID, invoice.customerID != customerID { return false }
            return true
        }

        let outstandingRows = book.filter { $0.isReceivable(asOf: now) }
        let overdueRows = book.filter { $0.isOverdue(asOf: now) }
        // Overdue invoices are counted under overdue, never again here, so the
        // two figures never double-count the same money.
        let dueThisWeekRows = outstandingRows.filter {
            !$0.isOverdue(asOf: now) && InvoiceListFilter.isDueWithinAWeek($0, now: now)
        }

        func sum(_ rows: [Invoice]) -> Decimal {
            Money.rounded(rows.reduce(Decimal(0)) { $0 + $1.balance })
        }
        func countLabel(_ count: Int, _ noun: String) -> String {
            count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
        }

        let invoiceIDs = book.map(\.id)
        let paymentRows = try await paymentRecords(session, invoiceIDs: invoiceIDs, query: "receivables.payments")
        let collectedPayments = paymentRows.filter { $0.status.reducesBalance }
        let collected = Money.rounded(
            collectedPayments.reduce(Decimal(0)) { $0 + SupabaseCoding.decimal($1.amount) }
        )

        let outstandingTotal = sum(outstandingRows)
        let overdueTotal = sum(overdueRows)
        let dueThisWeekTotal = sum(dueThisWeekRows)
        let code = try await currencyCode(session)

        let metrics = [
            ReceivablesMetric(
                id: "outstanding",
                caption: "Outstanding",
                amountLabel: Formatters.currencyRounded(outstandingTotal, code: code),
                amount: outstandingTotal,
                countLabel: countLabel(outstandingRows.count, "invoice"),
                symbolName: "tray.full.fill",
                tone: .info
            ),
            ReceivablesMetric(
                id: "overdue",
                caption: "Overdue",
                amountLabel: Formatters.currencyRounded(overdueTotal, code: code),
                amount: overdueTotal,
                countLabel: countLabel(overdueRows.count, "invoice"),
                symbolName: "exclamationmark.triangle.fill",
                tone: overdueRows.isEmpty ? .neutral : .danger
            ),
            ReceivablesMetric(
                id: "dueThisWeek",
                caption: "Due this week",
                amountLabel: Formatters.currencyRounded(dueThisWeekTotal, code: code),
                amount: dueThisWeekTotal,
                countLabel: countLabel(dueThisWeekRows.count, "invoice"),
                symbolName: "calendar.badge.clock",
                tone: dueThisWeekRows.isEmpty ? .neutral : .warning
            ),
            ReceivablesMetric(
                id: "collected",
                caption: "Collected",
                amountLabel: Formatters.currencyRounded(collected, code: code),
                amount: collected,
                countLabel: countLabel(collectedPayments.count, "payment"),
                symbolName: "checkmark.circle.fill",
                tone: .success
            )
        ]

        let names = try await customerNames(Array(Set(book.map(\.customerID))))
        let references = try await documentNumbers(for: book, session)

        func rows(_ invoices: [Invoice]) -> [InvoiceRow] {
            invoices.map {
                invoiceRow(
                    $0,
                    customerName: names[$0.customerID] ?? "Customer",
                    jobNumbers: references.jobs,
                    quoteNumbers: references.quotes
                )
            }
        }

        let listed = rows(
            book
                .filter { query.filter.matches($0, now: now) }
                .sorted { lhs, rhs in
                    if lhs.isOverdue(asOf: now) != rhs.isOverdue(asOf: now) { return lhs.isOverdue(asOf: now) }
                    if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
                    return lhs.number > rhs.number
                }
        )
        let worstFirst = rows(Array(overdueRows.sorted { $0.dueDate < $1.dueDate }.prefix(5)))

        let byID = Dictionary(book.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let authors = try await users(ids: Array(Set(paymentRows.compactMap { $0.recordedByUserID?.uuidString })))
        let recent = paymentRows
            .sorted { $0.receivedAt > $1.receivedAt }
            .prefix(6)
            .compactMap { payment -> PaymentProjection? in
                guard let invoice = byID[payment.invoiceID.uuidString] else { return nil }
                return paymentProjection(
                    payment,
                    invoice,
                    authors: authors,
                    customerName: names[invoice.customerID],
                    includeContext: true
                )
            }

        // Customer filter options. `addressLine` carries the classification so
        // the picker reads well; no address or asset data is needed here.
        var customerOptions: [CustomerOption] = []
        if session.can(.customersReadAll) {
            let customers = try await fetch(
                CustomerRecord.self,
                client.from("customers").select(CustomerRecord.columns)
            )
            customerOptions = customers
                .sorted { $0.name < $1.name }
                .map {
                    CustomerOption(
                        id: $0.id.uuidString,
                        name: $0.name,
                        addressID: "",
                        addressLine: $0.type.title,
                        equipment: []
                    )
                }
        }

        record(
            "receivables",
            session,
            allowed: true,
            "\(outstandingRows.count) outstanding, \(overdueRows.count) overdue, \(dueThisWeekRows.count) due this week, \(collectedPayments.count) payments collected"
        )

        return ReceivablesSnapshot(
            metrics: metrics,
            invoices: listed,
            overdueInvoices: worstFirst,
            recentPayments: Array(recent),
            currencyCode: code,
            customerOptions: customerOptions,
            collectedCaption: query.dateScope == .all ? "All time" : query.dateScope.title
        )
    }
}
