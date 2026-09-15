import Foundation
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
            let result = (try? await storeMedia(
                session: session,
                jobID: jobID,
                threadID: nil,
                upload: upload,
                allowInline: true
            ))
                ?? JobMediaResult(
                    id: upload.id,
                    kindTitle: upload.kind.title,
                    stored: false,
                    detail: "Couldn't be attached — try again from the job."
                )
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
            print("[data] completion recorded, but the asset history row was refused: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Media

    func attachJobMedia(session: TenantSession, jobID: String, upload: JobMediaUpload) async throws -> JobMediaResult {
        try require(.jobPhotosCreate, session, query: "jobs.attachMedia")
        return try await storeMedia(session: session, jobID: jobID, threadID: nil, upload: upload, allowInline: true)
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
            allowInline: jobID != nil
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

        var reference: String?
        var detail = ""

        let folder = jobID ?? "threads/\(threadID ?? "")"
        let path = "\(session.companyID)/\(folder)/\(upload.id.uuidString.lowercased()).\(Self.fileExtension(for: upload.mimeType))"
        do {
            _ = try await client.storage
                .from(JobMediaBucket.name)
                .upload(path, data: upload.data, options: FileOptions(contentType: upload.mimeType, upsert: true))
            reference = JobMediaReference.storageReference(bucket: JobMediaBucket.name, path: path)
            detail = "Uploaded (\(upload.sizeLabel))"
        } catch {
            guard allowInline else { throw Self.mediaError(error) }
            print("[data] media bucket unavailable, storing the image with the record: \(error.localizedDescription)")
            reference = JobMediaReference.inline(upload.data, mimeType: upload.mimeType)
            detail = "Stored with the job record (\(upload.sizeLabel))"
        }

        guard let storageReference = reference else {
            return JobMediaResult(id: upload.id, kindTitle: upload.kind.title, stored: false, detail: "Couldn't be stored.")
        }

        func insert(kind: JobPhotoKind) async throws {
            if let jobID {
                // Job evidence, including a photo sent in a job conversation.
                // The thread is stamped on server-side by `send_office_message`
                // so this write never names a column that predates 0011.
                try await performWrite(
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
                try await performWrite(
                    client.from("job_photos").insert(
                        ThreadMediaPayload(
                            id: upload.id.uuidString,
                            company_id: session.companyID,
                            thread_id: threadID ?? "",
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
            if isThreadScoped {
                print("[data] a general-conversation image was refused by job_photos. Apply migration 0011 (nullable job_id + thread_id): \(error.localizedDescription)")
            }
            return JobMediaResult(
                id: upload.id,
                kindTitle: upload.kind.title,
                stored: false,
                detail: isThreadScoped
                    ? "Photos in general conversations aren't switched on for this company yet."
                    : ((error as? DataError)?.errorDescription ?? "The job record refused the photo.")
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
            let fallback = upload.kind.storageFallback
            guard fallback != upload.kind else { return refusal(error) }

            do {
                try await insert(kind: fallback)
                print("[data] job_photo_kind '\(upload.kind.rawValue)' was refused; stored as '\(fallback.rawValue)'. Apply migration 0011.")
            } catch {
                return refusal(error)
            }
        }

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
            print("[data] could not sign a media URL: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private nonisolated static func fileExtension(for mimeType: String) -> String {
        switch mimeType {
        case "image/png": return "png"
        case "image/heic": return "heic"
        default: return "jpg"
        }
    }

    private nonisolated static func mediaError(_ error: Error) -> DataError {
        let text = error.localizedDescription.lowercased()
        if text.contains("bucket") && text.contains("not found") {
            return .rejected("Photo storage isn't set up for this company yet.")
        }
        if text.contains("network") || text.contains("offline") { return .offline }
        return .unexpected("The photo couldn't be uploaded. Try again when you have a better signal.")
    }
}
