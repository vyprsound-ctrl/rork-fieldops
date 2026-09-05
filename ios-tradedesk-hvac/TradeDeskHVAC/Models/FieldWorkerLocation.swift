import Foundation

/// A single position fix for a field worker.
///
/// Stored as its own time series rather than on the user record so retention can
/// be capped independently — see `LocationRetentionPolicy`. Rows are written
/// only at job workflow events; nothing in this platform writes them on a timer.
///
/// `captureEvent` records *why* the fix exists, which is what makes the capture
/// policy auditable rather than merely stated. `isSimulated` travels with the
/// row so a fixture can never later be mistaken for a real position.
nonisolated struct FieldWorkerLocation: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    let userID: String
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double
    var heading: Double?
    var speedMetersPerSecond: Double?
    var jobID: String?
    var recordedAt: Date
    /// The workflow event that triggered the capture, when known.
    var captureEvent: LocationCaptureEvent?
    /// True for every fix produced by a simulated location adapter.
    var isSimulated: Bool

    init(
        id: String,
        companyID: String,
        userID: String,
        latitude: Double,
        longitude: Double,
        accuracyMeters: Double,
        heading: Double? = nil,
        speedMetersPerSecond: Double? = nil,
        jobID: String? = nil,
        recordedAt: Date,
        captureEvent: LocationCaptureEvent? = nil,
        isSimulated: Bool = true
    ) {
        self.id = id
        self.companyID = companyID
        self.userID = userID
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.heading = heading
        self.speedMetersPerSecond = speedMetersPerSecond
        self.jobID = jobID
        self.recordedAt = recordedAt
        self.captureEvent = captureEvent
        self.isSimulated = isSimulated
    }

    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }

    /// Recent enough to act on, per the retention policy.
    func freshness(asOf now: Date = Date()) -> LocationFreshness {
        let minutes = now.timeIntervalSince(recordedAt) / 60
        return minutes <= Double(LocationRetentionPolicy.recentThresholdMinutes) ? .recent : .lastKnown
    }
}

nonisolated extension LocationCaptureEvent: Codable {}
