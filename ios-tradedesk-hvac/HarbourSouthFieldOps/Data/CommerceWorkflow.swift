import Foundation

// =============================================================================
// Phase 2 commercial layer — projections, drafts and gateway contract.
//
// Every member added to `DataGateway` below is a protocol REQUIREMENT with a
// default implementation, never an extension-only member. The app holds a
// `DataGateway` existential; only a requirement dispatches dynamically to the
// Supabase implementation, so an extension-only member would silently answer
// with the default for every caller and never reach the database.
//
// The defaults throw `DataError.rejected` with a plain sentence rather than
// pretending. The development stack answers honestly that it cannot take money
// or send a message, which is the truth: there is no Stripe account and no
// Twilio credential behind it.
// =============================================================================

// MARK: - Subscription and seats

/// Where the company's SaaS subscription actually stands, plus the itemised
/// price derived server-side.
nonisolated struct SubscriptionOverview: Hashable, Sendable {
    let subscription: CompanySubscription?
    /// The authoritative price for the current head count.
    let quote: SubscriptionQuote
    /// The full published price list, so an owner can see the tier they are in
    /// and the ones around it.
    let pricing: PlatformPricing
    let canManage: Bool
    /// Active people, broken out so "why is my bill this?" has a visible answer.
    let activeUsers: Int
    let invitedUsers: Int
    let suspendedUsers: Int
    /// Set when the subscription is past due or payment has failed, so the UI
    /// can say what is wrong instead of showing a healthy-looking price.
    let alert: String?

    var isOverCapacity: Bool { quote.isOverCapacity }
}

// MARK: - Stripe Connect

nonisolated enum ConnectReadiness: String, Codable, Hashable, Sendable {
    /// This deployment has no Stripe keys at all.
    case notConfigured
    /// Configured, but this company has not started onboarding.
    case notConnected
    /// Onboarding started, Stripe still wants information.
    case pending
    /// Ready to take a card.
    case ready
    /// Stripe has disabled the account.
    case restricted

    var title: String {
        switch self {
        case .notConfigured: return "Unavailable"
        case .notConnected: return "Not connected"
        case .pending: return "Action needed"
        case .ready: return "Ready"
        case .restricted: return "Restricted"
        }
    }
}

/// The company's own Stripe account — the destination for *their* customers'
/// money. Nothing here concerns the Harbour South subscription.
nonisolated struct ConnectAccountStatus: Hashable, Sendable {
    let readiness: ConnectReadiness
    let accountID: String?
    let chargesEnabled: Bool
    let payoutsEnabled: Bool
    let detailsSubmitted: Bool
    /// What Stripe still wants, in Stripe's own words.
    let requirementsDue: [String]
    let disabledReason: String?
    let canManage: Bool
    /// The manual payment link from Phase 1, still offered as a fallback for a
    /// business that has not connected Stripe.
    let fallbackLink: PaymentLinkSettings?

    var acceptsCards: Bool { readiness == .ready && chargesEnabled }
}

/// How the trade business is constituted, as Stripe understands it.
///
/// Stripe verifies a sole trader against personal identity documents and an
/// incorporated business against company registration data — two different
/// checks. Sending the wrong one stranded every sole trader in onboarding,
/// because the account used to be created hardcoded as a company.
///
/// `unspecified` is a real, safe answer rather than a placeholder: it makes the
/// server omit the field entirely so Stripe asks the owner directly during
/// onboarding, which is better than this app guessing.
nonisolated enum ConnectBusinessType: String, CaseIterable, Identifiable, Sendable {
    case unspecified
    case individual
    case company

    var id: String { rawValue }

    /// The value sent to the Edge Function. Nil means "do not prefill".
    var wireValue: String? {
        self == .unspecified ? nil : rawValue
    }

    var title: String {
        switch self {
        case .unspecified: return "Not sure"
        case .individual: return "Sole trader"
        case .company: return "Limited company"
        }
    }

    var detail: String {
        switch self {
        case .unspecified:
            return "Stripe will ask you during setup."
        case .individual:
            return "You trade as yourself. Stripe verifies your personal identity."
        case .company:
            return "You trade through a registered company. Stripe verifies the company."
        }
    }
}

// MARK: - SMS

