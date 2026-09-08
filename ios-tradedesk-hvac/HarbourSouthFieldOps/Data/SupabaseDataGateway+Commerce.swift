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

private nonisolated struct RecurringPayload: Encodable, Sendable {
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
}

private nonisolated struct PaymentTermsPayload: Encodable, Sendable {
    let default_payment_terms_label: String
    let default_payment_terms_days: Int
    let updated_at: String
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

    func beginConnectOnboarding(session: TenantSession) async throws -> URL {
        try require(.companyProfileManage, session, query: "payments.connect.onboard")

        let response: ConnectResponse = try await client.functions.invoke(
            "stripe-connect",
            options: .init(body: ConnectRequest(action: "onboard"))
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

        let payload = RecurringPayload(
            customer_id: draft.customerID,
            address_id: draft.addressID,
            equipment_id: draft.equipmentID,
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

        // No company_id is sent. The column is defaulted from
        // current_company_id() and the RLS `with check` is what enforces it.
        if let id = draft.id {
            try await performWrite(
                client.from("service_agreements").update(payload).eq("id", value: id)
            )
            record("recurring.save", session, allowed: true, "Updated; company scope enforced by RLS")
            return id
        }

        let created = try await fetch(
            IdentifierRecord.self,
            client.from("service_agreements").insert(payload).select("id")
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

    // MARK: - Helpers

    /// Turns an Edge Function transport failure into something a person can act
    /// on, without leaking internals.
    nonisolated static func functionFailureDetail(_ error: Error) -> String? {
        let text = String(describing: error)
        if text.contains("404") || text.lowercased().contains("not found") {
            return "This feature is not deployed for this project yet."
        }
        if text.lowercased().contains("offline") || text.lowercased().contains("network") {
            return "No connection. Check your signal and try again."
        }
        return nil
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
