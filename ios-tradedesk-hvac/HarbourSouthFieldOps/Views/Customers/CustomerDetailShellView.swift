import SwiftUI

/// Customer detail shell. The record model (contacts, addresses, equipment,
/// history) is in place; the full profile screen lands with the CRM phase.
struct CustomerDetailShellView: View {
    let customerID: String

    @Environment(AppEnvironment.self) private var env
    @State private var row: CustomerRow?
    @State private var error: DataError?
    @State private var isLoading: Bool = true

    private var session: TenantSession? { env.session }

    var body: some View {
        ScrollView {
            if isLoading {
                LoadingStateView(message: "Loading customer")
                    .frame(minHeight: 240)
            } else if let error {
                ErrorStateView(error: error)
            } else if let row {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Text(row.initials)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 56, height: 56)
                            .background(Theme.primaryTint)
                            .clipShape(.circle)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.ink)
                            Text(row.typeTitle)
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondary)
                        }
                    }

                    VStack(spacing: 0) {
                        detailRow(symbol: "mappin.and.ellipse", title: "Site", value: row.addressShort)
                        Divider().padding(.leading, 54)
                        detailRow(symbol: "person.crop.circle", title: "Contacts", value: "\(row.contactCount)")
                        Divider().padding(.leading, 54)
                        detailRow(symbol: "briefcase", title: "Open jobs", value: "\(row.openJobCount)")
                        if let balance = row.balanceLabel {
                            Divider().padding(.leading, 54)
                            detailRow(symbol: "doc.plaintext", title: "Outstanding", value: balance)
                        }
                    }
                    .cardSurface()

                    Text("Full customer profile — contact management, site list, equipment register and service history — is scheduled for the CRM phase.")
                        .font(.footnote)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.margin)
            }
        }
        .background(Theme.canvas)
        .navigationTitle("Customer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: customerID) { await load() }
    }

    private func detailRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 30, height: 30)
                .background(Theme.primaryTint)
                .clipShape(.circle)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Theme.minTap)
    }

    private func load() async {
        guard let session else { return }
        isLoading = true
        error = nil
        do {
            let rows = try await env.gateway.customers(session: session, query: "")
            guard let match = rows.first(where: { $0.id == customerID }) else {
                error = .notFound
                isLoading = false
                return
            }
            row = match
        } catch {
            self.error = DataError.wrap(error)
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        CustomerDetailShellView(customerID: "cus_ramirez")
            .environment(AppEnvironment())
    }
}
