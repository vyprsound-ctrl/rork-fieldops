import Foundation
import Supabase

// MARK: - Wire records

private nonisolated struct SetupStatusRecord: Decodable, Sendable {
    let friendlyStatus: String
    let registrationRoute: String?
    let phoneNumber: String?
    let billingState: String?
    let nextFeeDueAt: Date?
    let numberFeeCents: Int?
    let numberFeeCredits: Int?
    let setupFeeCents: Int?
    let retentionDays: Int?
    let graceDays: Int?
    let attention: String?
    let businessName: String?
    let canManage: Bool?
    let hasSubscription: Bool?
    let balance: Int?
    let needsNumberChoice: Bool?
    let solePropVerificationPending: Bool?

    enum CodingKeys: String, CodingKey {
        case friendlyStatus = "friendly_status", registrationRoute = "registration_route", phoneNumber = "phone_number"
        case billingState = "billing_state", nextFeeDueAt = "next_fee_due_at", numberFeeCents = "number_fee_cents"
        case numberFeeCredits = "number_fee_credits", setupFeeCents = "setup_fee_cents", retentionDays = "retention_days"
        case graceDays = "grace_days", attention, businessName = "business_name", canManage = "can_manage"
        case hasSubscription = "has_subscription", balance, needsNumberChoice = "needs_number_choice"
        case solePropVerificationPending = "sole_prop_verification_pending"
    }

    func model(providerAvailable: Bool) -> MessagingSetupStatus {
        MessagingSetupStatus(
            friendly: SmsFriendlyStatus(rawValue: friendlyStatus) ?? .notSetUp,
            registrationRoute: registrationRoute.flatMap(SmsRegistrationRoute.init(rawValue:)),
            phoneNumber: phoneNumber, billingState: billingState ?? "current", nextFeeDueAt: nextFeeDueAt,
            numberFeeCents: numberFeeCents ?? 299, numberFeeCredits: numberFeeCredits ?? 0,
            setupFeeCents: setupFeeCents ?? 0, retentionDays: retentionDays ?? 60, graceDays: graceDays ?? 7,
            attention: attention, businessName: businessName, canManage: canManage ?? false,
            hasSubscription: hasSubscription ?? false, balance: balance ?? 0,
            needsNumberChoice: needsNumberChoice ?? false, solePropVerificationPending: solePropVerificationPending ?? false,
            providerAvailable: providerAvailable
        )
    }
}

private nonisolated struct SetupResponse: Decodable, Sendable {
    let status: SetupStatusRecord?
    let providerAvailable: Bool?
    let error: String?
    let numberUnavailable: Bool?
    let numbers: [NumberRecord]?

    nonisolated struct NumberRecord: Decodable, Sendable {
        let phoneNumber: String
        let locality: String?
        let region: String?
    }
}

private nonisolated struct SetupRequest: Encodable, Sendable {
    let action: String
    var areaCode: String?
    var contains: String?
    var phoneNumber: String?
    var details: DetailsPayload?
    var acceptedTerms: Bool?

    nonisolated struct DetailsPayload: Encodable, Sendable {
        let route: String
        let legal_name: String
        let business_type: String?
        let ein: String?
        let website: String?
        let street: String
        let street2: String?
        let city: String
        let state: String
        let postal_code: String
        let rep_first_name: String
        let rep_last_name: String
        let rep_title: String
        let rep_email: String
        let rep_phone: String
        let opt_in_description: String
        let mobile_phone: String?
    }
}

private nonisolated struct UnreadRecord: Decodable, Sendable {
    let customerUnread: Int?
    let officeUnread: Int?
    let latestTitle: String?
    let latestBody: String?
    let latestLink: String?
    let latestAt: Date?

    enum CodingKeys: String, CodingKey {
        case customerUnread = "customer_unread", officeUnread = "office_unread", latestTitle = "latest_title"
        case latestBody = "latest_body", latestLink = "latest_link", latestAt = "latest_at"
    }
}

