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

    /// Images chosen but not yet sent. Held here rather than in the view so a
    /// keyboard dismissal or a redraw cannot quietly discard them.
    var pendingUploads: [JobMediaUpload] = []

    /// What the send button is doing, so a slow upload on site reads as
    /// progress rather than as a frozen screen.
    private(set) var sendProgress: String?

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

    /// True when there is something to send — words, pictures, or both.
    ///
    /// A photograph of a failed part IS the message. Forcing somebody to type
    /// "see photo" before the send button lights up is ceremony, and the
    /// database no longer demands it either.
    var canSend: Bool {
        !isSending
            && (!draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !pendingUploads.isEmpty)
    }

    /// Sends the message, uploading any attached photographs first.
    ///
    /// ORDER MATTERS. Each image becomes a `job_photos` row before the message
    /// is posted, and the message then carries the resulting ids.
    ///
    /// ONE UPLOAD, TWO SURFACES. On a job-linked conversation that row carries
    /// both the job and the thread, so the picture is the message attachment
    /// AND that job's permanent visual evidence — it appears in the job's
    /// Photos section without anybody uploading it twice. On a general
    /// conversation the row is anchored to the thread alone and belongs to no
    /// job. Which of the two happens is decided by the thread, never by this
    /// screen, so a photo cannot be filed against the wrong job.
    ///
    /// PARTIAL FAILURE IS NOT TOTAL FAILURE. If one image fails on a weak site
    /// connection the message still goes, carrying the ones that succeeded, and
    /// the person is told exactly which did not and that it is still in the
    /// tray to retry. Losing a typed message because the fourth photo timed out
    /// would be the worse outcome by far.
    ///
    /// A FAILED PHOTO IS NEVER SHOWN AS SENT. Only ids the gateway confirmed
    /// are attached; the rest stay in the tray.
    func send(
        gateway: DataGateway,
        session: TenantSession,
        threadID: String,
        jobID: String?
    ) async {
        let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let uploads = pendingUploads
        guard !body.isEmpty || !uploads.isEmpty else { return }

        isSending = true
        actionError = nil
        defer {
            isSending = false
            sendProgress = nil
        }

        var photoIDs: [String] = []
        var failedUploadIDs: Set<UUID> = []
        // The first real reason a photo was refused. Kept so the person is told
        // what actually happened instead of being sent to check a connection
        // that was never the problem.
        var firstFailureReason: String?

        for (index, upload) in uploads.enumerated() {
            sendProgress = uploads.count == 1
                ? "Sending photo…"
                : "Sending photo \(index + 1) of \(uploads.count)…"
            do {
                // The job comes from the thread, not from a parameter this
                // screen invented — and on a general thread there is no job at
                // all, which is exactly the case that used to be impossible.
                let result = try await gateway.attachMessageMedia(
                    session: session,
                    threadID: threadID,
                    jobID: jobID,
                    upload: upload
                )
                if result.stored {
                    photoIDs.append(upload.id.uuidString)
                } else {
                    failedUploadIDs.insert(upload.id)
                    if firstFailureReason == nil, !result.detail.isEmpty {
                        firstFailureReason = result.detail
                    }
                }
            } catch {
                failedUploadIDs.insert(upload.id)
                if firstFailureReason == nil {
                    firstFailureReason = DataError.wrap(error).errorDescription
                }
            }
        }

        // Every photo failed and there are no words behind them. Sending an
        // empty message would be a lie about what happened.
        if body.isEmpty, photoIDs.isEmpty, !uploads.isEmpty {
            // Say what the server said. "Check your connection" was shown for
            // every failure including ones the server refused outright, which
            // invited an endless retry over a request that could never work.
            let reason = firstFailureReason ?? "The photo couldn't be sent."
            actionError = uploads.count == 1
                ? reason
                : "\(reason) None of the \(uploads.count) photos were sent."
            return
        }

        sendProgress = "Sending…"
        do {
            var draft = OfficeMessageDraft()
            draft.threadID = threadID
            draft.body = body
            draft.photoIDs = photoIDs
            _ = try await gateway.sendOfficeMessage(session: session, draft: draft)

            // Only cleared once the server has it. A message that failed to
            // send is still in the box, not silently discarded. Photos that
            // failed stay in the tray so they can be retried; the ones that
            // went are removed so retrying cannot send them twice.
            draftBody = ""
            pendingUploads = uploads.filter { failedUploadIDs.contains($0.id) }
            if !failedUploadIDs.isEmpty {
                let reason = firstFailureReason.map { " \($0)" } ?? ""
                actionError = failedUploadIDs.count == 1
                    ? "Your message was sent, but one photo couldn't be attached.\(reason) It's still here — tap send to try it again."
                    : "Your message was sent, but \(failedUploadIDs.count) photos couldn't be attached.\(reason) They're still here — tap send to try them again."
            }
            await load(gateway: gateway, session: session, threadID: threadID, showLoading: false)
        } catch {
            // Any image that did upload is dropped from the tray, so retrying
            // the message cannot attach the same picture twice.
            pendingUploads = pendingUploads.filter { !photoIDs.contains($0.id.uuidString) }
            actionError = DataError.wrap(error).errorDescription
        }
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
