import Foundation

// =============================================================================
// The Harbour South commercial model, as the app renders it.
//
// EVERY DECISION IN THIS FILE IS MADE SERVER-SIDE.
//
// `CommercialState` is a decode of one call to `company_commercial_state()`.
// The database decides whether the company holds an Apple subscription
// entitlement, which plan and period, whether a free Apple offer is running,
// how many people the plan allows, whether Stripe can take payments and what
// platform fee applies. The computed properties below only turn those answers
// into sentences.
//
// The commercial model is the same for every customer. There is no founding
// programme, no allocation and no benefit for connecting Stripe.
// =============================================================================

/// Every customer-facing name for Harbour South's own fee.
///
/// Harbour South's fee is called the "platform fee" everywhere a customer can
/// read it — "0.3% Harbour South platform fee" for a Stripe-connected company,
/// "0% Harbour South platform fee" for one on its own payment provider.
/// Stripe's processing fees are a separate charge made by Stripe and are
/// always named as such alongside it.
///
/// WORDING ONLY. The rate itself is `platform_settings.application_fee_bps`,
/// read by the server; nothing here computes or changes it.
nonisolated enum PlatformFeeCopy {
    /// The label for an itemised fee row.
    static var rowTitle: String { "\(Brand.company) platform fee" }

    /// "0.3% Harbour South platform fee".
    static func phrase(_ feeLabel: String) -> String {
        "\(feeLabel) \(Brand.company) platform fee"
    }

    /// "0% Harbour South platform fee" — for payments Harbour South is not a
    /// party to at all.
    static var zeroPhrase: String { phrase("0%") }

    /// Stated wherever the platform fee is, so the two are never confused.
    static func withStripeFees(_ feeLabel: String) -> String {
        "Customer card payments carry the \(phrase(feeLabel)), plus Stripe's standard processing fees, which Stripe charges separately."
    }

    /// Earlier names for the same fee. Asserted absent from customer-facing
    /// copy so the old wording cannot drift back in.
    static let retiredWording: [String] = [
        "payment fee",
        "transaction fee",
        "0.30%"
    ]
}

/// The two permanent payment models, plus "not chosen yet".
nonisolated enum PaymentModel: String, Codable, Hashable, Sendable {
    case undecided
    /// MODEL A — the company's own connected Stripe account, with Harbour
    /// South's platform fee on payments processed through Harbour South.
    case harbourSouthPayments
    /// MODEL B — the company keeps its existing payment provider and supplies
    /// its customer-facing payment link. No Harbour South platform fee.
    case externalProvider

    var title: String {
        switch self {
        case .undecided: return "Not chosen yet"
        case .harbourSouthPayments: return "Harbour South Payments"
        case .externalProvider: return "My own payment provider"
        }
    }
}

// MARK: - Stripe

