import SwiftUI

struct CustomersView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = CustomersViewModel()
    @State private var path = NavigationPath()
    @State private var isAddingCustomer: Bool = false

    private var session: TenantSession? { env.activeSession }
    private var canManage: Bool { session?.can(.customersManage) ?? false }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle("Customers")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $viewModel.query, prompt: "Search customers")
            .navigationDestination(for: AppRoute.self) { route in
                RouteDestinationView(route: route)
            }
            .toolbar {
                if canManage {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isAddingCustomer = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add customer")
                    }
                }
            }
            .sheet(isPresented: $isAddingCustomer) {
                CustomerEditorView { customerID in
                    Task { await reload(showLoading: false) }
                    path.append(AppRoute.customer(customerID))
                }
            }
        }
        .task(id: session?.userID) { await reload() }
        .task(id: viewModel.query) { await reload(showLoading: false) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading customers")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let rows):
            if rows.isEmpty {
                ScrollView {
                    EmptyStateView(
                        symbolName: "person.2",
                        title: viewModel.query.isEmpty ? "No customers yet" : "No matches",
                        message: viewModel.query.isEmpty
                            ? "Add your first customer and their service address, then you can book work for them."
                            : "Try a different name.",
                        actionTitle: viewModel.query.isEmpty && canManage ? "Add customer" : nil,
                        action: viewModel.query.isEmpty && canManage ? { isAddingCustomer = true } : nil
                    )
                }
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NavigationLink(value: AppRoute.customer(row.id)) {
                                customerRow(row)
                            }
                            .buttonStyle(.plain)

                            if index < rows.count - 1 {
                                Divider().padding(.leading, 62)
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

    private func customerRow(_ row: CustomerRow) -> some View {
        HStack(spacing: 12) {
            Text(row.initials)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38)
                .background(Theme.primaryTint)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text("\(row.typeTitle) · \(row.addressShort)")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                if let balance = row.balanceLabel {
                    Text(balance)
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.red)
                }
                if row.openJobCount > 0 {
                    Text("\(row.openJobCount) open")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 64)
        .contentShape(.rect)
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    CustomersView()
        .environment(AppEnvironment())
}
