import Foundation
import Supabase

// MARK: - Records

nonisolated struct SubscriptionTierRecord: Decodable, Sendable {
    let id: String
    let displayName: String
    let minUsers: Int
    let maxUsers: Int
    let baseCents: Int
    let additionalUserCents: Int
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case minUsers = "min_users"
        case maxUsers = "max_users"
        case baseCents = "base_cents"
        case additionalUserCents = "additional_user_cents"
        case sortOrder = "sort_order"
    }

    static let columns = "id,display_name,min_users,max_users,base_cents,additional_user_cents,sort_order"

    var model: SubscriptionTier {
        SubscriptionTier(
            id: id, displayName: displayName, minUsers: minUsers, maxUsers: maxUsers,
            baseCents: baseCents, additionalUserCents: additionalUserCents, sortOrder: sortOrder
        )
    }
}

nonisolated struct SmsBundleRecord: Decodable, Sendable {
    let id: String
    let credits: Int
    let priceCents: Int

    enum CodingKeys: String, CodingKey {
        case id, credits
        case priceCents = "price_cents"
    }

    static let columns = "id,credits,price_cents,sort_order"

    var model: SmsBundle { SmsBundle(id: id, credits: credits, priceCents: priceCents) }
}

/// What `subscription_quote()` returns. The app renders these numbers; it never
/// derives a subscription total of its own from a live company.
private nonisolated struct SubscriptionQuoteRecord: Decodable, Sendable {
    let activePaidUsers: Int
    let tierID: String?
    let tierName: String?
    let baseCents: Int
    let additionalUsers: Int
    let additionalUserCents: Int
    let monthlyPriceCents: Int
    let maxUsers: Int
    let isOverCapacity: Bool
    let nextUserCents: Int?

    enum CodingKeys: String, CodingKey {
        case activePaidUsers = "active_paid_users"
        case tierID = "tier_id"
        case tierName = "tier_name"
        case baseCents = "base_cents"
        case additionalUsers = "additional_users"
        case additionalUserCents = "additional_user_cents"
        case monthlyPriceCents = "monthly_price_cents"
        case maxUsers = "max_users"
        case isOverCapacity = "is_over_capacity"
        case nextUserCents = "next_user_cents"
    }

    var model: SubscriptionQuote {
        SubscriptionQuote(
            activePaidUsers: activePaidUsers,
            tierID: tierID ?? "",
            tierName: tierName ?? "Current plan",
            baseCents: baseCents,
            additionalUsers: additionalUsers,
            additionalUserCents: additionalUserCents,
            monthlyPriceCents: monthlyPriceCents,
            maxUsers: maxUsers,
            isOverCapacity: isOverCapacity,
            nextUserCents: nextUserCents
        )
    }
}

nonisolated struct SubscriptionRecord: Decodable, Sendable {
    let id: UUID
    let companyID: UUID
    let status: SubscriptionStatus
    let plan: SubscriptionPlan
    let billingPeriod: BillingPeriod
    let isTrial: Bool
    let trialEndsAt: Date?
    let currentPeriodStart: Date
    let currentPeriodEnd: Date
    let renewalDate: Date
    let seatCount: Int
    let includedUsers: Int
    let additionalUsers: Int
    let store: BillingStore
    let cancelledAt: Date?
    let pastDueSince: Date?
    let lastPaymentFailure: String?
    let stripeSubscriptionID: String?

    enum CodingKeys: String, CodingKey {
        case id, status, plan, store
        case companyID = "company_id"
        case billingPeriod = "billing_period"
        case isTrial = "is_trial"
        case trialEndsAt = "trial_ends_at"
        case currentPeriodStart = "current_period_start"
        case currentPeriodEnd = "current_period_end"
        case renewalDate = "renewal_date"
        case seatCount = "seat_count"
        case includedUsers = "included_users"
        case additionalUsers = "additional_users"
        case cancelledAt = "cancelled_at"
        case pastDueSince = "past_due_since"
        case lastPaymentFailure = "last_payment_failure"
        case stripeSubscriptionID = "stripe_subscription_id"
    }

    static let columns = """
    id,company_id,status,plan,billing_period,is_trial,trial_ends_at,\
    current_period_start,current_period_end,renewal_date,seat_count,included_users,\
    additional_users,store,cancelled_at,past_due_since,last_payment_failure,stripe_subscription_id
    """

    var model: CompanySubscription {
        CompanySubscription(
            id: id.uuidString, companyID: companyID.uuidString, status: status, plan: plan,
            billingPeriod: billingPeriod, isTrial: isTrial, trialEndsAt: trialEndsAt,
            currentPeriodStart: currentPeriodStart, currentPeriodEnd: currentPeriodEnd,
            renewalDate: renewalDate, seatCount: seatCount, includedUsers: includedUsers,
            additionalUsers: additionalUsers, store: store,
            appleOriginalTransactionID: nil, googlePurchaseToken: nil, cancelledAt: cancelledAt
        )
    }
}

private nonisolated struct SmsLedgerRecord: Decodable, Sendable {
    let id: UUID
    let transactionType: SmsLedgerKind
    let amount: Int
    let balanceAfter: Int
    let createdAt: Date
    let purchaseReference: String?
    let customerID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, amount
        case transactionType = "transaction_type"
        case balanceAfter = "balance_after"
        case createdAt = "created_at"
        case purchaseReference = "purchase_reference"
        case customerID = "customer_id"
    }

    static let columns = "id,transaction_type,amount,balance_after,created_at,purchase_reference,customer_id"
}

