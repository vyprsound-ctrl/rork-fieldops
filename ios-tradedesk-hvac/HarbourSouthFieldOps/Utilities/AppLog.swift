import Foundation
import os

/// Signposts for the parts of the app whose failures are only ever seen on
/// somebody else's device.
///
/// `print` writes to stdout, which exists in a debugger and nowhere else — a
/// TestFlight failure left no trace at all, which is exactly why the photo
/// failure had to be diagnosed from HTTP status codes alone. `Logger` writes to
/// the unified log, where it can be read back from Console or a sysdiagnose
/// after the fact.
///
/// Nothing here is allowed to carry a credential. Ids and HTTP statuses are
/// marked public because they are what makes a report actionable; anything a
/// person wrote or signed is not logged at all.
nonisolated enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.harboursouth.fieldservice"

    /// Photo and signature storage: uploads, the references they produce, and
    /// the `job_photos` rows written against them.
    static let media = Logger(subsystem: subsystem, category: "media")

    /// Everything else the data gateway needs to be able to explain.
    static let data = Logger(subsystem: subsystem, category: "data")
}
