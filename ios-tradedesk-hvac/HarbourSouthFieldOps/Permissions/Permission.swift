import Foundation

/// Every capability the data layer knows how to gate.
///
/// These are checked inside the data gateway before rows or fields are
/// assembled — hiding a control in the UI is never treated as enforcement.
/// Names are trade-neutral: the same permission set serves every trade.
nonisolated enum Permission: String, CaseIterable, Sendable {
    // Company
    case companyProfileRead
    case companyProfileManage
    case companyDelete

    // Users
    case usersRead
    case usersManage

    // Platform (SaaS) subscription — deliberately separate from the money the
    // trade business collects from its own customers
    case saasBillingRead
    case saasBillingManage

    // Customers
    case customersReadAll
    case customersReadAssignedSiteOnly
    case customersManage
    case customerBillingDetailsRead

    // Jobs
    case jobsReadAll
    case jobsReadAssignedOnly
    case jobsManage
    case jobStatusUpdateOwn
    case jobStatusHistoryReadAll

    // Scheduling
    case calendarReadAll
    case calendarReadOwnOnly
    case assignmentsManage

    // Field records
    case jobNotesRead
    case jobNotesCreate
    case jobPhotosRead
    case jobPhotosCreate
    case equipmentRead
    case equipmentManage

    // Location
    case fieldWorkerLocationReadAll
    case fieldWorkerLocationReadOwnOnly

    // Financial
    case quotesRead
    case quotesManage
    case quoteFinancialsRead
    case invoicesRead
    case invoicesManage
    case paymentsRead
    case paymentsManage

    // Messaging credits
    case smsLedgerRead
    case smsCreditsConsume
    case smsCreditsPurchase

    // Reporting
    case reportsOperational
    case reportsFinancial

    /// Trade-neutral description. `title(_:)` renders it in the company's own
    /// vocabulary where that reads better.
    var title: String {
        switch self {
        case .companyProfileRead: return "View company profile"
        case .companyProfileManage: return "Manage company profile"
        case .companyDelete: return "Delete company"
        case .usersRead: return "View users"
        case .usersManage: return "Manage users and roles"
        case .saasBillingRead: return "View SaaS subscription"
        case .saasBillingManage: return "Manage SaaS subscription"
        case .customersReadAll: return "View all customers"
        case .customersReadAssignedSiteOnly: return "View assigned site only"
        case .customersManage: return "Manage customers"
        case .customerBillingDetailsRead: return "View customer billing details"
        case .jobsReadAll: return "View all jobs"
        case .jobsReadAssignedOnly: return "View assigned jobs only"
        case .jobsManage: return "Create and edit jobs"
        case .jobStatusUpdateOwn: return "Update own job status"
        case .jobStatusHistoryReadAll: return "View job status history"
        case .calendarReadAll: return "View full calendar"
        case .calendarReadOwnOnly: return "View own schedule only"
        case .assignmentsManage: return "Assign {workerPlural}"
        case .jobNotesRead: return "Read job notes"
        case .jobNotesCreate: return "Add job notes"
        case .jobPhotosRead: return "View job photos"
        case .jobPhotosCreate: return "Add job photos"
        case .equipmentRead: return "View {asset} history"
        case .equipmentManage: return "Manage {assetPlural}"
        case .fieldWorkerLocationReadAll: return "View {worker} locations"
        case .fieldWorkerLocationReadOwnOnly: return "Share own location"
        case .quotesRead: return "View quotes"
        case .quotesManage: return "Create and edit quotes"
        case .quoteFinancialsRead: return "View quote totals"
        case .invoicesRead: return "View invoices"
        case .invoicesManage: return "Create and edit invoices"
        case .paymentsRead: return "View payments"
        case .paymentsManage: return "Record and manage payments"
        case .smsLedgerRead: return "View SMS credit ledger"
        case .smsCreditsConsume: return "Send SMS using credits"
        case .smsCreditsPurchase: return "Buy SMS credits"
        case .reportsOperational: return "Operational reports"
        case .reportsFinancial: return "Financial reports"
        }
    }

    func title(_ terms: Terminology) -> String {
        terms.resolve(title).capitalizedFirst
    }

    var group: String {
        switch self {
        case .companyProfileRead, .companyProfileManage, .companyDelete: return "Company"
        case .usersRead, .usersManage: return "Users"
        case .saasBillingRead, .saasBillingManage: return "SaaS billing"
        case .customersReadAll, .customersReadAssignedSiteOnly, .customersManage, .customerBillingDetailsRead: return "Customers"
        case .jobsReadAll, .jobsReadAssignedOnly, .jobsManage, .jobStatusUpdateOwn, .jobStatusHistoryReadAll: return "Jobs"
        case .calendarReadAll, .calendarReadOwnOnly, .assignmentsManage: return "Scheduling"
        case .jobNotesRead, .jobNotesCreate, .jobPhotosRead, .jobPhotosCreate, .equipmentRead, .equipmentManage: return "Field records"
        case .fieldWorkerLocationReadAll, .fieldWorkerLocationReadOwnOnly: return "Location"
        case .quotesRead, .quotesManage, .quoteFinancialsRead, .invoicesRead, .invoicesManage, .paymentsRead, .paymentsManage: return "Financial"
        case .smsLedgerRead, .smsCreditsConsume, .smsCreditsPurchase: return "Messaging"
        case .reportsOperational, .reportsFinancial: return "Reports"
        }
    }
}