nonisolated enum SmsLedgerKind: String, Codable, Hashable, Sendable {
    case purchase
    case consumption
    case refund
    case adjustment

    var title: String {
        switch self {
        case .purchase: return "Credits bought"
        case .consumption: return "Message sent"
        case .refund: return "Credit returned"
        case .adjustment: return "Adjustment"
        }
    }
}

nonisolated struct SmsLedgerRow: Identifiable, Hashable, Sendable {
    let id: String
    let kind: SmsLedgerKind
    /// Signed: negative for a message, positive for a purchase or refund.
    let amount: Int
    let balanceAfter: Int
    let at: Date
    let detail: String

    var amountLabel: String { amount > 0 ? "+\(amount)" : "\(amount)" }
}

/// Delivery states, kept distinct on purpose. "Sent" means the carrier accepted
/// the message; only "delivered" means it arrived. Conflating the two is how an
/// app ends up claiming an outcome it does not know.
nonisolated enum SmsDeliveryState: String, Codable, Hashable, Sendable {
    case queued
    case accepted
    case sent
    case delivered
    case failed
    case undelivered

    var title: String {
        switch self {
        case .queued: return "Queued"
        case .accepted: return "Accepted"
        case .sent: return "Sent to carrier"
        case .delivered: return "Delivered"
        case .failed: return "Failed"
        case .undelivered: return "Not delivered"
        }
    }

    var tone: StatusTone {
        switch self {
        case .delivered: return .success
        case .failed, .undelivered: return .danger
        case .queued, .accepted, .sent: return .neutral
        }
    }

    /// True once nothing further will happen to this message.
    var isSettled: Bool {
        self == .delivered || self == .failed || self == .undelivered
    }
}

nonisolated struct SmsMessageRow: Identifiable, Hashable, Sendable {
    let id: String
    let recipient: String
    let body: String
    let state: SmsDeliveryState
    let customerName: String?
    let sentAt: Date?
    let createdAt: Date
    let creditsCharged: Int
    let creditsRefunded: Int
    let failureReason: String?
    let providerReference: String?
}

/// Everything the SMS screen needs: balance, the price list, history and what
/// this role may actually do.
nonisolated struct SmsCreditOverview: Hashable, Sendable {
    /// The name the customer sees as the sender. Carried here so a message
    /// composer never has to guess it, or be handed it by a caller that might
    /// be wrong.
    let companyName: String
    let balance: Int
    let bundles: [SmsBundle]
    let ledger: [SmsLedgerRow]
    let recentMessages: [SmsMessageRow]
    let canPurchase: Bool
    let canSend: Bool
    let canReadLedger: Bool
    /// False when this deployment has no Twilio credentials, so the UI can say
    /// messaging is unavailable rather than offering a button that fails.
    let messagingConfigured: Bool
    let purchasingConfigured: Bool

    var isEmpty: Bool { balance <= 0 }
}

/// One outbound customer message. Carries no company: tenancy is derived from
/// the authenticated session inside the Edge Function, and the customer is
/// re-checked against that company before anything is sent.
nonisolated struct SmsSendDraft: Hashable, Sendable {
    let customerID: String
    var jobID: String?
    var invoiceID: String?
    var template: SmsTemplate
    var body: String
    /// Optional override, validated against the customer's own contacts.
    var phone: String?

    init(
        customerID: String,
        jobID: String? = nil,
        invoiceID: String? = nil,
        template: SmsTemplate = .custom,
        body: String = "",
        phone: String? = nil
    ) {
        self.customerID = customerID
        self.jobID = jobID
        self.invoiceID = invoiceID
        self.template = template
        self.body = body
        self.phone = phone
    }
}