private nonisolated struct ConversationRecord: Decodable, Sendable {
    let conversationId: UUID
    let phoneE164: String
    let customerId: UUID?
    let customerName: String?
    let jobId: UUID?
    let jobNumber: String?
    let lastMessageAt: Date
    let lastPreview: String?
    let lastDirection: String?
    let unread: Int?
    let optedOut: Bool?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id", phoneE164 = "phone_e164", customerId = "customer_id"
        case customerName = "customer_name", jobId = "job_id", jobNumber = "job_number"
        case lastMessageAt = "last_message_at", lastPreview = "last_preview", lastDirection = "last_direction"
        case unread, optedOut = "opted_out"
    }

    var model: SmsConversationRow {
        SmsConversationRow(id: conversationId.uuidString.lowercased(), phone: phoneE164,
                           customerID: customerId?.uuidString.lowercased(), customerName: customerName,
                           jobID: jobId?.uuidString.lowercased(), jobNumber: jobNumber, lastMessageAt: lastMessageAt,
                           lastPreview: lastPreview ?? "", lastWasInbound: lastDirection == "inbound",
                           unread: unread ?? 0, optedOut: optedOut ?? false)
    }
}

private nonisolated struct ThreadMessageRecord: Decodable, Sendable {
    let id: UUID
    let conversationId: UUID?
    let direction: String
    let body: String?
    let at: Date
    let status: String
    let template: String?
    let segments: Int?
    let creditsCharged: Int?
    let creditsRefunded: Int?
    let jobId: UUID?
    let failureReason: String?

    static let columns = "id,conversation_id,direction,body,at,status,template,segments,credits_charged,credits_refunded,job_id,failure_reason"

    enum CodingKeys: String, CodingKey {
        case id, conversationId = "conversation_id", direction, body, at, status, template, segments
        case creditsCharged = "credits_charged", creditsRefunded = "credits_refunded", jobId = "job_id"
        case failureReason = "failure_reason"
    }

    var model: SmsThreadMessage {
        SmsThreadMessage(id: id.uuidString.lowercased(), conversationID: conversationId?.uuidString.lowercased(),
                         direction: direction == "inbound" ? .inbound : .outbound, body: body ?? "", at: at,
                         status: status, kind: template.flatMap(SmsMessageKind.init(rawValue:)), segments: segments,
                         creditsCharged: creditsCharged ?? 0, creditsRefunded: creditsRefunded ?? 0,
                         jobID: jobId?.uuidString.lowercased(), failureReason: failureReason)
    }
}

private nonisolated struct ScheduledRecord: Decodable, Sendable {
    let id: UUID
    let customerId: UUID
    let jobId: UUID?
    let templateKey: String
    let body: String?
    let scheduledFor: Date
    let status: String
    let source: String
    let failureReason: String?

    static let columns = "id,customer_id,job_id,template_key,body,scheduled_for,status,source,failure_reason"

    enum CodingKeys: String, CodingKey {
        case id, customerId = "customer_id", jobId = "job_id", templateKey = "template_key", body
        case scheduledFor = "scheduled_for", status, source, failureReason = "failure_reason"
    }
}

private nonisolated struct SentRecord: Decodable, Sendable {
    let id: UUID
    let recipient: String
    let customerId: UUID?
    let jobId: UUID?
    let template: String?
    let body: String?
    let createdAt: Date
    let status: String
    let segments: Int?
    let creditsCharged: Int?
    let creditsRefunded: Int?
    let failureReason: String?

    static let columns = "id,recipient,customer_id,job_id,template,body,created_at,status,segments,credits_charged,credits_refunded,failure_reason"

    enum CodingKeys: String, CodingKey {
        case id, recipient, customerId = "customer_id", jobId = "job_id", template, body, createdAt = "created_at"
        case status, segments, creditsCharged = "credits_charged", creditsRefunded = "credits_refunded"
        case failureReason = "failure_reason"
    }
}

private nonisolated struct SmsJobNumberRecord: Decodable, Sendable {
    let id: UUID
    let number: String
}

private nonisolated struct TemplateRecord: Decodable, Sendable {
    let templateKey: String
    let body: String
    let defaultBody: String
    let allowedVariables: [String]
    let isCustomised: Bool
    let isAutomatable: Bool
    let automationEnabled: Bool
    let automationDescription: String?

    enum CodingKeys: String, CodingKey {
        case templateKey = "template_key", body, defaultBody = "default_body", allowedVariables = "allowed_variables"
        case isCustomised = "is_customised", isAutomatable = "is_automatable", automationEnabled = "automation_enabled"
        case automationDescription = "automation_description"
    }
}

