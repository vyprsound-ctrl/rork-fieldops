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
        case .message(let threadID):
            OfficeConversationView(threadID: threadID)
        case .smsConversation(let conversationID):
            SmsConversationView(conversationID: conversationID)
        // #11 — a report metric opens the real list, already filtered, rather
        // than a parallel screen that could disagree with it.
        case .invoiceList(let filter):
            InvoicesView(initialFilter: filter)
        case .jobList(let filter):
            JobsView(initialFilter: filter)
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
            case .recurring:
                RecurringServiceView()
            case .subscription:
                SubscriptionView()
            case .smsCredits:
                SmsCreditsView()
            case .paymentTerms:
                PaymentTermsView()
            case .companyProfile:
                CompanyProfileView()
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
            case .payments_integration:
                PaymentsIntegrationView()
            case .paymentLink:
                PaymentLinkView()
            case .businessEmail:
                BusinessEmailView()
            case .messages:
                OfficeInboxView()
            case .communications:
                CommunicationsView()
            case .smsMessaging:
                SmsMessagingView()
            case .legal:
                LegalView()
            }
        }
    }
}
