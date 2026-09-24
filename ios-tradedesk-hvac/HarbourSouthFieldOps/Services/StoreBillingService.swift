import Foundation
import StoreKit

// =============================================================================
// Harbour South's own subscription — Apple auto-renewable subscriptions via
// StoreKit 2.
//
// THE DEVICE IS NOT THE AUTHORITY. StoreKit tells the app what Apple sold;
// the app hands Apple's SIGNED transaction and renewal info (JWS) to the
// `apple-subscription` Edge Function, which verifies them against Apple's root
// certificate and records the entitlement. Every screen then renders
// `company_commercial_state()`, never a local guess. App Store Server
// Notifications keep the server current when the app is closed.
//
// This is the only money seam for Harbour South's own subscription. Customer
// payments to the trade business are a separate Stripe flow and never pass
// through here.
// =============================================================================

/// Apple's signed evidence of one subscription purchase.
nonisolated struct SignedStorePurchase: Hashable, Sendable, Encodable {
    /// `VerificationResult<Transaction>.jwsRepresentation`.
    let transaction: String
    /// `VerificationResult<RenewalInfo>.jwsRepresentation`, when available.
    let renewal: String?
    let transactionID: UInt64
    let productID: String
    enum CodingKeys: String, CodingKey { case transaction, renewal }
}

/// One plan product as the App Store sells it in this storefront.
nonisolated struct StorePlanProduct: Identifiable, Hashable, Sendable {
    let id: String
    let plan: PlanID
    let period: BillingPeriod
    /// Apple's localized price, e.g. "$39.99".
    let displayPrice: String
    /// Days of free introductory offer configured in App Store Connect.
    let introFreeDays: Int?
    /// Whether this Apple ID can still take the introductory offer.
    let isEligibleForIntroOffer: Bool
}

nonisolated enum StorePurchaseOutcome: Hashable, Sendable {
    case purchased(SignedStorePurchase)
    /// Ask to Buy or Strong Customer Authentication: Apple will finish later
    /// and deliver it through `Transaction.updates`.
    case pending
    case cancelled
}

nonisolated enum StoreBillingError: LocalizedError, Equatable {
    case productsUnavailable
    case unverified
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .productsUnavailable:
            return "Plans can't be bought right now. Check your connection and try again."
        case .unverified:
            return "Apple couldn't confirm that purchase. Try Restore purchases."
        case .unavailable(let reason):
            return reason
        }
    }
}

protocol StoreBillingService: Sendable {
    var mode: ServiceMode { get }
    /// The six plan products, with the customer's own local prices.
    func products() async throws -> [StorePlanProduct]
    /// Buys (or switches to) a plan. `appAccountToken` is the company id, so
    /// Apple's notifications can be tied back to the company.
    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome
    /// Asks Apple to resync, then returns every current subscription.
    func restore() async throws -> [SignedStorePurchase]
    /// Every subscription this Apple ID currently holds for the app.
    func currentPurchases() async -> [SignedStorePurchase]
    /// Purchases, renewals, Offer Code redemptions and refunds that happen
    /// outside a purchase call.
    func transactionUpdates() -> AsyncStream<SignedStorePurchase>
    /// Marks a transaction handled once the server has recorded it.
    func finish(transactionID: UInt64) async
}

// MARK: - Production