private nonisolated struct UsageRecord: Decodable, Sendable {
    let balance: Int
    let purchased: Int
    let used: Int
    let refunded: Int
    let fees: Int
    let segments30d: Int
    let messagesSent30d: Int
    let messagesFailed30d: Int
    let messagesReceived30d: Int

    enum CodingKeys: String, CodingKey {
        case balance, purchased, used, refunded, fees, segments30d = "segments_30d"
        case messagesSent30d = "messages_sent_30d", messagesFailed30d = "messages_failed_30d"
        case messagesReceived30d = "messages_received_30d"
    }
}

private nonisolated struct SendRequest: Encodable, Sendable {
    let action: String
    let customerId: String
    let jobId: String?
    let quoteId: String?
    let invoiceId: String?
    let template: String
    let body: String
    let phone: String?
    let eta: String?
    let scheduledFor: String?
}

private nonisolated struct SendResponse: Decodable, Sendable {
    let sent: Bool?
    let scheduled: Bool?
    let preview: Bool?
    let body: String?
    let recipient: String?
    let segments: Int?
    let encoding: String?
    let blockerMessage: String?
    let creditsCharged: Int?
    let balance: Int?
    let conversationId: String?
    let detail: String?
    let error: String?
}

// MARK: - Gateway

extension SupabaseDataGateway {
    private func requireAnySms(_ session: TenantSession, query: String) throws {
        guard session.can(.smsCreditsConsume) || session.can(.smsLedgerRead) else {
            record(query, session, allowed: false, "Blocked before the request — missing SMS permission")
            throw DataError.notPermitted(.smsCreditsConsume)
        }
    }

    private func rpcRows<T: Decodable>(_ type: T.Type, _ name: String, _ params: [String: AnyJSON] = [:]) async throws -> [T] {
        do {
            let data = try await client.rpc(name, params: params).execute().data
            return try SupabaseCoding.decoder.decode([T].self, from: data)
        } catch let error as DecodingError {
            print("[comms] could not decode \(name): \(error)")
            throw DataError.unexpected("This screen couldn't read its messages. Nothing was changed.")
        } catch {
            throw Self.translate(error)
        }
    }

    private func setupCall(_ request: SetupRequest) async throws -> SetupResponse {
        do {
            return try await client.functions.invoke("sms-setup", options: .init(body: request))
        } catch {
            throw Self.translateFunctionFailure(error, fallback: "SMS setup couldn't be reached. Try again shortly.")
        }
    }

    private func setupResult(_ response: SetupResponse) throws -> SmsSetupResult {
        guard let status = response.status else {
            throw DataError.rejected(response.error ?? "SMS setup couldn't be read.")
        }
        return SmsSetupResult(status: status.model(providerAvailable: response.providerAvailable ?? true),
                              message: response.error, numberUnavailable: response.numberUnavailable ?? false)
    }

    func messagingSetupStatus(session: TenantSession) async throws -> MessagingSetupStatus {
        guard session.can(.smsCreditsConsume) || session.can(.smsLedgerRead) || session.can(.saasBillingRead) else {
            throw DataError.notPermitted(.smsCreditsConsume)
        }
        let response = try await setupCall(SetupRequest(action: "status"))
        record("sms.setup.status", session, allowed: true, "Company resolved from the session server-side")
        return try setupResult(response).status
    }

    func searchSmsNumbers(session: TenantSession, areaCode: String, contains: String?) async throws -> [AvailableSmsNumber] {
        guard session.role == .owner else { throw DataError.rejected("Only the company owner can set up SMS.") }
        let response = try await setupCall(SetupRequest(action: "search", areaCode: areaCode, contains: contains))
        if let error = response.error, (response.numbers ?? []).isEmpty { throw DataError.rejected(error) }
        return (response.numbers ?? []).map { AvailableSmsNumber(phoneNumber: $0.phoneNumber, locality: $0.locality, region: $0.region) }
    }

