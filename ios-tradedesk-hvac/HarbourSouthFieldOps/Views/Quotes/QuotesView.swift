import SwiftUI

struct QuotesView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = QuotesViewModel()
    @State private var isCreating: Bool = false

    private var session: TenantSession? { env.session }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: 10) {
                filterBar
                content
            }
        }
        .navigationTitle("Quotes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $viewModel.searchText, prompt: "Quote number or customer")
        .toolbar {
            if session?.can(.quotesManage) == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .tint(Theme.primary)
                    .accessibilityLabel("New quote")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            QuoteEditorView { _ in
                Task { await reload(showLoading: false) }
            }
        }
        .task(id: session?.userID) { await reload() }
        .task(id: viewModel.filter) { await reload(showLoading: false) }
        .task(id: viewModel.searchText) { await reload(showLoading: false) }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(QuoteListFilter.allCases) { filter in
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
        .contentMargins(.horizontal, Theme.margin, for: .scrollContent)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading quotes")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let rows):
            if rows.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbolName: "doc.text",
                        title: viewModel.searchText.isEmpty ? "No quotes here" : "No matches",
                        message: viewModel.searchText.isEmpty
                            ? "Quotes you raise will appear here."
                            : "Try a different quote number or customer."
                    )
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NavigationLink(value: AppRoute.quote(row.id)) {
                                QuoteRowView(row: row)
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
}

struct QuoteRowView: View {
    let row: QuoteRow

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

                HStack(spacing: 6) {
                    Text(row.itemCountLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                    if let validity = row.validityLabel {
                        Text("· \(validity)")
                            .font(.caption)
                            .foregroundStyle(row.status == .expired ? Theme.amber : Theme.meta)
                            .lineLimit(1)
                    }
                }

                if let jobNumber = row.convertedJobNumber {
                    Label("Job \(jobNumber) raised", systemImage: "arrow.turn.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.green)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 6) {
                if let total = row.totalLabel {
                    Text(total)
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
        QuotesView()
            .environment(AppEnvironment())
    }
}
