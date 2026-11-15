import SwiftUI
import CoreImage.CIFilterBuiltins

/// Invoicing and payment collection on an engineer's own job.
///
/// Appears only when the office has switched on at least one of the engineer's
/// two grants. The server decides everything: what it returns is what is
/// shown, and every button lands on a function that re-checks the grant, so a
/// grant switched off in the office stops the next tap even if this card is
/// still on screen.
struct EngineerBillingCard: View {
    let jobID: String
    let jobStatus: JobStatus

    @Environment(AppEnvironment.self) private var env
    @State private var billing: EngineerJobBilling = .hidden
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var editingLine: LineEditorContext?
    @State private var isSending: Bool = false
    @State private var paymentLink: PaymentLinkContext?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        Group {
            if billing.isVisible {
                card
            }
        }
        .task(id: "\(jobID)-\(jobStatus.rawValue)") { await load() }
        .sheet(item: $editingLine) { context in
            InvoiceLineEditorSheet(context: context) { description, quantity, price in
                await saveLine(context: context, description: description, quantity: quantity, price: price)
            }
        }
        .sheet(isPresented: $isSending) {
            if let invoice = billing.invoice {
                EngineerSendInvoiceSheet(invoice: invoice) { recipient in
                    await send(invoice: invoice, recipient: recipient)
                }
            }
        }
        .sheet(item: $paymentLink) { context in
            EngineerPaymentLinkSheet(context: context)
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invoice & payment")
                .sectionLabelStyle()

            VStack(alignment: .leading, spacing: 12) {
                if let invoice = billing.invoice {
                    invoiceSummary(invoice)
                } else {
                    noInvoice
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.green)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .animation(.snappy, value: billing)
        }
    }

    @ViewBuilder
    private var noInvoice: some View {
        HStack(spacing: 12) {
            badgeIcon("doc.text")
            VStack(alignment: .leading, spacing: 2) {
                Text("No invoice yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(noInvoiceExplanation)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }

        if billing.canInvoice && jobStatus == .completed {
            primaryButton("Generate invoice", symbol: "doc.badge.plus") {
                Task { await generate() }
            }
        }
    }

    private var noInvoiceExplanation: String {
        if !billing.canInvoice {
            return "The office raises the invoice for this job. Once it's sent you can show the customer a payment link here."
        }
        if jobStatus == .completed {
            return "Raise the invoice from this job, check the lines, then send it to the customer."
        }
        return "You can raise the invoice once the job is marked complete."
    }

    @ViewBuilder
    private func invoiceSummary(_ invoice: EngineerInvoice) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(invoice.number)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(invoice.status.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor(invoice.status))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(invoice.money(invoice.total))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
                if invoice.amountPaid > 0 {
                    Text("Balance \(invoice.money(invoice.balance))")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .monospacedDigit()
                }
            }
        }

        if !invoice.lines.isEmpty {
            Divider()
            VStack(spacing: 0) {
                ForEach(invoice.lines) { line in
                    lineRow(line, invoice: invoice)
                    if line.id != invoice.lines.last?.id { Divider().padding(.leading, 2) }
                }
            }
        }

        if invoice.isDraft && billing.canInvoice {
            Button {
                editingLine = LineEditorContext(invoiceID: invoice.id, line: nil, currencyCode: invoice.currencyCode)
            } label: {
                Label("Add a line", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 40)
            }
            .buttonStyle(.plain)
        }

        Divider()
        HStack {
            Text("Subtotal").foregroundStyle(Theme.secondary)
            Spacer()
            Text(invoice.money(invoice.subtotal)).monospacedDigit()
        }
        .font(.footnote)
        HStack {
            Text("Tax").foregroundStyle(Theme.secondary)
            Spacer()
            Text(invoice.money(invoice.tax)).monospacedDigit()
        }
        .font(.footnote)

        if billing.canInvoice && invoice.status != .paid && invoice.status != .void {
            primaryButton(
                invoice.isDraft ? "Issue & email invoice" : "Email invoice again",
                symbol: "paperplane.fill"
            ) {
                errorMessage = nil
                notice = nil
                isSending = true
            }
            .disabled(invoice.lines.isEmpty)
        }

        if billing.canCollect && invoice.isOpenForPayment {
            secondaryButton("Collect payment", symbol: "qrcode") {
                Task { await openPaymentLink(invoice) }
            }
        }
    }

