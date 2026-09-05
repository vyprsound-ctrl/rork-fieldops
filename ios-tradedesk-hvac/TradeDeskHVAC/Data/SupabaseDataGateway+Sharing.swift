import Foundation
import Supabase

// Customer-facing invoice delivery, against the real database.
//
// Three separate boundaries hold here, and none of them is this file:
//
//  - the payment link is written through the `companies` policy, which already
//    requires `companyProfileManage`, and its shape is re-checked by a database
//    constraint;
//  - share tokens are issued by a database function running as the caller, so
//    RLS decides which invoice they can reach and whether they may write at all;
//  - sending happens in an edge function, because a provider credential must
//    never live in an app someone can unzip.
//
// The permission checks below are the same courtesy checks used elsewhere in
// this gateway: they turn a refusal into a sentence instead of an empty screen.

/// One live share token row.
nonisolated struct InvoiceShareTokenRecord: Decodable, Sendable {
    let id: UUID
    let token: String
    let createdAt: Date
    let revokedAt: Date?
    let lastViewedAt: Date?
    let viewCount: Int

    enum CodingKeys: String, CodingKey {
        case id, token
        case createdAt = "created_at"
        case revokedAt = "revoked_at"
        case lastViewedAt = "last_viewed_at"
        case viewCount = "view_count"
    }

    static let columns = "id,token,created_at,revoked_at,last_viewed_at,view_count"
}

/// A recorded delivery attempt from the shared notifications ledger.
nonisolated struct NotificationRecord: Decodable, Sendable {
    let id: UUID
    let channel: NotificationChannel
    let template: String
    let recipient: String
    let status: NotificationStatus
    let sentAt: Date?
    let deliveredAt: Date?
    let failureReason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, channel, template, recipient, status
        case sentAt = "sent_at"
        case deliveredAt = "delivered_at"
        case failureReason = "failure_reason"
        case createdAt = "created_at"
    }

    static let columns = "id,channel,template,recipient,status,sent_at,delivered_at,failure_reason,created_at"
}

nonisolated struct CompanyPaymentLinkUpdate: Encodable, Sendable {
    let onlinePaymentLinkURL: String?

    enum CodingKeys: String, CodingKey {
        case onlinePaymentLinkURL = "online_payment_link_url"
    }
}

nonisolated struct SendInvoiceRequest: Encodable, Sendable {
    let invoiceId: String
    let channels: [String]
}

nonisolated struct SendInvoiceChannelResult: Decodable, Sendable {
    let channel: String
    let recipient: String
    let status: String
    let configured: Bool
    let detail: String
}

nonisolated struct SendInvoiceResponse: Decodable, Sendable {
    let invoiceId: String
    let viewUrl: String
    let results: [SendInvoiceChannelResult]
}

/// The shape the function uses to refuse.
nonisolated struct EdgeFunctionError: Decodable, Sendable {
    let error: String?
    let message: String?
    let permission: String?
}

extension SupabaseDataGateway {
    // MARK: - The company's own payment link

    func companyPaymentLink(session: TenantSession) async throws -> PaymentLinkSettings {
        try require(.companyProfileRead, session, query: "company.paymentLink")

        let stored = try await companyRecord(session)?.onlinePaymentLinkURL
        record(
            "company.paymentLink",
            session,
            allowed: true,
            stored == nil
                ? "No payment link configured for this company"
                : "Payment link configured — a URL only, no processor account and no credential"
        )

        return PaymentLinkSettings(
            url: stored,
            displayHost: OnlinePaymentLink.displayHost(stored),
            canManage: session.can(.companyProfileManage)
        )
    }

    func updateCompanyPaymentLink(session: TenantSession, url: String?) async throws {
        try require(.companyProfileManage, session, query: "company.paymentLink.update")

        // Validated here for a readable message, and again by the database's
        // own check constraint, which is what actually holds.
        let normalised = try OnlinePaymentLink.normalise(url ?? "")

        try await performWrite(
            client.from("companies")
                .update(CompanyPaymentLinkUpdate(onlinePaymentLinkURL: normalised))
                .eq("id", value: session.companyID)
        )
        invalidateCompanyCache(session.companyID)

        record(
            "company.paymentLink.update",
            session,
            allowed: true,
            normalised == nil
                ? "Payment link cleared — no payment button is shown to customers"
                : "Payment link stored (\(OnlinePaymentLink.displayHost(normalised) ?? "—")) — TradeDesk connects nothing and moves no money"
        )
    }

    // MARK: - Sharing one invoice

    func invoiceSharing(session: TenantSession, invoiceID: String) async throws -> InvoiceSharing {
        let invoice = try await requireInvoice(invoiceID, session, query: "invoices.sharing")

        let tokens = try await fetch(
            InvoiceShareTokenRecord.self,
            client.from("invoice_share_tokens")
                .select(InvoiceShareTokenRecord.columns)
                .eq("invoice_id", value: invoice.id)
                .is("revoked_at", value: nil)
                .limit(1)
        )

        // Delivery history is governed by the notifications policy; a role
        // without it simply gets no rows rather than an error.
        let deliveries = try await fetch(
            NotificationRecord.self,
            client.from("notifications")
                .select(NotificationRecord.columns)
                .eq("invoice_id", value: invoice.id)
                .order("created_at", ascending: false)
                .limit(20)
        )

        var emailRecipient: String?
        var smsRecipient: String?
        if let contactID = invoice.billingContactID, session.can(.customerBillingDetailsRead) {
            let contacts = try await fetch(
                BillingContactRecord.self,
                client.from("customer_contacts")
                    .select(BillingContactRecord.columns)
                    .eq("id", value: contactID)
                    .limit(1)
            )
            emailRecipient = contacts.first?.email
            smsRecipient = contacts.first?.phone
        }

        let company = try await companyRecord(session)
        let blocked = Self.sharingBlockedReason(for: invoice)

        return InvoiceSharing(
            shareURL: tokens.first.flatMap { BackendConfiguration.invoiceViewURL(token: $0.token) },
            canShare: blocked == nil,
            blockedReason: blocked,
            canSend: session.can(.invoicesManage),
            emailRecipient: emailRecipient,
            smsRecipient: smsRecipient,
            paymentLink: PaymentLinkSettings(
                url: company?.onlinePaymentLinkURL,
                displayHost: OnlinePaymentLink.displayHost(company?.onlinePaymentLinkURL),
                canManage: session.can(.companyProfileManage)
            ),
            deliveries: deliveries.map(Self.deliveryProjection),
            isSimulated: false
        )
    }

