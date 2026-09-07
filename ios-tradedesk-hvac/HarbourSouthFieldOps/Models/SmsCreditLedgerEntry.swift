import Foundation

nonisolated enum SmsLedgerTransactionType: String, Codable, Sendable {
    case purchase
    case consumption
    case refund
    case adjustment

    var title: String {
        switch self {
        case .purchase: return "Purchase"
        case .consumption: return "Consumption"
        case .refund: return "Refund"
        case .adjustment: return "Adjustment"
        }
    }
}

/// Full double-entry style ledger for SMS credits. The balance is always
/// derived from `balanceAfter` of the newest entry — never stored alone.
nonisolated struct SmsCreditLedgerEntry: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    var transactionType: SmsLedgerTransactionType
    /// Signed: positive for purchase/refund, negative for consumption.
    var amount: Int
    var balanceAfter: Int
    var jobID: String?
    var customerID: String?
    var notificationID: String?
    var purchaseReference: String?
    var createdAt: Date
}