/// The messages a field-service business actually sends. Each one is chosen by
/// a person — nothing here fires automatically, because a customer who gets six
/// unexpected texts about one visit stops reading them.
nonisolated enum SmsTemplate: String, CaseIterable, Codable, Hashable, Sendable {
    case jobConfirmation
    case appointmentReminder
    case engineerEnRoute
    case runningLate
    case jobCompleted
    case quoteReady
    case invoiceSent
    case paymentReminder
    case custom

    var title: String {
        switch self {
        case .jobConfirmation: return "Job confirmed"
        case .appointmentReminder: return "Appointment reminder"
        case .engineerEnRoute: return "On the way"
        case .runningLate: return "Running late"
        case .jobCompleted: return "Work completed"
        case .quoteReady: return "Quote ready"
        case .invoiceSent: return "Invoice sent"
        case .paymentReminder: return "Payment reminder"
        case .custom: return "Write your own"
        }
    }

    var symbolName: String {
        switch self {
        case .jobConfirmation: return "checkmark.circle"
        case .appointmentReminder: return "calendar"
        case .engineerEnRoute: return "car.fill"
        case .runningLate: return "clock.badge.exclamationmark"
        case .jobCompleted: return "checkmark.seal"
        case .quoteReady: return "doc.text"
        case .invoiceSent: return "doc.plaintext"
        case .paymentReminder: return "creditcard"
        case .custom: return "square.and.pencil"
        }
    }

    /// A starting point the sender edits. Deliberately plain — a trades
    /// customer wants the time and the name, not marketing copy.
    func draftBody(company: String, worker: String?, when: String?) -> String {
        switch self {
        case .jobConfirmation:
            return "\(company): your appointment is booked\(when.map { " for \($0)" } ?? ""). We'll be in touch if anything changes."
        case .appointmentReminder:
            return "\(company): a reminder that we're scheduled to visit\(when.map { " \($0)" } ?? "") . Reply if that no longer suits."
        case .engineerEnRoute:
            return "\(company): \(worker ?? "your engineer") is on the way to you now."
        case .runningLate:
            return "\(company): we're running behind today and will be with you a little later than planned. Sorry for the delay."
        case .jobCompleted:
            return "\(company): the work at your property is complete. Thanks for your business."
        case .quoteReady:
            return "\(company): your quote is ready. Let us know if you'd like to go ahead."
        case .invoiceSent:
            return "\(company): your invoice has been sent by email."
        case .paymentReminder:
            return "\(company): a friendly reminder that your invoice is now due. Thank you."
        case .custom:
            return ""
        }
    }
}

/// What actually happened to a send attempt.
nonisolated struct SmsSendOutcome: Hashable, Sendable {
    let sent: Bool
    let creditsCharged: Int
    let balance: Int
    let providerReference: String?
    let detail: String
    /// True when the send was refused for want of credit, which is a business
    /// answer rather than a failure — the balance is untouched and the message
    /// was never handed to the provider.
    let insufficientCredit: Bool
}

// MARK: - Recurring service

// `ServiceFrequency` is NOT redeclared here. Phase 1 already owns it in
// `Models/ServiceAgreement.swift`; this phase extended that type with `.custom`
// rather than introducing a second, subtly different copy.

nonisolated struct RecurringServiceRow: Identifiable, Hashable, Sendable {
    let id: String
    let customerID: String
    let customerName: String
    let siteLine: String
    let equipmentLabel: String?
    let title: String
    let frequency: ServiceFrequency
    let intervalDays: Int?
    let nextDueDate: Date
    let isActive: Bool
    let lastGeneratedOn: Date?
    let lastGeneratedJobID: String?

    var frequencyLabel: String {
        frequency == .custom
            ? "Every \(intervalDays ?? 30) days"
            : frequency.title
    }

    /// Overdue generation is a real operational problem — it means a contracted
    /// visit has not been booked — so it is surfaced, not hidden.
    var isDue: Bool { nextDueDate <= Date() }
}

nonisolated struct RecurringServiceDraft: Hashable, Sendable {
    var id: String?
    var customerID: String
    var addressID: String
    var equipmentID: String?
    var title: String
    var description: String
    var kind: JobKind
    var frequency: ServiceFrequency
    var intervalDays: Int
    var nextDueDate: Date
    var isActive: Bool
    var notes: String

    init(
        id: String? = nil,
        customerID: String = "",
        addressID: String = "",
        equipmentID: String? = nil,
        title: String = "",
        description: String = "",
        kind: JobKind = .maintenance,
        frequency: ServiceFrequency = .semiAnnual,
        intervalDays: Int = 90,
        nextDueDate: Date = Date().addingTimeInterval(60 * 60 * 24 * 30),
        isActive: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.customerID = customerID
        self.addressID = addressID
        self.equipmentID = equipmentID
        self.title = title
        self.description = description
        self.kind = kind
        self.frequency = frequency
        self.intervalDays = intervalDays
        self.nextDueDate = nextDueDate
        self.isActive = isActive
        self.notes = notes
    }

    /// One message at a time, so the form corrects one thing at a time.
    var validationMessage: String? {
        if customerID.isEmpty { return "Choose a customer." }
        if addressID.isEmpty { return "Choose which site this covers." }
        if title.tidied.isEmpty { return "Give the recurring visit a name." }
        if frequency == .custom, intervalDays < 1 { return "A custom interval needs at least one day." }
        return nil
    }
}

