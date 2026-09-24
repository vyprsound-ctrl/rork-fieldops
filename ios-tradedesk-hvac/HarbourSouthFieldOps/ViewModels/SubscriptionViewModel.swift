import Foundation
import Observation

/// Drives the Subscription screen.
///
/// Holds no commercial logic. Plans come from the database, local prices from
/// StoreKit, and the entitlement from `company_commercial_state()`, which the
/// server derives from Apple's verified data. A purchase is only "done" once
/// the server has verified Apple's signed transaction and the refreshed state
/// says so.
@Observable
final class SubscriptionViewModel {
    private(set) var state: LoadState<SubscriptionOverview> = .idle
    /// The company's position, decided server-side.
    private(set) var commercial: CommercialState?
    /// Why the plan position is absent, when it is.
    private(set) var commercialError: String?
    /// Apple's local prices and intro-offer eligibility, keyed by product id.
    private(set) var storeProducts: [String: StorePlanProduct] = [:]
    private(set) var storeUnavailable: Bool = false
    private(set) var workingProductID: String?
    private(set) var isRestoring: Bool = false
    /// Apple's subscription ids this device's Apple ID holds.
    private(set) var deviceSubscriptionIDs: Set<String> = []
    var period: BillingPeriod = .monthly
    var actionError: String?
    var notice: String?
    /// Neither success nor failure: e.g. a TestFlight purchase that did not
    /// change the company's plan.
    var caution: String?

    static let testPurchaseMessage = "This was a test purchase (TestFlight or Sandbox). It doesn't change your company's plan — nothing has been charged and your plan is exactly as it was."

    var isWorking: Bool { workingProductID != nil || isRestoring }

    /// The company already has a live Apple subscription, but it is billed to
    /// a different Apple ID (e.g. the previous owner's). Plan changes must be
    /// made on that Apple ID; buying here would start a SECOND subscription.
    var isBilledToAnotherAppleID: Bool {
        guard let commercial, commercial.hasEntitlement, commercial.billingStore == .apple,
              let original = commercial.appleOriginalTransactionID else { return false }
        return !deviceSubscriptionIDs.contains(original)
    }

    static let billedElsewhereMessage = "Your company's plan is billed to the Apple ID of the person who subscribed. Change or cancel it from that Apple ID — everyone in your company keeps access in the meantime."

