import Foundation

/// The five fixed roles. A user has exactly one role within one company.
///
/// Role names are platform-level and trade-neutral: `fieldWorker` is displayed
/// as Engineer, Plumber, Electrician or Technician depending on the company's
/// trade, without any change to permissions or data access.
nonisolated enum Role: String, Codable, CaseIterable, Identifiable, Sendable {
    case owner
    case admin
    case dispatcher
    case fieldWorker
    case accounts

    var id: String { rawValue }

    /// Trade-neutral name, used where no company context is available.
    var title: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .dispatcher: return "Dispatcher"
        case .fieldWorker: return "Field worker"
        case .accounts: return "Accounts"
        }
    }

    /// Name as this company's trade would say it.
    func title(_ terms: Terminology) -> String {
        self == .fieldWorker ? terms.Worker : title
    }

    func summary(_ terms: Terminology) -> String {
        switch self {
        case .owner: return "Full company access, users and subscription"
        case .admin: return "Full operations, no company or SaaS billing"
        case .dispatcher: return "Jobs, calendar, customers and assignments"
        case .fieldWorker: return "Assigned stops only"
        case .accounts: return "Invoices, payments and financial reports"
        }
    }

    /// Field workers get a completely separate, stripped-down shell.
    var usesFieldShell: Bool { self == .fieldWorker }
}
