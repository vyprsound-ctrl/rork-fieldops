import Foundation

/// Harbour South's own price list, as served by the database.
///
/// THE ONE RULE THAT MATTERS: this is **not** progressive bracket pricing. A
/// company falls into exactly one tier, chosen by its *total* active paid-user
/// count, and every user beyond the first is charged that tier's single
/// additional-user rate.
///
///     5 users  → 19.99 + (4 × 12.99)
///     15 users → 19.99 + (14 × 9.99)
///     35 users → 19.99 + (34 × 7.99)
///
/// It is emphatically *not* "the first 10 at one rate, the next 20 at another".
/// A company that grows from 10 to 11 people sees every additional seat reprice
/// downward, not just the eleventh.
///
/// Nothing here is a hard-coded price. `SubscriptionTier` values arrive from the
/// `subscription_tiers` table, so Harbour South can reprice with an UPDATE and
/// no app release. `PlatformPricing.fallback` exists only so a screen can render
/// something truthful when the table cannot be read, and it is labelled as such
/// wherever it is used.
nonisolated struct SubscriptionTier: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let displayName: String
    let minUsers: Int
    let maxUsers: Int
    /// Price of the company's first user, in cents. Included in every tier.
    let baseCents: Int
    /// Flat rate for each user *after* the first, in cents.
    let additionalUserCents: Int
    let sortOrder: Int

    func contains(_ users: Int) -> Bool { users >= minUsers && users <= maxUsers }

    /// Total monthly price for a head count sitting in this tier.
    func monthlyCents(for users: Int) -> Int {
        baseCents + (max(users - 1, 0) * additionalUserCents)
    }
}

/// The complete price list plus the supported ceiling.
nonisolated struct PlatformPricing: Codable, Hashable, Sendable {
    let tiers: [SubscriptionTier]
    let maxUsers: Int
    /// True when these values came from the database rather than the built-in
    /// fallback. Screens say so rather than quietly showing stale prices.
    let isLive: Bool

    /// Mirrors the seed data in migration 0003. Used only when the price list
    /// cannot be read, and always rendered with a caveat.
    static let fallback = PlatformPricing(
        tiers: [
            SubscriptionTier(id: "solo", displayName: "Solo", minUsers: 1, maxUsers: 1,
                             baseCents: 1999, additionalUserCents: 0, sortOrder: 1),
            SubscriptionTier(id: "team", displayName: "Team", minUsers: 2, maxUsers: 10,
                             baseCents: 1999, additionalUserCents: 1299, sortOrder: 2),
            SubscriptionTier(id: "growing", displayName: "Growing Business", minUsers: 11, maxUsers: 30,
                             baseCents: 1999, additionalUserCents: 999, sortOrder: 3),
            SubscriptionTier(id: "larger", displayName: "Larger Business", minUsers: 31, maxUsers: 100,
                             baseCents: 1999, additionalUserCents: 799, sortOrder: 4),
        ],
        maxUsers: 100,
        isLive: false
    )

    func tier(for users: Int) -> SubscriptionTier? {
        let clamped = min(max(users, 1), maxUsers)
        return tiers.first { $0.contains(clamped) } ?? tiers.last
    }

    /// The full derivation for a head count. The app never adds up a
    /// subscription price anywhere else.
    func quote(for users: Int) -> SubscriptionQuote {
        let count = max(users, 1)
        guard let band = tier(for: count) else {
            return SubscriptionQuote(
                activePaidUsers: count, tierID: "", tierName: "Unavailable",
                baseCents: 0, additionalUsers: 0, additionalUserCents: 0,
                monthlyPriceCents: 0, maxUsers: maxUsers,
                isOverCapacity: count > maxUsers, nextUserCents: nil
            )
        }

        let additional = max(count - 1, 0)
        let total = band.monthlyCents(for: count)

        // The marginal cost of the next seat, which may cross into a cheaper
        // tier and reprice every existing seat with it. Showing the sticker
        // rate here would be a lie at the boundary: going from 10 to 11 people
        // actually *reduces* the bill.
        let next: Int? = count >= maxUsers
            ? nil
            : (tier(for: count + 1)?.monthlyCents(for: count + 1)).map { $0 - total }

        return SubscriptionQuote(
            activePaidUsers: count,
            tierID: band.id,
            tierName: band.displayName,
            baseCents: band.baseCents,
            additionalUsers: additional,
            additionalUserCents: band.additionalUserCents,
            monthlyPriceCents: total,
            maxUsers: maxUsers,
            isOverCapacity: count > maxUsers,
            nextUserCents: next
        )
    }
}

/// One company's price, fully itemised so an owner can see exactly why the bill
/// is what it is rather than being shown a total to take on trust.
nonisolated struct SubscriptionQuote: Codable, Hashable, Sendable {
    let activePaidUsers: Int
    let tierID: String
    let tierName: String
    let baseCents: Int
    let additionalUsers: Int
    let additionalUserCents: Int
    let monthlyPriceCents: Int
    let maxUsers: Int
    let isOverCapacity: Bool
    /// Marginal cost of adding one more person. `nil` at the ceiling.
    let nextUserCents: Int?

    var additionalCents: Int { additionalUsers * additionalUserCents }
    var isAtCapacity: Bool { activePaidUsers >= maxUsers }

    /// "$19.99 + 14 × $9.99" — the arithmetic spelled out.
    var breakdownLine: String {
        guard additionalUsers > 0 else { return SubscriptionQuote.money(baseCents) }
        return "\(SubscriptionQuote.money(baseCents)) + \(additionalUsers) × \(SubscriptionQuote.money(additionalUserCents))"
    }

    var monthlyLabel: String { SubscriptionQuote.money(monthlyPriceCents) }

    static func money(_ cents: Int) -> String {
        let value = Decimal(cents) / 100
        return value.formatted(.currency(code: "USD").precision(.fractionLength(2)))
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

    var priceLabel: String { SubscriptionQuote.money(priceCents) }

    /// Cost per message, which is the only number that lets a buyer compare
    /// bundles honestly.
    var unitLabel: String {
        let unit = Decimal(priceCents) / Decimal(max(credits, 1)) / 100
        return unit.formatted(.currency(code: "USD").precision(.fractionLength(3))) + " each"
    }

    var creditsLabel: String { credits.formatted(.number.grouping(.automatic)) }
}
