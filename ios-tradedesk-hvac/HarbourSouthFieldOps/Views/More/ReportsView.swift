import SwiftUI

/// Practical reporting for a small field-service company.
///
/// Every figure is read through the same gateway the rest of the app uses, so
/// nothing here is computed from a separate source and nothing is estimated.
/// Operational and financial reporting are separate permissions held by
/// different roles, so each block is gated on its own grant and a role that
/// holds only one still gets a working screen.
struct ReportsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = ReportsViewModel()

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    private var canReadOperational: Bool { session?.can(.reportsOperational) ?? false }
    private var canReadFinancial: Bool { session?.can(.reportsFinancial) ?? false }

    var body: some View {
        ScrollView {
            content
        }
        .background(Theme.canvas)
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await reload(showLoading: false) }
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        if !canReadOperational, !canReadFinancial {
            ErrorStateView(error: .notPermitted(.reportsOperational))
        } else {
            VStack(alignment: .leading, spacing: 22) {
                periodPicker

                if canReadOperational {
                    operationalSection
                }

                if canReadFinancial {
                    financialSection
                }

                Text("Every figure is read from your own company's records under your sign-in. Nothing is estimated and nothing is carried over from another company.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    // MARK: Period

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Period")
                .sectionLabelStyle()

            Picker("Period", selection: Binding(
                get: { viewModel.period },
                set: { newValue in
                    viewModel.period = newValue
                    Task { await reload(showLoading: false) }
                }
            )) {
                ForEach(InvoiceDateScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: Jobs

    @ViewBuilder
    private var operationalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Jobs")
                .sectionLabelStyle()

            switch viewModel.operational {
            case .idle, .loading:
                LoadingStateView(message: "Counting \(terms.jobPlural)")
                    .frame(height: 140)
            case .failed(let error):
                ErrorStateView(error: error) { Task { await reload() } }
            case .loaded(let report):
                jobsReport(report)
            }
        }
    }

    private func jobsReport(_ report: JobsReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Right now")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)

                HStack(spacing: 10) {
                    metricTile(
                        value: "\(report.openNow)",
                        caption: "Open",
                        symbol: "hammer.fill",
                        tone: report.openNow == 0 ? Theme.meta : Theme.primary
                    )
                    metricTile(
                        value: "\(report.unscheduledNow)",
                        caption: "Unscheduled",
                        symbol: "calendar.badge.exclamationmark",
                        tone: report.unscheduledNow == 0 ? Theme.meta : Theme.amber
                    )
                }

                Text("Live counts across all dates, so nothing waiting for a slot is missed.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(report.periodTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)

                HStack(spacing: 10) {
                    metricTile(
                        value: "\(report.scheduledInPeriod)",
                        caption: "Scheduled",
                        symbol: "calendar",
                        tone: Theme.primary
                    )
                    metricTile(
                        value: "\(report.completedInPeriod)",
                        caption: "Completed",
                        symbol: "checkmark.circle.fill",
                        tone: Theme.green
                    )
                }

                HStack(spacing: 10) {
                    metricTile(
                        value: "\(report.billedInPeriod)",
                        caption: "Invoiced or paid",
                        symbol: "doc.plaintext.fill",
                        tone: Theme.primary
                    )
                    metricTile(
                        value: completionRate(report),
                        caption: "Completion rate",
                        symbol: "chart.pie.fill",
                        tone: Theme.ink
                    )
                }

                Text("Counted by scheduled date, up to today. Work booked for a future date is not counted as done.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Completed as a share of everything scheduled in the window. Shown as a
    /// dash rather than 0% when the window holds no work at all, because zero
    /// of zero is not a performance figure.
    private func completionRate(_ report: JobsReport) -> String {
        guard report.scheduledInPeriod > 0 else { return "—" }
        let share = Double(report.completedInPeriod) / Double(report.scheduledInPeriod)
        return "\(Int((share * 100).rounded()))%"
    }

    // MARK: Money

    @ViewBuilder
    private var financialSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invoicing and payments")
                .sectionLabelStyle()

            switch viewModel.financial {
            case .idle, .loading:
                LoadingStateView(message: "Adding up invoices")
                    .frame(height: 140)
            case .failed(let error):
                ErrorStateView(error: error) { Task { await reload() } }
            case .loaded(let snapshot):
                financialReport(snapshot)
            }
        }
    }

    private func financialReport(_ snapshot: ReceivablesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 0) {
                ForEach(Array(snapshot.metrics.enumerated()), id: \.element.id) { index, metric in
                    if index > 0 { Divider().padding(.leading, 52) }
                    metricRow(metric)
                }
            }
            .cardSurface()

            if snapshot.recentPayments.isEmpty {
                Text("No payments recorded in this period.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Payments received")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondary)

                    VStack(spacing: 0) {
                        ForEach(Array(snapshot.recentPayments.prefix(8).enumerated()), id: \.element.id) { index, payment in
                            if index > 0 { Divider().padding(.leading, 14) }
                            paymentRow(payment)
                        }
                    }
                    .cardSurface()
                }
            }
        }
    }

    private func metricRow(_ metric: ReceivablesMetric) -> some View {
        HStack(spacing: 12) {
            Image(systemName: metric.symbolName)
                .font(.footnote)
                .foregroundStyle(tone(metric.tone))
                .frame(width: 30, height: 30)
                .background(tone(metric.tone).opacity(0.12))
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.caption)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ink)
                Text(metric.countLabel)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }

            Spacer(minLength: 8)

            Text(metric.amountLabel)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 54)
    }

    private func paymentRow(_ payment: PaymentProjection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: payment.methodSymbol)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(payment.customerName ?? payment.methodTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(payment.receivedLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                    if let number = payment.invoiceNumber {
                        Text("· \(number)")
                            .font(.caption2)
                            .foregroundStyle(Theme.meta)
                    }
                }
            }

            Spacer(minLength: 6)

            if payment.isSimulated {
                SimulatedBadge()
            }

            Text(payment.amountLabel)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }

    // MARK: Shared

    private func metricTile(value: String, caption: String, symbol: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(tone)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: 10))
    }

    private func tone(_ tone: StatusTone) -> Color {
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

#Preview {
    NavigationStack {
        ReportsView()
            .environment(AppEnvironment())
    }
}
