import SwiftUI

/// Single place where routes resolve to screens, so every tab's stack behaves
/// identically.
struct RouteDestinationView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .job(let jobID):
            JobDetailView(jobID: jobID)
        case .quote(let quoteID):
            QuoteDetailView(quoteID: quoteID)
        case .invoice(let invoiceID):
            InvoiceDetailView(invoiceID: invoiceID)
        case .customer(let customerID):
            CustomerDetailView(customerID: customerID)
        case .more(let section):
            switch section {
            case .dispatch:
                DispatchView()
            case .workerLocations:
                WorkerLocationView()
            case .quotes:
                QuotesView()
            case .invoices:
                InvoicesView()
            case .payments:
                ReceivablesView()
            case .fieldWorkers:
                TeamView()
            case .reports:
                ReportsView()
            case .notifications:
                NotificationsView()
            case .dataAccess:
                RoleAccessView()
            case .integrations:
                IntegrationsView()
            case .developmentTests:
                WorkflowTestsView()
            case .settings:
                SettingsView()
            case .paymentLink:
                PaymentLinkView()
            }
        }
    }
}