private nonisolated struct SmsMessageRecord: Decodable, Sendable {
    let id: UUID
    let recipient: String
    let body: String?
    let status: String
    let createdAt: Date
    let sentAt: Date?
    let creditsCharged: Int?
    let creditsRefunded: Int?
    let failureReason: String?
    let providerReference: String?
    let customerID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, recipient, body, status
        case createdAt = "created_at"
        case sentAt = "sent_at"
        case creditsCharged = "credits_charged"
        case creditsRefunded = "credits_refunded"
        case failureReason = "failure_reason"
        case providerReference = "provider_reference"
        case customerID = "customer_id"
    }

    static let columns = """
    id,recipient,body,status,created_at,sent_at,credits_charged,credits_refunded,\
    failure_reason,provider_reference,customer_id
    """
}

/// The full agreement row the recurring screen needs.
///
/// Deliberately NOT `ServiceAgreementRecord`, which already exists in
/// `SupabaseRecords.swift` as a narrow three-column projection used elsewhere.
/// Widening that one would change what other callers select.
private nonisolated struct RecurringAgreementRecord: Decodable, Sendable {
    let id: UUID
    let customerID: UUID
    let addressID: UUID
    let equipmentID: UUID?
    let frequency: ServiceFrequency
    let intervalDays: Int?
    let nextDueDate: Date
    let isActive: Bool
    let templateTitle: String
    let templateJobKind: JobKind
    let lastGeneratedOn: Date?
    let lastGeneratedJobID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, frequency
        case customerID = "customer_id"
        case addressID = "address_id"
        case equipmentID = "equipment_id"
        case intervalDays = "interval_days"
        case nextDueDate = "next_due_date"
        case isActive = "is_active"
        case templateTitle = "template_title"
        case templateJobKind = "template_job_kind"
        case lastGeneratedOn = "last_generated_on"
        case lastGeneratedJobID = "last_generated_job_id"
    }

    static let columns = """
    id,customer_id,address_id,equipment_id,frequency,interval_days,next_due_date,\
    is_active,template_title,template_job_kind,last_generated_on,last_generated_job_id
    """
}

// MARK: - Edge Function payloads

private nonisolated struct ConnectRequest: Encodable, Sendable {
    let action: String
    /// Only sent for `onboard`, and only when the owner actually chose one.
    /// Omitted otherwise so Stripe asks them during onboarding instead.
    let businessType: String?

    init(action: String, businessType: String? = nil) {
        self.action = action
        self.businessType = businessType
    }
}

/// The error envelope every Edge Function in this project returns on failure.
nonisolated struct FunctionErrorBody: Decodable, Sendable {
    let error: String?
}

private nonisolated struct ConnectResponse: Decodable, Sendable {
    let configured: Bool?
    let connected: Bool?
    let accountId: String?
    let chargesEnabled: Bool?
    let payoutsEnabled: Bool?
    let detailsSubmitted: Bool?
    let requirementsDue: [String]?
    let disabledReason: String?
    let url: String?
    let error: String?
}

private nonisolated struct SmsSendRequest: Encodable, Sendable {
    let customerId: String
    let jobId: String?
    let invoiceId: String?
    let template: String
    let body: String
    let phone: String?
}

private nonisolated struct SmsSendResponse: Decodable, Sendable {
    let sent: Bool?
    let reason: String?
    let messageId: String?
    let providerReference: String?
    let creditsCharged: Int?
    let balance: Int?
    let detail: String?
    let error: String?
    let configured: Bool?
}

private nonisolated struct SmsPurchaseRequest: Encodable, Sendable {
    let action: String
    let bundleId: String?
    let credits: Int?
}

private nonisolated struct SmsPurchaseResponse: Decodable, Sendable {
    let configured: Bool?
    let balance: Int?
    let checkoutUrl: String?
    let purchaseId: String?
    let error: String?
}

/// The columns a recurring agreement is written from.
///
/// `company_id` is REQUIRED on insert. `service_agreements.company_id` is
/// `not null` with no column default, so an insert that omits it is refused by
/// PostgreSQL before RLS is ever consulted — which is precisely why creating a
/// recurring visit failed. It is still not a trust decision: the value comes
/// from the session the database itself issued, and the `with check` on the
/// table re-tests it against `current_company_id()`, so a tampered value is
/// rejected rather than honoured.
///
/// The encoding is written by hand for one reason: Swift's synthesised encoder
/// uses `encodeIfPresent` for optionals, which would silently DROP a cleared
/// field instead of nulling it. Switching an agreement from a custom interval
/// back to monthly, or removing its equipment, has to send `null` — otherwise
/// the old value survives the edit.
private nonisolated struct RecurringPayload: Encodable, Sendable {
    /// Omitted on update, where the row's company is already settled and the
    /// policy forbids moving it.
    let company_id: String?
    let customer_id: String
    let address_id: String
    let equipment_id: String?
    let frequency: String
    let interval_days: Int?
    let next_due_date: String
    let is_active: Bool
    let template_title: String
    let template_description: String
    let template_job_kind: String
    let notes: String?
    let updated_at: String

    enum CodingKeys: String, CodingKey {
        case company_id, customer_id, address_id, equipment_id, frequency
        case interval_days, next_due_date, is_active, template_title
        case template_description, template_job_kind, notes, updated_at
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(company_id, forKey: .company_id)
        try container.encode(customer_id, forKey: .customer_id)
        try container.encode(address_id, forKey: .address_id)
        // Explicit nulls: these are cleared, not left alone.
        try container.encode(equipment_id, forKey: .equipment_id)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(interval_days, forKey: .interval_days)
        try container.encode(next_due_date, forKey: .next_due_date)
        try container.encode(is_active, forKey: .is_active)
        try container.encode(template_title, forKey: .template_title)
        try container.encode(template_description, forKey: .template_description)
        try container.encode(template_job_kind, forKey: .template_job_kind)
        try container.encode(notes, forKey: .notes)
        try container.encode(updated_at, forKey: .updated_at)
    }
}

private nonisolated struct PaymentTermsPayload: Encodable, Sendable {
    let default_payment_terms_label: String
    let default_payment_terms_days: Int
    let updated_at: String
}

