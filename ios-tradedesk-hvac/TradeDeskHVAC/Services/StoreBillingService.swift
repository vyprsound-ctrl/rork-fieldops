import Foundation

nonisolated struct StoreSubscriptionResult: Hashable, Sendable {
    let reference: String
    let store: BillingStore
    let simulated: Bool
}

/// The company's subscription to this platform.
/// Production will be Apple In-App Purchase and Google Play Billing.
///
/// This is the *only* money seam in the app. The money a trade business
/// collects from its own customers is never processed here: TradeDesk records
/// payments the contractor tells it about and, when they have configured one,
/// points their customer at the contractor's own payment link. There is no
/// customer-payment service protocol on purpose.
protocol StoreBillingService: Sendable {
    var mode: ServiceMode { get }
    func purchase(plan: SubscriptionPlan, period: BillingPeriod) async throws -> StoreSubscriptionResult
    func restore() async throws -> StoreSubscriptionResult?
}

/// DEVELOPMENT IMPLEMENTATION — no store transaction takes place.
struct MockStoreBillingService: StoreBillingService {
    let mode: ServiceMode = .simulated

    func purchase(plan: SubscriptionPlan, period: BillingPeriod) async throws -> StoreSubscriptionResult {
        try? await Task.sleep(for: .milliseconds(400))
        return StoreSubscriptionResult(reference: "SIMULATED-STORE-\(plan.rawValue)-\(period.rawValue)", store: .apple, simulated: true)
    }

    func restore() async throws -> StoreSubscriptionResult? { nil }
}
