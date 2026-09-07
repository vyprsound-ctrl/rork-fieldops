import Foundation

/// The tenant. Everything the app formats, calculates or numbers is read from
/// here rather than from a constant somewhere in the code.
///
/// Country, currency and timezone are *company* configuration. V1 sells into
/// the United States, so the seeded companies are US/USD/US-timezone — but no
/// calculation, model or formatter is allowed to assume that. Adding a second
/// country later is a data change, not a code change.
nonisolated struct Company: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    /// Configuration only. Drives display terminology now, and later job
    /// templates and optional trade fields — never the data model itself.
    var trade: Trade
    /// ISO 3166-1 alpha-2, e.g. "US". Owns address shape and date conventions.
    var countryCode: String
    /// ISO 4217, e.g. "USD". Every money label is formatted with this code;
    /// nothing in the app formats currency without asking a company first.
    var currencyCode: String
    var timeZoneIdentifier: String
    var addressLine: String
    var city: String
    var state: String
    var postalCode: String
    var phone: String
    /// The company's **default** tax rate for new line items, as a decimal
    /// fraction (0.07 == 7%).
    ///
    /// This is a default, never a rule. Each quote and invoice line stores the
    /// rate that applied when it was written, so changing this value re-points
    /// future lines only and leaves every existing document's tax historically
    /// stable. Money never touches binary floating point.
    var defaultTaxRate: Decimal
    /// Optional. Where this company sends *their* customers to pay online — a
    /// Stripe payment link, a Square link, a PayPal.me page, their own portal:
    /// whatever they already use.
    ///
    /// TradeDesk stores a URL and nothing else. There is no processor account,
    /// no API credential and no integration behind it, and the money never
    /// passes through this product. `nil` simply means no payment button is
    /// offered to the customer.
    var onlinePaymentLinkURL: String?

    var terminology: Terminology { trade.terminology }

    var timeZone: TimeZone { TimeZone(identifier: timeZoneIdentifier) ?? .current }

    /// Used only when a company record cannot be resolved, so a label degrades
    /// instead of crashing. Never a business default.
    static let fallbackCurrencyCode = "USD"
}
