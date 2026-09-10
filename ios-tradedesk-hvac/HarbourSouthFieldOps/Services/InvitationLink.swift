import Foundation

/// The link an invited person taps in their invitation email.
///
/// WHY THERE IS A WEB HOP IN THE MIDDLE
/// The email points at the project's own web page (`/join?t=…`), not straight
/// at this URL scheme. A custom scheme in an email body is unreliable — many
/// mail clients refuse to render it, and it does nothing at all on a laptop.
/// The web page always opens, shows the code, and offers a button that hands
/// the code to the app on the phone. That button is what produces this URL.
///
/// NOTHING HERE IS TRUSTED. The token is matched by the database against a
/// live, unexpired, unrevoked invitation row, and the company and role come off
/// that row. A hand-edited link can only fail to match one. The name is a
/// convenience prefill the joiner can correct before they submit.
nonisolated enum InvitationLink {
    /// Shares the scheme the auth callback uses — one registered scheme, two
    /// hosts — so no second entry is needed in the app's URL types.
    static let scheme = AuthCallback.scheme
    static let host = "join"

    nonisolated struct Payload: Sendable, Equatable {
        let token: String
        let name: String
    }

    /// Whether this URL is an invitation hand-off rather than an auth callback.
    static func matches(_ url: URL) -> Bool {
        guard url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame else { return false }
        return normalisedHost(of: url) == host
    }

    /// The invitation carried by the URL, or `nil` when there isn't a usable one.
    ///
    /// A link without a token is not an invitation, however well formed the
    /// rest of it is, so it is rejected here rather than sent to the database
    /// to fail.
    static func payload(from url: URL) -> Payload? {
        guard matches(url) else { return nil }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var values: [String: String] = [:]
        for item in items {
            guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                continue
            }
            values[item.name.lowercased()] = value
        }

        guard let token = values["token"], !token.isEmpty else { return nil }
        return Payload(token: token, name: values["name"] ?? "")
    }

    /// Copes with both `scheme://join?…` (host = join) and `scheme:join?…`
    /// (no host, path = join), which different mail and browser stacks produce
    /// from the same anchor.
    private static func normalisedHost(of url: URL) -> String {
        if let host = url.host, !host.isEmpty { return host.lowercased() }
        return url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }
}
