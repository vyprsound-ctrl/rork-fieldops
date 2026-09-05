import Foundation

/// The single source of truth for what each role may do.
///
/// The data gateway consults this before assembling any payload. When Supabase
/// is connected these same sets become the basis for Row Level Security
/// policies and column-level grants. The matrix is trade-neutral — every trade
/// runs on exactly these five roles.
nonisolated enum PermissionMatrix {
    static func permissions(for role: Role) -> Set<Permission> {
        switch role {
        case .owner: return ownerPermissions
        case .admin: return adminPermissions
        case .dispatcher: return dispatcherPermissions
        case .fieldWorker: return fieldWorkerPermissions
        case .accounts: return accountsPermissions
        }
    }

    static func can(_ role: Role, _ permission: Permission) -> Bool {
        permissions(for: role).contains(permission)
    }

    /// Owner: everything, including company lifecycle and the SaaS subscription.
    private static let ownerPermissions: Set<Permission> = Set(Permission.allCases)
        .subtracting([.jobsReadAssignedOnly, .customersReadAssignedSiteOnly, .calendarReadOwnOnly, .fieldWorkerLocationReadOwnOnly])

    /// Admin: full operations. No company deletion, no SaaS billing management.
    private static let adminPermissions: Set<Permission> = [
        .companyProfileRead,
        .usersRead, .usersManage,
        .customersReadAll, .customersManage, .customerBillingDetailsRead,
        .jobsReadAll, .jobsManage, .jobStatusHistoryReadAll,
        .calendarReadAll, .assignmentsManage,
        .jobNotesRead, .jobNotesCreate, .jobPhotosRead, .jobPhotosCreate,
        .equipmentRead, .equipmentManage,
        .fieldWorkerLocationReadAll,
        .quotesRead, .quotesManage, .quoteFinancialsRead,
        .invoicesRead, .invoicesManage,
        .paymentsRead, .paymentsManage,
        .smsLedgerRead, .smsCreditsConsume,
        .reportsOperational, .reportsFinancial
    ]

    /// Dispatcher: operations only. Sees quotes for context but never their money.
    private static let dispatcherPermissions: Set<Permission> = [
        .companyProfileRead,
        .usersRead,
        .customersReadAll, .customersManage,
        .jobsReadAll, .jobsManage, .jobStatusHistoryReadAll,
        .calendarReadAll, .assignmentsManage,
        .jobNotesRead, .jobNotesCreate, .jobPhotosRead, .jobPhotosCreate,
        .equipmentRead,
        .fieldWorkerLocationReadAll,
        .quotesRead,
        .smsCreditsConsume,
        .reportsOperational
    ]

    /// Field worker: assigned work only. No financial permission of any kind.
    private static let fieldWorkerPermissions: Set<Permission> = [
        .jobsReadAssignedOnly,
        .customersReadAssignedSiteOnly,
        .calendarReadOwnOnly,
        .jobStatusUpdateOwn,
        .jobNotesRead, .jobNotesCreate,
        .jobPhotosRead, .jobPhotosCreate,
        .equipmentRead,
        .fieldWorkerLocationReadOwnOnly
    ]

    /// Accounts: the money. No operational job control, no SaaS billing by default.
    private static let accountsPermissions: Set<Permission> = [
        .companyProfileRead,
        .usersRead,
        .customersReadAll, .customerBillingDetailsRead,
        .jobsReadAll,
        .quotesRead, .quoteFinancialsRead,
        .invoicesRead, .invoicesManage,
        .paymentsRead, .paymentsManage,
        .smsLedgerRead,
        .reportsFinancial
    ]
}