    private func lineRow(_ line: EngineerInvoiceLine, invoice: EngineerInvoice) -> some View {
        let editable = invoice.isDraft && billing.canInvoice
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.description)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Self.quantityText(line.quantity)) × \(invoice.money(line.unitPrice))")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(invoice.money(line.lineTotal))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
            if editable {
                Menu {
                    Button("Edit", systemImage: "pencil") {
                        editingLine = LineEditorContext(invoiceID: invoice.id, line: line, currencyCode: invoice.currencyCode)
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        Task { await deleteLine(invoiceID: invoice.id, lineID: line.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(Theme.meta)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Line options")
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Pieces

    private func badgeIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.primary)
            .frame(width: 40, height: 40)
            .background(Theme.primaryTint)
            .clipShape(.rect(cornerRadius: 10))
    }

    private func primaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking { ProgressView().tint(.white) } else { Image(systemName: symbol) }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.primary)
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(PressableTileStyle())
        .disabled(isWorking)
        .sensoryFeedback(.impact(weight: .light), trigger: isWorking)
    }

    private func secondaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(Theme.primary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.primaryTint)
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(PressableTileStyle())
        .disabled(isWorking)
    }

    private func statusColor(_ status: InvoiceStatus) -> Color {
        switch status {
        case .draft: return Theme.secondary
        case .sent, .viewed: return Theme.primary
        case .partPaid: return Theme.amber
        case .paid: return Theme.green
        case .overdue, .void: return Theme.red
        }
    }

    nonisolated static func quantityText(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: number) ?? number.stringValue
    }

    // MARK: - Actions

    private func load() async {
        guard let session else { return }
        do {
            billing = try await env.gateway.engineerJobBilling(session: session, jobID: jobID)
        } catch {
            // A refused or unreachable billing read only hides the card; it
            // never blocks the rest of the job screen.
            billing = .hidden
        }
    }

    private func run(_ work: @escaping (TenantSession) async throws -> Void) async -> Bool {
        guard let session else { return false }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work(session)
            await load()
            return true
        } catch {
            errorMessage = DataError.wrap(error).errorDescription
            await load()
            return false
        }
    }

    private func generate() async {
        notice = nil
        let ok = await run { session in
            _ = try await env.gateway.engineerCreateInvoice(session: session, jobID: jobID)
        }
        if ok { notice = "Draft invoice raised. Check the lines, then issue it." }
    }

    private func saveLine(context: LineEditorContext, description: String, quantity: Decimal, price: Decimal) async -> String? {
        guard let session else { return "Sign in again to continue." }
        do {
            try await env.gateway.engineerSaveInvoiceLine(
                session: session,
                invoiceID: context.invoiceID,
                lineID: context.line?.id,
                description: description,
                quantity: quantity,
                unitPrice: price
            )
            await load()
            return nil
        } catch {
            return DataError.wrap(error).errorDescription ?? "The line couldn't be saved."
        }
    }

    private func deleteLine(invoiceID: String, lineID: String) async {
        _ = await run { session in
            try await env.gateway.engineerDeleteInvoiceLine(session: session, invoiceID: invoiceID, lineID: lineID)
        }
    }

    /// Issues a draft first (the server refuses if the grant has gone), then
    /// emails it. A refusal at either step is shown as it is.
    private func send(invoice: EngineerInvoice, recipient: String) async -> String? {
        guard let session else { return "Sign in again to continue." }
        do {
            if invoice.isDraft {
                try await env.gateway.engineerIssueInvoice(session: session, invoiceID: invoice.id)
            }
            let outcome = try await env.gateway.engineerEmailInvoice(
                session: session,
                invoiceID: invoice.id,
                recipient: recipient
            )
            await load()
            if outcome.didDeliverAnything {
                notice = "\(invoice.number) emailed to \(recipient)."
                errorMessage = nil
            } else {
                notice = nil
                errorMessage = outcome.results.first?.detail.nilIfBlank
                    ?? "\(invoice.number) was issued but the email couldn't be delivered. The office can resend it."
            }
            return nil
        } catch {
            await load()
            return DataError.wrap(error).errorDescription ?? "The invoice couldn't be sent."
        }
    }

    private func openPaymentLink(_ invoice: EngineerInvoice) async {
        guard let session else { return }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let url = try await env.gateway.engineerPaymentLink(session: session, invoiceID: invoice.id)
            paymentLink = PaymentLinkContext(
                url: url,
                number: invoice.number,
                amount: invoice.money(invoice.balance)
            )
        } catch {
            errorMessage = DataError.wrap(error).errorDescription
            await load()
        }
    }
}

// MARK: - Line editor

struct LineEditorContext: Identifiable, Hashable {
    let id = UUID()
    let invoiceID: String
    let line: EngineerInvoiceLine?
    let currencyCode: String
}

