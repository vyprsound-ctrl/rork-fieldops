import Foundation

/// What a job photograph is evidence OF.
///
/// Field service photographs are not a gallery — they are the record of what a
/// property looked like before somebody attended, what was found, and what was
/// left behind. That record settles disputes, supports warranty claims and
/// tells a property manager what they are paying for, so the category is worth
/// capturing even though it is never mandatory.
///
/// STORAGE COMPATIBILITY
/// `before`, `after`, `part`, `proof` and `signature` have always existed in the
/// `job_photo_kind` database enum. The remaining cases are added by migration
/// `0010`. Because a build can reach a database where that migration has not
/// been applied yet, every case carries a `storageFallback` — a value the enum
/// has always contained — and the upload path retries with it if the database
/// rejects the newer label. A photograph is never lost to a schema lag.
nonisolated enum JobPhotoKind: String, Codable, Sendable, CaseIterable {
    case before
    case during
    case after
    case equipment
    case damage
    case propertyCondition = "property_condition"
    case part
    case proof
    case signature
    case other

    var title: String {
        switch self {
        case .before: return "Before"
        case .during: return "During"
        case .after: return "After"
        case .equipment: return "Equipment"
        case .damage: return "Damage"
        case .propertyCondition: return "Property"
        case .part: return "Part"
        case .proof: return "Proof"
        case .signature: return "Signature"
        case .other: return "Other"
        }
    }

    /// The categories offered when attaching evidence to a job.
    ///
    /// `proof` and `signature` are deliberately absent: those are written by the
    /// completion flow, which knows what it is recording. Making a worker choose
    /// them by hand would invite mislabelled evidence.
    static let selectable: [JobPhotoKind] = [
        .before, .during, .after, .equipment, .damage, .propertyCondition, .other
    ]

    /// A label the `job_photo_kind` enum has contained since the first release.
    ///
    /// Used only if the database refuses the newer value, so an unmigrated
    /// deployment still stores the image with the closest honest category
    /// rather than failing the upload.
    var storageFallback: JobPhotoKind {
        switch self {
        case .before, .after, .part, .proof, .signature: return self
        // Work in progress is closest to "before" — it is not the finished state.
        case .during: return .before
        // Equipment, damage and property condition are all findings recorded on
        // arrival rather than completed work.
        case .equipment, .damage, .propertyCondition, .other: return .before
        }
    }

    /// Decodes unknown values rather than failing the whole record.
    ///
    /// The database can legitimately hold a label this build does not know —
    /// after a migration, or on an older app version. Losing an entire job's
    /// photo list to one unrecognised category would be far worse than showing
    /// that photo as "Other".
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JobPhotoKind(rawValue: raw) ?? .other
    }
}

/// One stored image.
///
/// ANCHORING
/// An image is anchored to a job, to a conversation, or to both — and the pair
/// is what makes a single upload serve two purposes:
///
///   job only      evidence added from the job screen or the completion flow
///   thread only   an image sent in a general conversation, about no job
///   both          an image sent in a job conversation: it is the message
///                 attachment AND that job's permanent visual evidence, stored
///                 once rather than uploaded twice
///
/// `jobID` is therefore optional. Migration 0011 relaxes the matching NOT NULL
/// in the database; a build older than that migration simply never writes a row
/// without one.
nonisolated struct JobPhoto: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let jobID: String?
    let userID: String
    var storageReference: String
    var caption: String?
    var kind: JobPhotoKind
    var capturedAt: Date
    /// The conversation this image was sent in, when it was sent as a message
    /// attachment. Never set for evidence added directly to a job.
    var threadID: String?

    init(
        id: String,
        companyID: String,
        jobID: String?,
        userID: String,
        storageReference: String,
        caption: String? = nil,
        kind: JobPhotoKind,
        capturedAt: Date,
        threadID: String? = nil
    ) {
        self.id = id
        self.companyID = companyID
        self.jobID = jobID
        self.userID = userID
        self.storageReference = storageReference
        self.caption = caption
        self.kind = kind
        self.capturedAt = capturedAt
        self.threadID = threadID
    }
}
