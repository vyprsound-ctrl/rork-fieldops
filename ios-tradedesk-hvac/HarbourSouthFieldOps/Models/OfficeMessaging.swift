import Foundation

/// A conversation between one field worker and the office, as the DEVELOPMENT
/// store holds it.
///
/// These mirror the `office_threads` / `office_messages` tables rather than
/// inventing a second messaging model: the same columns, the same company
/// scoping, the same "one field worker per thread" rule the database enforces.
/// The production path never touches these types — `SupabaseDataGateway` reads
/// the real tables and decodes its own private row structs — but having them
/// means the development stack can exercise the messaging screens instead of
/// showing an "unavailable" placeholder.
///
/// WHY THAT MATTERS: the "Open" button on a job-linked message was broken in
/// shipped builds and no automated test could catch it, because the only stack
/// the tests could drive had no conversations in it at all.
///
/// The `Dev` prefix is deliberate. It keeps these clear of the Supabase row
/// types of a similar name, and it makes it obvious in any screen or test that
/// touches them that this is seeded data, not a second production model.
nonisolated struct DevOfficeThread: Identifiable, Hashable, Sendable {
    let id: String
    let companyID: String
    /// The field worker this thread belongs to. Office roles can read every
    /// thread in their company; a worker only ever reads their own.
    let engineerUserID: String
    var subject: String
    /// The job under discussion, when there is one. A general enquiry has none.
    let jobID: String?
    let customerID: String?
    var lastMessageAt: Date
    var lastReadByEngineerAt: Date?
    var lastReadByOfficeAt: Date?
}

/// One message in a thread, mirroring `office_messages`.
nonisolated struct DevOfficeMessage: Identifiable, Hashable, Sendable {
    let id: String
    let companyID: String
    let threadID: String
    let senderUserID: String
    var body: String
    /// `job_photos.id` values. Photographs are stored as job evidence first and
    /// referenced here, which is why an attached image also appears on the job
    /// rather than living only inside a conversation.
    var jobPhotoIDs: [String]
    let createdAt: Date
}