private struct InvoiceLineEditorSheet: View {
    let context: LineEditorContext
    let onSave: (String, Decimal, Decimal) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var description: String
    @State private var quantity: String
    @State private var price: String
    @State private var isSaving: Bool = false
    @State private var error: String?

    init(context: LineEditorContext, onSave: @escaping (String, Decimal, Decimal) async -> String?) {
        self.context = context
        self.onSave = onSave
        _description = State(initialValue: context.line?.description ?? "")
        _quantity = State(initialValue: context.line.map { EngineerBillingCard.quantityText($0.quantity) } ?? "1")
        _price = State(initialValue: context.line.map { NSDecimalNumber(decimal: $0.unitPrice).stringValue } ?? "")
    }

    private var parsedQuantity: Decimal? { Self.decimal(quantity) }
    private var parsedPrice: Decimal? { Self.decimal(price) }

    private var canSave: Bool {
        !description.tidied.isEmpty && (parsedQuantity ?? 0) > 0 && (parsedPrice ?? -1) >= 0 && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Work or part") {
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(1...4)
                }
                Section {
                    LabeledContent("Quantity") {
                        TextField("1", text: $quantity)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Unit price (\(context.currencyCode))") {
                        TextField("0.00", text: $price)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Tax is applied at your company's standard rate.")
                }
                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(Theme.red)
                    }
                }
            }
            .navigationTitle(context.line == nil ? "Add line" : "Edit line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            guard let q = parsedQuantity, let p = parsedPrice else { return }
                            isSaving = true
                            Task {
                                let problem = await onSave(description, q, p)
                                isSaving = false
                                if let problem { error = problem } else { dismiss() }
                            }
                        }
                        .disabled(!canSave)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static func decimal(_ text: String) -> Decimal? {
        let cleaned = text.tidied.replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

// MARK: - Send

private struct EngineerSendInvoiceSheet: View {
    let invoice: EngineerInvoice
    let onSend: (String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var isSending: Bool = false
    @State private var error: String?

    init(invoice: EngineerInvoice, onSend: @escaping (String) async -> String?) {
        self.invoice = invoice
        self.onSend = onSend
        _email = State(initialValue: invoice.billingEmail)
    }

    private var isValid: Bool {
        let address = email.tidied
        return address.contains("@") && address.contains(".") && !address.contains(" ")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Invoice", value: invoice.number)
                    LabeledContent("Total", value: invoice.money(invoice.total))
                }
                Section {
                    TextField("customer@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Customer email")
                } footer: {
                    Text(invoice.isDraft
                         ? "Issuing locks the invoice lines. The customer gets a link to view and pay online."
                         : "The customer gets a link to view and pay online.")
                }
                if let error {
                    Section {
                        Text(error).font(.footnote).foregroundStyle(Theme.red)
                    }
                }
            }
            .navigationTitle(invoice.isDraft ? "Issue & email" : "Email invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Send") {
                            isSending = true
                            Task {
                                let problem = await onSend(email.tidied)
                                isSending = false
                                if let problem { error = problem } else { dismiss() }
                            }
                        }
                        .disabled(!isValid)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Payment link

struct PaymentLinkContext: Identifiable, Hashable {
    var id: String { url }
    let url: String
    let number: String
    let amount: String
}

/// Shows the customer the invoice's secure payment page as a QR code they can
/// scan with their own phone. Payment runs through the company's existing
/// online payment page; nothing about the card ever touches this device.
private struct EngineerPaymentLinkSheet: View {
    let context: PaymentLinkContext

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        Text(context.amount)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .monospacedDigit()
                        Text("Due on \(context.number)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }
                    .padding(.top, 8)

                    if let image = Self.qrImage(context.url) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 260)
                            .padding(18)
                            .background(.white)
                            .clipShape(.rect(cornerRadius: 20))
                            .shadow(color: Theme.ink.opacity(0.08), radius: 16, y: 6)
                            .accessibilityLabel("Payment QR code")
                    }

                    Text("Ask the customer to scan this with their phone camera to pay securely online.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    VStack(spacing: 10) {
                        if let url = URL(string: context.url) {
                            Button {
                                openURL(url)
                            } label: {
                                Label("Open payment page", systemImage: "safari")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Theme.primary)
                                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                            }
                            .buttonStyle(PressableTileStyle())

                            ShareLink(item: url) {
                                Label("Share link", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .foregroundStyle(Theme.primary)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Theme.primaryTint)
                                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                            }
                        }
                    }
                    .padding(.horizontal, Theme.margin)

                    Text("The payment shows on the invoice as soon as it clears.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
                .padding(.bottom, 24)
            }
            .background(Theme.canvas)
            .navigationTitle("Collect payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let context = CIContext()
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