/// Where the company's Stripe account actually stands, in five states a
/// person can act on. Derived in ONE place (`classify`) from what Stripe
/// reports, so every screen uses the same words.
///
/// Stripe's own internal codes (`requirements.past_due`, `rejected.fraud`, …)
/// are never shown to anybody; they only decide which of these applies.
nonisolated enum StripeConnectionState: Hashable, Sendable {
    /// No Stripe account for this company.
    case notConnected
    /// Account exists; Stripe still needs details before payments can start.
    case setupIncomplete
    /// Charges enabled.
    case connected
    /// Everything submitted; Stripe is checking it.
    case underReview
    /// Stripe has restricted or rejected the account.
    case restricted

    /// The one classification. `disabledReason` is Stripe's
    /// `requirements.disabled_reason`.
    static func classify(
        connected: Bool,
        chargesEnabled: Bool,
        detailsSubmitted: Bool,
        requirementsDue: [String],
        disabledReason: String?
    ) -> StripeConnectionState {
        guard connected else { return .notConnected }
        if let reason = disabledReason?.trimmingCharacters(in: .whitespaces), !reason.isEmpty {
            if reason.hasPrefix("requirements.past_due") || reason.hasPrefix("action_required") {
                return .setupIncomplete
            }
            if reason == "requirements.pending_verification" || reason == "under_review" {
                return .underReview
            }
            return .restricted
        }
        if chargesEnabled { return .connected }
        if !detailsSubmitted || !requirementsDue.isEmpty { return .setupIncomplete }
        return .underReview
    }

    var title: String {
        switch self {
        case .notConnected: return "Set up Stripe"
        case .setupIncomplete: return "Finish setting up Stripe"
        case .connected: return "Stripe connected"
        case .underReview: return "Stripe is reviewing your account"
        case .restricted: return "Stripe needs your attention"
        }
    }

    var message: String {
        switch self {
        case .notConnected:
            return "Connect Stripe to receive online payments from your customers."
        case .setupIncomplete:
            return "Complete your Stripe setup to start accepting online payments."
        case .connected:
            return "You're ready to receive online payments."
        case .underReview:
            return "Stripe is checking the details you sent. Online payments start once it finishes — open Stripe to see if it needs anything else."
        case .restricted:
            return "Stripe has paused online payments on this account. Open Stripe to see what it needs from you."
        }
    }

    /// The button. Every state has exactly one next step.
    var actionTitle: String {
        switch self {
        case .notConnected: return "Connect Stripe"
        case .setupIncomplete: return "Finish Stripe setup"
        case .connected: return "Manage Stripe"
        case .underReview, .restricted: return "Open Stripe"
        }
    }

    /// Short form for a status pill or a menu row.
    var shortLabel: String {
        switch self {
        case .notConnected: return "Not connected"
        case .setupIncomplete: return "Setup incomplete"
        case .connected: return "Connected"
        case .underReview: return "In review"
        case .restricted: return "Action needed"
        }
    }

    var tone: StatusTone {
        switch self {
        case .notConnected: return .neutral
        case .setupIncomplete: return .warning
        case .connected: return .success
        case .underReview: return .info
        case .restricted: return .danger
        }
    }

    var isConnected: Bool { self == .connected }

    /// Whether the action opens the Stripe dashboard (as opposed to Stripe's
    /// hosted setup). An Express dashboard exists only once setup was submitted.
    func actionOpensDashboard(detailsSubmitted: Bool) -> Bool {
        switch self {
        case .connected: return true
        case .underReview, .restricted: return detailsSubmitted
        case .notConnected, .setupIncomplete: return false
        }
    }
}

/// Stripe's requirement keys, as a person reads them.
///
/// `external_account` becomes "Bank account for payouts". Anything not
/// recognised becomes "Other details" rather than a raw key.
nonisolated enum StripeRequirementCopy {
    static func friendly(_ keys: [String]) -> [String] {
        var seen: [String] = []
        for key in keys {
            let label = label(for: key)
            if !seen.contains(label) { seen.append(label) }
        }
        return seen
    }

    static func label(for key: String) -> String {
        let k = key.lowercased()
        if k.contains("external_account") { return "Bank account for payouts" }
        if k.hasPrefix("tos_acceptance") { return "Accept Stripe's terms" }
        if k.contains("verification.document") || k.contains("verification.additional_document") { return "Photo ID" }
        if k.hasPrefix("business_profile") { return "Business details" }
        if k.hasPrefix("business_type") { return "Business type" }
        if k.hasPrefix("company") { return "Company details" }
        if k.hasPrefix("individual") || k.hasPrefix("representative") || k.hasPrefix("person_") { return "Your personal details" }
        if k.hasPrefix("owners") || k.hasPrefix("directors") || k.hasPrefix("executives") { return "Owner details" }
        if k.hasPrefix("settings") { return "Account settings" }
        return "Other details"
    }
}

// MARK: - Apple subscription entitlement

/// Where the company's Apple subscription stands, exactly as the server
/// derived it (`subscription_entitlement_state` in migration 0013).
nonisolated enum EntitlementState: String, Codable, Hashable, Sendable {
    case none
    case trial
    case offer
    case active
    case cancelling
    case gracePeriod
    case billingRetry
    case expired
    case revoked

    var isEntitled: Bool {
        switch self {
        case .trial, .offer, .active, .cancelling, .gracePeriod: return true
        case .none, .billingRetry, .expired, .revoked: return false
        }
    }

    var tone: StatusTone {
        switch self {
        case .active: return .success
        case .trial, .offer: return .info
        case .cancelling, .gracePeriod, .billingRetry: return .warning
        case .expired, .revoked: return .danger
        case .none: return .neutral
        }
    }

    var pillText: String {
        switch self {
        case .none: return "No plan"
        case .trial: return "Free trial"
        case .offer: return "Free offer"
        case .active: return "Active"
        case .cancelling: return "Ending"
        case .gracePeriod: return "Payment problem"
        case .billingRetry: return "Paused"
        case .expired: return "Ended"
        case .revoked: return "Refunded"
        }
    }
}