/// What `company_commercial_state()` returns.
///
/// Every field is an ANSWER, not an input. The function decides the trial
/// window, Stripe readiness, the founding number, whether the benefit is live
/// this month, the tier price and the applicable fee; this struct is the decode
/// of that decision. There is no corresponding request type because the
/// function takes no parameter from the app at all — it derives the company
/// from the caller's own session inside the database.
private nonisolated struct CommercialStateRecord: Decodable, Sendable {
    let paymentModel: String?
    let subscriptionStatus: String?
    let trialEndsAt: Date?
    let trialDaysRemaining: Int?
    let isTrialActive: Bool?
    let stripeConnected: Bool?
    let chargesEnabled: Bool?
    let payoutsEnabled: Bool?
    let detailsSubmitted: Bool?
    let requirementsDue: [String]?
    let disabledReason: String?
    let stripeAccountID: String?
    let foundingMemberNumber: Int?
    let foundingClaimedAt: Date?
    let foundingPlacesClaimed: Int?
    let foundingPlacesRemaining: Int?
    let foundingOfferOpen: Bool?
    let foundingBenefitActive: Bool?
    let qualifyingPaymentsThisMonth: Int?
    let lastQualifyingPaymentAt: Date?
    let activityMonthStart: Date?
    let tierID: String?
    let tierName: String?
    let subscriptionMonthlyCents: Int?
    let effectiveMonthlyCents: Int?
    let platformFeeBps: Int?
    let externalPaymentURL: String?
    let businessEmail: String?

    enum CodingKeys: String, CodingKey {
        case paymentModel = "payment_model"
        case subscriptionStatus = "subscription_status"
        case trialEndsAt = "trial_ends_at"
        case trialDaysRemaining = "trial_days_remaining"
        case isTrialActive = "is_trial_active"
        case stripeConnected = "stripe_connected"
        case chargesEnabled = "charges_enabled"
        case payoutsEnabled = "payouts_enabled"
        case detailsSubmitted = "details_submitted"
        case requirementsDue = "requirements_due"
        case disabledReason = "disabled_reason"
        case stripeAccountID = "stripe_account_id"
        case foundingMemberNumber = "founding_member_number"
        case foundingClaimedAt = "founding_claimed_at"
        case foundingPlacesClaimed = "founding_places_claimed"
        case foundingPlacesRemaining = "founding_places_remaining"
        case foundingOfferOpen = "founding_offer_open"
        case foundingBenefitActive = "founding_benefit_active"
        case qualifyingPaymentsThisMonth = "qualifying_payments_this_month"
        case lastQualifyingPaymentAt = "last_qualifying_payment_at"
        case activityMonthStart = "activity_month_start"
        case tierID = "tier_id"
        case tierName = "tier_name"
        case subscriptionMonthlyCents = "subscription_monthly_cents"
        case effectiveMonthlyCents = "effective_monthly_cents"
        case platformFeeBps = "platform_fee_bps"
        case externalPaymentURL = "external_payment_url"
        case businessEmail = "business_email"
    }

    func model(canManageBilling: Bool) -> CommercialState {
        CommercialState(
            paymentModel: PaymentModel(rawValue: paymentModel ?? "") ?? .undecided,
            subscriptionStatus: SubscriptionStatus(rawValue: subscriptionStatus ?? "") ?? .trialing,
            trialEndsAt: trialEndsAt,
            trialDaysRemaining: max(trialDaysRemaining ?? 0, 0),
            isTrialActive: isTrialActive ?? false,
            stripeConnected: stripeConnected ?? false,
            chargesEnabled: chargesEnabled ?? false,
            payoutsEnabled: payoutsEnabled ?? false,
            detailsSubmitted: detailsSubmitted ?? false,
            requirementsDue: requirementsDue ?? [],
            disabledReason: disabledReason,
            stripeAccountID: stripeAccountID,
            foundingMemberNumber: foundingMemberNumber,
            foundingClaimedAt: foundingClaimedAt,
            foundingPlacesClaimed: foundingPlacesClaimed ?? 0,
            foundingPlacesRemaining: foundingPlacesRemaining ?? 0,
            foundingOfferOpen: foundingOfferOpen ?? false,
            foundingBenefitActive: foundingBenefitActive ?? false,
            qualifyingPaymentsThisMonth: qualifyingPaymentsThisMonth ?? 0,
            lastQualifyingPaymentAt: lastQualifyingPaymentAt,
            activityMonthStart: activityMonthStart,
            tierID: tierID ?? "",
            tierName: tierName ?? "Current plan",
            subscriptionMonthlyCents: subscriptionMonthlyCents ?? 0,
            effectiveMonthlyCents: effectiveMonthlyCents ?? 0,
            platformFeeBps: platformFeeBps ?? 0,
            externalPaymentURL: externalPaymentURL,
            businessEmail: businessEmail,
            canManageBilling: canManageBilling
        )
    }
}

private nonisolated struct BusinessEmailPayload: Encodable, Sendable {
    /// Explicitly encoded, never `encodeIfPresent`: clearing the address has to
    /// send `null`, or the old one survives the edit.
    let business_email: String?
    let updated_at: String

    enum CodingKeys: String, CodingKey {
        case business_email, updated_at
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(business_email, forKey: .business_email)
        try container.encode(updated_at, forKey: .updated_at)
    }
}

// =============================================================================
// The commercial layer against Supabase.
//
// TWO MONEY FLOWS, NEVER MIXED:
//
//   FLOW A — the trade business pays Harbour South (subscription, SMS credits).
//            Platform Stripe account. Handled by `stripe-subscription` and
//            `sms-purchase`.
//   FLOW B — the trade business's customer pays the trade business (invoices).
//            The company's OWN connected Stripe account. Handled by
//            `invoice-payment` and reconciled by `stripe-webhook`.
//
// Nothing in this file holds a Stripe or Twilio credential, and nothing here
// decides that money moved. Payment truth comes from the webhook; delivery
// truth comes from the Twilio callback. The app reads the consequences.
// =============================================================================
extension SupabaseDataGateway {

