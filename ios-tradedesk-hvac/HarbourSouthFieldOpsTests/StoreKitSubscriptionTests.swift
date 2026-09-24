import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import HarbourSouthFieldOps

/// StoreKit 2 against a local StoreKit configuration that mirrors the App
/// Store Connect setup Harbour South needs: one subscription group, six
/// products, a 14-day free introductory offer on each, and 30/90-day free
/// Offer Codes.
///
/// These prove the app's StoreKit service loads the products and reads
/// purchases, renewals, expiry, upgrades and refunds correctly. They do NOT
/// prove anything about App Store Connect itself, and the transactions here are
/// signed by Xcode, not Apple — the server correctly refuses them.
///
/// DISABLED IN THE MANAGED RUNNER: it refuses `SKTestSession` with
/// `SKTestError.notEntitled` and serves no local products, so every test here
/// fails before reaching app code. Remove the trait and run in Xcode
/// (Product → Test) to execute them against the bundled .storekit file.
@Suite(.serialized, .disabled("SKTestSession is not permitted by the managed test runner (notEntitled); run locally in Xcode"))
struct StoreKitSubscriptionTests {
    private func makeSession() throws -> SKTestSession {
        let url = try #require(
            Bundle(for: StoreKitBundleToken.self).url(forResource: "HarbourSouthFieldOps", withExtension: "storekit"),
            "The StoreKit configuration must be bundled with the tests"
        )
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
        return session
    }

    private func status(_ productID: String) async throws -> Product.SubscriptionInfo.Status? {
        let product = try #require(try await Product.products(for: [productID]).first)
        return try await product.subscription?.status.first
    }

    private func payload(_ jws: String) throws -> [String: Any] {
        let part = jws.split(separator: ".")[1]
        var b64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        let data = try #require(Data(base64Encoded: b64))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("All six plan products load with the right plan, period and price")
    func productsLoad() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let products = try await StoreKitBillingService().products()
        #expect(products.count == 6)
        for plan in PlanCatalog.standard {
            for period in BillingPeriod.allCases {
                let product = products.first { $0.id == plan.productID(for: period) }
                #expect(product?.plan == plan.id)
                #expect(product?.period == period)
                #expect(product?.displayPrice.contains(PriceLabel.usd(plan.priceCents(for: period)).filter { $0.isNumber || $0 == "." }) == true)
            }
        }
    }

    @Test("Every product offers a 14-day free trial to a new subscriber")
    func introductoryTrial() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let products = try await StoreKitBillingService().products()
        for product in products {
            #expect(product.introFreeDays == 14, "\(product.id)")
            #expect(product.isEligibleForIntroOffer, "\(product.id)")
        }
    }

    @Test("A first purchase starts the free trial, is an entitlement, and hands the server signed data")
    func firstPurchaseIsTrial() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let transaction = try await session.buyProduct(identifier: "com.harboursouth.fieldservice.team.monthly")
        #expect(transaction.offer?.type == .introductory)
        #expect(transaction.offer?.paymentMode == .freeTrial)

        let purchases = await StoreKitBillingService().currentPurchases()
        let purchase = try #require(purchases.first { $0.productID == "com.harboursouth.fieldservice.team.monthly" })
        #expect(purchase.transaction.split(separator: ".").count == 3)
        #expect(purchase.renewal?.split(separator: ".").count == 3)

        let decoded = try payload(purchase.transaction)
        #expect(decoded["productId"] as? String == "com.harboursouth.fieldservice.team.monthly")
        #expect(decoded["offerType"] as? Int == 1)
        #expect(decoded["type"] as? String == "Auto-Renewable Subscription")

        let current = try await status("com.harboursouth.fieldservice.team.monthly")
        #expect(current?.state == .subscribed)
    }

    @Test("After the trial Apple renews automatically into the paid plan")
    func renewalAfterTrial() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        _ = try await session.buyProduct(identifier: "com.harboursouth.fieldservice.starter.monthly")
        try session.forceRenewalOfSubscription(productIdentifier: "com.harboursouth.fieldservice.starter.monthly")

        let current = try await status("com.harboursouth.fieldservice.starter.monthly")
        #expect(current?.state == .subscribed)
        if case .verified(let renewed) = current?.transaction {
            #expect(renewed.offer == nil, "The renewal after a free trial is the normal paid period")
        }
    }

    @Test("An expired subscription is reported as expired")
    func expiry() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        _ = try await session.buyProduct(identifier: "com.harboursouth.fieldservice.team.annual")
        try session.expireSubscription(productIdentifier: "com.harboursouth.fieldservice.team.annual")

        let current = try await status("com.harboursouth.fieldservice.team.annual")
        #expect(current?.state == .expired)
    }

    @Test("Upgrading from Team monthly to Business annual moves the subscription to Business")
    func upgrade() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        _ = try await session.buyProduct(identifier: "com.harboursouth.fieldservice.team.monthly")
        _ = try await session.buyProduct(identifier: "com.harboursouth.fieldservice.business.annual")

        var entitled: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result { entitled.append(transaction.productID) }
        }
        #expect(entitled.contains("com.harboursouth.fieldservice.business.annual"))
        #expect(entitled.contains("com.harboursouth.fieldservice.team.monthly") == false)
    }

    @Test("A refunded subscription is no longer an entitlement")
    func refund() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let transaction = try await session.buyProduct(identifier: "com.harboursouth.fieldservice.starter.annual")
        try session.refundTransaction(identifier: UInt(transaction.id))

        var entitled: [String] = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result { entitled.append(t.productID) }
        }
        #expect(entitled.isEmpty)
    }

    @Test("A cancelled subscription reports that it will not auto-renew")
    func cancellation() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let transaction = try await session.buyProduct(identifier: "com.harboursouth.fieldservice.team.monthly")
        try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))

        let current = try await status("com.harboursouth.fieldservice.team.monthly")
        if case .verified(let renewal) = current?.renewalInfo {
            #expect(renewal.willAutoRenew == false)
        } else {
            Issue.record("No verified renewal info")
        }
    }

    @Test("A second purchase by the same Apple ID gets no second free trial")
    func trialOncePerGroup() async throws {
        let session = try makeSession()
        defer { session.clearTransactions() }

        let first = try await session.buyProduct(identifier: "com.harboursouth.fieldservice.starter.monthly")
        try session.expireSubscription(productIdentifier: "com.harboursouth.fieldservice.starter.monthly")
        _ = first

        let products = try await StoreKitBillingService().products()
        #expect(products.allSatisfy { $0.isEligibleForIntroOffer == false })
    }
}

private final class StoreKitBundleToken {}
