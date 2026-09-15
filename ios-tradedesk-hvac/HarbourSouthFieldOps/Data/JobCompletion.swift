import Foundation

/// One part or material used on a job.
nonisolated struct JobPartLine: Identifiable, Hashable, Sendable {
    let id: UUID
    var quantity: Int
    var name: String

    init(id: UUID = UUID(), quantity: Int = 1, name: String = "") {
        self.id = id
        self.quantity = quantity
        self.name = name
    }

    var isUsable: Bool { !name.tidied.isEmpty && quantity > 0 }

    var line: String { "\(quantity) × \(name.tidied)" }
}

/// Everything an engineer records when they finish on site.
///
/// Nothing here is mandatory except the work performed, because a business that
/// forces five fields on a wet engineer standing in a plant room gets five
/// fields of rubbish. What is required is stated once, in `validationMessage`.
nonisolated struct JobCompletionDraft: Hashable, Sendable {
    /// Customer-facing: what was actually done. Ends up on the job as a
    /// customer-visible note, and on the asset's service history.
    var workPerformed: String = ""
    /// Office-only: anything the customer should not read.
    var internalNotes: String = ""
    var parts: [JobPartLine] = []
    /// Time on site, in hours. Zero means "not recorded".
    var labourHours: Double = 0
    var followUpRequired: Bool = false
    var followUpNotes: String = ""

    /// Who signed. Empty when the customer was not on site.
    var signatureName: String = ""
    /// A PNG of the signature stroke, rendered on device.
    var signatureImage: Data?

    var photos: [JobMediaUpload] = []

    var usableParts: [JobPartLine] { parts.filter(\.isUsable) }

    var hasSignature: Bool { signatureImage != nil && !signatureName.tidied.isEmpty }

    var validationMessage: String? {
        if workPerformed.tidied.count < 3 { return "Say what you did on site before completing." }
        if signatureImage != nil, signatureName.tidied.isEmpty {
            return "Add the name of the person who signed."
        }
        if followUpRequired, followUpNotes.tidied.isEmpty {
            return "Say what the follow-up is for."
        }
        return nil
    }

    /// The internal record, assembled once so the office reads the same thing
    /// the engineer typed.
    var internalRecord: String? {
        var blocks: [String] = []
        if !internalNotes.tidied.isEmpty { blocks.append(internalNotes.tidied) }

        let parts = usableParts
        if !parts.isEmpty {
            blocks.append("Parts and materials used:\n" + parts.map { "• \($0.line)" }.joined(separator: "\n"))
        }
        if labourHours > 0 {
            blocks.append("Labour on site: \(Self.hoursLabel(labourHours))")
        }
        if followUpRequired {
            blocks.append("FOLLOW-UP REQUIRED: \(followUpNotes.tidied)")
        }
        return blocks.isEmpty ? nil : blocks.joined(separator: "\n\n")
    }

    static func hoursLabel(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return Formatters.relativeDuration(minutes: minutes)
    }
}

/// What actually happened when a completion was submitted.
///
/// Every step is reported separately, so "the job is completed but two photos
/// didn't upload" can be said out loud instead of hidden behind a tick.
nonisolated struct JobCompletionOutcome: Hashable, Sendable {
    let completed: Bool
    let workNoteStored: Bool
    let internalNoteStored: Bool
    let signatureStored: Bool
    let equipmentHistoryStored: Bool
    let media: [JobMediaResult]

    var failedMediaCount: Int { media.filter { !$0.stored }.count }

    /// A single honest sentence for the engineer.
    var summary: String {
        guard completed else { return "The job was not completed." }
        if failedMediaCount > 0 {
            return failedMediaCount == 1
                ? "Job completed. One photo couldn't be attached — try adding it again from the job."
                : "Job completed. \(failedMediaCount) photos couldn't be attached — try adding them again from the job."
        }
        return "Job completed and everything was saved."
    }
}

// MARK: - Gateway surface

extension DataGateway {
    /// Records the completion and moves the job to completed, in that order, so
    /// a job is never marked done with none of its record behind it.
    func completeJob(
        session: TenantSession,
        jobID: String,
        draft: JobCompletionDraft,
        locationFix: LocationFix?
    ) async throws -> JobCompletionOutcome {
        throw DataError.rejected(Self.completionUnavailable)
    }

    /// Attaches a photo captured on the device to a job.
    func attachJobMedia(session: TenantSession, jobID: String, upload: JobMediaUpload) async throws -> JobMediaResult {
        throw DataError.rejected(Self.completionUnavailable)
    }

    /// Attaches a photo captured on the device to a conversation.
    func attachMessageMedia(
        session: TenantSession,
        threadID: String,
        jobID: String?,
        upload: JobMediaUpload
    ) async throws -> JobMediaResult {
        throw DataError.rejected(Self.completionUnavailable)
    }

    /// A URL the app may load an uploaded photo from, or `nil` when the media is
    /// held inline or was never captured.
    func jobMediaURL(session: TenantSession, reference: String) async throws -> URL? { nil }

    fileprivate static var completionUnavailable: String {
        "Job completion is recorded against the live database. Sign in with your company account to use it."
    }
}
