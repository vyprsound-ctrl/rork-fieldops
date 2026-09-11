import Foundation

// =============================================================================
// The Harbour South commercial model, as the app renders it.
//
// EVERY VALUE IN THIS FILE IS COMPUTED SERVER-SIDE.
//
// `CommercialState` is a decode of one call to `company_commercial_state()`.
// Nothing here decides whether a company is a Founding Member, what its number
// is, whether the benefit is active this month, what its subscription costs, or
// what platform fee applies. The database decides all six and this type carries
// the answers. The computed properties below only turn those answers into
// sentences — they never re-derive the answer itself.
//
// That distinction is the whole security model for this feature: a client that
// cannot compute eligibility cannot grant itself eligibility.
// =============================================================================

/// The two permanent payment models, plus the trial's "not chosen yet".
nonisolated enum PaymentModel: String, Codable, Hashable, Sendable {
    /// In trial, or the end of the trial has been reached without a choice.
    case undecided
    /// MODEL A — the company's own connected Stripe account, with Harbour
    /// South's platform fee on payments processed through Harbour South.
    case harbourSouthPayments
    /// MODEL B — the company keeps its existing payment provider and supplies
    /// its customer-facing payment link. No Harbour South transaction fee.
    case externalProvider

    var title: String {
        switch self {
        case .undecided: return "Not chosen yet"
        case .harbourSouthPayments: return "Harbour South Payments"
        case .externalProvider: return "My own payment provider"
        }
    }
}

/// Where the company's Stripe onboarding actually stands.
///
/// Derived from the same three booleans Stripe itself reports, in one place, so
/// no screen invents a fourth interpretation of "connected".
nonisolated enum StripeConnectionState: Hashable, Sendable {
    /// No Stripe account for this company at all.
    case notConnected
    /// Account created, Stripe still wants information.
    case onboarding
    /// Charges enabled. The company can take a customer card payment.
    case connected
    /// Stripe is asking for something specific before it will continue.
    case actionRequired([String])
    /// Stripe has switched charges off.
    case paymentsDisabled(String?)

    var title: String {
        switch self {
        case .notConnected: return "Not connected"
        case .onboarding: return "Setup in progress"
        case .connected: return "Stripe connected"
        case .actionRequired: return "Action required"
        case .paymentsDisabled: return "Payments disabled"
        }
    }

    /// The single action this state offers, in the words of the button.
    var actionTitle: String? {
        switch self {
        case .notConnected: return "Connect Stripe"
        case .onboarding: return "Continue Stripe setup"
        case .connected: return "Manage Stripe"
        case .actionRequired: return "Resolve issue"
        case .paymentsDisabled: return "Resolve issue"
        }
    }

    var tone: StatusTone {
        switch self {
        case .notConnected: return .neutral
        case .onboarding: return .info
        case .connected: return .success
        case .actionRequired: return .warning
        case .paymentsDisabled: return .danger
        }
    }

    var isConnected: Bool { self == .connected }
}

