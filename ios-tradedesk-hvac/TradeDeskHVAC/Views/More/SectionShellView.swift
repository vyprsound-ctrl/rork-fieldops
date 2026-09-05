import SwiftUI

/// Navigation shell for the More sections whose feature work lands in a later
/// phase. It states scope plainly rather than faking a screen.
struct SectionShellView: View {
    let section: MoreSection

    @Environment(AppEnvironment.self) private var env

    private var session: TenantSession? { env.session }
    private var terms: Terminology { env.terms }

    private var isPermitted: Bool {
        guard let permission = section.requiredPermission else { return true }
        return session?.can(permission) ?? false
    }

    var body: some View {
        ScrollView {
            if isPermitted {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: section.symbolName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .frame(width: 56, height: 56)
                        .background(Theme.primaryTint)
                        .clipShape(.circle)

                    Text("\(section.title(terms)) is scheduled next")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let permission = section.requiredPermission {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Enforced by the data layer")
                                .sectionLabelStyle()
                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(Theme.primary)
                                Text(permission.title(terms))
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.ink)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()
                        }
                    }
                }
                .padding(Theme.margin)
            } else {
                ErrorStateView(error: .notPermitted(section.requiredPermission ?? .jobsReadAll))
            }
        }
        .background(Theme.canvas)
        .navigationTitle(section.title(terms))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private var detail: String {
        switch section {
        case .dispatch: return "The dispatch board for assigning and rescheduling work."
        case .workerLocations: return "Latest known \(terms.worker) positions, captured at job workflow events."
        case .fieldWorkers: return "The \(terms.worker) roster and availability build on the assignment records already in the schema."
        case .quotes: return "Quote building with multiple line items, tax and SMS delivery sits on the quote and line-item entities already defined."
        case .invoices: return "Invoicing with line items, balances and accounts receivable uses the invoice entities already defined."
        case .payments: return "Payments received are recorded by hand against an invoice. TradeDesk never processes the customer's card — the contractor's own payment provider does, through their own payment link."
        case .reports: return "Operational and financial reporting, split by the same permissions that gate the rest of the app."
        case .settings: return "Company profile, users, roles, trade configuration and subscription management."
        case .paymentLink: return "The company's own online payment destination, shown to customers on their invoice."
        case .dataAccess: return "Permission inspector."
        case .integrations: return "Integration status."
        case .developmentTests: return "Acceptance scenarios."
        }
    }
}

#Preview {
    NavigationStack {
        SectionShellView(section: .invoices)
            .environment(AppEnvironment())
    }
}
