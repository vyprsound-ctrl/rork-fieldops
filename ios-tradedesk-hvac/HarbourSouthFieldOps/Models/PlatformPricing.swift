import Foundation

// =============================================================================
// Harbour South's own plans.
//
// Three plans, the same for every customer:
//
//     Starter   $19.99/month   $191.99/year   1 user          "Just me"
//     Team      $39.99/month   $384.99/year   up to 5 users   "My small team"
//     Business  $69.99/month   $669.99/year   10+ users       "My business"
//
// Billed ONLY by Apple (auto-renewable subscriptions in one subscription
// group). The 14-day free trial is Apple's introductory offer; longer
// promotions are Apple Offer Codes. Nothing in this file charges anybody.
//
// The live price list comes from the `subscription_tiers` table and the
// customer's local price from StoreKit; `PlanCatalog.standard` exists so a
// screen can still explain the plans when neither can be read, and is labelled
// as such wherever it is used.
// =============================================================================

/// The three plans. Raw values are the `subscription_tiers.id` values.
nonisolated enum PlanID: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case starter
    case team
    case business

    var id: String { rawValue }
}

/// One plan as it can be bought.
nonisolated struct PlanOffer: Identifiable, Hashable, Sendable {
    let id: PlanID
    let displayName: String
    /// Who the plan is for, in the owner's own words: "Just me".
    let tagline: String
    let monthlyCents: Int
    let annualCents: Int
    /// Users covered by the price.
    let includedUsers: Int
    /// Hard cap on active users. `nil` means the plan has no cap — Business is
    /// a "10+" plan, never "maximum 10".
    let userLimit: Int?
    let monthlyProductID: String
    let annualProductID: String

    func productID(for period: BillingPeriod) -> String {
        period == .annual ? annualProductID : monthlyProductID
    }

    func priceCents(for period: BillingPeriod) -> Int {
        period == .annual ? annualCents : monthlyCents
    }

    /// "1 user", "Up to 5 users", "10+ users".
    var usersLabel: String {
        guard let userLimit else { return "\(includedUsers)+ users" }
        return userLimit == 1 ? "1 user" : "Up to \(userLimit) users"
    }

    /// Whether a company of this size fits the plan today.
    func fits(activeUsers: Int) -> Bool {
        guard let userLimit else { return true }
        return activeUsers <= userLimit
    }

    /// Percent saved by paying yearly instead of 12 monthly payments, rounded.
    var annualSavingPercent: Int {
        let twelveMonths = Decimal(monthlyCents * 12)
        guard twelveMonths > 0 else { return 0 }
        let saving = (twelveMonths - Decimal(annualCents)) / twelveMonths * 100
        return NSDecimalNumber(decimal: Money.rounded(saving, scale: 0)).intValue
    }

    /// Money saved in a year by paying annually.
    var annualSavingCents: Int { max(monthlyCents * 12 - annualCents, 0) }

    /// What the annual price works out to per month, to the cent.
    var annualPerMonthCents: Int {
        NSDecimalNumber(decimal: Money.rounded(Decimal(annualCents) / 12 / 100, scale: 2) * 100).intValue
    }
}

nonisolated enum PlanCatalog {
    static let productPrefix = "com.harboursouth.fieldservice"

    /// Mirrors migration 0013. Used only when the live price list cannot be
    /// read, and always rendered with a caveat.
    static let standard: [PlanOffer] = [
        PlanOffer(
            id: .starter, displayName: "Starter", tagline: "Just me",
            monthlyCents: 1999, annualCents: 19199, includedUsers: 1, userLimit: 1,
            monthlyProductID: "\(productPrefix).starter.monthly",
            annualProductID: "\(productPrefix).starter.annual"
        ),
        PlanOffer(
            id: .team, displayName: "Team", tagline: "My small team",
            monthlyCents: 3999, annualCents: 38499, includedUsers: 5, userLimit: 5,
            monthlyProductID: "\(productPrefix).team.monthly",
            annualProductID: "\(productPrefix).team.annual"
        ),
        PlanOffer(
            id: .business, displayName: "Business", tagline: "My business, 10+ people",
            monthlyCents: 6999, annualCents: 66999, includedUsers: 10, userLimit: nil,
            monthlyProductID: "\(productPrefix).business.monthly",
            annualProductID: "\(productPrefix).business.annual"
        )
    ]

    /// Every App Store product id, for StoreKit.
    static var allProductIDs: [String] {
        standard.flatMap { [$0.monthlyProductID, $0.annualProductID] }
    }

    /// Which plan and period an App Store product id is.
    static func resolve(productID: String, in plans: [PlanOffer] = standard) -> (plan: PlanID, period: BillingPeriod)? {
        for plan in plans {
            if plan.monthlyProductID == productID { return (plan.id, .monthly) }
            if plan.annualProductID == productID { return (plan.id, .annual) }
        }
        return nil
    }

    /// The smallest plan a company of this size fits.
    static func recommended(forActiveUsers users: Int, in plans: [PlanOffer] = standard) -> PlanOffer? {
        plans.first { $0.fits(activeUsers: max(users, 1)) } ?? plans.last
    }
}

/// Dollar formatting for Harbour South's own US price list.
///
/// Pinned to en_US: these are US-dollar list prices, and formatting them in
/// the device locale turned "$39.99" into "39,99 $US" on a comma-decimal
/// phone. The price a customer actually pays is Apple's localized
/// `displayPrice`, shown instead whenever StoreKit has it.
nonisolated enum PriceLabel {
    private static let locale = Locale(identifier: "en_US")

    static func usd(_ cents: Int) -> String {
        let value = Decimal(cents) / 100
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(locale))
    }

    static func usd3(_ value: Decimal) -> String {
        value.formatted(.currency(code: "USD").precision(.fractionLength(3)).locale(locale))
    }
}

/// A single SMS bundle from the `sms_bundles` table.
///
/// There is deliberately no minimum purchase anywhere in this type or the
/// schema behind it: the smallest seeded bundle is 25 messages, and the
/// consumption path accepts any positive quantity, so a one-van business is
/// never forced to buy 500 messages it will not use.
nonisolated struct SmsBundle: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let credits: Int
    let priceCents: Int

    var priceLabel: String { PriceLabel.usd(priceCents) }

    /// Cost per message, which is the only number that lets a buyer compare
    /// bundles honestly.
    var unitLabel: String {
        let unit = Decimal(priceCents) / Decimal(max(credits, 1)) / 100
        return PriceLabel.usd3(unit) + " each"
    }

    var creditsLabel: String { credits.formatted(.number.grouping(.automatic)) }
}