nonisolated struct RecurringServiceBoard: Hashable, Sendable {
    let agreements: [RecurringServiceRow]
    let canManage: Bool
    let dueCount: Int
    let activeCount: Int
}

// MARK: - Payment terms

/// The terms a trades business actually offers.
///
/// "Due on completion" is a *rule*, not a horizon: the due date is the day the
/// work finished, not a number of days after the invoice was raised. Every
/// other case adds its days to the reference date. Keeping the distinction in
/// the type stops it being re-derived — and re-decided — at each call site.
nonisolated enum PaymentTermOption: String, CaseIterable, Codable, Hashable, Sendable {
    case onCompletion
    case net7
    case net14
    case net30
    case net60
    case net90
    case custom

    var label: String {
        switch self {
        case .onCompletion: return "Due on completion"
        case .net7: return "Due in 7 days"
        case .net14: return "Due in 14 days"
        case .net30: return "Due in 30 days"
        case .net60: return "Due in 60 days"
        case .net90: return "Due in 90 days"
        case .custom: return "Custom"
        }
    }

    var days: Int? {
        switch self {
        case .onCompletion: return 0
        case .net7: return 7
        case .net14: return 14
        case .net30: return 30
        case .net60: return 60
        case .net90: return 90
        case .custom: return nil
        }
    }

    /// Reads a stored label back. Unrecognised text is `custom` rather than a
    /// silent fallback to 30 days, because guessing somebody's payment terms is
    /// how invoices become due on the wrong day.
    static func from(label: String) -> PaymentTermOption {
        let normalised = label.lowercased()
        if normalised.contains("completion") { return .onCompletion }
        for option in [PaymentTermOption.net7, .net14, .net30, .net60, .net90] {
            if let days = option.days, normalised.contains("\(days)") { return option }
        }
        return .custom
    }

    /// The due date for these terms.
    ///
    /// `reference` must be the completion date for `.onCompletion` and the
    /// issue date otherwise — the caller decides which, because only the caller
    /// knows whether the job is finished.
    func dueDate(from reference: Date, customDays: Int? = nil, calendar: Calendar = .current) -> Date {
        switch self {
        case .onCompletion:
            return calendar.startOfDay(for: reference)
        case .custom:
            let days = max(customDays ?? 0, 0)
            return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: reference)) ?? reference
        default:
            let days = self.days ?? 30
            return calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: reference)) ?? reference
        }
    }

    /// The label written to the invoice. Custom terms carry their day count so
    /// the stored text stays self-describing.
    func storedLabel(customDays: Int? = nil) -> String {
        guard self == .custom else { return label }
        let days = max(customDays ?? 0, 0)
        return days == 0 ? "Due on receipt" : "Due in \(days) days"
    }
}

nonisolated struct PaymentTermsSettings: Hashable, Sendable {
    let option: PaymentTermOption
    let customDays: Int
    let label: String
    let canManage: Bool
}

// MARK: - Company profile