/// One company's whole commercial position, exactly as the server reported it.
nonisolated struct CommercialState: Hashable, Sendable {
    let paymentModel: PaymentModel

    // Apple subscription
    let entitlementState: EntitlementState
    let planID: PlanID?
    let planName: String?
    let billingPeriod: BillingPeriod?
    /// What the plan costs per billing period, in cents.
    let planPriceCents: Int
    let userLimit: Int?
    let includedUsers: Int
    let activeUsers: Int
    let openInvitations: Int
    let canAddUser: Bool
    let seatLimitsEnforced: Bool
    let periodEndsAt: Date?
    let willAutoRenew: Bool?
    let renewsToPlanID: PlanID?
    let renewsToPeriod: BillingPeriod?
    /// Apple's offerType: 1 introductory, 2 promotional, 3 Offer Code, 4 win-back.
    let offerType: Int?
    let offerIdentifier: String?
    let isFreeOffer: Bool
    let freeOfferDaysRemaining: Int
    let gracePeriodEndsAt: Date?
    let billingStore: BillingStore

    // Stripe, as Stripe reports it.
    let stripeConnected: Bool
    let chargesEnabled: Bool
    let payoutsEnabled: Bool
    let detailsSubmitted: Bool
    let requirementsDue: [String]
    let disabledReason: String?
    let stripeAccountID: String?

    /// Harbour South's platform fee in basis points. 30 = 0.3%. Always 0 for
    /// an external-provider company.
    let platformFeeBps: Int
    let externalPaymentURL: String?
    let businessEmail: String?

    /// Whether this session may initiate or change Stripe/billing.
    let canManageBilling: Bool

    init(
        paymentModel: PaymentModel = .undecided,
        entitlementState: EntitlementState = .none,
        planID: PlanID? = nil,
        planName: String? = nil,
        billingPeriod: BillingPeriod? = nil,
        planPriceCents: Int = 0,
        userLimit: Int? = 1,
        includedUsers: Int = 1,
        activeUsers: Int = 1,
        openInvitations: Int = 0,
        canAddUser: Bool = true,
        seatLimitsEnforced: Bool = false,
        periodEndsAt: Date? = nil,
        willAutoRenew: Bool? = nil,
        renewsToPlanID: PlanID? = nil,
        renewsToPeriod: BillingPeriod? = nil,
        offerType: Int? = nil,
        offerIdentifier: String? = nil,
        isFreeOffer: Bool = false,
        freeOfferDaysRemaining: Int = 0,
        gracePeriodEndsAt: Date? = nil,
        billingStore: BillingStore = .none,
        stripeConnected: Bool = false,
        chargesEnabled: Bool = false,
        payoutsEnabled: Bool = false,
        detailsSubmitted: Bool = false,
        requirementsDue: [String] = [],
        disabledReason: String? = nil,
        stripeAccountID: String? = nil,
        platformFeeBps: Int = 30,
        externalPaymentURL: String? = nil,
        businessEmail: String? = nil,
        canManageBilling: Bool = true
    ) {
        self.paymentModel = paymentModel
        self.entitlementState = entitlementState
        self.planID = planID
        self.planName = planName
        self.billingPeriod = billingPeriod
        self.planPriceCents = planPriceCents
        self.userLimit = userLimit
        self.includedUsers = includedUsers
        self.activeUsers = activeUsers
        self.openInvitations = openInvitations
        self.canAddUser = canAddUser
        self.seatLimitsEnforced = seatLimitsEnforced
        self.periodEndsAt = periodEndsAt
        self.willAutoRenew = willAutoRenew
        self.renewsToPlanID = renewsToPlanID
        self.renewsToPeriod = renewsToPeriod
        self.offerType = offerType
        self.offerIdentifier = offerIdentifier
        self.isFreeOffer = isFreeOffer
        self.freeOfferDaysRemaining = freeOfferDaysRemaining
        self.gracePeriodEndsAt = gracePeriodEndsAt
        self.billingStore = billingStore
        self.stripeConnected = stripeConnected
        self.chargesEnabled = chargesEnabled
        self.payoutsEnabled = payoutsEnabled
        self.detailsSubmitted = detailsSubmitted
        self.requirementsDue = requirementsDue
        self.disabledReason = disabledReason
        self.stripeAccountID = stripeAccountID
        self.platformFeeBps = platformFeeBps
        self.externalPaymentURL = externalPaymentURL
        self.businessEmail = businessEmail
        self.canManageBilling = canManageBilling
    }

    // MARK: - Derived presentation (sentences only)

    var hasEntitlement: Bool { entitlementState.isEntitled }

    var stripeState: StripeConnectionState {
        StripeConnectionState.classify(
            connected: stripeConnected,
            chargesEnabled: chargesEnabled,
            detailsSubmitted: detailsSubmitted,
            requirementsDue: requirementsDue,
            disabledReason: disabledReason
        )
    }

    /// What Stripe still needs, in plain words.
    var stripeNeeds: [String] { StripeRequirementCopy.friendly(requirementsDue) }

    /// The fee as a person reads it: "0.3%".
    var platformFeeLabel: String { platformFeeLabel(locale: .current) }

    func platformFeeLabel(locale: Locale) -> String {
        guard platformFeeBps > 0 else { return "0%" }
        let percent = Decimal(platformFeeBps) / 100
        return percent.formatted(.number.precision(.fractionLength(0...2)).locale(locale)) + "%"
    }

    /// "$39.99/month", or nil with no plan.
    var planPriceLabel: String? {
        guard hasEntitlement, let billingPeriod else { return nil }
        return PriceLabel.usd(planPriceCents) + billingPeriod.perUnit
    }

    /// "5 of 5 people", "3 people · no limit".
    var seatsLabel: String {
        let people = activeUsers == 1 ? "person" : "people"
        guard let userLimit else { return "\(activeUsers) \(people) · no limit" }
        return "\(activeUsers) of \(userLimit) \(userLimit == 1 ? "person" : "people")"
    }

    var isOverPlan: Bool {
        guard let userLimit else { return false }
        return activeUsers > userLimit
    }

    /// The one-line position, for the account card and settings rows.
    var headline: String {
        let name = planName ?? "Your plan"
        switch entitlementState {
        case .none:
            return "No plan yet"
        case .trial:
            return freeOfferDaysRemaining == 1 ? "Free trial — 1 day left" : "Free trial — \(freeOfferDaysRemaining) days left"
        case .offer:
            return freeOfferDaysRemaining == 1 ? "Free offer — 1 day left" : "Free offer — \(freeOfferDaysRemaining) days left"
        case .active:
            if let periodEndsAt { return "\(name) · renews \(Formatters.shortDate(periodEndsAt))" }
            return "\(name) · active"
        case .cancelling:
            if let periodEndsAt { return "\(name) · ends \(Formatters.shortDate(periodEndsAt))" }
            return "\(name) · ending"
        case .gracePeriod:
            return "Payment problem — update your payment method"
        case .billingRetry:
            return "Subscription paused — Apple couldn't take payment"
        case .expired:
            return "Subscription ended"
        case .revoked:
            return "Subscription refunded"
        }
    }

    /// The fuller explanation under the headline.
    var detail: String? {
        switch entitlementState {
        case .none:
            return "Choose a plan to get started. Every plan starts with a 14-day free trial for new subscribers."
        case .trial, .offer:
            guard let planName, let label = planPriceLabel, let periodEndsAt else { return nil }
            if willAutoRenew == false {
                return "Your free period ends \(Formatters.shortDate(periodEndsAt)) and will not renew."
            }
            return "Free until \(Formatters.shortDate(periodEndsAt)). Then \(planName) at \(label), billed by Apple unless you cancel."
        case .active:
            if let next = renewsToPlanID, next != planID,
               let plan = PlanCatalog.standard.first(where: { $0.id == next }) {
                return "Changes to \(plan.displayName) at your next renewal."
            }
            return planPriceLabel.map { "\($0), billed by Apple." }
        case .cancelling:
            return "You've turned off auto-renew. Your plan stays active until then."
        case .gracePeriod:
            if let gracePeriodEndsAt {
                return "Apple couldn't take your last payment. Your plan keeps working until \(Formatters.shortDate(gracePeriodEndsAt)) — update your payment method in the App Store."
            }
            return "Apple couldn't take your last payment. Update your payment method in the App Store."
        case .billingRetry:
            return "Update your payment method in the App Store and Apple will try again."
        case .expired, .revoked:
            return "Choose a plan to keep adding people and working as a team."
        }
    }

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
