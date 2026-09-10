import Foundation
import Observation

/// The engineer's own forward schedule.
///
/// There is no reschedule, reassign or delete action on this view model, and
/// none on the gateway call behind it. Scheduling is dispatch's job; an
/// engineer reads their own and nothing else.
@Observable
final class EngineerScheduleViewModel {
    private(set) var state: LoadState<EngineerSchedule> = .idle

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.engineerSchedule(session: session, dayCount: 14))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}

/// Sites the engineer has legitimate work at — never the company directory.
@Observable
final class EngineerSitesViewModel {
    private(set) var state: LoadState<[EngineerSiteRow]> = .idle
    var searchText: String = ""

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading, state.value == nil { state = .loading }
        do {
            state = .loaded(try await gateway.engineerSites(session: session, query: searchText))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}

@Observable
final class EngineerSiteDetailViewModel {
    private(set) var state: LoadState<EngineerSiteDetail> = .idle

    func load(gateway: DataGateway, session: TenantSession, addressID: String, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.engineerSiteDetail(session: session, addressID: addressID))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}

/// The engineer's own completed work. Field history, deliberately not a report:
/// there is no total, no value and no financial column anywhere in it.
@Observable
final class EngineerWorkHistoryViewModel {
    private(set) var state: LoadState<[EngineerWorkRecord]> = .idle

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.engineerWorkHistory(session: session, limit: 100))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}

/// Profile and availability.
@Observable
final class EngineerProfileViewModel {
    private(set) var state: LoadState<EngineerProfile> = .idle
    private(set) var isUpdatingDuty: Bool = false
    var actionError: String?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.engineerProfile(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    /// Sets the engineer's own availability.
    ///
    /// Reloads rather than assuming: what the office actually sees is the duty
    /// state combined with any live job, so echoing the tapped value back
    /// could show "Available" to somebody who is mid-repair.
    func setDuty(gateway: DataGateway, session: TenantSession, to duty: DutyState) async {
        isUpdatingDuty = true
        actionError = nil
        do {
            try await gateway.updateDutyState(session: session, state: duty)
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isUpdatingDuty = false
    }
}

/// Engineer ↔ office conversations.
@Observable
final class OfficeMessagesViewModel {
    private(set) var state: LoadState<OfficeInbox> = .idle

    var unreadCount: Int { state.value?.unreadCount ?? 0 }

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading, state.value == nil { state = .loading }
        do {
            state = .loaded(try await gateway.officeInbox(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}

@Observable
final class OfficeConversationViewModel {
    private(set) var state: LoadState<OfficeConversation> = .idle
    private(set) var isSending: Bool = false
    var draftBody: String = ""
    var actionError: String?

    func load(
        gateway: DataGateway,
        session: TenantSession,
        threadID: String,
        showLoading: Bool = true
    ) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.officeConversation(session: session, threadID: threadID))
            // Marking read must never be the thing that fails the screen.
            try? await gateway.markOfficeThreadRead(session: session, threadID: threadID)
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func send(gateway: DataGateway, session: TenantSession, threadID: String) async {
        let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        isSending = true
        actionError = nil
        do {
            var draft = OfficeMessageDraft()
            draft.threadID = threadID
            draft.body = body
            _ = try await gateway.sendOfficeMessage(session: session, draft: draft)
            // Only cleared once the server has it. A message that failed to
            // send is still in the box, not silently discarded.
            draftBody = ""
            await load(gateway: gateway, session: session, threadID: threadID, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isSending = false
    }
}

/// Composing a brand new message to the office.
@Observable
final class OfficeComposerViewModel {
    private(set) var isSending: Bool = false
    var actionError: String?
    var topic: OfficeMessageTopic = .partRequired
    var body: String = ""

    var canSend: Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    /// Returns the conversation the message landed in, or `nil` if it failed.
    func send(
        gateway: DataGateway,
        session: TenantSession,
        jobID: String?,
        jobNumber: String?,
        photoIDs: [String] = []
    ) async -> String? {
        guard canSend else { return nil }

        isSending = true
        actionError = nil
        defer { isSending = false }

        var draft = OfficeMessageDraft()
        draft.jobID = jobID
        draft.photoIDs = photoIDs
        draft.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // The subject is what the office sees in their list, so it names the
        // topic and the job rather than repeating the first line of the note.
        draft.subject = jobNumber.map { "\(topic.title) · \($0)" } ?? topic.title

        do {
            return try await gateway.sendOfficeMessage(session: session, draft: draft)
        } catch {
            actionError = DataError.wrap(error).errorDescription
            return nil
        }
    }
}