/// The company's own details, as they appear on quotes and invoices.
///
/// Read-only fields are deliberately part of the type. `trade`, `countryCode`
/// and `currencyCode` decide terminology, address shape and every money label in
/// the app; changing them after documents exist would retro-relabel historical
/// records, so they are shown and not edited here.
nonisolated struct CompanyProfileSettings: Hashable, Sendable {
    var name: String
    var phone: String
    var addressLine: String
    var city: String
    var state: String
    var postalCode: String
    /// Percentage as typed by a person — 7.5 means 7.5%. Stored as the decimal
    /// fraction the database holds, converted at the boundary so nobody has to
    /// think in hundredths.
    var defaultTaxRatePercent: Decimal
    var timeZoneIdentifier: String

    // Displayed, never edited.
    let trade: Trade
    let countryCode: String
    let currencyCode: String
    let canManage: Bool

    /// What the database stores: 0.075 for 7.5%.
    var defaultTaxRateFraction: Decimal { defaultTaxRatePercent / 100 }

    /// Everything a document needs to identify who issued it. Empty lines are
    /// dropped rather than printed as blanks.
    var addressSummary: String {
        [addressLine, [city, state].filter { !$0.isEmpty }.joined(separator: ", "), postalCode]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Why a save would be refused, in the user's words. Nil means valid.
    var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Your company needs a name — it appears on every quote and invoice you send."
        }
        if defaultTaxRatePercent < 0 || defaultTaxRatePercent > 100 {
            return "A tax rate has to be between 0% and 100%."
        }
        return nil
    }
}

// MARK: - Gateway defaults

extension DataGateway {
    func subscriptionOverview(session: TenantSession) async throws -> SubscriptionOverview {
        throw DataError.rejected("Subscription details are only available on a live company account.")
    }

    func connectAccountStatus(session: TenantSession) async throws -> ConnectAccountStatus {
        throw DataError.rejected("Card payments are only available on a live company account.")
    }

    func beginConnectOnboarding(
        session: TenantSession,
        businessType: ConnectBusinessType
    ) async throws -> URL {
        throw DataError.rejected("Card payments are only available on a live company account.")
    }

    func connectDashboardLink(session: TenantSession) async throws -> URL {
        throw DataError.rejected("Card payments are only available on a live company account.")
    }

    // MARK: The commercial model
    //
    // The development stack answers honestly that it has no commercial
    // position. There is no Stripe account behind it, no trial clock and no
    // Founding Member allocation — and inventing a plausible-looking one here
    // would be the single most misleading thing this file could do, because
    // Founding Member status is a real commercial commitment.

    func commercialState(session: TenantSession) async throws -> CommercialState {
        throw DataError.rejected("Your commercial plan is only available on a live company account.")
    }

    func selectPaymentModel(session: TenantSession, model: PaymentModel) async throws {
        throw DataError.rejected("The payment model is only configurable on a live company account.")
    }

    func businessEmailSettings(session: TenantSession) async throws -> BusinessEmailSettings {
        throw DataError.rejected("Your business email is only configurable on a live company account.")
    }

    func updateBusinessEmail(session: TenantSession, email: String?) async throws {
        throw DataError.rejected("Your business email is only configurable on a live company account.")
    }

    func smsCreditOverview(session: TenantSession) async throws -> SmsCreditOverview {
        throw DataError.rejected("SMS credits are only available on a live company account.")
    }

    func sendCustomerSms(session: TenantSession, draft: SmsSendDraft) async throws -> SmsSendOutcome {
        throw DataError.rejected("This build cannot send messages. Sign in to a live company account.")
    }

    func purchaseSmsCredits(session: TenantSession, bundleID: String?, credits: Int?) async throws -> URL {
        throw DataError.rejected("Buying credits is only available on a live company account.")
    }

    func recurringServices(session: TenantSession) async throws -> RecurringServiceBoard {
        throw DataError.rejected("Recurring service is only available on a live company account.")
    }

    func saveRecurringService(session: TenantSession, draft: RecurringServiceDraft) async throws -> String {
        throw DataError.rejected("Recurring service is only available on a live company account.")
    }

    func deleteRecurringService(session: TenantSession, id: String) async throws {
        throw DataError.rejected("Recurring service is only available on a live company account.")
    }

    func paymentTermsSettings(session: TenantSession) async throws -> PaymentTermsSettings {
        PaymentTermsSettings(option: .net30, customDays: 30, label: PaymentTermOption.net30.label, canManage: false)
    }

    func updatePaymentTerms(session: TenantSession, option: PaymentTermOption, customDays: Int) async throws {
        throw DataError.rejected("Payment terms are only configurable on a live company account.")
    }

    func companyProfile(session: TenantSession) async throws -> CompanyProfileSettings {
        throw DataError.rejected("Company details are only available on a live company account.")
    }

    func updateCompanyProfile(session: TenantSession, profile: CompanyProfileSettings) async throws {
        throw DataError.rejected("Company details are only editable on a live company account.")
    }
}
