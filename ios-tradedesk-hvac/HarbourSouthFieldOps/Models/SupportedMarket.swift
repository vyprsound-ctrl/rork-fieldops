import Foundation

/// ISSUE #15 — the markets Harbour South can actually operate in.
///
/// THE DEFECT: sign-up asked for a country and a currency as two free-text
/// boxes. A new company could type `ZZ` / `XYZ` and be created in a market where
/// Stripe Connect cannot onboard it, take payments or pay it out — a company
/// that looks fine until the day it tries to get paid. Meanwhile address forms
/// said "State" and "ZIP", and customer validation *required* both, which made
/// the product quietly US-only.
///
/// THE RULE: a market is listed here only where Stripe Connect supports the
/// whole chain — onboarding, connected accounts, charges, payouts and
/// application fees — because a Connect button that cannot work is worse than
/// one that is honestly unavailable.
///
/// WHAT THIS IS NOT: a localisation system. English remains the only language;
/// this decides currency, address vocabulary and Connect eligibility, nothing
/// more. It is also not a second country/currency store — `companies.country`
/// and `companies.currency` remain the authoritative columns, and this type
/// only describes what may be written into them.
nonisolated enum SupportedMarket: String, CaseIterable, Sendable, Identifiable {
    case unitedStates = "US"
    case canada = "CA"
    case unitedKingdom = "GB"
    case australia = "AU"
    case newZealand = "NZ"
    case ireland = "IE"

    var id: String { rawValue }

    /// ISO 3166-1 alpha-2, as stored on `companies.country`.
    var countryCode: String { rawValue }

    var countryName: String {
        switch self {
        case .unitedStates: return "United States"
        case .canada: return "Canada"
        case .unitedKingdom: return "United Kingdom"
        case .australia: return "Australia"
        case .newZealand: return "New Zealand"
        case .ireland: return "Ireland"
        }
    }

    /// The default currency for this market, as stored on `companies.currency`.
    ///
    /// A default, not a constraint: currency stays an explicit company-level
    /// value, because a business may legitimately invoice in another currency.
    var defaultCurrencyCode: String {
        switch self {
        case .unitedStates: return "USD"
        case .canada: return "CAD"
        case .unitedKingdom: return "GBP"
        case .australia: return "AUD"
        case .newZealand: return "NZD"
        case .ireland: return "EUR"
        }
    }

    /// What this country calls the sub-national part of an address. Nil where
    /// the concept does not meaningfully exist, so the field is simply not
    /// shown rather than being labelled with a foreign word.
    var regionLabel: String? {
        switch self {
        case .unitedStates: return "State"
        case .canada: return "Province"
        case .australia: return "State"
        case .ireland: return "County"
        case .unitedKingdom, .newZealand: return nil
        }
    }

    /// What this country calls its postal code. Nil for Ireland, whose Eircode
    /// is optional in practice, and where demanding one blocks real addresses.
    var postalCodeLabel: String? {
        switch self {
        case .unitedStates: return "ZIP"
        case .canada, .australia, .newZealand: return "Postcode"
        case .unitedKingdom: return "Postcode"
        case .ireland: return "Eircode"
        }
    }

    /// Whether Harbour South Payments (Stripe Connect) can serve this market.
    ///
    /// Every listed market is currently supported by Stripe Connect for the
    /// full chain. The property exists so that withdrawing a market is a
    /// one-line data change that automatically disables the Connect call to
    /// action and explains why, instead of leaving a button that 400s.
    var supportsHarbourSouthPayments: Bool {
        switch self {
        case .unitedStates, .canada, .unitedKingdom, .australia, .newZealand, .ireland:
            return true
        }
    }

    /// The market for a stored country code, or nil if it is not one we serve.
    static func market(forCountryCode code: String) -> SupportedMarket? {
        SupportedMarket(rawValue: code.uppercased())
    }

    /// Address vocabulary for a stored country code, falling back to neutral
    /// wording rather than to American wording for an unrecognised country.
    static func addressLabels(forCountryCode code: String) -> (region: String?, postalCode: String?) {
        guard let market = market(forCountryCode: code) else {
            return (region: "Region", postalCode: "Postal code")
        }
        return (region: market.regionLabel, postalCode: market.postalCodeLabel)
    }

    static let fallback: SupportedMarket = .unitedStates
}