    // MARK: - Subscription

    func subscriptionOverview(session: TenantSession) async throws -> SubscriptionOverview {
        try require(.saasBillingRead, session, query: "subscription.overview")

        // The published price list. Readable by any signed-in user by policy —
        // it is a price list, not a secret.
        let tiers = try await fetch(
            SubscriptionTierRecord.self,
            client.from("subscription_tiers")
                .select(SubscriptionTierRecord.columns)
                .eq("is_active", value: true)
                .order("sort_order")
        )

        // The authoritative price, computed in the database from the live head
        // count. The client does not add this up for a real company.
        let quotes: [SubscriptionQuoteRecord] = await {
            do {
                let data = try await client.rpc("subscription_quote").execute().data
                return try SupabaseCoding.decoder.decode([SubscriptionQuoteRecord].self, from: data)
            } catch {
                // Falls back to the local engine over the same tier data below.
                return []
            }
        }()

        let pricing = tiers.isEmpty
            ? PlatformPricing.fallback
            : PlatformPricing(tiers: tiers.map(\.model), maxUsers: tiers.map(\.maxUsers).max() ?? 100, isLive: true)

        let subscription = try await fetch(
            SubscriptionRecord.self,
            client.from("company_subscriptions").select(SubscriptionRecord.columns).limit(1)
        ).first

        // Roster counts, so "why is my bill this?" has a visible answer rather
        // than a number to take on trust.
        let users = try await fetch(
            TeamUserRecord.self,
            client.from("app_users").select(TeamUserRecord.columns)
        )
        let active = users.filter { $0.status == .active }.count
        let invited = users.filter { $0.status == .invited }.count
        let suspended = users.filter { $0.status == .suspended }.count

        // Prefer the database's own arithmetic; fall back to the local engine
        // only if the RPC is unavailable, and only over the same tier data.
        let quote = quotes.first?.model ?? pricing.quote(for: max(active, 1))

        var alert: String?
        if let subscription {
            switch subscription.status {
            case .pastDue:
                alert = "The last payment failed. Update the card to keep the account active."
            case .cancelled:
                alert = "This subscription is cancelled and will not renew."
            case .expired:
                alert = "This subscription has expired."
            case .trialing, .active:
                alert = nil
            }
        }
        if quote.isOverCapacity {
            alert = "This company has more than \(quote.maxUsers) active people, which is beyond the supported maximum."
        }

        record(
            "subscription.overview",
            session,
            allowed: true,
            "Price derived in the database from \(active) active user(s); the app renders it and never recomputes it"
        )

        return SubscriptionOverview(
            subscription: subscription?.model,
            quote: quote,
            pricing: pricing,
            canManage: session.can(.saasBillingManage),
            activeUsers: active,
            invitedUsers: invited,
            suspendedUsers: suspended,
            alert: alert
        )
    }

    // MARK: - Stripe Connect (FLOW B)

    func connectAccountStatus(session: TenantSession) async throws -> ConnectAccountStatus {
        guard session.can(.paymentsRead) || session.can(.saasBillingRead) else {
            record("payments.connect.status", session, allowed: false, "Blocked before the request — missing paymentsRead")
            throw DataError.notPermitted(.paymentsRead)
        }

        let link = try? await companyPaymentLink(session: session)

        do {
            let response: ConnectResponse = try await client.functions.invoke(
                "stripe-connect",
                options: .init(body: ConnectRequest(action: "status"))
            )

            let readiness: ConnectReadiness
            if response.configured == false {
                readiness = .notConfigured
            } else if response.connected != true {
                readiness = .notConnected
            } else if response.disabledReason != nil {
                readiness = .restricted
            } else if response.chargesEnabled == true {
                readiness = .ready
            } else {
                readiness = .pending
            }

            record(
                "payments.connect.status",
                session,
                allowed: true,
                "Read from Stripe server-side; no Stripe credential exists in this app"
            )

            return ConnectAccountStatus(
                readiness: readiness,
                accountID: response.accountId,
                chargesEnabled: response.chargesEnabled ?? false,
                payoutsEnabled: response.payoutsEnabled ?? false,
                detailsSubmitted: response.detailsSubmitted ?? false,
                requirementsDue: response.requirementsDue ?? [],
                disabledReason: response.disabledReason,
                canManage: session.can(.companyProfileManage),
                fallbackLink: link
            )
        } catch {
            // A missing function is not a lie about readiness: report it as
            // unavailable rather than as "not connected", which would invite
            // the owner to start an onboarding that cannot work.
            return ConnectAccountStatus(
                readiness: .notConfigured,
                accountID: nil,
                chargesEnabled: false,
                payoutsEnabled: false,
                detailsSubmitted: false,
                requirementsDue: [],
                disabledReason: Self.functionFailureDetail(error),
                canManage: session.can(.companyProfileManage),
                fallbackLink: link
            )
        }
    }

    func beginConnectOnboarding(
        session: TenantSession,
        businessType: ConnectBusinessType
    ) async throws -> URL {
        try require(.companyProfileManage, session, query: "payments.connect.onboard")

        let response: ConnectResponse = try await client.functions.invoke(
            "stripe-connect",
            options: .init(
                body: ConnectRequest(action: "onboard", businessType: businessType.wireValue)
            )
        )

        if let error = response.error { throw DataError.rejected(error) }
        guard let raw = response.url, let url = URL(string: raw) else {
            throw DataError.unexpected("Stripe did not return an onboarding link.")
        }

        record("payments.connect.onboard", session, allowed: true, "One-time Stripe onboarding link issued server-side")
        return url
    }

