import Foundation

nonisolated enum DataError: LocalizedError, Equatable {
    /// Returned instead of a "forbidden" so out-of-scope records never leak
    /// their existence to the caller.
    case notFound
    case notPermitted(Permission)
    /// The write was understood but breaks the workflow rules.
    case invalidTransition(from: JobStatus, to: JobStatus)
    /// The write breaks a business rule (e.g. editing a sent quote).
    case rejected(String)
    case offline
    case unexpected(String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "That record isn't available."
        case .notPermitted(let permission):
            return "Your role doesn't include: \(permission.title)."
        case .invalidTransition(let from, let to):
            return "A job can't go from \(from.title) to \(to.title)."
        case .rejected(let reason):
            return reason
        case .offline:
            return "No connection. Check your signal and try again."
        case .unexpected(let detail):
            return detail
        }
    }

    var recoveryHint: String {
        switch self {
        case .notFound: return "It may have been reassigned or removed."
        case .notPermitted: return "Ask an owner or admin if you need access."
        case .invalidTransition: return "Follow the job through its normal steps."
        case .rejected: return "Adjust the record and try again."
        case .offline: return "Your work is kept until you're back online."
        case .unexpected: return "Try again in a moment."
        }
    }
}
