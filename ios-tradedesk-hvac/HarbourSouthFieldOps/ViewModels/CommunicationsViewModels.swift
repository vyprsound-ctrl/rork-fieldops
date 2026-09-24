import AudioToolbox
import Foundation
import Observation
import UserNotifications

extension Notification.Name {
    /// Posted when a push arrives while the app is in the foreground, so the
    /// global indicator refreshes at once instead of on its next poll.
    static let communicationsPushReceived = Notification.Name("communications.pushReceived")
}

/// App-wide unread state for customer replies and office messages.
///
/// Lives above both shells, so a new message is noticed on ANY screen: it
/// drives the tab badges, the Communications row, the app icon badge and the
/// in-app banner ("New message from Mike · Job #1047") that deep-links to the
/// conversation. Push covers the background and terminated cases; this covers
/// the foreground even when push is off.
@Observable
final class CommunicationsMonitor {
    private(set) var unread: CommunicationsUnread = .none
    private(set) var hasLoaded: Bool = false
    /// The banner currently shown, if any.
    var banner: MessageBanner?
    private var lastAnnouncedAt: Date?

    nonisolated struct MessageBanner: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let body: String
        let link: String
    }

    func reset() {
        unread = .none
        hasLoaded = false
        banner = nil
        lastAnnouncedAt = nil
    }

    /// `announce` is false when the OS has already shown the push banner, so
    /// the same message never produces two banners.
    func refresh(gateway: DataGateway, session: TenantSession, announce: Bool = true, updateAppBadge: Bool = false) async {
        guard let latest = try? await gateway.communicationsUnread(session: session) else { return }
        let isNew = latest.latestAt.map { at in lastAnnouncedAt.map { at > $0 } ?? false } ?? false
        if hasLoaded, isNew, announce, let title = latest.latestTitle, let link = latest.latestLink {
            banner = MessageBanner(id: "\(link)-\(latest.latestAt?.timeIntervalSince1970 ?? 0)", title: title,
                                   body: latest.latestBody ?? "", link: link)
            AudioServicesPlaySystemSound(1007)
        }
        if let at = latest.latestAt { lastAnnouncedAt = max(lastAnnouncedAt ?? at, at) }
        unread = latest
        hasLoaded = true
        if updateAppBadge {
            try? await UNUserNotificationCenter.current().setBadgeCount(latest.total)
        }
    }

    func openBanner() {
        guard let banner else { return }
        PushDeepLinkInbox.shared.receive(PushDeepLink.route(fromLink: banner.link))
        self.banner = nil
    }
}

