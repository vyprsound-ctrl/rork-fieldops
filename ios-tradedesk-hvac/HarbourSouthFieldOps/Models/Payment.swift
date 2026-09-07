import Foundation

nonisolated enum PaymentMethod: String, Codable, CaseIterable, Sendable, Identifiable {
    case card
    case ach
    case cash
    case check

    var id: String { rawValue }

    var title: String {
        switch self {
        case .card: return "Card"
        case .ach: return "ACH"
        case .cash: return "Cash"
        case .check: return "Check"
        }
    }

    var symbolName: String {
        switch self {
        case .card: return "creditcard.fill"
        case .ach: return "building.columns.fill"
        case .cash: return "banknote.fill"
        case .check: return "doc.text.fill"
        }
    }

    /// What the person recording it is asked for: a check number, an ACH trace,
    /// a receipt reference. Free text so it suits any country's conventions.
    var referencePrompt: String {
        switch self {
        case .card: return "Card reference (optional)"
        case .ach: return "ACH trace number (optional)"
        case .cash: return "Receipt number (optional)"
        case .check: return "Check number"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PaymentMethod(rawValue: raw) ?? .cash
    }
}

nonisolated enum PaymentStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case pending
    case succeeded
    case failed
    case refunded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pending: return "Pending"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .refunded: return "Refunded"
        }
    }

    var tone: StatusTone {
        switch self {
        case .pending: return .warning
        case .succeeded: return .success
        case .failed: return .danger
        case .refunded: return .neutral
        }
    }

    /// Only a succeeded payment reduces an invoice balance. Pending, failed and
    /// refunded rows are kept for the audit trail and counted as nothing.
    var reducesBalance: Bool { self == .succeeded }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = PaymentStatus(rawValue: raw) ?? .pending
    }
}

/// Money the trade business collects from *its* customers, recorded by hand.
///
/// TradeDesk is not a payment processor and holds no processor identifiers. A
/// payment row is the contractor's own record that money arrived — by card
/// terminal, bank transfer, cash or check — and `reference` is whatever they
/// write down for it. It is never mixed with the platform's own subscription
/// billing.
///
/// DEVELOPMENT: `isSimulated` is a stored fact on the record, not a display
/// flag, so a simulated payment can never be mistaken for a real one anywhere
/// in the app or in a later migration of this data.
nonisolated struct Payment: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let invoiceID: String
    var amount: Decimal
    var method: PaymentMethod
    var status: PaymentStatus
    /// The company's own reference: check number, ACH trace, receipt number.
    var reference: String?
    var note: String?
    var receivedAt: Date
    var recordedByUserID: String
    /// True for every payment taken in a development build.
    var isSimulated: Bool

    init(
        id: String,
        companyID: String,
        invoiceID: String,
        amount: Decimal,
        method: PaymentMethod,
        status: PaymentStatus,
        reference: String? = nil,
        note: String? = nil,
        receivedAt: Date,
        recordedByUserID: String,
        isSimulated: Bool = true
    ) {
        self.id = id
        self.companyID = companyID
        self.invoiceID = invoiceID
        self.amount = amount
        self.method = method
        self.status = status
        self.reference = reference
        self.note = note
        self.receivedAt = receivedAt
        self.recordedByUserID = recordedByUserID
        self.isSimulated = isSimulated
    }
}
