import Foundation

/// Default (development) behaviour for the communications surface.
///
/// The development stack has no Twilio behind it, so it says so plainly:
/// SMS reads as "not set up", sending is refused with a clear sentence, and
/// the template catalogue is the same one the server seeds. The Supabase
/// gateway overrides every member here with the real server calls.
extension DataGateway {
    private var liveOnly: DataError {
        .rejected("SMS is only available on a live company account.")
    }

    func messagingSetupStatus(session: TenantSession) async throws -> MessagingSetupStatus {
        MessagingSetupStatus(
            friendly: .notSetUp, registrationRoute: nil, phoneNumber: nil, billingState: "current",
            nextFeeDueAt: nil, numberFeeCents: 299, numberFeeCredits: 19, setupFeeCents: 0,
            retentionDays: 60, graceDays: 7, attention: nil, businessName: nil,
            canManage: session.role == .owner, hasSubscription: true, balance: 0,
            needsNumberChoice: false, solePropVerificationPending: false, providerAvailable: false
        )
    }

    func searchSmsNumbers(session: TenantSession, areaCode: String, contains: String?) async throws -> [AvailableSmsNumber] {
        throw liveOnly
    }

    func startSmsSetup(session: TenantSession, details: SmsBusinessDetailsDraft, phoneNumber: String) async throws -> SmsSetupResult {
        throw liveOnly
    }

    func chooseSmsNumber(session: TenantSession, phoneNumber: String) async throws -> SmsSetupResult {
        throw liveOnly
    }

    func refreshSmsSetup(session: TenantSession, retry: Bool) async throws -> SmsSetupResult {
        throw liveOnly
    }

    func releaseSmsNumber(session: TenantSession) async throws -> MessagingSetupStatus {
        throw liveOnly
    }

    /// Office unread is real even in development (the seeded office threads);
    /// customer SMS is always zero because nothing can arrive.
    func communicationsUnread(session: TenantSession) async throws -> CommunicationsUnread {
        let canReadOffice = session.role.usesFieldShell || session.can(.assignmentsManage) || session.can(.usersManage)
        let office = canReadOffice ? ((try? await officeInbox(session: session))?.unreadCount ?? 0) : 0
        return CommunicationsUnread(customerUnread: 0, officeUnread: office, latestTitle: nil, latestBody: nil,
                                    latestLink: nil, latestAt: nil)
    }

    func smsConversations(session: TenantSession) async throws -> [SmsConversationRow] { [] }

    func smsConversation(session: TenantSession, conversationID: String) async throws -> SmsConversationDetail {
        throw DataError.notFound
    }

    func markSmsConversationRead(session: TenantSession, conversationID: String) async throws {}

    func customerCommunications(session: TenantSession, customerID: String) async throws -> [SmsThreadMessage] { [] }

    func jobCommunications(session: TenantSession, jobID: String) async throws -> [SmsThreadMessage] { [] }

    func scheduledMessages(session: TenantSession) async throws -> [ScheduledMessageRow] { [] }

    func cancelScheduledMessage(session: TenantSession, id: String) async throws { throw liveOnly }

    func sentMessages(session: TenantSession) async throws -> [SentMessageRow] { [] }

    func smsTemplates(session: TenantSession) async throws -> [SmsTemplateEntry] {
        guard session.can(.smsCreditsConsume) || session.can(.smsLedgerRead) else {
            throw DataError.notPermitted(.smsCreditsConsume)
        }
        return SmsMessageKind.allCases.map { kind in
            SmsTemplateEntry(kind: kind, body: kind.defaultBody, defaultBody: kind.defaultBody,
                             allowedVariables: kind.allowedVariables, isCustomised: false,
                             isAutomatable: kind.isAutomatable, automationEnabled: kind.isAutomatable && kind.automationDefault,
                             automationDescription: kind.automationDescription)
        }
    }

    func saveSmsTemplate(session: TenantSession, kind: SmsMessageKind, body: String) async throws { throw liveOnly }
    func resetSmsTemplate(session: TenantSession, kind: SmsMessageKind) async throws { throw liveOnly }
    func setSmsAutomation(session: TenantSession, kind: SmsMessageKind, enabled: Bool) async throws { throw liveOnly }

    func smsUsage(session: TenantSession) async throws -> SmsUsageSummary {
        SmsUsageSummary(balance: 0, purchased: 0, used: 0, refunded: 0, numberFees: 0, segments30d: 0,
                        sent30d: 0, failed30d: 0, received30d: 0)
    }

    func previewSms(session: TenantSession, draft: SmsComposeDraft) async throws -> SmsPreview {
        let estimate = SmsTemplateValidator.estimate(draft.body)
        let count = SmsSegmentCounter.count(estimate)
        return SmsPreview(body: estimate, recipient: draft.phone ?? "", segments: max(count.segments, 1),
                          encoding: count.encoding, blockerMessage: "SMS is only available on a live company account.")
    }

    func dispatchSms(session: TenantSession, draft: SmsComposeDraft, scheduledFor: Date?) async throws -> SmsDispatchOutcome {
        throw liveOnly
    }
}
