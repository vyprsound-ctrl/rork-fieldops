import SwiftUI

/// Operational accounts receivable: what is owed, what is late, what lands this
/// week and what has been collected.
///
/// Deliberately not accounting software — there is no ledger, no chart of
/// accounts and no bookkeeping here. It answers one question: which money is the
/// business still waiting on, and who owes it.
struct ReceivablesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = ReceivablesViewModel()
    @State private var isFiltering: Bool = false

    private var session: TenantSession? { env.session }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isFiltering = true
                } label: {
                    Image(systemName: viewModel.query.hasRefinements
                          ? "line.3.horizontal.decrease.circle.fill"
                          : "line.3.horizontal.decrease.circle")
                }
                .tint(Theme.primary)
                .accessibilityLabel("Filter receivables")
            }
        }
        .sheet(isPresented: $isFiltering) {
            ReceivablesFilterSheet(
                query: $viewModel.query,
                customers: viewModel.state.value?.customerOptions ?? []
            )
        }
        .task(id: session?.userID) { await reload() }
        .task(id: viewModel.query) { await reload(showLoading: false) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading receivables")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let snapshot):
            loaded(snapshot)
        }
    }

    private func loaded(_ snapshot: ReceivablesSnapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                metrics(snapshot)

                if viewModel.query.hasRefinements {
                    activeFilters
                }

                if !snapshot.overdueInvoices.isEmpty {
                    chaseSection(snapshot)
                }

                invoiceSection(snapshot)

                if session?.can(.paymentsRead) == true {
                    paymentsSection(snapshot)
                }

                Text("Operational receivables only — this is not a ledger, a chart of accounts or a bookkeeping system.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
            .padding(.top, 4)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private func metrics(_ snapshot: ReceivablesSnapshot) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
            spacing: 10
        ) {
            ForEach(snapshot.metrics) { metric in
                metricTile(metric, collectedCaption: snapshot.collectedCaption)
            }
        }
    }

    private func metricTile(_ metric: ReceivablesMetric, collectedCaption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.symbolName)
                    .font(.caption)
                    .foregroundStyle(tint(metric.tone))
                Text(metric.caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
            }

            Text(metric.amountLabel)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(metric.tone == .danger ? Theme.red : Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(metric.id == "collected" ? "\(metric.countLabel) · \(collectedCaption)" : metric.countLabel)
                .font(.caption2)
                .foregroundStyle(Theme.meta)
                .lineLimit(1)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var activeFilters: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.caption)
            Text("\(viewModel.query.refinementCount) filter\(viewModel.query.refinementCount == 1 ? "" : "s") applied")
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Button("Clear") {
                viewModel.query.clearRefinements()
            }
            .font(.caption.weight(.semibold))
            .tint(Theme.primary)
        }
        .foregroundStyle(Theme.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: 10)
    }

    private func chaseSection(_ snapshot: ReceivablesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Chase first").sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(snapshot.overdueInvoices.enumerated()), id: \.element.id) { index, row in
                    NavigationLink(value: AppRoute.invoice(row.id)) {
                        InvoiceRowView(row: row)
                    }
                    .buttonStyle(.plain)

                    if index < snapshot.overdueInvoices.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .cardSurface()
        }
    }

    private func invoiceSection(_ snapshot: ReceivablesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            filterBar

            if snapshot.invoices.isEmpty {
                EmptyStateView(
                    symbolName: "tray",
                    title: "Nothing here",
                    message: "No invoices match this filter."
                )
                .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.invoices.enumerated()), id: \.element.id) { index, row in
                        NavigationLink(value: AppRoute.invoice(row.id)) {
                            InvoiceRowView(row: row)
                        }
                        .buttonStyle(.plain)

                        if index < snapshot.invoices.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .cardSurface()
            }
        }
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
                            .background(isSelected ? Theme.primary : Theme.surface)
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
        .scrollClipDisabled()
    }

    private func paymentsSection(_ snapshot: ReceivablesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent payments").sectionLabelStyle()
                SimulatedBadge()
            }

            if snapshot.recentPayments.isEmpty {
                Text("No payments recorded in this period.")
                    .font(.footnote)
                    .foregroundStyle(Theme.meta)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(snapshot.recentPayments.enumerated()), id: \.element.id) { index, payment in
                        PaymentRowView(payment: payment, showsInvoice: true)
                        if index < snapshot.recentPayments.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .cardSurface()
            }
        }
    }

    private func tint(_ tone: StatusTone) -> Color {
        switch tone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

/// Customer and date narrowing for the receivables view.
struct ReceivablesFilterSheet: View {
    @Binding var query: InvoiceQuery
    let customers: [CustomerOption]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Issue date") {
                    Picker("Period", selection: $query.dateScope) {
                        ForEach(InvoiceDateScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Customer") {
                    Picker("Customer", selection: $query.customerID) {
                        Text("Every customer").tag(String?.none)
                        ForEach(customers) { customer in
                            Text(customer.name).tag(String?.some(customer.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button("Clear filters", role: .destructive) {
                        query.clearRefinements()
                    }
                    .disabled(!query.hasRefinements)
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack {
        ReceivablesView()
            .environment(AppEnvironment())
    }
}
