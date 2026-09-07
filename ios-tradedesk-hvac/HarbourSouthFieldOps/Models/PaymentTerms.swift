import Foundation

/// A convenience list of common payment terms, used to *offer* a due date when
/// an invoice is raised.
///
/// This enum is a picker, not a schema. The invoice itself stores the agreed
/// terms as a free-text snapshot plus an explicit due date, so a company that
/// works to "50% on delivery" or a country with its own conventions is never
/// forced into this list. Nothing here is trade-specific: net terms mean the
/// same thing to a roofer, a locksmith and a pest controller.
nonisolated enum PaymentTerms: String, CaseIterable, Sendable, Identifiable {
    case dueOnReceipt
    case net7
    case net14
    case net15
    case net30
    case net45
    case net60

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dueOnReceipt: return "Due on receipt"
        case .net7: return "Net 7"
        case .net14: return "Net 14"
        case .net15: return "Net 15"
        case .net30: return "Net 30"
        case .net45: return "Net 45"
        case .net60: return "Net 60"
        }
    }

    /// Days from issue to due.
    var dueDays: Int {
        switch self {
        case .dueOnReceipt: return 0
        case .net7: return 7
        case .net14: return 14
        case .net15: return 15
        case .net30: return 30
        case .net45: return 45
        case .net60: return 60
        }
    }

    func dueDate(from issueDate: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: dueDays, to: issueDate) ?? issueDate
    }

    /// Best-effort match for a customer's stored billing terms, which are free
    /// text. Returns `nil` when the text is something this list can't express —
    /// the caller then keeps the customer's own wording rather than forcing it
    /// into the wrong bucket.
    static func matching(_ raw: String) -> PaymentTerms? {
        let normalised = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalised.isEmpty else { return nil }
        return allCases.first { $0.title.lowercased() == normalised }
    }
}
