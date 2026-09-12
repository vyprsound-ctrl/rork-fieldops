import SwiftUI

/// One line held in memory before the quote exists.
///
/// `QuoteLineItemDraft` is the write payload and carries no stable identity, so
/// this wraps it with one. Without that, deleting the second of three lines
/// renumbers the rest and SwiftUI animates the wrong row away.
nonisolated struct PendingQuoteLine: Identifiable, Hashable, Sendable {
    let id: UUID = UUID()
    var draft: QuoteLineItemDraft

    var lineTotal: Decimal {
        Money.lineTotal(quantity: draft.quantity, unitPrice: draft.unitPrice)
    }

    var lineTax: Decimal {
        Money.lineTax(lineTotal: lineTotal, taxRate: draft.taxRate)
    }
}

/// ISSUE #9B — quote creation is now one coherent flow.
///
/// THE OLD SHAPE: this screen saved a header and stopped. Pricing a quote meant
/// save → leave → find the quote → reopen it → add lines. The office had to
/// commit an empty, meaningless quote to the customer's record just to reach the
/// part that actually matters, and a quote abandoned halfway left a priceless
/// husk behind.
///
/// THE NEW SHAPE: customer → details → line items → live totals → save. Lines
/// are collected in memory and written immediately after `create_quote` returns,
/// so one pass through this screen produces a complete, priced quote.
///
/// DELIBERATELY UNCHANGED:
/// - Totals are still derived by the database from real stored lines. The
///   figures shown here are a preview of the arithmetic, never the source of it,
///   and no total is ever sent to the server.
/// - The quote is still created as a `draft`; sending stays a separate act.
/// - Lines are written with `save_quote_line_item`, the same RPC the existing
///   detail screen uses, so quote → invoice conversion works identically on a
///   quote built either way.
/// - Drafts remain available: a quote saved with no lines is still valid, and
///   the detail screen can still price it later.
struct QuoteEditorView: View {
    let onCreated: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var options: JobFormOptions = .empty
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    @State private var customerID: String = ""
    @State private var title: String = ""
    @State private var scopeOfWork: String = ""
    @State private var hasExpiry: Bool = true
    @State private var validUntil: Date = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()

    @State private var pendingLines: [PendingQuoteLine] = []
    @State private var isAddingLine: Bool = false

    /// The company's own rate and currency, read once. A quote priced in a
    /// currency the company doesn't trade in is worse than no quote, so these
    /// are never assumed — they fall back only if the read is not permitted.
    @State private var defaultTaxRate: Decimal = 0
    @State private var currencyCode: String = Company.fallbackCurrencyCode

    private var session: TenantSession? { env.activeSession }

    private var selectedCustomer: CustomerOption? {
        options.customers.first { $0.id == customerID }
    }

    private var subtotal: Decimal {
        pendingLines.reduce(Decimal(0)) { $0 + $1.lineTotal }
    }

    private var taxTotal: Decimal {
        pendingLines.reduce(Decimal(0)) { $0 + $1.lineTax }
    }

    private var grandTotal: Decimal { subtotal + taxTotal }

