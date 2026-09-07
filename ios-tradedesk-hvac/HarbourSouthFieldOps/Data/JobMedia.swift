import Foundation

/// How a job photo or a signature was actually stored.
///
/// `job_photos.storage_reference` is a text column, and three different things
/// have legitimately been written into it. Parsing it into a closed set here
/// means no screen has to guess, and a reference the app does not understand is
/// shown as exactly that rather than as a broken image.
nonisolated enum JobMediaReference: Hashable, Sendable {
    /// An object in a Supabase Storage bucket: `storage://bucket/path`.
    case storage(bucket: String, path: String)
    /// The bytes themselves, as a `data:` URI. Used for signatures, which are
    /// small, and for photos on a project whose media bucket is not configured.
    case inlineData(Data, mimeType: String)
    /// A development-stack placeholder — no file was ever captured.
    case simulated
    /// Something this version of the app does not recognise.
    case unrecognised(String)

    static func parse(_ raw: String) -> JobMediaReference {
        if raw.hasPrefix("sim://") { return .simulated }

        if raw.hasPrefix("storage://") {
            let trimmed = String(raw.dropFirst("storage://".count))
            guard let slash = trimmed.firstIndex(of: "/") else { return .unrecognised(raw) }
            let bucket = String(trimmed[trimmed.startIndex..<slash])
            let path = String(trimmed[trimmed.index(after: slash)...])
            guard !bucket.isEmpty, !path.isEmpty else { return .unrecognised(raw) }
            return .storage(bucket: bucket, path: path)
        }

        if raw.hasPrefix("data:") {
            let body = raw.dropFirst("data:".count)
            guard let comma = body.firstIndex(of: ",") else { return .unrecognised(raw) }
            let header = String(body[body.startIndex..<comma])
            let payload = String(body[body.index(after: comma)...])
            guard header.hasSuffix(";base64"), let data = Data(base64Encoded: payload) else {
                return .unrecognised(raw)
            }
            return .inlineData(data, mimeType: String(header.dropLast(";base64".count)))
        }

        return .unrecognised(raw)
    }

    /// True when there is an image to show, wherever it lives.
    var hasImage: Bool {
        switch self {
        case .storage, .inlineData: return true
        case .simulated, .unrecognised: return false
        }
    }

    static func inline(_ data: Data, mimeType: String) -> String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    static func storageReference(bucket: String, path: String) -> String {
        "storage://\(bucket)/\(path)"
    }
}

/// Media captured on site, on its way to the job record.
nonisolated struct JobMediaUpload: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: JobPhotoKind
    var caption: String
    /// Already compressed by the capture screen — the data layer stores what it
    /// is given rather than re-encoding it.
    let data: Data
    let mimeType: String

    init(id: UUID = UUID(), kind: JobPhotoKind, caption: String = "", data: Data, mimeType: String = "image/jpeg") {
        self.id = id
        self.kind = kind
        self.caption = caption
        self.data = data
        self.mimeType = mimeType
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
    }
}

/// The result of storing one piece of media. Failures are reported, never
/// swallowed and never dressed up as a success.
nonisolated struct JobMediaResult: Identifiable, Hashable, Sendable {
    let id: UUID
    let kindTitle: String
    let stored: Bool
    /// Where it ended up, in plain words — "uploaded", "stored with the record".
    let detail: String
}

/// The bucket job media is uploaded to when the project has one.
nonisolated enum JobMediaBucket {
    static let name = "job-media"
}
