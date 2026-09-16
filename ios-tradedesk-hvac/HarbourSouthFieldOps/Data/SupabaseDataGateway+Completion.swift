import Foundation
import os
import Supabase

/// An image filed against a job.
///
/// `thread_id` is deliberately absent rather than sent as null. A message
/// attachment on a job conversation is stamped with its thread by
/// `send_office_message` server-side, so this payload never has to name a
/// column that exists only after migration 0011 — which keeps every existing
/// job photo write working unchanged on a database that has not had it applied.
private nonisolated struct JobMediaPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let job_id: String
    let user_id: String
    let storage_reference: String
    let caption: String?
    let kind: String
    let captured_at: String
}

/// An image sent in a general conversation — one about no job at all.
///
/// `job_id` is omitted entirely so the column takes its null default, and
/// `thread_id` is written here rather than left to the send function because
/// the `job_photos_anchored` constraint requires an image to be anchored to
/// something at the moment it is inserted.
///
/// This shape only works after migration 0011. Before it, the insert is
/// refused by the surviving NOT NULL on `job_id`, and the caller reports that
/// honestly instead of pretending the photo was stored.
private nonisolated struct ThreadMediaPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let thread_id: String
    let user_id: String
    let storage_reference: String
    let caption: String?
    let kind: String
    let captured_at: String
}

/// Where one image is being filed, and the object key that follows from it.
///
/// THE KEY IS CASE-SENSITIVE AND THE DATABASE IS NOT SHOUTING. Every
/// `job-media` policy authorises a write by comparing the first path segment
/// against `public.current_company_id()::text`, and PostgreSQL renders a `uuid`
/// as lower-case text. Swift's `UUID.uuidString` is upper-case. An object key
/// built from the raw session id therefore reads `DE21FA6E-…` where the policy
/// expects `de21fa6e-…`, the `WITH CHECK` cannot match, and *every* upload is
/// refused — on a correctly configured bucket, by a user with the right
/// permission, in every flow that shares this path. Normalising here is the
/// single place that has to be right.
nonisolated struct JobMediaDestination: Sendable {
    let jobID: String?
    let threadID: String?
    let path: String

    init?(companyID: String, jobID: String?, threadID: String?, upload: JobMediaUpload) {
        let company = Self.segment(companyID)
        guard !company.isEmpty else { return nil }
        guard jobID != nil || threadID != nil else { return nil }
        self.jobID = jobID
        self.threadID = threadID

        let folder = jobID.map { Self.segment($0) }
            ?? "threads/\(Self.segment(threadID ?? ""))"
        let file = upload.id.uuidString.lowercased()
        self.path = "\(company)/\(folder)/\(file).\(Self.fileExtension(for: upload.mimeType))"
    }

    /// Lower-cased to match `uuid::text`, and trimmed so a stray space can
    /// never become part of a tenant segment.
    private static func segment(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/png": return "png"
        case "image/heic": return "heic"
        default: return "jpg"
        }
    }
}

private nonisolated struct EquipmentHistoryPayload: Encodable, Sendable {
    let id: String
    let company_id: String
    let equipment_id: String
    let job_id: String
    let summary: String
    let occurred_at: String
    let created_at: String
}

/// Job completion, photos and signatures against Supabase.
///
/// The order is deliberate and is the whole point of this file: the record is
/// written **first**, and the status moves **last**. A job that reaches
/// `completed` therefore always has the completion behind it. If the notes,
/// the signature or the history cannot be written, the transition never
/// happens and the engineer is told why — rather than seeing a green tick over
/// an empty job.
///
/// Photos are the one exception, and on purpose. A failed upload on a bad
/// signal must not trap an engineer on a finished job, so uploads are reported
/// individually in the outcome and can be retried from the job afterwards.
extension SupabaseDataGateway {

    // MARK: - Completion

