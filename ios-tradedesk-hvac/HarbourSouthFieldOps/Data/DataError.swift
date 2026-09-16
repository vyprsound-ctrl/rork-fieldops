import Foundation

/// A refused write, carrying both the sentence a person should read and the
/// database's own SQLSTATE.
///
/// The two are needed for different jobs. The sentence is what the UI shows;
/// the code is the only honest basis for deciding whether a *different* request
/// could succeed. Retrying on anything softer than the code is what turned a
/// single refused photo row into a repeated one.
nonisolated struct WriteFailure: Error {
    /// e.g. `22P02` for an invalid enum label. `nil` when the failure never
    /// reached PostgreSQL.
    let sqlState: String?
    let dataError: DataError
}

extension WriteFailure: LocalizedError {
    var errorDescription: String? { dataError.errorDescription }
}

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

    /// True when the failure is one no amount of retrying can clear.
    var isDeterministic: Bool {
        switch self {
        case .offline: return false
        case .notFound, .notPermitted, .invalidTransition, .rejected, .unexpected: return true
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