    func issueInvoiceShareLink(session: TenantSession, invoiceID: String, rotate: Bool) async throws -> String {
        try require(.invoicesManage, session, query: "invoices.share.issue")

        let token = try await performReturningID(
            "issue_invoice_share_token",
            ["p_invoice": .string(invoiceID), "p_rotate": .bool(rotate)]
        )
        guard let url = BackendConfiguration.invoiceViewURL(token: token) else {
            throw DataError.unexpected("The link was created but this build has no backend address to build it from.")
        }

        record(
            "invoices.share.issue",
            session,
            allowed: true,
            rotate
                ? "Previous link revoked and a new random token issued by the database"
                : "Random token issued by the database — the URL carries no company, customer or invoice identifier"
        )
        return url
    }

    func revokeInvoiceShareLink(session: TenantSession, invoiceID: String) async throws {
        try require(.invoicesManage, session, query: "invoices.share.revoke")
        try await perform("revoke_invoice_share_tokens", ["p_invoice": .string(invoiceID)])
        record("invoices.share.revoke", session, allowed: true, "Every live link for this invoice stopped working")
    }

    // MARK: - Sending

    func sendInvoice(
        session: TenantSession,
        invoiceID: String,
        channels: Set<NotificationChannel>
    ) async throws -> InvoiceSendOutcome {
        try require(.invoicesManage, session, query: "invoices.send")

        let wanted = [NotificationChannel.email, .sms].filter { channels.contains($0) }
        guard !wanted.isEmpty else { throw DataError.rejected("Choose email, SMS or both.") }

        do {
            let response: SendInvoiceResponse = try await client.functions.invoke(
                "send-invoice",
                options: .init(
                    body: SendInvoiceRequest(invoiceId: invoiceID, channels: wanted.map(\.rawValue))
                )
            )

            let results = response.results.map { result in
                InvoiceSendResult(
                    channel: NotificationChannel(rawValue: result.channel) ?? .email,
                    recipient: result.recipient,
                    delivered: result.status == "sent",
                    providerConfigured: result.configured,
                    detail: result.detail
                )
            }

            let outcome = InvoiceSendOutcome(results: results)
            record(
                "invoices.send",
                session,
                allowed: true,
                "\(outcome.deliveredCount) of \(results.count) channel(s) delivered — every attempt recorded in the notifications ledger with its real outcome"
            )
            return outcome
        } catch let error as FunctionsError {
            throw Self.translateSend(error)
        } catch let error as DataError {
            throw error
        } catch {
            print("[data] send-invoice failed: \(error)")
            throw DataError.unexpected("Couldn't reach the server to send this invoice. Try again in a moment.")
        }
    }

    /// Turns the function's own refusal into the same `DataError` the rest of
    /// the app speaks.
    private static func translateSend(_ error: FunctionsError) -> DataError {
        guard case .httpError(let code, let data) = error else {
            return .unexpected("Couldn't reach the server to send this invoice. Try again in a moment.")
        }

        let decoded = try? JSONDecoder().decode(EdgeFunctionError.self, from: data)

        switch code {
        case 401:
            return .unexpected("Your session has expired. Sign in again.")
        case 403:
            return .notPermitted(decoded?.permission.flatMap(Permission.init(rawValue:)) ?? .invoicesManage)
        case 404:
            return .notFound
        case 422:
            return .rejected(decoded?.message ?? "That invoice can't be sent as it stands.")
        default:
            print("[data] send-invoice refused: \(code)")
            return .unexpected("The server couldn't send this invoice. Try again in a moment.")
        }
    }

    private static func sharingBlockedReason(for invoice: Invoice) -> String? {
        switch invoice.status {
        case .draft:
            return "Move \(invoice.number) out of draft before sharing it with the customer."
        case .void:
            return "\(invoice.number) has been voided and can't be shared."
        default:
            return nil
        }
    }

    private static func deliveryProjection(_ record: NotificationRecord) -> InvoiceDeliveryProjection {
        InvoiceDeliveryProjection(
            id: record.id.uuidString,
            channel: record.channel,
            channelTitle: record.channel.title,
            channelSymbol: record.channel == .email ? "envelope.fill" : "message.fill",
            recipient: record.recipient,
            status: record.status,
            statusTitle: record.status.title,
            statusTone: Self.tone(for: record.status),
            timeLabel: Formatters.shortDayAndTime(record.sentAt ?? record.createdAt),
            failureReason: record.failureReason
        )
    }

    private static func tone(for status: NotificationStatus) -> StatusTone {
        switch status {
        case .queued: return .warning
        case .sent: return .info
        case .delivered: return .success
        case .failed: return .danger
        }
    }
}