/// StoreKit 2.
actor StoreKitBillingService: StoreBillingService {
    nonisolated let mode: ServiceMode = .production

    private var cachedProducts: [String: Product] = [:]
    private var unfinished: [UInt64: Transaction] = [:]

    func products() async throws -> [StorePlanProduct] {
        let loaded = try await loadProducts()
        var result: [StorePlanProduct] = []
        for product in loaded.values {
            guard let resolved = PlanCatalog.resolve(productID: product.id) else { continue }
            let intro = product.subscription?.introductoryOffer
            let freeDays: Int? = intro.flatMap { offer in
                offer.paymentMode == .freeTrial ? Self.days(offer.period, count: offer.periodCount) : nil
            }
            let eligible = await product.subscription?.isEligibleForIntroOffer ?? false
            result.append(StorePlanProduct(
                id: product.id,
                plan: resolved.plan,
                period: resolved.period,
                displayPrice: product.displayPrice,
                introFreeDays: freeDays,
                isEligibleForIntroOffer: eligible
            ))
        }
        return result
    }

    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome {
        let loaded = try await loadProducts()
        guard let product = loaded[productID] else { throw StoreBillingError.productsUnavailable }

        var options: Set<Product.PurchaseOption> = []
        if let appAccountToken { options.insert(.appAccountToken(appAccountToken)) }

        switch try await product.purchase(options: options) {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { throw StoreBillingError.unverified }
            unfinished[transaction.id] = transaction
            let renewal = await renewalJWS(for: product)
            return .purchased(SignedStorePurchase(
                transaction: verification.jwsRepresentation,
                renewal: renewal,
                transactionID: transaction.id,
                productID: transaction.productID
            ))
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    func restore() async throws -> [SignedStorePurchase] {
        try await AppStore.sync()
        return await currentPurchases()
    }

    func currentPurchases() async -> [SignedStorePurchase] {
        var purchases: [SignedStorePurchase] = []
        let loaded = (try? await loadProducts()) ?? [:]

        // Subscription status carries both the latest transaction and its
        // renewal info (auto-renew, billing retry, grace period).
        if let product = loaded.values.first, let statuses = try? await product.subscription?.status {
            for status in statuses {
                guard case .verified(let transaction) = status.transaction else { continue }
                purchases.append(SignedStorePurchase(
                    transaction: status.transaction.jwsRepresentation,
                    renewal: status.renewalInfo.jwsRepresentation,
                    transactionID: transaction.id,
                    productID: transaction.productID
                ))
            }
        }

        for await verification in Transaction.currentEntitlements {
            guard case .verified(let transaction) = verification,
                  transaction.productType == .autoRenewable,
                  !purchases.contains(where: { $0.transactionID == transaction.id }) else { continue }
            purchases.append(SignedStorePurchase(
                transaction: verification.jwsRepresentation,
                renewal: nil,
                transactionID: transaction.id,
                productID: transaction.productID
            ))
        }
        return purchases
    }

    nonisolated func transactionUpdates() -> AsyncStream<SignedStorePurchase> {
        AsyncStream { continuation in
            let task = Task.detached {
                for await verification in Transaction.updates {
                    guard case .verified(let transaction) = verification,
                          transaction.productType == .autoRenewable else { continue }
                    await self.remember(transaction)
                    continuation.yield(SignedStorePurchase(
                        transaction: verification.jwsRepresentation,
                        renewal: nil,
                        transactionID: transaction.id,
                        productID: transaction.productID
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func finish(transactionID: UInt64) async {
        if let transaction = unfinished.removeValue(forKey: transactionID) {
            await transaction.finish()
            return
        }
        for await verification in Transaction.unfinished {
            if case .verified(let transaction) = verification, transaction.id == transactionID {
                await transaction.finish()
                return
            }
        }
    }

    // MARK: Private

    private func remember(_ transaction: Transaction) {
        unfinished[transaction.id] = transaction
    }

    private func loadProducts() async throws -> [String: Product] {
        if cachedProducts.count == PlanCatalog.allProductIDs.count { return cachedProducts }
        let loaded = try await Product.products(for: PlanCatalog.allProductIDs)
        guard !loaded.isEmpty else { throw StoreBillingError.productsUnavailable }
        cachedProducts = Dictionary(uniqueKeysWithValues: loaded.map { ($0.id, $0) })
        return cachedProducts
    }

    private func renewalJWS(for product: Product) async -> String? {
        guard let statuses = try? await product.subscription?.status else { return nil }
        return statuses.first?.renewalInfo.jwsRepresentation
    }

    private static func days(_ period: Product.SubscriptionPeriod, count: Int) -> Int {
        let unitDays: Int
        switch period.unit {
        case .day: unitDays = 1
        case .week: unitDays = 7
        case .month: unitDays = 30
        case .year: unitDays = 365
        @unknown default: unitDays = 1
        }
        return unitDays * period.value * max(count, 1)
    }
}

// MARK: - Development

/// DEVELOPMENT IMPLEMENTATION — no App Store involvement at all. Shows the
/// standard plan prices and refuses to sell anything, because the development
/// stack has no company Apple could bill.
struct MockStoreBillingService: StoreBillingService {
    let mode: ServiceMode = .simulated

    func products() async throws -> [StorePlanProduct] {
        PlanCatalog.standard.flatMap { plan in
            BillingPeriod.allCases.map { period in
                StorePlanProduct(
                    id: plan.productID(for: period),
                    plan: plan.id,
                    period: period,
                    displayPrice: PriceLabel.usd(plan.priceCents(for: period)),
                    introFreeDays: 14,
                    isEligibleForIntroOffer: true
                )
            }
        }
    }

    func purchase(productID: String, appAccountToken: UUID?) async throws -> StorePurchaseOutcome {
        throw StoreBillingError.unavailable("Plans can only be bought on a live company account.")
    }

    func restore() async throws -> [SignedStorePurchase] { [] }
    func currentPurchases() async -> [SignedStorePurchase] { [] }
    func transactionUpdates() -> AsyncStream<SignedStorePurchase> { AsyncStream { $0.finish() } }
    func finish(transactionID: UInt64) async {}
}