    func connectDashboardLink(session: TenantSession) async throws -> URL {
        try require(.companyProfileManage, session, query: "payments.connect.dashboard")

        let response: ConnectResponse = try await client.functions.invoke(
            "stripe-connect",
            options: .init(body: ConnectRequest(action: "dashboard"))
        )

        if let error = response.error { throw DataError.rejected(error) }
        guard let raw = response.url, let url = URL(string: raw) else {
            throw DataError.unexpected("Stripe did not return a dashboard link.")
        }
        return url
    }

    // MARK: - The commercial model

    /// One authoritative read of where the company stands commercially.
    ///
    /// The permission check below is the usual legibility check, not the
    /// boundary: `company_commercial_state()` performs its own check inside the
    /// database and raises TD403 for a caller without a SaaS billing grant, so
    /// a role that is not the owner cannot reach this data by any route,
    /// including a hand-crafted request.
    ///
    /// Before reading, Stripe is refreshed when the company is already
    /// connected. That matters for the Founding 100: `stripe-connect` claims a
    /// place the moment Stripe reports `charges_enabled`, so an owner returning
    /// from browser onboarding sees the right answer on first load rather than
    /// after a manual retry. A failure to refresh is not fatal — the stored
    /// state is still read and shown.
    func commercialState(session: TenantSession) async throws -> CommercialState {
        try require(.saasBillingRead, session, query: "commercial.state")

        _ = try? await client.functions.invoke(
            "stripe-connect",
            options: .init(body: ConnectRequest(action: "status"))
        ) as ConnectResponse

        let rows: [CommercialStateRecord]
        do {
            let data = try await client.rpc("company_commercial_state").execute().data
            rows = try SupabaseCoding.decoder.decode([CommercialStateRecord].self, from: data)
        } catch let error as DecodingError {
            print("[data] could not decode commercial state: \(error)")
            throw DataError.unexpected("The server sent commercial details this version of the app can't read.")
        } catch {
            throw DataError.wrap(error)
        }

        guard let row = rows.first else { throw DataError.notFound }

        record(
            "commercial.state",
            session,
            allowed: true,
            "Trial, Stripe readiness, Founding Member number, monthly benefit, price and fee all computed in the database; the app renders them and derives none of them"
        )

        return row.model(canManageBilling: session.can(.saasBillingManage))
    }

    /// Records that the company keeps its own payment provider.
    ///
    /// `harbourSouthPayments` is refused by the database, not here: that model
    /// follows from Stripe reporting the connected account can take charges,
    /// and is set server-side by the founding-claim path. Sending it returns
    /// TD422, which surfaces as a plain sentence.
    func selectPaymentModel(session: TenantSession, model: PaymentModel) async throws {
        try require(.saasBillingManage, session, query: "commercial.paymentModel")

        try await perform("set_company_payment_model", ["p_model": .string(model.rawValue)])

        record(
            "commercial.paymentModel",
            session,
            allowed: true,
            "Payment model set to \(model.rawValue); Harbour South Payments cannot be claimed this way — it follows from Stripe"
        )
    }

    // MARK: - Business email identity

    func businessEmailSettings(session: TenantSession) async throws -> BusinessEmailSettings {
        try require(.companyProfileRead, session, query: "company.businessEmail")

        let company = try await companyRecord(session)

        record(
            "company.businessEmail",
            session,
            allowed: true,
            (company?.businessEmail ?? "").isEmpty
                ? "No business email set — invoice replies have nowhere to go"
                : "Business email set; used as the reply identity on customer invoice email"
        )

        return BusinessEmailSettings(
            email: company?.businessEmail?.nilIfBlank,
            companyName: company?.name ?? "",
            canManage: session.can(.companyProfileManage)
        )
    }

    func updateBusinessEmail(session: TenantSession, email: String?) async throws {
        try require(.companyProfileManage, session, query: "company.businessEmail.update")

        // Validated here for a readable sentence, and again by the
        // `companies_business_email_valid` check constraint, which is the one
        // that actually holds.
        let normalised = try BusinessEmail.normalise(email ?? "")

        try await performWrite(
            client.from("companies")
                .update(BusinessEmailPayload(
                    business_email: normalised,
                    updated_at: SupabaseCoding.timestamp(Date())
                ))
                .eq("id", value: session.companyID)
        )
        invalidateCompanyCache(session.companyID)

        record(
            "company.businessEmail.update",
            session,
            allowed: true,
            normalised == nil
                ? "Business email cleared"
                : "Business email stored; it is a reply identity only — no DNS, SPF, DKIM or API key is involved"
        )
    }

    // MARK: - SMS

