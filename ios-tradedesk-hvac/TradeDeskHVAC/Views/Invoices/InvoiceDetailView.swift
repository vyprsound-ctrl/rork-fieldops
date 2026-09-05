import SwiftUI
import UIKit

struct InvoiceDetailView: View {
    let invoiceID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = InvoiceDetailViewModel()
    @State private var editingLine: InvoiceLineItemProjection?
    @State private var isAddingLine: Bool = false
    @State private var isRecordingPayment: Bool = false
    @State private var isSendingInvoice: Bool = false
    @State private var didCopyLink: Bool = false
    @State private var pendingStatus: InvoiceStatus?

    private var session: TenantSession? { env.session }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.state.value?.number ?? "Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.userID) { await reload() }
        .alert(
            "Couldn't do that",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .confirmationDialog(
            pendingStatus.map { "Move this invoice to \($0.title.lowercased())?" } ?? "",
            isPresented: Binding(
                get: { pendingStatus != nil },
                set: { if !$0 { pendingStatus = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let status = pendingStatus {
                Button(
                    InvoiceWorkflow.actionTitle(for: status),
                    role: status == .void ? .destructive : nil
                ) {
                    Task { await updateStatus(status) }
                    pendingStatus = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingStatus = nil }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading invoice")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let invoice):
            loaded(invoice)
        }
    }

    private func loaded(_ invoice: InvoiceDetailProjection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(invoice)
                billedTo(invoice)
                if !invoice.scopeOfWork.isEmpty { scope(invoice) }
                lineItems(invoice)
                totals(invoice)
                if let sharing = viewModel.sharing { sendSection(invoice, sharing) }
                if session?.can(.paymentsRead) == true { paymentsSection(invoice) }
                references(invoice)
                if !invoice.statusActions.isEmpty { statusActions(invoice) }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
        }
        .refreshable { await reload(showLoading: false) }
        .safeAreaInset(edge: .bottom) {
            if invoice.canRecordPayment {
                recordPaymentBar(invoice)
            }
        }
        .sheet(isPresented: $isAddingLine) {
            InvoiceLineItemSheet(
                existing: nil,
                defaultTaxRate: invoice.defaultTaxRate ?? 0,
                currencyCode: invoice.currencyCode
            ) { draft in
                Task { await saveLine(draft) }
            }
        }
        .sheet(item: $editingLine) { line in
            InvoiceLineItemSheet(
                existing: line,
                defaultTaxRate: invoice.defaultTaxRate ?? 0,
                currencyCode: invoice.currencyCode
            ) { draft in
                Task { await saveLine(draft) }
            }
        }
        .sheet(isPresented: $isRecordingPayment) {
            RecordPaymentSheet(
                invoiceNumber: invoice.number,
                currencyCode: invoice.currencyCode,
                outstanding: invoice.maximumPayment,
                outstandingLabel: invoice.maximumPaymentLabel
            ) { draft in
                Task { await recordPayment(draft) }
            }
        }
        .sheet(isPresented: $isSendingInvoice, onDismiss: { viewModel.lastSendOutcome = nil }) {
            if let sharing = viewModel.sharing {
                SendInvoiceSheet(
                    invoiceNumber: invoice.number,
                    sharing: sharing,
                    isSending: viewModel.isSending,
                    outcome: viewModel.lastSendOutcome
                ) { channels in
                    Task { await send(channels) }
                }
            }
        }
    }

    // MARK: - Send to customer

    @ViewBuilder
    private func sendSection(_ invoice: InvoiceDetailProjection, _ sharing: InvoiceSharing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Send to customer").sectionLabelStyle()
                if sharing.isSimulated { SimulatedBadge() }
            }

            VStack(alignment: .leading, spacing: 0) {
                if let blocked = sharing.blockedReason {
                    Text(blocked)
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                } else {
                    shareLinkRow(sharing)

                    if sharing.canSend {
                        Divider().padding(.leading, 14)
                        Button {
                            viewModel.lastSendOutcome = nil
                            isSendingInvoice = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "paperplane.fill")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.primary)
                                    .frame(width: 32, height: 32)
                                    .background(Theme.primaryTint)
                                    .clipShape(.rect(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Send by email or SMS")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.ink)
                                    Text(recipientSummary(sharing))
                                        .font(.caption)
                                        .foregroundStyle(Theme.meta)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.meta)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: Theme.minTap)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isWorking || viewModel.isSending)
                    }
                }
            }
            .cardSurface()

            paymentLinkNote(sharing)

            if !sharing.deliveries.isEmpty {
                deliveryHistory(sharing)
            }
        }
    }

    @ViewBuilder
    private func shareLinkRow(_ sharing: InvoiceSharing) -> some View {
        if let url = sharing.shareURL {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(Theme.primary)
                    Text(didCopyLink ? "Link copied" : "Customer link")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(didCopyLink ? Theme.green : Theme.meta)
                    Spacer(minLength: 0)
                }

                Text(url)
                    .font(.caption2)
                    .monospaced()
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    linkButton("Copy", "doc.on.doc") {
                        UIPasteboard.general.string = url
                        didCopyLink = true
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            didCopyLink = false
                        }
                    }
                    if sharing.canSend {
                        linkButton("New link", "arrow.triangle.2.circlepath") {
                            Task { await issueLink(rotate: true) }
                        }
                        linkButton("Revoke", "nosign", tint: Theme.red) {
                            Task { await revokeLink() }
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if sharing.canSend {
            Button {
                Task { await issueLink(rotate: false) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "link.badge.plus")
                        .font(.footnote)
                        .foregroundStyle(Theme.primary)
                        .frame(width: 32, height: 32)
                        .background(Theme.primaryTint)
                        .clipShape(.rect(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create customer link")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("A private page showing this invoice")
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.meta)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: Theme.minTap)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking)
        } else {
            Text("No customer link has been created for this invoice.")
                .font(.footnote)
                .foregroundStyle(Theme.meta)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
    }

    private func linkButton(_ title: String, _ symbol: String, tint: Color = Theme.primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(tint.opacity(0.10))
                .clipShape(.rect(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isWorking)
    }

    private func recipientSummary(_ sharing: InvoiceSharing) -> String {
        let parts = [sharing.emailRecipient, sharing.smsRecipient].compactMap { $0 }
        return parts.isEmpty ? "No contact details on file" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func paymentLinkNote(_ sharing: InvoiceSharing) -> some View {
        if sharing.paymentLink.isConfigured {
            Text("Your customer sees a Pay online button through to \(sharing.paymentLink.displayHost ?? "your payment page"). They pay you directly — TradeDesk isn't part of that transaction and won't know it happened, so record the payment here when the money reaches you.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        } else if sharing.paymentLink.canManage {
            NavigationLink(value: AppRoute.more(.paymentLink)) {
                Label("No online payment link set. Add one and customers can pay you from the invoice.", systemImage: "link")
                    .font(.caption)
                    .foregroundStyle(Theme.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
        } else {
            Text("No online payment link is set for this company, so the invoice shows no payment button.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func deliveryHistory(_ sharing: InvoiceSharing) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Delivery history").sectionLabelStyle()
                .padding(.top, 4)

            VStack(spacing: 0) {
                ForEach(Array(sharing.deliveries.enumerated()), id: \.element.id) { index, delivery in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: delivery.channelSymbol)
                            .font(.footnote)
                            .foregroundStyle(tone(delivery.statusTone))
                            .frame(width: 32, height: 32)
                            .background(tone(delivery.statusTone).opacity(0.12))
                            .clipShape(.rect(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(delivery.recipient)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text("\(delivery.channelTitle) · \(delivery.timeLabel)")
                                .font(.caption)
                                .foregroundStyle(Theme.meta)
                            if let reason = delivery.failureReason {
                                Text(reason)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.red)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Spacer(minLength: 4)

                        Text(delivery.statusTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tone(delivery.statusTone))
                    }
                    .padding(14)

                    if index < sharing.deliveries.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func tone(_ statusTone: StatusTone) -> Color {
        switch statusTone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }

    // MARK: - Sections

    private func header(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                StatusPill(badge: invoice.badge)
                if let days = invoice.daysOverdue {
                    Text("\(days) day\(days == 1 ? "" : "s") past due")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.red)
                }
                Spacer(minLength: 0)
                Text(invoice.currencyCode)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.meta)
            }

            Text(invoice.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 14) {
                metaColumn("Issued", invoice.issuedLabel)
                metaColumn("Due", invoice.dueLabel)
                metaColumn("Terms", invoice.paymentTermsLabel)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .padding(.top, 4)
    }

    private func metaColumn(_ caption: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.meta)
                .textCase(.uppercase)
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func billedTo(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Billed to").sectionLabelStyle()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(invoice.customerName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if !invoice.customerTypeTitle.isEmpty {
                        Text(invoice.customerTypeTitle)
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                    }
                }

                if let name = invoice.billingContactName {
                    Text([name, invoice.billingContactRole].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                if let phone = invoice.billingContactPhone {
                    Text(phone)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                if let email = invoice.billingContactEmail {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                if let addressLine = invoice.addressLine {
                    Label(addressLine, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    private func scope(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Work carried out").sectionLabelStyle()
            Text(invoice.scopeOfWork)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .cardSurface()
        }
    }

    private func lineItems(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Line items").sectionLabelStyle()
                if invoice.canEditLineItems {
                    Button {
                        isAddingLine = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                    }
                    .tint(Theme.primary)
                }
            }

            if invoice.lineItems.isEmpty {
                Text(invoice.canEditLineItems
                     ? "No lines yet. Add what the customer is being charged for."
                     : "This invoice has no line items.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(invoice.lineItems.enumerated()), id: \.element.id) { index, line in
                        lineRow(line, invoice: invoice)
                        if index < invoice.lineItems.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private func lineRow(_ line: InvoiceLineItemProjection, invoice: InvoiceDetailProjection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(line.itemDescription)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)

                HStack(spacing: 6) {
                    Text("\(line.quantityLabel) × \(line.pricing?.unitPriceLabel ?? "—")")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.meta)
                    if let pricing = line.pricing {
                        Text("· tax \(pricing.taxRateLabel)")
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                    }
                }

                if line.isFromQuote {
                    Label("From the accepted quote", systemImage: "doc.on.doc")
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(line.pricing?.lineTotalLabel ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                if let pricing = line.pricing, pricing.lineTax > 0 {
                    Text("+\(pricing.lineTaxLabel) tax")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.meta)
                }
            }
        }
        .padding(14)
        .contentShape(.rect)
        .onTapGesture {
            if invoice.canEditLineItems { editingLine = line }
        }
        .swipeActions(edge: .trailing) {
            if invoice.canEditLineItems {
                Button(role: .destructive) {
                    Task { await deleteLine(line.id) }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func totals(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Totals").sectionLabelStyle()

            VStack(spacing: 9) {
                totalRow("Subtotal", invoice.totals.subtotalLabel)
                totalRow("Tax", invoice.totals.taxLabel)
                Divider()
                totalRow("Total", invoice.totals.totalLabel, isBold: true)
                if invoice.totals.amountPaid > 0 {
                    totalRow("Paid", "−\(invoice.totals.amountPaidLabel)", tint: Theme.green)
                }
                Divider()
                totalRow(
                    "Balance",
                    invoice.totals.balanceLabel,
                    isBold: true,
                    tint: invoice.totals.balance > 0 ? (invoice.isOverdue ? Theme.red : Theme.ink) : Theme.green
                )
            }
            .padding(14)
            .cardSurface()

            Text("Tax is worked out on each line and rounded to the cent before the lines are added up, so the printed lines always reconcile with the total.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func totalRow(_ caption: String, _ value: String, isBold: Bool = false, tint: Color = Theme.ink) -> some View {
        HStack {
            Text(caption)
                .font(isBold ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(isBold ? Theme.ink : Theme.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(isBold ? .headline : .subheadline)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }

    private func paymentsSection(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Payments").sectionLabelStyle()
                SimulatedBadge()
            }

            if invoice.payments.isEmpty {
                Text("Nothing received against this invoice yet.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(invoice.payments.enumerated()), id: \.element.id) { index, payment in
                        PaymentRowView(payment: payment)
                        if index < invoice.payments.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .cardSurface()
            }

            Text("Payments are recorded by hand — this is the contractor's own record that money arrived. TradeDesk never takes the payment itself. Development build: every payment here is recorded as simulated.")
                .font(.caption)
                .foregroundStyle(Theme.amber)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func references(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raised from").sectionLabelStyle()

            VStack(spacing: 0) {
                if let jobReference = invoice.jobReference {
                    referenceRow("Job", jobReference, symbol: "briefcase.fill", route: invoice.jobID.map { AppRoute.job($0) })
                }
                if invoice.jobReference != nil, invoice.quoteReference != nil {
                    Divider().padding(.leading, 14)
                }
                if let quoteReference = invoice.quoteReference {
                    referenceRow("Quote", quoteReference, symbol: "doc.text.fill", route: invoice.quoteID.map { AppRoute.quote($0) })
                }
                if invoice.jobReference == nil, invoice.quoteReference == nil {
                    Text("Raised directly, with no job or quote behind it.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                }
            }
            .cardSurface()
        }
    }

    @ViewBuilder
    private func referenceRow(_ caption: String, _ value: String, symbol: String, route: AppRoute?) -> some View {
        let row = HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.meta)
                    .textCase(.uppercase)
                Text(value)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
            }

            Spacer(minLength: 4)

            if route != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)

        if let route {
            NavigationLink(value: route) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func statusActions(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Move this invoice on").sectionLabelStyle()

            VStack(spacing: 8) {
                ForEach(invoice.statusActions) { action in
                    Button {
                        pendingStatus = action.status
                    } label: {
                        HStack {
                            Text(action.title)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 0)
                            Image(systemName: action.status.symbolName)
                                .font(.footnote)
                        }
                        .foregroundStyle(action.isDestructive ? Theme.red : Theme.primary)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .cardSurface()
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isWorking)
                }
            }

            Text("Part paid, paid and overdue aren't listed here on purpose — they follow the payments and the due date, so the document can never disagree with the money recorded against it.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recordPaymentBar(_ invoice: InvoiceDetailProjection) -> some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                isRecordingPayment = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                    Text("Record payment · \(invoice.maximumPaymentLabel) outstanding")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                .background(Theme.primary)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isWorking)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
        .background(.bar)
    }

    // MARK: - Actions

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, invoiceID: invoiceID, showLoading: showLoading)
    }

    private func saveLine(_ draft: InvoiceLineItemDraft) async {
        guard let session else { return }
        await viewModel.saveLine(gateway: env.gateway, session: session, invoiceID: invoiceID, draft: draft)
    }

    private func deleteLine(_ lineItemID: String) async {
        guard let session else { return }
        await viewModel.deleteLine(gateway: env.gateway, session: session, invoiceID: invoiceID, lineItemID: lineItemID)
    }

    private func updateStatus(_ status: InvoiceStatus) async {
        guard let session else { return }
        await viewModel.updateStatus(gateway: env.gateway, session: session, invoiceID: invoiceID, to: status)
    }

    private func recordPayment(_ draft: PaymentDraft) async {
        guard let session else { return }
        await viewModel.recordPayment(gateway: env.gateway, session: session, invoiceID: invoiceID, draft: draft)
    }

    private func issueLink(rotate: Bool) async {
        guard let session else { return }
        await viewModel.issueShareLink(gateway: env.gateway, session: session, invoiceID: invoiceID, rotate: rotate)
    }

    private func revokeLink() async {
        guard let session else { return }
        await viewModel.revokeShareLink(gateway: env.gateway, session: session, invoiceID: invoiceID)
    }

    private func send(_ channels: Set<NotificationChannel>) async {
        guard let session else { return }
        await viewModel.send(gateway: env.gateway, session: session, invoiceID: invoiceID, channels: channels)
    }
}

struct PaymentRowView: View {
    let payment: PaymentProjection
    var showsInvoice: Bool = false

    private var tint: Color {
        switch payment.statusTone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: payment.methodSymbol)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12))
                .clipShape(.rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(payment.methodTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    if payment.isSimulated {
                        SimulatedBadge()
                    }
                }

                if showsInvoice, let number = payment.invoiceNumber {
                    Text([number, payment.customerName].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }

                Text("\(payment.receivedLabel) · \(payment.recordedByName)")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)

                if let reference = payment.reference {
                    Text(reference)
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(Theme.meta)
                }
                if let note = payment.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(payment.amountLabel)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(payment.statusTone == .success ? Theme.green : Theme.ink)
                Text(payment.statusTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
        .padding(14)
    }
}

#Preview {
    NavigationStack {
        InvoiceDetailView(invoiceID: "inv_1176")
            .environment(AppEnvironment())
    }
}
