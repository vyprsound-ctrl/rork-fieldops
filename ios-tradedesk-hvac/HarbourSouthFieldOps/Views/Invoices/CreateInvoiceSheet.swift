import SwiftUI

/// Picks what an invoice is being raised from: a completed job, or an accepted
/// quote.
///
/// Sources already billed are absent from these lists, which is the first line
/// of defence against billing the same work twice. The second — and the one that
/// actually counts — is in the data layer, which refuses a duplicate however the
/// request arrives.
struct CreateInvoiceSheet: View {
    let sources: InvoiceSourceOptions
    let onCreated: (String) -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: SourceTab = .jobs
    @State private var isWorking: Bool = false
    @State private var errorMessage: String?

    private var session: TenantSession? { env.activeSession }

    private enum SourceTab: String, CaseIterable, Identifiable {
        case jobs
        case quotes

        var id: String { rawValue }
        var title: String { self == .jobs ? "Completed jobs" : "Accepted quotes" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.canvas.ignoresSafeArea()

                VStack(spacing: 12) {
                    Picker("Source", selection: $selectedTab) {
                        ForEach(SourceTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Theme.margin)

                    content
                }
                .padding(.top, 10)

                if isWorking {
                    Color.black.opacity(0.06).ignoresSafeArea()
                    ProgressView().controlSize(.large)
                }
            }
            .navigationTitle("New invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(
                "Couldn't raise the invoice",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let options = selectedTab == .jobs ? sources.completedJobs : sources.acceptedQuotes

        if options.isEmpty {
            ScrollView {
                EmptyStateView(
                    symbolName: selectedTab == .jobs ? "checkmark.circle" : "doc.text",
                    title: selectedTab == .jobs ? "No jobs waiting to be billed" : "No quotes waiting to be billed",
                    message: selectedTab == .jobs
                        ? "Completed jobs that haven't been invoiced yet will show up here."
                        : "Accepted quotes that haven't been invoiced yet will show up here."
                )
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedTab == .jobs
                         ? "The invoice inherits the customer, billing contact, site and agreed scope. If the job came from an accepted quote, that quote's priced lines and its reference come across too."
                         : "The invoice takes a snapshot of the quote's line items as they stand right now. The quote itself is left exactly as the customer accepted it.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .padding(.horizontal, Theme.margin)

                    VStack(spacing: 0) {
                        ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                            Button {
                                Task { await create(option) }
                            } label: {
                                sourceRow(option)
                            }
                            .buttonStyle(.plain)
                            .disabled(isWorking)

                            if index < options.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .cardSurface()
                    .padding(.horizontal, Theme.margin)
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func sourceRow(_ option: InvoiceSourceOption) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(option.number)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                    if option.lineItemCount > 0 {
                        Text("· \(option.lineItemCount) priced line\(option.lineItemCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                    }
                }

                Text(option.customerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text(option.title)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)

                Text(option.dateLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                if let value = option.valueLabel {
                    Text(value)
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    private func create(_ option: InvoiceSourceOption) async {
        guard let session else { return }
        isWorking = true
        errorMessage = nil
        do {
            let input = InvoiceConversionInput()
            let invoiceID = selectedTab == .jobs
                ? try await env.gateway.createInvoiceFromJob(session: session, jobID: option.id, input: input)
                : try await env.gateway.createInvoiceFromQuote(session: session, quoteID: option.id, input: input)
            isWorking = false
            onCreated(invoiceID)
            dismiss()
        } catch {
            errorMessage = DataError.wrap(error).errorDescription
            isWorking = false
        }
    }
}

#Preview {
    CreateInvoiceSheet(sources: .empty) { _ in }
        .environment(AppEnvironment())
}
