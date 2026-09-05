import Foundation

/// Sections reachable from the More tab. Each declares the permission the data
/// layer will require, so the UI and the gateway can never drift apart.
nonisolated enum MoreSection: String, Hashable, CaseIterable, Identifiable, Sendable {
    case dispatch
    case fieldWorkers
    case workerLocations
    case quotes
    case invoices
    case payments
    case reports
    case settings
    case paymentLink
    case dataAccess
    case integrations
    case developmentTests

    var id: String { rawValue }

    /// Trade-neutral title. Use `title(_:)` where a company context exists.
    var title: String {
        switch self {
        case .dispatch: return "Dispatch"
        case .fieldWorkers: return "Field workers"
        case .workerLocations: return "Field worker locations"
        case .quotes: return "Quotes"
        case .invoices: return "Invoices"
        case .payments: return "Accounts receivable"
        case .reports: return "Reports"
        case .settings: return "Settings"
        case .paymentLink: return "Online payment link"
        case .dataAccess: return "Role & data access"
        case .integrations: return "Integrations"
        case .developmentTests: return "Development tests"
        }
    }

    func title(_ terms: Terminology) -> String {
        switch self {
        case .fieldWorkers: return terms.WorkerPlural
        case .workerLocations: return "\(terms.Worker) locations"
        default: return title
        }
    }

    var symbolName: String {
        switch self {
        case .dispatch: return "antenna.radiowaves.left.and.right"
        case .fieldWorkers: return "person.2.fill"
        case .workerLocations: return "location.fill"
        case .quotes: return "doc.text.fill"
        case .invoices: return "doc.plaintext.fill"
        case .payments: return "chart.line.uptrend.xyaxis"
        case .reports: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        case .paymentLink: return "link"
        case .dataAccess: return "lock.shield.fill"
        case .integrations: return "app.connected.to.app.below.fill"
        case .developmentTests: return "checklist"
        }
    }

    /// Permission the data layer enforces for this section.
    var requiredPermission: Permission? {
        switch self {
        case .dispatch: return .calendarReadAll
        case .fieldWorkers: return .usersRead
        case .workerLocations: return .fieldWorkerLocationReadAll
        case .quotes: return .quotesRead
        case .invoices: return .invoicesRead
        case .payments: return .paymentsRead
        case .reports: return nil
        case .settings: return .companyProfileRead
        case .paymentLink: return .companyProfileRead
        case .dataAccess: return nil
        case .integrations: return nil
        case .developmentTests: return nil
        }
    }

    var isBuilt: Bool {
        switch self {
        case .dispatch, .workerLocations, .quotes, .invoices, .payments, .dataAccess, .integrations, .settings, .paymentLink, .developmentTests: return true
        default: return false
        }
    }
}

nonisolated enum AppRoute: Hashable, Sendable {
    case job(String)
    case quote(String)
    case invoice(String)
    case customer(String)
    case more(MoreSection)
}

/// Actions on the office home grid.
nonisolated enum QuickAction: String, CaseIterable, Identifiable, Sendable {
    case newJob
    case newQuote
    case newInvoice
    case addCustomer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newJob: return "New Job"
        case .newQuote: return "New Quote"
        case .newInvoice: return "New Invoice"
        case .addCustomer: return "Add Customer"
        }
    }

    var symbolName: String {
        switch self {
        case .newJob: return "briefcase.fill"
        case .newQuote: return "doc.text.fill"
        case .newInvoice: return "doc.plaintext.fill"
        case .addCustomer: return "person.badge.plus.fill"
        }
    }

    var requiredPermission: Permission {
        switch self {
        case .newJob: return .jobsManage
        case .newQuote: return .quotesManage
        case .newInvoice: return .invoicesManage
        case .addCustomer: return .customersManage
        }
    }
}
