import Foundation

/// The document families that carry a customer-facing reference number.
nonisolated enum DocumentKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case quote
    case job
    case invoice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quote: return "Quotes"
        case .job: return "Jobs"
        case .invoice: return "Invoices"
        }
    }

    /// Sensible starting point for a newly created company. A default, not a
    /// rule: every company owns its own sequence row and may change these.
    var defaultPrefix: String {
        switch self {
        case .quote: return "Q-"
        case .job: return "J-"
        case .invoice: return "INV-"
        }
    }

    var defaultStartValue: Int { 1001 }
}

/// One company's numbering sequence for one document family.
///
/// Numbering is company-scoped by construction: the sequence row is keyed by
/// `companyID`, so one tenant's counter can never be advanced, read or
/// influenced by another's. Uniqueness is enforced within the company only —
/// two companies are free to both issue "Q-1001".
///
/// In production this is a `document_sequences` table with a unique constraint
/// on `(company_id, kind)` and the increment taken under a row lock; the same
/// shape backs the eventual numbering-settings screen without another
/// migration.
nonisolated struct DocumentSequence: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let kind: DocumentKind
    /// Company-configurable, e.g. "Q-", "EST", "" for no prefix at all.
    var prefix: String
    /// The value the next issued document will take.
    var nextValue: Int
    /// Zero-padding width; 0 means no padding.
    var padWidth: Int

    init(
        id: String,
        companyID: String,
        kind: DocumentKind,
        prefix: String? = nil,
        nextValue: Int? = nil,
        padWidth: Int = 0
    ) {
        self.id = id
        self.companyID = companyID
        self.kind = kind
        self.prefix = prefix ?? kind.defaultPrefix
        self.nextValue = nextValue ?? kind.defaultStartValue
        self.padWidth = padWidth
    }

    func format(_ value: Int) -> String {
        let digits = padWidth > 0
            ? String(format: "%0\(padWidth)d", value)
            : String(value)
        return prefix + digits
    }

    /// The company's default sequence, created on demand the first time a
    /// company issues a document of this kind.
    static func makeDefault(companyID: String, kind: DocumentKind) -> DocumentSequence {
        DocumentSequence(
            id: "seq_\(companyID)_\(kind.rawValue)",
            companyID: companyID,
            kind: kind
        )
    }
}