    func smsCreditOverview(session: TenantSession) async throws -> SmsCreditOverview {
        let canRead = session.can(.smsLedgerRead)
        let canSend = session.can(.smsCreditsConsume)
        let canBuy = session.can(.smsCreditsPurchase)

        guard canRead || canSend || canBuy else {
            record("sms.overview", session, allowed: false, "Blocked before the request — missing smsLedgerRead")
            throw DataError.notPermitted(.smsLedgerRead)
        }

        // Balance is derived from the ledger in the database, never from a
        // mutable counter this app could get out of step with.
        let balance: Int = await {
            do {
                let data = try await client.rpc("sms_credit_balance").execute().data
                return (try? SupabaseCoding.decoder.decode(Int.self, from: data)) ?? 0
            } catch {
                return 0
            }
        }()

        let bundles = (try? await fetch(
            SmsBundleRecord.self,
            client.from("sms_bundles")
                .select(SmsBundleRecord.columns)
                .eq("is_active", value: true)
                .order("sort_order")
        )) ?? []

        var ledger: [SmsLedgerRow] = []
        var messages: [SmsMessageRow] = []

        if canRead {
            // RLS scopes both of these to the caller's company. Company A
            // cannot express a query that returns Company B's ledger.
            let rows = try await fetch(
                SmsLedgerRecord.self,
                client.from("sms_credit_ledger")
                    .select(SmsLedgerRecord.columns)
                    .order("created_at", ascending: false)
                    .limit(60)
            )

            ledger = rows.map { row in
                SmsLedgerRow(
                    id: row.id.uuidString,
                    kind: row.transactionType,
                    amount: row.amount,
                    balanceAfter: row.balanceAfter,
                    at: row.createdAt,
                    detail: row.transactionType.title
                )
            }

            let messageRows = try await fetch(
                SmsMessageRecord.self,
                client.from("notifications")
                    .select(SmsMessageRecord.columns)
                    .eq("channel", value: "sms")
                    .order("created_at", ascending: false)
                    .limit(40)
            )

            messages = messageRows.map { row in
                SmsMessageRow(
                    id: row.id.uuidString,
                    recipient: row.recipient,
                    body: row.body ?? "",
                    state: SmsDeliveryState(rawValue: row.status) ?? .queued,
                    customerName: nil,
                    sentAt: row.sentAt,
                    createdAt: row.createdAt,
                    creditsCharged: row.creditsCharged ?? 0,
                    creditsRefunded: row.creditsRefunded ?? 0,
                    failureReason: row.failureReason,
                    providerReference: row.providerReference
                )
            }
        }

        record(
            "sms.overview",
            session,
            allowed: true,
            "Balance and ledger scoped to this company by RLS; balance derived from the ledger, not a stored counter"
        )

        let company = try? await companyRecord(session)

        return SmsCreditOverview(
            companyName: company?.name ?? "",
            balance: balance,
            bundles: bundles.map(\.model),
            ledger: ledger,
            recentMessages: messages,
            canPurchase: canBuy,
            canSend: canSend,
            canReadLedger: canRead,
            messagingConfigured: true,
            purchasingConfigured: true
        )
    }

    func sendCustomerSms(session: TenantSession, draft: SmsSendDraft) async throws -> SmsSendOutcome {
        try require(.smsCreditsConsume, session, query: "sms.send")

        let body = draft.body.tidied
        guard !body.isEmpty else { throw DataError.rejected("Write the message first.") }
        guard body.count <= 640 else { throw DataError.rejected("Keep the message under 640 characters.") }

        do {
            // Everything privileged happens server-side: the company is derived
            // from the session, the customer is re-checked against it, and the
            // credit is consumed atomically *before* Twilio is called.
            let response: SmsSendResponse = try await client.functions.invoke(
                "sms-send",
                options: .init(body: SmsSendRequest(
                    customerId: draft.customerID,
                    jobId: draft.jobID,
                    invoiceId: draft.invoiceID,
                    template: draft.template.rawValue,
                    body: body,
                    phone: draft.phone
                ))
            )

            if response.sent == true {
                record(
                    "sms.send",
                    session,
                    allowed: true,
                    "Credit consumed atomically server-side before the provider was called"
                )
                return SmsSendOutcome(
                    sent: true,
                    creditsCharged: response.creditsCharged ?? 1,
                    balance: response.balance ?? 0,
                    providerReference: response.providerReference,
                    detail: response.detail ?? "Message handed to the carrier.",
                    insufficientCredit: false
                )
            }

            if response.reason == "insufficientCredits" {
                record("sms.send", session, allowed: false, "Refused for insufficient credit; balance unchanged, nothing sent")
                return SmsSendOutcome(
                    sent: false,
                    creditsCharged: 0,
                    balance: response.balance ?? 0,
                    providerReference: nil,
                    detail: response.error ?? "Not enough SMS credit. Buy more to continue.",
                    insufficientCredit: true
                )
            }

            throw DataError.rejected(response.error ?? "The message could not be sent.")
        } catch let error as DataError {
            throw error
        } catch {
            throw DataError.unexpected(Self.functionFailureDetail(error) ?? "The message could not be sent.")
        }
    }

    func purchaseSmsCredits(session: TenantSession, bundleID: String?, credits: Int?) async throws -> URL {
        try require(.smsCreditsPurchase, session, query: "sms.purchase")

        let response: SmsPurchaseResponse = try await client.functions.invoke(
            "sms-purchase",
            options: .init(body: SmsPurchaseRequest(action: "checkout", bundleId: bundleID, credits: credits))
        )

        if let error = response.error { throw DataError.rejected(error) }
        guard let raw = response.checkoutUrl, let url = URL(string: raw) else {
            throw DataError.unexpected("The checkout could not be started.")
        }

        record(
            "sms.purchase",
            session,
            allowed: true,
            "Checkout opened; credits are granted by the Stripe webhook only once the money arrives"
        )
        return url
    }

    // MARK: - Recurring service

    func recurringServices(session: TenantSession) async throws -> RecurringServiceBoard {
        try require(.jobsReadAll, session, query: "recurring.list")

        let rows = try await fetch(
            RecurringAgreementRecord.self,
            client.from("service_agreements")
                .select(RecurringAgreementRecord.columns)
                .order("next_due_date")
        )

        let customerIDs = Set(rows.map(\.customerID.uuidString))
        let addressIDs = Set(rows.map(\.addressID.uuidString))

        var customerNames: [String: String] = [:]
        var siteLines: [String: String] = [:]

        if !customerIDs.isEmpty {
            let customers = try await fetch(
                CustomerNameRecord.self,
                client.from("customers").select("id,name").in("id", values: Array(customerIDs))
            )
            for customer in customers { customerNames[customer.id.uuidString] = customer.name }
        }

        if !addressIDs.isEmpty {
            let addresses = try await fetch(
                RecurringAddressRecord.self,
                client.from("addresses").select("id,line1,city").in("id", values: Array(addressIDs))
            )
            for address in addresses {
                siteLines[address.id.uuidString] = "\(address.line1), \(address.city)"
            }
        }

        let agreements = rows.map { row in
            RecurringServiceRow(
                id: row.id.uuidString,
                customerID: row.customerID.uuidString,
                customerName: customerNames[row.customerID.uuidString] ?? "Customer",
                siteLine: siteLines[row.addressID.uuidString] ?? "Site",
                equipmentLabel: nil,
                title: row.templateTitle.isEmpty ? "Scheduled service" : row.templateTitle,
                frequency: row.frequency,
                intervalDays: row.intervalDays,
                nextDueDate: row.nextDueDate,
                isActive: row.isActive,
                lastGeneratedOn: row.lastGeneratedOn,
                lastGeneratedJobID: row.lastGeneratedJobID?.uuidString
            )
        }

        record("recurring.list", session, allowed: true, "Scoped to this company by RLS")

        return RecurringServiceBoard(
            agreements: agreements,
            canManage: session.can(.jobsManage),
            dueCount: agreements.filter { $0.isActive && $0.isDue }.count,
            activeCount: agreements.filter(\.isActive).count
        )
    }

