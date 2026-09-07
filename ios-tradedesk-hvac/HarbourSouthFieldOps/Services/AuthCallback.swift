import Foundation

/// The native return address for Supabase email links.
///
/// Confirmation and recovery emails previously pointed at the project's Site
/// URL (`http://localhost:3000`), which resolves to nothing on a phone — Safari
/// simply reported that it could not connect. Supabase is now told to redirect
/// to this custom scheme instead, so the link reopens the app and the session is
/// exchanged natively.
///
/// The scheme reuses the bundle identifier because a URL scheme is first-come,
/// first-served across the whole device: a reverse-DNS name we own is the only
/// kind unlikely to collide with another app. Registering it does not change the
/// bundle identifier itself.
nonisolated enum AuthCallback {
    static let scheme = "com.harboursouth.fieldservice"
    static let host = "auth-callback"

    /// The exact string that must also be present in Supabase's redirect
    /// allowlist. Anything not on that list is silently ignored by Supabase,
    /// which falls back to the Site URL.
    static let urlString = "\(scheme)://\(host)"

    static let url: URL = {
        guard let url = URL(string: urlString) else {
            preconditionFailure("Auth callback URL is malformed: \(urlString)")
        }
        return url
    }()

    /// Whether an incoming URL is ours to handle.
    ///
    /// Matching on the scheme alone is deliberate: Supabase appends its
    /// parameters in different shapes depending on the link type, and a URL that
    /// carries our scheme is never intended for anything else.
    static func matches(_ url: URL) -> Bool {
        url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame
    }

    /// A failure Supabase reported inside the callback itself.
    ///
    /// An expired or already-used link still redirects here successfully — the
    /// failure arrives as parameters rather than as a network error, so it has
    /// to be read out of the URL before attempting any exchange.
    static func reportedFailure(in url: URL) -> AuthError? {
        let parameters = parameters(in: url)

        guard parameters["error"] != nil || parameters["error_code"] != nil else {
            return nil
        }

        let code = parameters["error_code"]?.lowercased() ?? ""
        let description = parameters["error_description"]?.lowercased() ?? ""

        if code.contains("expired") || description.contains("expired") || description.contains("invalid") {
            return .confirmationLinkExpired
        }
        return .confirmationLinkUnusable
    }

    /// Supabase labels recovery links so the app can tell a password reset from
    /// an email confirmation.
    static func isPasswordRecovery(_ url: URL) -> Bool {
        parameters(in: url)["type"]?.lowercased() == "recovery"
    }

    /// Reads parameters from both the query and the fragment.
    ///
    /// PKCE puts them in the query, the implicit flow puts them in the fragment,
    /// and error redirects can use either. Reading both means the same code
    /// copes with whichever shape arrives.
    private static func parameters(in url: URL) -> [String: String] {
        var found: [String: String] = [:]

        func absorb(_ query: String?) {
            guard let query, !query.isEmpty else { return }
            for pair in URLComponents(string: "?\(query)")?.queryItems ?? [] {
                if let value = pair.value, !value.isEmpty {
                    found[pair.name] = value
                }
            }
        }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        absorb(components?.query)
        absorb(components?.fragment)
        return found
    }
}
