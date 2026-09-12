import SwiftUI

struct InvoicesView: View {
    /// ISSUE #11 — the filter this screen opens on.
    ///
    /// A report metric drills into this list rather than into a second,
    /// parallel list of its own, so the figure and the records behind it can
    /// never disagree. Nil keeps the screen's own default (Outstanding), which
    /// is what every existing entry point relies on.
    var initialFilter: InvoiceListFilter?

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = InvoicesViewModel()
    @State private var isCreating: Bool = false
    @State private var hasAppliedInitialFilter: Bool = false

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 10) {
                filterBar
                content
            }
        }
        .navigationTitle("Invoices")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $viewModel.searchText, prompt: "Invoice number or customer")
        .toolbar {
            if session?.can(.invoicesManage) == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Theme.actionTint)
                    .accessibilityLabel("New invoice")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            CreateInvoiceSheet(sources: viewModel.sources) { _ in
                Task {
                    await reload(showLoading: false)
                    await loadSources()
                }
            }
        }
        .task(id: session?.userID) {
            // Applied once, before the first read, so the drill-down never
            // flashes the default list on its way to the right one. Guarded so
            // a later refresh doesn't undo a filter the user has since changed.
            if let initialFilter, !hasAppliedInitialFilter {
                viewModel.filter = initialFilter
                hasAppliedInitialFilter = true
            }
            await reload()
            await loadSources()
        }
        .task(id: viewModel.filter) { await reload(showLoading: false) }
        .task(id: viewModel.searchText) { await reload(showLoading: false) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(InvoiceListFilter.allCases) { filter in
                    let isSelected = viewModel.filter == filter
                    Button {
                        viewModel.filter = filter
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : Theme.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(isSelected ? Theme.selectedFill : Theme.surface)
                            .clipShape(.capsule)
                            .overlay {
                                Capsule().stroke(isSelected ? Color.clear : Theme.border, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading invoices")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let rows):
            if rows.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbolName: "doc.plaintext",
                        title: viewModel.searchText.isEmpty ? "Nothing here" : "No matches",
                        message: viewModel.searchText.isEmpty
                            ? "Invoices you raise from completed jobs and accepted quotes will appear here."
                            : "Try a different invoice number or customer."
                    )
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NavigationLink(value: AppRoute.invoice(row.id)) {
                                InvoiceRowView(row: row)
                            }
                            .buttonStyle(.plain)

                            if index < rows.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .cardSurface()
                    .padding(.horizontal, Theme.margin)
                    .padding(.bottom, 20)
                }
                .refreshable { await reload(showLoading: false) }
            }
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }

    private func loadSources() async {
        guard let session else { return }
        await viewModel.loadSources(gateway: env.gateway, session: session)
    }
}

struct InvoiceRowView: View {
    let row: InvoiceRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.status.symbolName)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12))
                .clipShape(.rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(row.number)
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondary)
                    StatusPill(badge: row.badge)
                }

                Text(row.customerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text(row.title)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)

                Text(row.dueLabel)
                    .font(.caption)
                    .foregroundStyle(row.isOverdue ? Theme.red : Theme.meta)

                if let sourceLine {
                    Label(sourceLine, systemImage: "arrow.turn.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(row.balanceLabel)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(row.isOverdue ? Theme.red : Theme.ink)

                if let paid = row.amountPaidLabel {
                    Text("\(paid) paid")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.green)
                } else {
                    Text("of \(row.totalLabel)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Theme.meta)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.meta)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    /// Where the invoice came from, as an operational reference only.
    private var sourceLine: String? {
        switch (row.jobReference, row.quoteReference) {
        case let (job?, quote?): return "\(job) · \(quote)"
        case let (job?, nil): return job
        case let (nil, quote?): return quote
        default: return nil
        }
    }

    private var tint: Color {
        switch row.badge.tone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }
}

#Preview {
    NavigationStack {
        InvoicesView()
            .environment(AppEnvironment())
    }
}