/// One company's whole commercial position, exactly as the server reported it.
nonisolated struct CommercialState: Hashable, Sendable {
    let paymentModel: PaymentModel
    let subscriptionStatus: SubscriptionStatus

    // Trial — server-authoritative window.
    let trialEndsAt: Date?
    let trialDaysRemaining: Int
    let isTrialActive: Bool

    // Stripe, as Stripe reports it.
    let stripeConnected: Bool
    let chargesEnabled: Bool
    let payoutsEnabled: Bool
    let detailsSubmitted: Bool
    let requirementsDue: [String]
    let disabledReason: String?
    let stripeAccountID: String?

    // Founding 100.
    /// The company's assigned number, 1–100. `nil` means it holds no place.
    let foundingMemberNumber: Int?
    let foundingClaimedAt: Date?
    let foundingPlacesClaimed: Int
    let foundingPlacesRemaining: Int
    /// False once all hundred places are gone — and the UI must then stop
    /// promising Founding Member status to anyone who does not already hold it.
    let foundingOfferOpen: Bool
    /// Whether the $0/month benefit applies **this calendar month**. Requires
    /// both a number and a qualifying payment; computed in the database.
    let foundingBenefitActive: Bool
    let qualifyingPaymentsThisMonth: Int
    let lastQualifyingPaymentAt: Date?
    let activityMonthStart: Date?

    // Price, from the company's existing tier. No new pricing lives here.
    let tierID: String
    let tierName: String
    /// What the company's tier costs at its current head count.
    let subscriptionMonthlyCents: Int
    /// What it actually pays right now — 0 while the Founding benefit is live.
    let effectiveMonthlyCents: Int
    /// Harbour South's platform fee in basis points. 30 = 0.30%. Always 0 for
    /// an external-provider company, because Harbour South is not a party to
    /// that payment at all.
    let platformFeeBps: Int

    let externalPaymentURL: String?
    let businessEmail: String?

    /// Whether this session may initiate or change Stripe/billing. Read from
    /// the session's grants, not from the server payload — the server has
    /// already refused the whole call to a role without billing read.
    let canManageBilling: Bool

    // MARK: - Derived presentation
    //
    // Sentences only. Every one of these reads a server-supplied fact.

    var stripeState: StripeConnectionState {
        if !stripeConnected { return .notConnected }
        if let disabledReason, !disabledReason.isEmpty {
            return .paymentsDisabled(disabledReason)
        }
        if chargesEnabled { return .connected }
        if !requirementsDue.isEmpty { return .actionRequired(requirementsDue) }
        return .onboarding
    }

    /// True when the company holds one of the hundred places, whether or not
    /// the benefit is active this month. A number is never taken away.
    var isFoundingMember: Bool { foundingMemberNumber != nil }

    /// "Founding Member #27"
    var foundingBadgeTitle: String? {
        foundingMemberNumber.map { "Founding Member #\($0)" }
    }

    /// The fee as a person reads it: "0.30%".
    var platformFeeLabel: String {
        guard platformFeeBps > 0 else { return "0%" }
        let percent = Decimal(platformFeeBps) / 100
        return percent.formatted(.number.precision(.fractionLength(0...2))) + "%"
    }

    var subscriptionPriceLabel: String { SubscriptionQuote.money(subscriptionMonthlyCents) }

    /// What the company pays Harbour South each month, right now.
    var effectivePriceLabel: String {
        effectiveMonthlyCents == 0 ? "$0" : SubscriptionQuote.money(effectiveMonthlyCents)
    }

    /// The headline commercial position, for a badge or a settings row.
    var headline: String {
        if isTrialActive {
            return trialDaysRemaining == 1
                ? "Free trial — 1 day left"
                : "Free trial — \(trialDaysRemaining) days left"
        }
        if isFoundingMember {
            return foundingBenefitActive
                ? "Founding Member — $0/month"
                : "Founding Member — subscription applies"
        }
        switch paymentModel {
        case .harbourSouthPayments:
            return "Harbour South Payments — \(subscriptionPriceLabel)/month"
        case .externalProvider:
            return "\(tierName) — \(subscriptionPriceLabel)/month"
        case .undecided:
            return "\(tierName) — \(subscriptionPriceLabel)/month"
        }
    }

    /// The Founding Member benefit explained positively, never as a penalty.
    var foundingBenefitMessage: String? {
        guard isFoundingMember else { return nil }
        return foundingBenefitActive
            ? "Your Harbour South subscription is $0/month while you actively process customer payments through Harbour South."
            : "Process a customer payment through Harbour South this month to maintain your Founding Member benefit."
    }

    /// What an unconnected company can honestly be told about the offer. Nil
    /// when the hundred places are gone, so nothing promises a place that no
    /// longer exists.
    var foundingInvitation: String? {
        guard !isFoundingMember, foundingOfferOpen else { return nil }
        return "Founding Members can receive $0/month while actively processing customer payments through Harbour South. \(foundingPlacesRemaining) of 100 places remain."
    }

    /// What the trial ends with, given the model the company is on.
    var trialOutcomeMessage: String {
        switch paymentModel {
        case .harbourSouthPayments where isFoundingMember:
            return "When your trial ends you stay on $0/month as a Founding Member, for as long as you process customer payments through Harbour South each month."
        case .harbourSouthPayments:
            return "When your trial ends, your \(tierName) subscription of \(subscriptionPriceLabel)/month begins. Customer card payments carry a \(platformFeeLabel) Harbour South fee."
        case .externalProvider:
            return "When your trial ends, your \(tierName) subscription of \(subscriptionPriceLabel)/month begins. Harbour South charges no transaction fee on payments you take through your own provider."
        case .undecided:
            return "Choose how you take customer payments before your trial ends. Connect Stripe to use Harbour South Payments, or keep your own payment provider."
        }
    }

    /// Shown while no payment model has been chosen and the trial is nearly up.
    var needsPaymentModelChoice: Bool {
        paymentModel == .undecided && !stripeConnected
    }
}

/// One editable business email identity, plus whether this caller may set it.
nonisolated struct BusinessEmailSettings: Hashable, Sendable {
    /// The address customers see as the sender and reply to. `nil` means the
    /// business has not set one, and replies reach nobody in particular.
    var email: String?
    /// The company name, which is the display name on the invoice email.
    let companyName: String
    let canManage: Bool

    var isConfigured: Bool { (email ?? "").isEmpty == false }
}

/// Validation for the business's customer-facing email address.
///
/// The rule is expressed twice on purpose: here, so the person typing gets a
/// sentence they can act on, and again as the `companies_business_email_valid`
/// check constraint in the database, which is the one that actually holds.
nonisolated enum BusinessEmail {
    static let maximumLength = 254

    nonisolated enum ValidationError: LocalizedError, Equatable {
        case malformed
        case tooLong

        var errorDescription: String? {
            switch self {
            case .malformed:
                return "That doesn't look like an email address. Use the address your customers already write to, like invoices@yourbusiness.com."
            case .tooLong:
                return "That address is too long."
            }
        }
    }

    /// Trims and validates. Empty input returns `nil`, which is how the address
    /// is cleared.
    static func normalise(_ raw: String) throws -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= maximumLength, trimmed.count >= 6 else {
            throw ValidationError.tooLong
        }
        guard !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw ValidationError.malformed
        }

        // One @, a local part, and a dotted domain. Deliberately the same shape
        // as the database's constraint rather than a stricter local rule that
        // would reject an address the server would accept.
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2,
              !parts[0].isEmpty,
              parts[1].contains("."),
              !parts[1].hasPrefix("."),
              !parts[1].hasSuffix("."),
              !parts[1].contains("..") else {
            throw ValidationError.malformed
        }

        return trimmed
    }
}
