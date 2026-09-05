import SwiftUI

struct QuoteDetailView: View {
    let quoteID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = QuoteDetailViewModel()
    @State private var editingLine: QuoteLineItemProjection?
    @State private var isAddingLine: Bool = false
    @State private var isConverting: Bool = false
    @State private var isReordering: Bool = false
    @State private var isInvoicing: Bool = false
    @State private var invoiceError: String?
    @State private var raisedInvoiceID: String?

    private var session: TenantSession? { env.session }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.state.value?.number ?? "Quote")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: quoteID) {
            guard let session else { return }
            await viewModel.loadOptions(gateway: env.gateway, session: session)
            await reload()
        }
        .sheet(isPresented: $isAddingLine) {
            QuoteLineItemSheet(existing: nil, defaultTaxRate: defaultTaxRate, currencyCode: currencyCode) { draft in
                save(draft)
            }
        }
        .sheet(item: $editingLine) { line in
            QuoteLineItemSheet(existing: line, defaultTaxRate: defaultTaxRate, currencyCode: currencyCode) { draft in
                save(draft)
            }
        }
        .sheet(isPresented: $isConverting) {
            if let quote = viewModel.state.value {
                QuoteConvertSheet(quote: quote, workers: viewModel.options.workers, terms: env.terms) { input in
                    guard let session else { return }
                    Task {
                        await viewModel.convert(gateway: env.gateway, session: session, quoteID: quoteID, input: input)
                    }
                }
            }
        }
        .alert(
            "Couldn't raise the invoice",
            isPresented: Binding(
                get: { invoiceError != nil },
                set: { if !$0 { invoiceError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { invoiceError = nil }
        } message: {
            Text(invoiceError ?? "")
        }
        .navigationDestination(item: $raisedInvoiceID) { invoiceID in
            InvoiceDetailView(invoiceID: invoiceID)
        }
    }

    /// The company's configured default for a new line. Existing lines are
    /// primed from their own stored rate inside the sheet.
    private var defaultTaxRate: Decimal {
        viewModel.state.value?.defaultTaxRate ?? 0
    }

    private var currencyCode: String {
        viewModel.state.value?.currencyCode ?? Company.fallbackCurrencyCode
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading quote")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let quote):
            loaded(quote)
        }
    }

    private func loaded(_ quote: QuoteDetailProjection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(quote)
                if let error = viewModel.actionError { errorBanner(error) }
                customerCard(quote)
                scopeCard(quote)
                lineItemsSection(quote)
                if let totals = quote.totals {
                    totalsCard(totals, itemCount: quote.lineItems.count)
                } else {
                    restrictedTotalsCard
                }
                historyCard(quote)
                if quote.canConvert || quote.convertedJobNumber != nil { conversionCard(quote) }
                if quote.canRaiseInvoice || quote.invoicedReference != nil { invoiceCard(quote) }
                if !quote.statusActions.isEmpty { statusActions(quote) }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
        }
        .refreshable { await reload(showLoading: false) }
    }

    // MARK: - Sections

    private func header(_ quote: QuoteDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(quote.number)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.primaryTint)
                    .clipShape(.rect(cornerRadius: 6))
                StatusPill(badge: quote.badge)
            }

            Text(quote.title)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let validity = quote.validUntilLabel {
                Label(validity, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(quote.isExpiringSoon ? Theme.amber : Theme.meta)
            }
        }
        .padding(.top, 4)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.octagon.fill")
                .font(.footnote)
                .foregroundStyle(Theme.red)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func customerCard(_ quote: QuoteDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Customer & site")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                NavigationLink(value: AppRoute.customer(quote.customerID)) {
                    row(symbol: "person.crop.circle", title: quote.customerName, detail: quote.contactLabel, showsChevron: true)
                }
                .buttonStyle(.plain)
                Divider().padding(.leading, 54)
                row(symbol: "mappin.and.ellipse", title: quote.addressLine)
            }
            .cardSurface()
        }
    }

    private func scopeCard(_ quote: QuoteDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scope of work")
                .sectionLabelStyle()
            Text(quote.scopeOfWork.isEmpty ? "No scope recorded." : quote.scopeOfWork)
                .font(.subheadline)
                .foregroundStyle(quote.scopeOfWork.isEmpty ? Theme.meta : Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
        }
    }

    private func lineItemsSection(_ quote: QuoteDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Line items")
                    .sectionLabelStyle()
                if quote.canEditLineItems {
                    if quote.lineItems.count > 1 {
                        Button(isReordering ? "Done" : "Reorder") {
                            withAnimation { isReordering.toggle() }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                    }
                    Button("Add") { isAddingLine = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                }
            }

            VStack(spacing: 0) {
                if quote.lineItems.isEmpty {
                    Text(quote.canEditLineItems ? "No line items yet. Add the first one to build the total." : "No line items on this quote.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    ForEach(Array(quote.lineItems.enumerated()), id: \.element.id) { index, item in
                        lineRow(item, index: index, quote: quote)
                        if index < quote.lineItems.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
            }
            .cardSurface()

            if !quote.canEditLineItems, quote.canManage, !quote.status.isEditable {
                Text("\(quote.number) has been sent, so its line items are locked. The customer's copy and this record stay identical.")
                    .font(.caption2)
                    .foregroundStyle(Theme.meta)
            }
        }
    }

    private func lineRow(_ item: QuoteLineItemProjection, index: Int, quote: QuoteDetailProjection) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if isReordering, quote.canEditLineItems {
                VStack(spacing: 4) {
                    Button {
                        move(item, in: quote, by: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(index == 0 ? Theme.border : Theme.primary)
                            .frame(width: 30, height: 26)
                    }
                    .disabled(index == 0)

                    Button {
                        move(item, in: quote, by: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(index == quote.lineItems.count - 1 ? Theme.border : Theme.primary)
                            .frame(width: 30, height: 26)
                    }
                    .disabled(index == quote.lineItems.count - 1)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.itemDescription)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let pricing = item.pricing {
                    Text("\(item.quantityLabel) × \(pricing.unitPriceLabel) · tax \(pricing.taxRateLabel)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                } else {
                    Text("Quantity \(item.quantityLabel)")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                if let pricing = item.pricing {
                    Text(pricing.lineTotalLabel)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                if quote.canEditLineItems, !isReordering {
                    HStack(spacing: 10) {
                        Button {
                            editingLine = item
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                        }
                        Button {
                            deleteLine(item)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.red)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
    }

    private func totalsCard(_ totals: QuoteTotalsProjection, itemCount: Int) -> some View {
        VStack(spacing: 0) {
            totalRow(label: "Subtotal", value: totals.subtotalLabel)
            Divider().padding(.horizontal, 14)
            totalRow(label: "Tax", value: totals.taxLabel)
            Divider().padding(.horizontal, 14)
            HStack {
                Text("Total")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(totals.totalLabel)
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .padding(14)

            Text("Calculated from \(itemCount) line item\(itemCount == 1 ? "" : "s") in exact decimals — tax is rounded per line, so the lines always add up to the total.")
                .font(.caption2)
                .foregroundStyle(Theme.meta)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
        }
        .cardSurface()
    }

    private func totalRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }

    private var restrictedTotalsCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.footnote)
                .foregroundStyle(Theme.meta)
            Text("Quote values aren't part of this role's data. Line pricing and totals are never assembled for this device — only the scope and quantities.")
                .font(.footnote)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func historyCard(_ quote: QuoteDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quote history")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                row(symbol: "plus.circle", title: "Created", detail: quote.createdLabel)
                if let sent = quote.sentLabel {
                    Divider().padding(.leading, 54)
                    row(symbol: "paperplane", title: "Sent", detail: sent)
                }
                if let viewed = quote.viewedLabel {
                    Divider().padding(.leading, 54)
                    row(symbol: "eye", title: "Viewed by customer", detail: viewed)
                }
                if let accepted = quote.acceptedLabel {
                    Divider().padding(.leading, 54)
                    row(symbol: "checkmark.seal", title: "Accepted", detail: accepted)
                }
                if let declined = quote.declinedLabel {
                    Divider().padding(.leading, 54)
                    row(symbol: "hand.thumbsdown", title: "Declined", detail: declined)
                }
            }
            .cardSurface()
        }
    }

    /// Billing this quote. Present only for roles that may actually raise an
    /// invoice, and money-free until they do.
    private func invoiceCard(_ quote: QuoteDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invoice")
                .sectionLabelStyle()

            if let reference = quote.invoicedReference {
                Group {
                    if let invoiceID = quote.invoiceID {
                        NavigationLink(value: AppRoute.invoice(invoiceID)) {
                            row(symbol: "doc.plaintext.fill", title: reference, detail: "Raised from this quote", showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        row(symbol: "doc.plaintext.fill", title: reference, detail: "Raised from this quote", showsChevron: false)
                    }
                }
                .cardSurface()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Billing this quote takes a snapshot of its line items as they stand now. The quote stays exactly as the customer accepted it, and later changes to it can never alter the invoice.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        Task { await raiseInvoice() }
                    } label: {
                        HStack(spacing: 8) {
                            if isInvoicing { ProgressView().tint(.white) }
                            Image(systemName: "doc.plaintext.fill")
                            Text("Create invoice from quote")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .background(Theme.primary)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(isInvoicing)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }

    private func raiseInvoice() async {
        guard let session else { return }
        isInvoicing = true
        invoiceError = nil
        do {
            let invoiceID = try await env.gateway.createInvoiceFromQuote(
                session: session,
                quoteID: quoteID,
                input: InvoiceConversionInput()
            )
            await reload(showLoading: false)
            raisedInvoiceID = invoiceID
        } catch {
            invoiceError = DataError.wrap(error).errorDescription
        }
        isInvoicing = false
    }

    private func conversionCard(_ quote: QuoteDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job")
                .sectionLabelStyle()

            if let jobNumber = quote.convertedJobNumber, let jobID = quote.convertedJobID {
                NavigationLink(value: AppRoute.job(jobID)) {
                    row(symbol: "briefcase.fill", title: "Job \(jobNumber)", detail: "Raised from this quote", showsChevron: true)
                }
                .buttonStyle(.plain)
                .cardSurface()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This quote is accepted. Turning it into a job carries over the customer, the site, the equipment and the agreed scope — the quote itself stays exactly as the customer accepted it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        isConverting = true
                    } label: {
                        HStack(spacing: 8) {
                            if viewModel.isWorking { ProgressView().tint(.white) }
                            Image(systemName: "arrow.turn.down.right")
                            Text("Create job from quote")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .background(Theme.primary)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(viewModel.isWorking)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }
        }
    }

    private func statusActions(_ quote: QuoteDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Move this quote on")
                .sectionLabelStyle()

            VStack(spacing: 8) {
                ForEach(quote.statusActions) { action in
                    Button {
                        guard let session else { return }
                        Task {
                            await viewModel.updateStatus(gateway: env.gateway, session: session, quoteID: quoteID, to: action.status)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: action.status.symbolName)
                                .font(.footnote)
                            Text(action.title)
                                .font(.headline)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(action.isDestructive ? Theme.red : Theme.primary)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap, alignment: .leading)
                        .background(action.isDestructive ? Theme.red.opacity(0.08) : Theme.primaryTint)
                        .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(viewModel.isWorking)
                }
            }

            if quote.status == .sent || quote.status == .viewed {
                Text("Sending the quote by SMS or email arrives with the messaging phase — for now the status is recorded on its own.")
                    .font(.caption2)
                    .foregroundStyle(Theme.meta)
            }
        }
    }

    private func row(symbol: String, title: String, detail: String? = nil, showsChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 30, height: 30)
                .background(Theme.primaryTint)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 4)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    // MARK: - Actions

    private func save(_ draft: QuoteLineItemDraft) {
        guard let session else { return }
        Task {
            await viewModel.saveLine(gateway: env.gateway, session: session, quoteID: quoteID, draft: draft)
        }
    }

    private func deleteLine(_ item: QuoteLineItemProjection) {
        guard let session else { return }
        Task {
            await viewModel.deleteLine(gateway: env.gateway, session: session, quoteID: quoteID, lineItemID: item.id)
        }
    }

    private func move(_ item: QuoteLineItemProjection, in quote: QuoteDetailProjection, by offset: Int) {
        guard let session else { return }
        var ids = quote.lineItems.map(\.id)
        guard let index = ids.firstIndex(of: item.id) else { return }
        let target = index + offset
        guard target >= 0, target < ids.count else { return }
        ids.swapAt(index, target)
        Task {
            await viewModel.reorder(gateway: env.gateway, session: session, quoteID: quoteID, orderedIDs: ids)
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, quoteID: quoteID, showLoading: showLoading)
    }
}

#Preview {
    NavigationStack {
        QuoteDetailView(quoteID: "qte_coastal")
            .environment(AppEnvironment())
    }
}