    func startSmsSetup(session: TenantSession, details: SmsBusinessDetailsDraft, phoneNumber: String) async throws -> SmsSetupResult {
        guard session.role == .owner else { throw DataError.rejected("Only the company owner can set up SMS.") }
        if let problem = details.problem { throw DataError.rejected(problem) }
        func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let payload = SetupRequest.DetailsPayload(
            route: details.route.rawValue, legal_name: clean(details.legalName),
            business_type: details.route.needsEIN ? details.structure.rawValue : nil,
            ein: details.route.needsEIN ? clean(details.ein) : nil,
            website: details.route.needsEIN ? clean(details.website) : (clean(details.website).isEmpty ? nil : clean(details.website)),
            street: clean(details.street), street2: clean(details.street2).isEmpty ? nil : clean(details.street2),
            city: clean(details.city), state: clean(details.state).uppercased(), postal_code: clean(details.postalCode),
            rep_first_name: clean(details.repFirstName), rep_last_name: clean(details.repLastName),
            rep_title: clean(details.repTitle).isEmpty ? "Owner" : clean(details.repTitle),
            rep_email: clean(details.repEmail), rep_phone: clean(details.repPhone),
            opt_in_description: clean(details.optInDescription),
            mobile_phone: details.route == .soleProprietor ? clean(details.mobilePhone) : nil
        )
        let response = try await setupCall(SetupRequest(action: "start", phoneNumber: phoneNumber, details: payload,
                                                        acceptedTerms: details.acceptedResponsibility))
        record("sms.setup.start", session, allowed: true, "Business details submitted for the company's own registration")
        return try setupResult(response)
    }

    func chooseSmsNumber(session: TenantSession, phoneNumber: String) async throws -> SmsSetupResult {
        guard session.role == .owner else { throw DataError.rejected("Only the company owner can set up SMS.") }
        return try setupResult(try await setupCall(SetupRequest(action: "choose_number", phoneNumber: phoneNumber)))
    }

    func refreshSmsSetup(session: TenantSession, retry: Bool) async throws -> SmsSetupResult {
        guard session.role == .owner else { throw DataError.rejected("Only the company owner can manage SMS.") }
        return try setupResult(try await setupCall(SetupRequest(action: retry ? "retry" : "refresh")))
    }

    func releaseSmsNumber(session: TenantSession) async throws -> MessagingSetupStatus {
        guard session.role == .owner else { throw DataError.rejected("Only the company owner can release the SMS number.") }
        return try setupResult(try await setupCall(SetupRequest(action: "release"))).status
    }

    func communicationsUnread(session: TenantSession) async throws -> CommunicationsUnread {
        let rows = try await rpcRows(UnreadRecord.self, "communications_unread")
        guard let row = rows.first else { return .none }
        return CommunicationsUnread(customerUnread: row.customerUnread ?? 0, officeUnread: row.officeUnread ?? 0,
                                    latestTitle: row.latestTitle, latestBody: row.latestBody,
                                    latestLink: row.latestLink, latestAt: row.latestAt)
    }

    func smsConversations(session: TenantSession) async throws -> [SmsConversationRow] {
        try requireAnySms(session, query: "sms.conversations")
        try require(.customersReadAll, session, query: "sms.conversations")
        let rows = try await rpcRows(ConversationRecord.self, "sms_conversation_list", ["p_limit": .integer(200)])
        record("sms.conversations", session, allowed: true, "Conversations scoped to this company by the database")
        return rows.map(\.model)
    }

    func smsConversation(session: TenantSession, conversationID: String) async throws -> SmsConversationDetail {
        try requireAnySms(session, query: "sms.conversation")
        let list = try await smsConversations(session: session)
        guard let conversation = list.first(where: { $0.id == conversationID.lowercased() }) else { throw DataError.notFound }
        let messages = try await fetch(
            ThreadMessageRecord.self,
            client.from("sms_thread_messages").select(ThreadMessageRecord.columns)
                .eq("conversation_id", value: conversationID.lowercased()).order("at").limit(500)
        )
        return SmsConversationDetail(conversation: conversation, messages: messages.map(\.model),
                                     recipientName: conversation.displayName)
    }

    func markSmsConversationRead(session: TenantSession, conversationID: String) async throws {
        _ = try await client.rpc("mark_sms_conversation_read", params: ["p_conversation": AnyJSON.string(conversationID.lowercased())] as [String: AnyJSON]).execute()
    }

    func customerCommunications(session: TenantSession, customerID: String) async throws -> [SmsThreadMessage] {
        try requireAnySms(session, query: "sms.customerHistory")
        let rows = try await fetch(
            ThreadMessageRecord.self,
            client.from("sms_thread_messages").select(ThreadMessageRecord.columns)
                .eq("customer_id", value: customerID.lowercased()).order("at").limit(300)
        )
        return rows.map(\.model)
    }