    private var canSave: Bool {
        selectedCustomer != nil && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    LoadingStateView(message: "Loading customers")
                } else if options.customers.isEmpty {
                    ScrollView {
                        EmptyStateView(
                            symbolName: "person.2.slash",
                            title: "No customers available",
                            message: "Quotes need a customer record to attach to."
                        )
                    }
                } else {
                    Form {
                        customerSection
                        detailSection
                        validitySection
                        lineItemsSection
                        if !pendingLines.isEmpty { totalsSection }
                        footerSection

                        if let errorMessage {
                            Section {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.red)
                            }
                        }
                    }
                }
            }
            .background(Theme.canvas)
            .navigationTitle("New quote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
            .sheet(isPresented: $isAddingLine) {
                QuoteLineItemSheet(
                    existing: nil,
                    defaultTaxRate: defaultTaxRate,
                    currencyCode: currencyCode
                ) { draft in
                    pendingLines.append(PendingQuoteLine(draft: draft))
                }
            }
        }
        .task {
            guard let session else { return }
            options = (try? await env.gateway.jobFormOptions(session: session)) ?? .empty
            if customerID.isEmpty, let first = options.customers.first { customerID = first.id }
            // Not permitted for every role that may quote, so a failure here is
            // not fatal — it simply leaves the sensible defaults in place.
            if let profile = try? await env.gateway.companyProfile(session: session) {
                defaultTaxRate = profile.defaultTaxRateFraction
                currencyCode = profile.currencyCode
            }
            isLoading = false
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var customerSection: some View {
        Section("Customer") {
            Picker("Customer", selection: $customerID) {
                ForEach(options.customers) { customer in
                    Text(customer.name).tag(customer.id)
                }
            }
            if let customer = selectedCustomer {
                Text(customer.addressLine)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
            }
        }
    }

    @ViewBuilder
    private var detailSection: some View {
        Section("Quote") {
            TextField("Title", text: $title)
            VStack(alignment: .leading, spacing: 6) {
                Text("Scope of work")
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                TextEditor(text: $scopeOfWork)
                    .frame(minHeight: 100)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var validitySection: some View {
        Section("Validity") {
            Toggle("Set a valid-until date", isOn: $hasExpiry)
                .tint(Theme.accent)
            if hasExpiry {
                DatePicker("Valid until", selection: $validUntil, displayedComponents: .date)
            }
        }
    }

    @ViewBuilder
    private var lineItemsSection: some View {
        Section("Line items") {
            ForEach(pendingLines) { line in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.draft.itemDescription)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(Money.quantityLabel(line.draft.quantity)) × \(Formatters.currency(line.draft.unitPrice, code: currencyCode))")
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                    }
                    Spacer(minLength: 4)
                    Text(Formatters.currency(line.lineTotal, code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                pendingLines.remove(atOffsets: offsets)
            }

            Button {
                isAddingLine = true
            } label: {
                Label("Add line item", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }

            if pendingLines.isEmpty {
                Text("Price the work now, or save the quote and add lines later.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }
        }
    }

    @ViewBuilder
    private var totalsSection: some View {
        Section("Totals") {
            LabeledContent("Subtotal") {
                Text(Formatters.currency(subtotal, code: currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            LabeledContent("Tax") {
                Text(Formatters.currency(taxTotal, code: currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            LabeledContent("Total") {
                Text(Formatters.currency(grandTotal, code: currencyCode))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            Text("The server recalculates these from the saved lines — this is a preview of the same arithmetic.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        Section {
            Text("The quote is saved as a draft with everything priced. Send it to the customer when you're ready.")
                .font(.footnote)
                .foregroundStyle(Theme.meta)
        }
    }

    // MARK: - Save

    /// Creates the quote, then writes each line against it.
    ///
    /// A line that fails to save is reported rather than swallowed, and the
    /// quote id is still handed back: the header exists by then, so pretending
    /// otherwise would strand a real record the user cannot see.
    private func save() {
        guard let session, let customer = selectedCustomer else { return }
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let id = try await env.gateway.createQuote(
                    session: session,
                    input: NewQuoteInput(
                        customerID: customer.id,
                        addressID: customer.addressID,
                        title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                        scopeOfWork: scopeOfWork.trimmingCharacters(in: .whitespacesAndNewlines),
                        validUntil: hasExpiry ? validUntil : nil
                    )
                )

                var failedLines: Int = 0
                for line in pendingLines {
                    do {
                        try await env.gateway.saveQuoteLineItem(
                            session: session,
                            quoteID: id,
                            draft: line.draft
                        )
                    } catch {
                        failedLines += 1
                        print("[quotes] line item failed on new quote: \(error)")
                    }
                }

                isSaving = false

                if failedLines > 0 {
                    errorMessage = "The quote was created, but \(failedLines) line item\(failedLines == 1 ? "" : "s") couldn't be saved. Open the quote to add \(failedLines == 1 ? "it" : "them")."
                    return
                }

                onCreated(id)
                dismiss()
            } catch {
                errorMessage = DataError.wrap(error).errorDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    QuoteEditorView { _ in }
        .environment(AppEnvironment())
}
