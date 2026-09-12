import Foundation
import Observation

/// Turns the destination carried by a notification into an app route.
///
/// The link is an internal convention between the database (which writes
/// `deep_link` when the event is raised) and this app. It is deliberately not a
/// registered URL scheme: nothing outside the app is allowed to drive
/// navigation, so there is no external entry point to defend.
///
/// Parsing is total — an unknown or malformed link yields `nil` and the tap
/// simply opens the app, rather than crashing or landing somewhere arbitrary.
nonisolated enum PushDeepLink {
    static let scheme = "tradedesk"

    /// The APNs payload key the dispatcher writes the destination into.
    static let payloadKey = "deepLink"

    static func link(for route: AppRoute) -> String? {
        switch route {
        case .job(let id): return "\(scheme)://job/\(id)"
        case .quote(let id): return "\(scheme)://quote/\(id)"
        case .invoice(let id): return "\(scheme)://invoice/\(id)"
        case .customer(let id): return "\(scheme)://customer/\(id)"
        case .message(let id): return "\(scheme)://message/\(id)"
        case .more: return nil
        // #11 — filtered list routes are in-app drill-downs from Reports, not
        // notification destinations. Nothing writes a push that means "open the
        // overdue list", so these have no link rather than an invented one.
        case .invoiceList, .jobList: return nil
        }
    }

    /// Parses a link string. Returns `nil` for anything it does not recognise.
    static func route(fromLink link: String?) -> AppRoute? {
        guard let link, let url = URL(string: link), url.scheme == scheme else { return nil }

        // Both "tradedesk://job/<id>" (host = job) and a path-only form are
        // accepted, because URL parses the two shapes differently.
        var components = [url.host, url.path]
            .compactMap { $0 }
            .flatMap { $0.split(separator: "/") }
            .map(String.init)
            .filter { !$0.isEmpty }

        guard let kind = components.first else { return nil }
        components.removeFirst()
        let identifier = components.first

        switch kind {
        case "job":
            guard let identifier, !identifier.isEmpty else { return .more(.dispatch) }
            return .job(identifier)
        case "quote":
            guard let identifier, !identifier.isEmpty else { return .more(.quotes) }
            return .quote(identifier)
        case "invoice":
            guard let identifier, !identifier.isEmpty else { return .more(.invoices) }
            return .invoice(identifier)
        case "customer":
            guard let identifier, !identifier.isEmpty else { return nil }
            return .customer(identifier)
        case "message":
            // Written by `send_office_message()` in the database. Without an id
            // there is no one conversation to open, so the tap simply opens the
            // app rather than guessing at one.
            guard let identifier, !identifier.isEmpty else { return nil }
            return .message(identifier)
        case "jobs":
            return .more(.dispatch)
        default:
            return nil
        }
    }

    /// Parses an APNs payload, falling back to the job id when the link itself
    /// is absent — an older notification, or one written before this convention.
    static func route(from userInfo: [AnyHashable: Any]) -> AppRoute? {
        if let link = userInfo[payloadKey] as? String, let route = route(fromLink: link) {
            return route
        }
        if let jobID = userInfo["jobId"] as? String, !jobID.isEmpty {
            return .job(jobID)
        }
        return nil
    }
}

/// Holds the destination from a tapped notification until a screen is ready to
/// show it.
///
/// A tap can arrive while the app is launching, while the session is still
/// being restored, or while the user is signed out entirely. Parking the route
/// here means none of those cases lose it, and none of them navigate a
/// signed-out user into a tenant screen.
@MainActor
@Observable
final class PushDeepLinkInbox {
    static let shared = PushDeepLinkInbox()

    private(set) var pending: AppRoute?

    private init() {}

    func receive(_ route: AppRoute?) {
        guard let route else { return }
        pending = route
    }

    /// Takes the route, if any, and clears it so a tap is never handled twice.
    func consume() -> AppRoute? {
        defer { pending = nil }
        return pending
    }

    func clear() {
        pending = nil
    }
}