    func load(gateway: DataGateway, store: StoreBillingService, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.subscriptionOverview(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
        await refreshCommercial(gateway: gateway, session: session)
        if let period = commercial?.billingPeriod, showLoading { self.period = period }

        do {
            let products = try await store.products()
            storeProducts = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            storeUnavailable = products.isEmpty
        } catch {
            storeProducts = [:]
            storeUnavailable = true
        }
        deviceSubscriptionIDs = Set(await store.currentPurchases().map { String($0.originalTransactionID) })
    }

    func refreshCommercial(gateway: DataGateway, session: TenantSession) async {
        do {
            commercial = try await gateway.commercialState(session: session)
            commercialError = nil
        } catch {
            commercial = nil
            commercialError = DataError.wrap(error).errorDescription
        }
    }

    /// The price to show: Apple's localized price when StoreKit has it, the
    /// server's price list otherwise.
    func priceLabel(for plan: PlanOffer, period: BillingPeriod) -> String {
        storeProducts[plan.productID(for: period)]?.displayPrice ?? PriceLabel.usd(plan.priceCents(for: period))
    }

    /// The introductory free trial offered on this product to this Apple ID,
    /// in days, or nil. Only Apple decides eligibility.
    func freeTrialDays(for plan: PlanOffer, period: BillingPeriod) -> Int? {
        guard let product = storeProducts[plan.productID(for: period)],
              product.isEligibleForIntroOffer else { return nil }
        return product.introFreeDays
    }

    func isCurrent(_ plan: PlanOffer) -> Bool {
        guard let commercial, commercial.hasEntitlement else { return false }
        return commercial.planID == plan.id && commercial.billingPeriod == period
    }

    func buy(_ plan: PlanOffer, gateway: DataGateway, store: StoreBillingService, session: TenantSession) async {
        guard session.can(.saasBillingManage) else {
            actionError = "Only the account owner can choose a plan."
            return
        }
        guard !isBilledToAnotherAppleID else {
            actionError = Self.billedElsewhereMessage
            return
        }
        let productID = plan.productID(for: period)
        workingProductID = productID
        actionError = nil
        notice = nil
        caution = nil
        defer { workingProductID = nil }

        do {
            // A plan with fewer seats than the company's active users is
            // refused before Apple is ever asked. The owner chooses who to
            // deactivate; nobody is suspended automatically.
            let check = try await gateway.planChangeCheck(session: session, planID: plan.id)
            guard check.allowed else {
                actionError = check.message ?? "Deactivate people first to move to \(plan.displayName)."
                return
            }

            switch try await store.purchase(productID: productID, appAccountToken: UUID(uuidString: session.companyID)) {
            case .cancelled:
                return
            case .pending:
                notice = "Apple is finishing this purchase. Your plan will appear here as soon as it's approved."
            case .purchased(let purchase):
                let result = try await gateway.linkStorePurchases(session: session, purchases: [purchase])
                for id in result.handledTransactionIDs { await store.finish(transactionID: id) }
                apply(Self.purchaseOutcome(result, planName: plan.displayName))
            }
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? DataError.wrap(error).errorDescription
        }
        await refreshCommercial(gateway: gateway, session: session)
    }

    func restore(gateway: DataGateway, store: StoreBillingService, session: TenantSession) async {
        isRestoring = true
        actionError = nil
        notice = nil
        caution = nil
        defer { isRestoring = false }
        do {
            let purchases = try await store.restore()
            guard !purchases.isEmpty else {
                notice = "No Harbour South subscription was found for this Apple ID."
                return
            }
            deviceSubscriptionIDs = Set(purchases.map { String($0.originalTransactionID) })
            let result = try await gateway.linkStorePurchases(session: session, purchases: purchases)
            for id in result.handledTransactionIDs { await store.finish(transactionID: id) }
            if result.belongsToAnotherCompany {
                actionError = "This Apple ID's Harbour South subscription already belongs to another company."
            } else if result.linked {
                notice = "Purchases restored."
            } else if result.testPurchaseNotApplied {
                caution = Self.testPurchaseMessage
            } else {
                notice = "No active Harbour South subscription was found for this Apple ID."
            }
        } catch {
            actionError = (error as? LocalizedError)?.errorDescription ?? DataError.wrap(error).errorDescription
        }
        await refreshCommercial(gateway: gateway, session: session)
    }

    /// What the owner is told after a purchase, from what the SERVER made of
    /// it. "You're on …" only when the server actually applied it.
    enum PurchaseOutcome: Equatable {
        case success(String)
        case failure(String)
        case caution(String)
    }

    static func purchaseOutcome(_ result: StoreLinkResult, planName: String) -> PurchaseOutcome {
        if result.belongsToAnotherCompany {
            return .failure("This Apple ID's Harbour South subscription already belongs to another company.")
        }
        if result.unverified {
            return .failure(StoreBillingError.unverified.errorDescription ?? "Apple couldn't confirm that purchase.")
        }
        if result.linked {
            return .success("You're on \(planName). Thanks for choosing Harbour South.")
        }
        if result.testPurchaseNotApplied {
            return .caution(testPurchaseMessage)
        }
        return .caution("Apple accepted the purchase, but Harbour South hasn't confirmed it yet. It will appear here shortly — or tap Restore purchases.")
    }

    private func apply(_ outcome: PurchaseOutcome) {
        switch outcome {
        case .success(let message): notice = message
        case .failure(let message): actionError = message
        case .caution(let message): caution = message
        }
    }
}
