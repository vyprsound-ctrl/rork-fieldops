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

/// The database's plan enum. `soloTrader` is the stored name of Starter and is
/// kept only because it is a Postgres enum value; customers only ever see
/// "Starter".
nonisolated enum SubscriptionPlan: String, Codable, Sendable {
    case soloTrader
    case team
    case business

    var title: String {
        switch self {
        case .soloTrader: return "Starter"
        case .team: return "Team"
        case .business: return "Business"
        }
    }

    var planID: PlanID {
        switch self {
        case .soloTrader: return .starter
        case .team: return .team
        case .business: return .business
        }
    }

    init(planID: PlanID) {
        switch planID {
        case .starter: self = .soloTrader
        case .team: self = .team
        case .business: self = .business
        }
    }
}

nonisolated enum BillingPeriod: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case monthly
    case annual

    var id: String { rawValue }
    var title: String { self == .monthly ? "Monthly" : "Annual" }
    /// "/month", "/year".
    var perUnit: String { self == .monthly ? "/month" : "/year" }
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
/// customers, which Harbour South records but never processes.
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