    func completeJob(
        session: TenantSession,
        jobID: String,
        draft: JobCompletionDraft,
        locationFix: LocationFix?
    ) async throws -> JobCompletionOutcome {
        if let problem = draft.validationMessage { throw DataError.rejected(problem) }

        // The job has to be one this caller can actually see and act on. RLS
        // answers `notFound` for anything else, so nothing leaks.
        let job = try await requireJob(jobID, session, query: "jobs.complete")
        guard job.status == .inProgress else {
            record("jobs.complete", session, allowed: false, "Refused — the job is \(job.status.title(session.terms))")
            throw DataError.invalidTransition(from: job.status, to: .completed)
        }

        // 1. What was done, for the customer.
        try await addJobNote(
            session: session,
            jobID: jobID,
            body: draft.workPerformed.tidied,
            visibility: .customerVisible
        )

        // 2. Parts, labour, follow-up and anything the customer shouldn't read.
        var internalStored = false
        if let internalRecord = draft.internalRecord {
            try await addJobNote(session: session, jobID: jobID, body: internalRecord, visibility: .internalOnly)
            internalStored = true
        }

        // 3. The signature, stored with the job record as a completion artefact.
        var signatureStored = false
        if let image = draft.signatureImage, draft.hasSignature {
            let upload = JobMediaUpload(
                kind: .proof,
                caption: "Signed on site by \(draft.signatureName.tidied)",
                data: image,
                mimeType: "image/png"
            )
            // A signature is part of the completion record, not an optional
            // extra, so a failure here stops the completion.
            let result = try await storeMedia(
                session: session,
                jobID: jobID,
                threadID: nil,
                upload: upload,
                allowInline: true
            )
            guard result.stored else {
                throw DataError.unexpected("The signature couldn't be saved, so the job hasn't been completed.")
            }
            signatureStored = true
        }

        // 4. The asset's own service history, so the next engineer at this site
        //    can see what was done to this unit and when.
        var historyStored = false
        if let equipmentID = job.equipmentID, session.can(.equipmentRead) {
            historyStored = await recordEquipmentHistory(
                session: session,
                equipmentID: equipmentID,
                jobID: jobID,
                summary: draft.workPerformed.tidied
            )
        }

        // 5. Photos. Reported individually; never allowed to block the finish.
        var media: [JobMediaResult] = []
        for upload in draft.photos {
            // Ordinary evidence is never inlined, so a refused upload is
            // reported as one failure carrying the server's own reason rather
            // than silently becoming a base64 blob inside the row.
            let result: JobMediaResult
            do {
                result = try await storeMedia(
                    session: session,
                    jobID: jobID,
                    threadID: nil,
                    upload: upload,
                    allowInline: false
                )
            } catch {
                result = JobMediaResult(
                    id: upload.id,
                    kindTitle: upload.kind.title,
                    stored: false,
                    detail: DataError.wrap(error).errorDescription ?? "Couldn't be attached — try again from the job."
                )
            }
            media.append(result)
        }

        // 6. Only now does the job move. The database applies the workflow rule
        //    itself and writes the history row inside the same transaction.
        try await updateJobStatus(session: session, jobID: jobID, to: .completed, locationFix: locationFix)

        record(
            "jobs.complete",
            session,
            allowed: true,
            "Completion recorded before the transition — \(media.filter(\.stored).count)/\(media.count) photo(s) stored"
                + (signatureStored ? ", signature captured" : "")
        )

        return JobCompletionOutcome(
            completed: true,
            workNoteStored: true,
            internalNoteStored: internalStored,
            signatureStored: signatureStored,
            equipmentHistoryStored: historyStored,
            media: media
        )
    }