/// More → SMS & Messaging.
@Observable
final class SmsSetupViewModel {
    private(set) var state: LoadState<MessagingSetupStatus> = .idle
    private(set) var isWorking: Bool = false
    var actionError: String?
    var notice: String?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading, state.value == nil { state = .loading }
        do {
            state = .loaded(try await gateway.messagingSetupStatus(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func refresh(gateway: DataGateway, session: TenantSession, retry: Bool) async {
        await run {
            let result = try await gateway.refreshSmsSetup(session: session, retry: retry)
            self.state = .loaded(result.status)
            self.notice = result.message
        }
    }

    func release(gateway: DataGateway, session: TenantSession) async {
        await run {
            self.state = .loaded(try await gateway.releaseSmsNumber(session: session))
            self.notice = "SMS has been turned off. Your number will be released."
        }
    }

    func apply(_ result: SmsSetupResult) {
        state = .loaded(result.status)
        notice = result.message
    }

    private func run(_ work: () async throws -> Void) async {
        isWorking = true
        actionError = nil
        notice = nil
        defer { isWorking = false }
        do { try await work() } catch { actionError = DataError.wrap(error).errorDescription }
    }
}

/// The step-by-step setup: business type → details → number → review.
@Observable
final class SmsSetupFlowViewModel {
    enum Step: Int, CaseIterable { case route, details, number, review }

    var step: Step = .route
    var details = SmsBusinessDetailsDraft()
    var areaCode: String = ""
    private(set) var numbers: [AvailableSmsNumber] = []
    var selectedNumber: AvailableSmsNumber?
    private(set) var isSearching: Bool = false
    private(set) var isSubmitting: Bool = false
    var error: String?
    private(set) var result: SmsSetupResult?

    func search(gateway: DataGateway, session: TenantSession) async {
        let digits = areaCode.filter(\.isNumber)
        guard digits.count == 3 else { error = "Enter a 3-digit area code."; return }
        isSearching = true
        error = nil
        defer { isSearching = false }
        do {
            numbers = try await gateway.searchSmsNumbers(session: session, areaCode: digits, contains: nil)
            if numbers.isEmpty { error = "No numbers are available in \(digits) right now. Try a nearby area code." }
            if let selected = selectedNumber, !numbers.contains(selected) { selectedNumber = nil }
        } catch {
            numbers = []
            self.error = DataError.wrap(error).errorDescription
        }
    }

    func submit(gateway: DataGateway, session: TenantSession) async -> Bool {
        guard let number = selectedNumber else { error = "Choose a number first."; return false }
        if let problem = details.problem { error = problem; return false }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            let outcome = try await gateway.startSmsSetup(session: session, details: details, phoneNumber: number.phoneNumber)
            result = outcome
            if outcome.numberUnavailable {
                selectedNumber = nil
                step = .number
                error = outcome.message ?? "That number was just taken. Choose another number."
                await search(gateway: gateway, session: session)
                return false
            }
            return true
        } catch {
            self.error = DataError.wrap(error).errorDescription
            return false
        }
    }

    func choose(gateway: DataGateway, session: TenantSession) async -> SmsSetupResult? {
        guard let number = selectedNumber else { error = "Choose a number first."; return nil }
        isSubmitting = true
        error = nil
        defer { isSubmitting = false }
        do {
            let outcome = try await gateway.chooseSmsNumber(session: session, phoneNumber: number.phoneNumber)
            if outcome.numberUnavailable {
                selectedNumber = nil
                error = outcome.message
                await search(gateway: gateway, session: session)
                return nil
            }
            return outcome
        } catch {
            self.error = DataError.wrap(error).errorDescription
            return nil
        }
    }
}

/// The composer behind every "Send SMS" action.
@Observable
final class SmsComposerViewModel {
    var kind: SmsMessageKind
    var body: String = ""
    var eta: String = ""
    var schedules: Bool = false
    var scheduledFor: Date = Date().addingTimeInterval(3600)
    private(set) var templates: [SmsMessageKind: String] = [:]
    private(set) var setup: MessagingSetupStatus?
    private(set) var preview: SmsPreview?
    private(set) var isPreviewing: Bool = false
    private(set) var isSending: Bool = false
    private(set) var outcome: SmsDispatchOutcome?
    var error: String?

    init(kind: SmsMessageKind) {
        self.kind = kind
    }

    /// Local estimate while typing; the server preview is authoritative.
    var estimate: SmsSegmentCounter.Result { SmsSegmentCounter.count(SmsTemplateValidator.estimate(body)) }

    var localProblem: String? { SmsTemplateValidator.problem(kind: kind, body: body) }

    func load(gateway: DataGateway, session: TenantSession) async {
        setup = try? await gateway.messagingSetupStatus(session: session)
        if let entries = try? await gateway.smsTemplates(session: session) {
            templates = Dictionary(entries.map { ($0.kind, $0.body) }, uniquingKeysWith: { a, _ in a })
        }
        applyTemplate()
    }

    func applyTemplate() {
        body = templates[kind] ?? kind.defaultBody
        preview = nil
    }

    func draft(customerID: String, jobID: String?, quoteID: String?, invoiceID: String?, phone: String?) -> SmsComposeDraft {
        SmsComposeDraft(customerID: customerID, jobID: jobID, quoteID: quoteID, invoiceID: invoiceID, kind: kind,
                        body: body, phone: phone,
                        eta: eta.trimmingCharacters(in: .whitespaces).isEmpty ? nil : eta.trimmingCharacters(in: .whitespaces))
    }

    func refreshPreview(gateway: DataGateway, session: TenantSession, draft: SmsComposeDraft) async {
        if let problem = localProblem { error = problem; preview = nil; return }
        isPreviewing = true
        error = nil
        defer { isPreviewing = false }
        do {
            preview = try await gateway.previewSms(session: session, draft: draft)
        } catch {
            preview = nil
            self.error = DataError.wrap(error).errorDescription
        }
    }

    func send(gateway: DataGateway, session: TenantSession, draft: SmsComposeDraft) async -> Bool {
        if let problem = localProblem { error = problem; return false }
        isSending = true
        error = nil
        defer { isSending = false }
        do {
            outcome = try await gateway.dispatchSms(session: session, draft: draft, scheduledFor: schedules ? scheduledFor : nil)
            return true
        } catch {
            self.error = DataError.wrap(error).errorDescription
            return false
        }
    }
}

/// One customer SMS conversation.
@Observable
final class SmsConversationViewModel {
    private(set) var state: LoadState<SmsConversationDetail> = .idle
    var reply: String = ""
    private(set) var isSending: Bool = false
    var error: String?

    var replySegments: SmsSegmentCounter.Result { SmsSegmentCounter.count(reply) }

    func load(gateway: DataGateway, session: TenantSession, conversationID: String, showLoading: Bool = true) async {
        if showLoading, state.value == nil { state = .loading }
        do {
            state = .loaded(try await gateway.smsConversation(session: session, conversationID: conversationID))
            try? await gateway.markSmsConversationRead(session: session, conversationID: conversationID)
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func send(gateway: DataGateway, session: TenantSession) async {
        guard let detail = state.value, let customerID = detail.conversation.customerID else { return }
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        error = nil
        defer { isSending = false }
        let draft = SmsComposeDraft(customerID: customerID, jobID: detail.conversation.jobID, quoteID: nil, invoiceID: nil,
                                    kind: .customMessage, body: text, phone: detail.conversation.phone, eta: nil)
        do {
            _ = try await gateway.dispatchSms(session: session, draft: draft, scheduledFor: nil)
            reply = ""
            await load(gateway: gateway, session: session, conversationID: detail.conversation.id, showLoading: false)
        } catch {
            self.error = DataError.wrap(error).errorDescription
        }
    }
}

/// Communications hub: inbox, scheduled, sent, templates, automations, usage.
@Observable
final class CommunicationsHubViewModel {
    private(set) var conversations: LoadState<[SmsConversationRow]> = .idle
    private(set) var team: OfficeInbox?
    private(set) var scheduled: LoadState<[ScheduledMessageRow]> = .idle
    private(set) var sent: LoadState<[SentMessageRow]> = .idle
    private(set) var templates: LoadState<[SmsTemplateEntry]> = .idle
    private(set) var usage: LoadState<SmsUsageSummary> = .idle
    private(set) var setup: MessagingSetupStatus?
    var actionError: String?

    func loadInbox(gateway: DataGateway, session: TenantSession) async {
        if conversations.value == nil { conversations = .loading }
        setup = try? await gateway.messagingSetupStatus(session: session)
        do { conversations = .loaded(try await gateway.smsConversations(session: session)) }
        catch { conversations = .failed(DataError.wrap(error)) }
        if session.can(.assignmentsManage) || session.can(.usersManage) {
            team = try? await gateway.officeInbox(session: session)
        }
    }

    func loadScheduled(gateway: DataGateway, session: TenantSession) async {
        if scheduled.value == nil { scheduled = .loading }
        do { scheduled = .loaded(try await gateway.scheduledMessages(session: session)) }
        catch { scheduled = .failed(DataError.wrap(error)) }
    }

    func cancel(_ row: ScheduledMessageRow, gateway: DataGateway, session: TenantSession) async {
        actionError = nil
        do {
            try await gateway.cancelScheduledMessage(session: session, id: row.id)
            await loadScheduled(gateway: gateway, session: session)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
    }

    func loadSent(gateway: DataGateway, session: TenantSession) async {
        if sent.value == nil { sent = .loading }
        do { sent = .loaded(try await gateway.sentMessages(session: session)) }
        catch { sent = .failed(DataError.wrap(error)) }
    }

    func loadTemplates(gateway: DataGateway, session: TenantSession) async {
        if templates.value == nil { templates = .loading }
        do { templates = .loaded(try await gateway.smsTemplates(session: session)) }
        catch { templates = .failed(DataError.wrap(error)) }
    }

    func setAutomation(_ entry: SmsTemplateEntry, enabled: Bool, gateway: DataGateway, session: TenantSession) async {
        actionError = nil
        do {
            try await gateway.setSmsAutomation(session: session, kind: entry.kind, enabled: enabled)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        await loadTemplates(gateway: gateway, session: session)
    }

    func loadUsage(gateway: DataGateway, session: TenantSession) async {
        if usage.value == nil { usage = .loading }
        do { usage = .loaded(try await gateway.smsUsage(session: session)) }
        catch { usage = .failed(DataError.wrap(error)) }
    }
}

/// SMS history on a customer or job record.
@Observable
final class CommunicationHistoryViewModel {
    private(set) var messages: [SmsThreadMessage] = []
    private(set) var hasLoaded: Bool = false

    func load(gateway: DataGateway, session: TenantSession, customerID: String?, jobID: String?) async {
        guard session.can(.smsCreditsConsume) || session.can(.smsLedgerRead) else { return }
        if let jobID {
            messages = (try? await gateway.jobCommunications(session: session, jobID: jobID)) ?? []
        } else if let customerID {
            messages = (try? await gateway.customerCommunications(session: session, customerID: customerID)) ?? []
        }
        hasLoaded = true
    }
}