    func saveRecurringService(session: TenantSession, draft: RecurringServiceDraft) async throws -> String {
        try require(.jobsManage, session, query: "recurring.save")

        if let message = draft.validationMessage { throw DataError.rejected(message) }

        func payload(companyID: String?) -> RecurringPayload {
            RecurringPayload(
                company_id: companyID,
                customer_id: draft.customerID,
                address_id: draft.addressID,
                equipment_id: draft.equipmentID?.nilIfBlank,
                frequency: draft.frequency.rawValue,
                interval_days: draft.frequency == .custom ? draft.intervalDays : nil,
                next_due_date: SupabaseCoding.day(draft.nextDueDate),
                is_active: draft.isActive,
                template_title: draft.title.tidied,
                template_description: draft.description.tidied,
                template_job_kind: draft.kind.rawValue,
                notes: draft.notes.nilIfBlank,
                updated_at: SupabaseCoding.timestamp(Date())
            )
        }

        // An update never restates the company: the row already has one, and
        // the policy refuses to move a row between tenants anyway.
        if let id = draft.id {
            try await performWrite(
                client.from("service_agreements").update(payload(companyID: nil)).eq("id", value: id)
            )
            record("recurring.save", session, allowed: true, "Updated; company scope enforced by RLS")
            return id
        }

        let created = try await fetch(
            IdentifierRecord.self,
            client.from("service_agreements").insert(payload(companyID: session.companyID)).select("id")
        )

        guard let id = created.first?.id.uuidString else {
            throw DataError.unexpected("The recurring visit was not created.")
        }

        record("recurring.save", session, allowed: true, "Created; company stamped server-side")
        return id
    }

    func deleteRecurringService(session: TenantSession, id: String) async throws {
        try require(.jobsManage, session, query: "recurring.delete")
        try await performWrite(client.from("service_agreements").delete().eq("id", value: id))
        record("recurring.delete", session, allowed: true, "Removed; jobs already generated are left intact")
    }

    // MARK: - Payment terms

    func paymentTermsSettings(session: TenantSession) async throws -> PaymentTermsSettings {
        let records = try await fetch(
            PaymentTermsRecord.self,
            client.from("companies")
                .select("default_payment_terms_label,default_payment_terms_days")
                .limit(1)
        )

        let label = records.first?.label ?? PaymentTermOption.net30.label
        let days = records.first?.days ?? 30
        let option = PaymentTermOption.from(label: label)

        return PaymentTermsSettings(
            option: option,
            customDays: days,
            label: label,
            canManage: session.can(.companyProfileManage)
        )
    }

    func updatePaymentTerms(session: TenantSession, option: PaymentTermOption, customDays: Int) async throws {
        try require(.companyProfileManage, session, query: "company.paymentTerms")

        let days = option == .custom ? max(customDays, 0) : (option.days ?? 30)
        let payload = PaymentTermsPayload(
            default_payment_terms_label: option.storedLabel(customDays: customDays),
            default_payment_terms_days: days,
            updated_at: SupabaseCoding.timestamp(Date())
        )

        try await performWrite(
            client.from("companies").update(payload).eq("id", value: session.companyID)
        )
        record("company.paymentTerms", session, allowed: true, "Company default updated; individual invoices may still override it")
    }

    // MARK: - Company profile

    func companyProfile(session: TenantSession) async throws -> CompanyProfileSettings {
        try require(.companyProfileRead, session, query: "company.profile")

        let rows = try await fetch(
            CompanyProfileRecord.self,
            client.from("companies")
                .select(CompanyProfileRecord.columns)
                .eq("id", value: session.companyID)
                .limit(1)
        )

        guard let row = rows.first else {
            // RLS returning nothing for the caller's own company means the
            // session no longer resolves to a company row. Saying "not found"
            // is more useful than an empty form that saves into nowhere.
            throw DataError.notFound
        }

        return CompanyProfileSettings(
            name: row.name,
            phone: row.phone ?? "",
            addressLine: row.addressLine ?? "",
            city: row.city ?? "",
            state: row.state ?? "",
            postalCode: row.postalCode ?? "",
            // Stored as a fraction, shown as a percentage.
            defaultTaxRatePercent: (row.defaultTaxRate.flatMap { Decimal(string: $0) } ?? 0) * 100,
            timeZoneIdentifier: row.timeZoneIdentifier ?? TimeZone.current.identifier,
            trade: row.trade,
            countryCode: row.countryCode,
            currencyCode: row.currencyCode,
            canManage: session.can(.companyProfileManage)
        )
    }