    /// Writes the asset's service history entry.
    ///
    /// Deliberately non-throwing: a company that has not granted this role
    /// `equipmentManage` still completes jobs, it simply does not add to the
    /// asset register. The caller is told through `equipmentHistoryStored`.
    private func recordEquipmentHistory(
        session: TenantSession,
        equipmentID: String,
        jobID: String,
        summary: String
    ) async -> Bool {
        let now = Date()
        do {
            try await performWrite(
                client.from("equipment_history").insert(
                    EquipmentHistoryPayload(
                        id: UUID().uuidString,
                        company_id: session.companyID,
                        equipment_id: equipmentID,
                        job_id: jobID,
                        summary: String(summary.prefix(400)),
                        occurred_at: SupabaseCoding.timestamp(now),
                        created_at: SupabaseCoding.timestamp(now)
                    )
                )
            )
            return true
        } catch {
            AppLog.data.error(
                "completion recorded, but the asset history row was refused: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    // MARK: - Media

    func attachJobMedia(session: TenantSession, jobID: String, upload: JobMediaUpload) async throws -> JobMediaResult {
        try require(.jobPhotosCreate, session, query: "jobs.attachMedia")
        // An ordinary photograph is never inlined. A failed upload has to be
        // reported as a failed upload — turning a 320 KB image into a `data:`
        // blob inside the row hid the real fault and produced a second, larger
        // failure on top of it.
        return try await storeMedia(session: session, jobID: jobID, threadID: nil, upload: upload, allowInline: false)
    }

    /// Stores an image sent in a conversation.
    ///
    /// ONE IMAGE, ONE ROW, TWO PURPOSES. When the conversation is about a job,
    /// `jobID` is that job and the resulting row is ordinary job evidence — it
    /// appears in the job's Photos section like any other photograph, and the
    /// message simply references it. Nobody uploads the same picture twice and
    /// there is no second copy to drift.
    ///
    /// When the conversation is general, the image is anchored to the thread
    /// instead and belongs to no job.
    func attachMessageMedia(
        session: TenantSession,
        threadID: String,
        jobID: String?,
        upload: JobMediaUpload
    ) async throws -> JobMediaResult {
        try require(.jobPhotosCreate, session, query: "messages.attachMedia")
        // Inline storage is refused here. A `data:` blob inside a row is a
        // reasonable last resort for a signature, but a general message image
        // has to be a real object under the company's storage prefix for the
        // bucket policy to be the thing protecting it.
        return try await storeMedia(
            session: session,
            jobID: jobID,
            threadID: threadID,
            upload: upload,
            allowInline: false
        )
    }

    /// Stores one image and writes its `job_photos` row.
    ///
    /// Uploading to the project's media bucket is the intended path. When the
    /// bucket is not configured the bytes are stored with the record itself, so
    /// an engineer's photo is never silently discarded — and the row says which
    /// of the two happened.
    ///
    /// THE OBJECT KEY CARRIES THE TENANT. Every path starts with the company
    /// id, because that first segment is what the `job-media` storage policies
    /// pivot on. A general message image uses `<company>/threads/<thread>/…`,
    /// which the existing policies already authorise — no bucket or policy
    /// change was needed to support it.
    private func storeMedia(
        session: TenantSession,
        jobID: String?,
        threadID: String?,
        upload: JobMediaUpload,
        allowInline: Bool
    ) async throws -> JobMediaResult {
        try require(.jobPhotosCreate, session, query: "jobs.attachMedia")
        guard !upload.data.isEmpty else {
            return JobMediaResult(id: upload.id, kindTitle: upload.kind.title, stored: false, detail: "Empty image.")
        }
        guard jobID != nil || threadID != nil else {
            return JobMediaResult(id: upload.id, kindTitle: upload.kind.title, stored: false, detail: "Nowhere to file this photo.")
        }

        guard let destination = JobMediaDestination(
            companyID: session.companyID,
            jobID: jobID,
            threadID: threadID,
            upload: upload
        ) else {
            return JobMediaResult(id: upload.id, kindTitle: upload.kind.title, stored: false, detail: "Nowhere to file this photo.")
        }

        let storageReference: String
        let detail: String

        AppLog.media.info(
            "upload starting \(destination.path, privacy: .public) bytes=\(upload.data.count, privacy: .public) type=\(upload.mimeType, privacy: .public)"
        )
        do {
            _ = try await client.storage
                .from(JobMediaBucket.name)
                .upload(destination.path, data: upload.data, options: FileOptions(contentType: upload.mimeType, upsert: true))
            storageReference = JobMediaReference.storageReference(bucket: JobMediaBucket.name, path: destination.path)
            detail = "Uploaded (\(upload.sizeLabel))"
            AppLog.media.info("upload succeeded \(destination.path, privacy: .public)")
        } catch {
            let mapped = Self.mediaError(error)
            AppLog.media.error(
                "upload failed \(destination.path, privacy: .public) \(Self.describeStorage(error), privacy: .public)"
            )
            // A signature is small, is part of the completion record, and has a
            // deliberate inline representation. Nothing else does: an ordinary
            // photo reports the upload failure and stops here, so one failed
            // photo is one failed request rather than a cascade.
            guard allowInline else { throw mapped }
            storageReference = JobMediaReference.inline(upload.data, mimeType: upload.mimeType)
            detail = "Stored with the job record (\(upload.sizeLabel))"
            AppLog.media.notice("stored inline with the record instead \(destination.path, privacy: .public)")
        }

        func insert(kind: JobPhotoKind) async throws {
            if let jobID {
                // Job evidence, including a photo sent in a job conversation.
                // The thread is stamped on server-side by `send_office_message`
                // so this write never names a column that predates 0011.
                try await performWriteReportingCode(
                    client.from("job_photos").insert(
                        JobMediaPayload(
                            id: upload.id.uuidString,
                            company_id: session.companyID,
                            job_id: jobID,
                            user_id: session.userID,
                            storage_reference: storageReference,
                            caption: upload.caption.nilIfBlank,
                            kind: kind.rawValue,
                            captured_at: SupabaseCoding.timestamp(Date())
                        )
                    )
                )
            } else {
                // `threadID` is guaranteed by the destination guard above: a
                // photo with neither a job nor a thread never reaches here. An
                // empty string was previously sent into a `uuid` column, which
                // is a malformed value rather than an absent one.
                guard let threadID else {
                    throw WriteFailure(
                        sqlState: nil,
                        dataError: .unexpected("This photo has no conversation to belong to.")
                    )
                }
                try await performWriteReportingCode(
                    client.from("job_photos").insert(
                        ThreadMediaPayload(
                            id: upload.id.uuidString,
                            company_id: session.companyID,
                            thread_id: threadID,
                            user_id: session.userID,
                            storage_reference: storageReference,
                            caption: upload.caption.nilIfBlank,
                            kind: kind.rawValue,
                            captured_at: SupabaseCoding.timestamp(Date())
                        )
                    )
                )
            }
        }

        /// What to tell somebody when the row is refused.
        ///
        /// A thread-scoped image needs migration 0011 — a nullable `job_id` and
        /// a `thread_id` column. On a database without it the insert cannot
        /// succeed by any retry, so the message says what is actually wrong
        /// instead of blaming the photo. The image is never reported as sent.
        func refusal(_ error: Error) -> JobMediaResult {
            let isThreadScoped = jobID == nil
            let failure = error as? WriteFailure
            let sqlState = failure?.sqlState ?? "-"
            let described = failure?.dataError.errorDescription
                ?? (error as? DataError)?.errorDescription
                ?? error.localizedDescription

            let scope = isThreadScoped ? "thread" : "job"
            AppLog.media.error(
                "job_photos write failed sqlstate=\(sqlState, privacy: .public) scope=\(scope, privacy: .public) job=\(jobID ?? "-", privacy: .public) thread=\(threadID ?? "-", privacy: .public) reason=\(described, privacy: .public)"
            )

            // Only a genuinely missing 0011 explains a thread-scoped row being
            // impossible. Anything else is reported as what it was, rather than
            // blamed on a migration that may well be applied.
            let missingThreadSupport = isThreadScoped && (sqlState == "42703" || sqlState == "23502")
            return JobMediaResult(
                id: upload.id,
                kindTitle: upload.kind.title,
                stored: false,
                detail: missingThreadSupport
                    ? "Photos in general conversations aren't switched on for this company yet."
                    : described
            )
        }

        do {
            try await insert(kind: upload.kind)
        } catch {
            // The newer categories (During, Damage, Property, Equipment) are
            // added to `job_photo_kind` by migration 0010, folded into 0011. A
            // build can reach a database where that has not been applied yet,
            // and the image is already uploaded by this point — discarding a
            // photograph of a fault because of a schema lag would be the worst
            // possible outcome. Retry once with a label the enum has always
            // contained.
            //
            // STRICTLY ONE CONDITION. `22P02` is PostgreSQL's "invalid text
            // representation", which is exactly what an unknown enum label
            // produces and nothing else here does. Retrying on any other
            // failure re-sent a row the database had already refused on its
            // merits — one refused photo became two identical 500s, and the
            // second one told nobody anything the first had not.
            let fallback = upload.kind.storageFallback
            let sqlState = (error as? WriteFailure)?.sqlState
            guard sqlState == "22P02", fallback != upload.kind else { return refusal(error) }

            do {
                try await insert(kind: fallback)
                AppLog.media.notice(
                    "job_photo_kind '\(upload.kind.rawValue, privacy: .public)' refused as 22P02; stored as '\(fallback.rawValue, privacy: .public)'. Apply migration 0011."
                )
            } catch {
                return refusal(error)
            }
        }

        let writtenScope = jobID == nil ? "thread" : "job"
        AppLog.media.info(
            "job_photos write succeeded id=\(upload.id.uuidString.lowercased(), privacy: .public) scope=\(writtenScope, privacy: .public)"
        )

        record("jobs.attachMedia", session, allowed: true, "\(upload.kind.title) image attached — \(detail.lowercased())")
        return JobMediaResult(id: upload.id, kindTitle: upload.kind.title, stored: true, detail: detail)
    }

    /// A time-limited URL for an uploaded image. Inline and simulated
    /// references have no URL, and say so by returning `nil`.
    func jobMediaURL(session: TenantSession, reference: String) async throws -> URL? {
        guard session.can(.jobPhotosRead) else { throw DataError.notPermitted(.jobPhotosRead) }
        guard case .storage(let bucket, let path) = JobMediaReference.parse(reference) else { return nil }
        do {
            return try await client.storage.from(bucket).createSignedURL(path: path, expiresIn: 3600)
        } catch {
            AppLog.media.error(
                "could not sign a media URL for \(path, privacy: .public): \(Self.describeStorage(error), privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - Helpers

    /// The full technical shape of a storage failure, for the log only.
    ///
    /// The previous code kept `localizedDescription` and threw the rest away,
    /// which is why a 400 could not be told apart from a 403 or a dropped
    /// connection. `StorageError` carries the HTTP status and the server's own
    /// message; both are recorded verbatim.
    nonisolated static func describeStorage(_ error: Error) -> String {
        if let storage = error as? StorageError {
            let status = storage.statusCode ?? "-"
            let name = storage.error ?? "-"
            return "StorageError status=\(status) error=\(name) message=\(storage.message)"
        }
        if let urlError = error as? URLError {
            return "URLError code=\(urlError.code.rawValue) \(urlError.localizedDescription)"
        }
        return "\(type(of: error)): \(error.localizedDescription)"
    }

    /// What a person is told when an upload fails.
    ///
    /// Every branch is driven by the HTTP status the server actually returned
    /// rather than by substring-matching a localised sentence. "Check your
    /// connection" is now reserved for failures that really are the connection:
    /// telling somebody to find better signal when the server refused the
    /// request outright sends them into a retry loop that can never succeed.
    nonisolated static func mediaError(_ error: Error) -> DataError {
        if let storage = error as? StorageError {
            let status = storage.statusCode.flatMap(Int.init)
            let message = storage.message.lowercased()

            if message.contains("bucket") && message.contains("not found") {
                return .rejected("Photo storage isn't set up for this company yet.")
            }
            switch status {
            case 401, 403:
                return .rejected("The server wouldn't accept this photo for your account. It hasn't been saved — this needs looking at rather than retrying.")
            case 400, 422:
                return .rejected("The server rejected this photo. It hasn't been saved — this needs looking at rather than retrying.")
            case 413:
                return .rejected("That photo is too large to upload.")
            case 415:
                return .rejected("That image format can't be uploaded.")
            case 409:
                return .rejected("That photo has already been uploaded.")
            case .some(let code) where code >= 500:
                return .unexpected("Photo storage is having trouble right now. Try again in a moment.")
            default:
                return .unexpected("The photo couldn't be uploaded. \(storage.message)")
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
                 .cannotFindHost, .timedOut, .dataNotAllowed:
                return .offline
            default:
                return .unexpected("The connection failed before the photo finished uploading.")
            }
        }

        if let dataError = error as? DataError { return dataError }
        return .unexpected("The photo couldn't be uploaded.")
    }
}
