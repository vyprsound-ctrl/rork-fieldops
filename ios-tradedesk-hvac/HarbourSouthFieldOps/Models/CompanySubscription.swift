import Foundation

nonisolated enum SubscriptionStatus: String, Codable, Sendable {
    case trialing
    case active
    case pastDue
    case cancelled
    case expired

    var title: String {
        switch self {
        case .trialing: return "Trial"
        case .active: return "Active"
        case .pastDue: return "Past due"
        case .cancelled: return "Cancelled"
        case .expired: return "Expired"
        }
    }
}

nonisolated enum SubscriptionPlan: String, Codable, Sendable {
    case soloTrader
    case team
    case business

    var title: String {
        switch self {
        case .soloTrader: return "Solo Trader"
        case .team: return "Team"
        case .business: return "Business"
        }
    }
}

nonisolated enum BillingPeriod: String, Codable, Sendable {
    case monthly
    case annual

    var title: String { self == .monthly ? "Monthly" : "Annual" }
}

nonisolated enum BillingStore: String, Codable, Sendable {
    case apple
    case google
    case none

    var title: String {
        switch self {
        case .apple: return "Apple In-App Purchase"
        case .google: return "Google Play Billing"
        case .none: return "Not linked"
        }
    }
}

/// The company's own SaaS subscription to this platform.
/// Deliberately isolated from the trade business's revenue from *their*
/// customers, which TradeDesk records but never processes.
nonisolated struct CompanySubscription: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    var status: SubscriptionStatus
    var plan: SubscriptionPlan
    var billingPeriod: BillingPeriod
    var isTrial: Bool
    var trialEndsAt: Date?
    var currentPeriodStart: Date
    var currentPeriodEnd: Date
    var renewalDate: Date
    var seatCount: Int
    var includedUsers: Int
    var additionalUsers: Int
    var store: BillingStore
    var appleOriginalTransactionID: String?
    var googlePurchaseToken: String?
    var cancelledAt: Date?
}