    func updateCompanyProfile(session: TenantSession, profile: CompanyProfileSettings) async throws {
        try require(.companyProfileManage, session, query: "company.profile.save")

        // Checked here as well as in the form. A screen is a convenience; this
        // is the boundary, and the database's own constraints are behind it.
        if let problem = profile.validationError {
            throw DataError.rejected(problem)
        }

        let payload = CompanyProfilePayload(
            name: profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
            phone: profile.phone.trimmingCharacters(in: .whitespacesAndNewlines),
            address_line: profile.addressLine.trimmingCharacters(in: .whitespacesAndNewlines),
            city: profile.city.trimmingCharacters(in: .whitespacesAndNewlines),
            state: profile.state.trimmingCharacters(in: .whitespacesAndNewlines),
            postal_code: profile.postalCode.trimmingCharacters(in: .whitespacesAndNewlines),
            // Back to the fraction the column holds. Sent as text so the
            // numeric column is not routed through a binary float.
            default_tax_rate: "\(profile.defaultTaxRateFraction)",
            time_zone_identifier: profile.timeZoneIdentifier,
            updated_at: SupabaseCoding.timestamp(Date())
        )

        // No trade, country or currency in the payload, and no company id in
        // the filter beyond the caller's own: RLS decides whether this row is
        // theirs, exactly as it does everywhere else.
        try await performWrite(
            client.from("companies").update(payload).eq("id", value: session.companyID)
        )

        // The cached row drives currency and terminology all over the app, so
        // it has to go or the next screen shows the old name.
        invalidateCompanyCache(session.companyID)
        record("company.profile.save", session, allowed: true, "Company details updated; trade, country and currency left unchanged")
    }

    // MARK: - Helpers

    /// Turns an Edge Function transport failure into something a person can act
    /// on, without leaking internals.
    ///
    /// ISSUE #2 — every Stripe failure was reported as "Something went wrong
    /// talking to the server."
    ///
    /// ROOT CAUSE, proven live: `stripe-connect` answers a Stripe rejection with
    /// `{"error": "<Stripe's own sentence>"}` and an HTTP 400. The Supabase SDK
    /// treats any non-2xx as a transport failure and *throws* — so the
    /// `if let error = response.error` line below the call site never ran, and
    /// the one genuinely useful sentence in the whole exchange was discarded.
    /// The live 400 currently carries: "You must complete your platform profile
    /// to use Connect and create live connected accounts." The owner saw none
    /// of that and was told to check their signal instead.
    ///
    /// This now reads the body off the thrown error and returns the server's
    /// message. Genuine transport problems still get their own wording.
    nonisolated static func functionFailureDetail(_ error: Error) -> String? {
        if let message = functionErrorBody(error) { return message }

        let text = String(describing: error)
        let lowered = text.lowercased()
        if text.contains("404") || lowered.contains("not found") {
            return "This feature is not deployed for this project yet."
        }
        if lowered.contains("offline") || lowered.contains("network") || lowered.contains("timed out") {
            return "No connection. Check your signal and try again."
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "No connection. Check your signal and try again."
            case .timedOut:
                return "The server took too long to answer. Try again in a moment."
            default:
                return nil
            }
        }
        return nil
    }

    /// Recovers the `{"error": "…"}` sentence from a non-2xx Edge Function reply.
    ///
    /// The SDK models this as `FunctionsError.httpError(code:data:)`, and the
    /// payload is the function's own JSON body — which is where Stripe's real
    /// explanation lives. Anything unrecognisable returns nil so the caller can
    /// fall back rather than show the user a blob of JSON.
    nonisolated static func functionErrorBody(_ error: Error) -> String? {
        guard let functionsError = error as? FunctionsError,
              case .httpError(let code, let data) = functionsError else { return nil }

        if let decoded = try? JSONDecoder().decode(FunctionErrorBody.self, from: data),
           let message = decoded.error?.trimmingCharacters(in: .whitespacesAndNewlines),
           !message.isEmpty {
            // 401/403 come from our own permission checks and are already
            // phrased for a person; Stripe's 400 is passed through verbatim
            // because Stripe tells the owner exactly what to go and fix.
            return message
        }

        switch code {
        case 401, 403:
            return "You don't have permission to change payment settings."
        case 409:
            return "This company has not connected Stripe yet."
        case 500...599:
            return "The payments service had a problem. Try again shortly."
        default:
            return nil
        }
    }
}

// MARK: - Small shared records

nonisolated struct CustomerNameRecord: Decodable, Sendable {
    let id: UUID
    let name: String
}

/// The `id` handed back by an insert that used `.select("id")`.
nonisolated struct IdentifierRecord: Decodable, Sendable {
    let id: UUID
}

private nonisolated struct RecurringAddressRecord: Decodable, Sendable {
    let id: UUID
    let line1: String
    let city: String
}

private nonisolated struct PaymentTermsRecord: Decodable, Sendable {
    let label: String?
    let days: Int?

    enum CodingKeys: String, CodingKey {
        case label = "default_payment_terms_label"
        case days = "default_payment_terms_days"
    }
}

/// The company row as the profile screen needs it.
///
/// `default_tax_rate` is read as text on purpose — a tax rate that has been
/// through a binary float is not the rate anybody typed.
private nonisolated struct CompanyProfileRecord: Decodable, Sendable {
    let name: String
    let trade: Trade
    let countryCode: String
    let currencyCode: String
    let phone: String?
    let addressLine: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let defaultTaxRate: String?
    let timeZoneIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case name, trade, phone, city, state
        case countryCode = "country_code"
        case currencyCode = "currency_code"
        case addressLine = "address_line"
        case postalCode = "postal_code"
        case defaultTaxRate = "default_tax_rate"
        case timeZoneIdentifier = "time_zone_identifier"
    }

    static let columns = "name,trade,country_code,currency_code,phone,address_line,city,state,postal_code,default_tax_rate::text,time_zone_identifier"
}

private nonisolated struct CompanyProfilePayload: Encodable, Sendable {
    let name: String
    let phone: String
    let address_line: String
    let city: String
    let state: String
    let postal_code: String
    let default_tax_rate: String
    let time_zone_identifier: String
    let updated_at: String
}