    func jobCommunications(session: TenantSession, jobID: String) async throws -> [SmsThreadMessage] {
        try requireAnySms(session, query: "sms.jobHistory")
        let rows = try await fetch(
            ThreadMessageRecord.self,
            client.from("sms_thread_messages").select(ThreadMessageRecord.columns)
                .eq("job_id", value: jobID.lowercased()).order("at").limit(300)
        )
        return rows.map(\.model)
    }

    private func customerNames(_ ids: [UUID]) async -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let rows = (try? await fetch(CustomerNameRecord.self,
                                     client.from("customers").select("id,name")
                                         .in("id", values: Array(Set(ids)).map { $0.uuidString.lowercased() }))) ?? []
        return Dictionary(rows.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    }

    private func jobNumbers(_ ids: [UUID]) async -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        let rows = (try? await fetch(SmsJobNumberRecord.self,
                                     client.from("jobs").select("id,number")
                                         .in("id", values: Array(Set(ids)).map { $0.uuidString.lowercased() }))) ?? []
        return Dictionary(rows.map { ($0.id, $0.number) }, uniquingKeysWith: { a, _ in a })
    }

    func scheduledMessages(session: TenantSession) async throws -> [ScheduledMessageRow] {
        try requireAnySms(session, query: "sms.scheduled")
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-7 * 86_400))
        let rows = try await fetch(
            ScheduledRecord.self,
            client.from("scheduled_messages").select(ScheduledRecord.columns)
                .gte("scheduled_for", value: since).order("scheduled_for").limit(200)
        )
        let names = await customerNames(rows.map(\.customerId))
        let jobs = await jobNumbers(rows.compactMap(\.jobId))
        return rows.map { row in
            let kind = SmsMessageKind(rawValue: row.templateKey) ?? .customMessage
            return ScheduledMessageRow(
                id: row.id.uuidString.lowercased(), customerID: row.customerId.uuidString.lowercased(),
                customerName: names[row.customerId] ?? "Customer", jobNumber: row.jobId.flatMap { jobs[$0] }, kind: kind,
                preview: row.body ?? kind.title, scheduledFor: row.scheduledFor, status: row.status,
                isAutomation: row.source == "automation", failureReason: row.failureReason)
        }
    }

    func cancelScheduledMessage(session: TenantSession, id: String) async throws {
        try require(.smsCreditsConsume, session, query: "sms.cancelScheduled")
        let data = try await client.rpc("cancel_scheduled_sms", params: ["p_id": AnyJSON.string(id.lowercased())] as [String: AnyJSON]).execute().data
        if (try? SupabaseCoding.decoder.decode(Bool.self, from: data)) == false {
            throw DataError.rejected("That message has already been sent or cancelled.")
        }
    }

    func sentMessages(session: TenantSession) async throws -> [SentMessageRow] {
        try requireAnySms(session, query: "sms.sent")
        let rows = try await fetch(
            SentRecord.self,
            client.from("notifications").select(SentRecord.columns)
                .eq("channel", value: "sms").order("created_at", ascending: false).limit(100)
        )
        let names = await customerNames(rows.compactMap(\.customerId))
        let jobs = await jobNumbers(rows.compactMap(\.jobId))
        return rows.map { row in
            SentMessageRow(
                id: row.id.uuidString.lowercased(), recipient: row.recipient,
                customerID: row.customerId?.uuidString.lowercased(), customerName: row.customerId.flatMap { names[$0] },
                jobNumber: row.jobId.flatMap { jobs[$0] }, kind: row.template.flatMap(SmsMessageKind.init(rawValue:)),
                body: row.body ?? "", at: row.createdAt, state: SmsDeliveryState(rawValue: row.status) ?? .queued,
                segments: row.segments, creditsCharged: row.creditsCharged ?? 0, creditsRefunded: row.creditsRefunded ?? 0,
                failureReason: row.failureReason)
        }
    }

    func smsTemplates(session: TenantSession) async throws -> [SmsTemplateEntry] {
        try requireAnySms(session, query: "sms.templates")
        let rows = try await rpcRows(TemplateRecord.self, "sms_template_catalog")
        return rows.compactMap { row in
            guard let kind = SmsMessageKind(rawValue: row.templateKey) else { return nil }
            return SmsTemplateEntry(kind: kind, body: row.body, defaultBody: row.defaultBody,
                                    allowedVariables: row.allowedVariables.compactMap(SmsTemplateVariable.init(rawValue:)),
                                    isCustomised: row.isCustomised, isAutomatable: row.isAutomatable,
                                    automationEnabled: row.automationEnabled, automationDescription: row.automationDescription)
        }
    }

    func saveSmsTemplate(session: TenantSession, kind: SmsMessageKind, body: String) async throws {
        if let problem = SmsTemplateValidator.problem(kind: kind, body: body) { throw DataError.rejected(problem) }
        try await perform("save_sms_template", ["p_key": .string(kind.rawValue), "p_body": .string(body)])
        record("sms.template.save", session, allowed: true, "Template validated server-side")
    }

    func resetSmsTemplate(session: TenantSession, kind: SmsMessageKind) async throws {
        try await perform("reset_sms_template", ["p_key": .string(kind.rawValue)])
    }

    func setSmsAutomation(session: TenantSession, kind: SmsMessageKind, enabled: Bool) async throws {
        try await perform("set_sms_automation", ["p_key": .string(kind.rawValue), "p_enabled": .bool(enabled)])
    }

    func smsUsage(session: TenantSession) async throws -> SmsUsageSummary {
        try require(.smsLedgerRead, session, query: "sms.usage")
        guard let row = try await rpcRows(UsageRecord.self, "sms_usage_summary").first else {
            throw DataError.unexpected("SMS usage couldn't be read.")
        }
        return SmsUsageSummary(balance: row.balance, purchased: row.purchased, used: row.used, refunded: row.refunded,
                               numberFees: row.fees, segments30d: row.segments30d, sent30d: row.messagesSent30d,
                               failed30d: row.messagesFailed30d, received30d: row.messagesReceived30d)
    }

    private func sendCall(_ action: String, _ draft: SmsComposeDraft, scheduledFor: Date?) async throws -> SendResponse {
        let request = SendRequest(
            action: action, customerId: draft.customerID, jobId: draft.jobID, quoteId: draft.quoteID,
            invoiceId: draft.invoiceID, template: draft.kind.rawValue, body: draft.body, phone: draft.phone,
            eta: draft.eta, scheduledFor: scheduledFor.map { ISO8601DateFormatter().string(from: $0) }
        )
        do {
            return try await client.functions.invoke("sms-send", options: .init(body: request))
        } catch {
            throw Self.translateFunctionFailure(error, fallback: "The message couldn't be sent. No credit was used.")
        }
    }

    func previewSms(session: TenantSession, draft: SmsComposeDraft) async throws -> SmsPreview {
        try require(.smsCreditsConsume, session, query: "sms.preview")
        let response = try await sendCall("preview", draft, scheduledFor: nil)
        guard let body = response.body else { throw DataError.rejected(response.error ?? "The message couldn't be prepared.") }
        return SmsPreview(body: body, recipient: response.recipient ?? "", segments: response.segments ?? 1,
                          encoding: response.encoding ?? "GSM-7", blockerMessage: response.blockerMessage)
    }

    func dispatchSms(session: TenantSession, draft: SmsComposeDraft, scheduledFor: Date?) async throws -> SmsDispatchOutcome {
        try require(.smsCreditsConsume, session, query: "sms.send")
        try requireWritableWorkspace(session, query: "sms.send")
        let response = try await sendCall(scheduledFor == nil ? "send" : "schedule", draft, scheduledFor: scheduledFor)
        if response.scheduled == true {
            record("sms.schedule", session, allowed: true, "Scheduled; every gate is re-checked at send time")
            return SmsDispatchOutcome(sent: false, scheduled: true, creditsCharged: 0, segments: response.segments,
                                      balance: nil, conversationID: nil, detail: "Scheduled. Credits are used when it sends.")
        }
        guard response.sent == true else { throw DataError.rejected(response.error ?? "The message couldn't be sent.") }
        record("sms.send", session, allowed: true, "Reserved atomically, sent from the company's own number")
        return SmsDispatchOutcome(sent: true, scheduled: false, creditsCharged: response.creditsCharged ?? 0,
                                  segments: response.segments, balance: response.balance,
                                  conversationID: response.conversationId,
                                  detail: response.detail ?? "Handed to the carrier. Delivery is confirmed separately.")
    }
}
