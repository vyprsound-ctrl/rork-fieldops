import Foundation

/// Validation for the company's own online payment destination.
///
/// The same rule is expressed three times on purpose — here, in the database's
/// `companies_online_payment_link_url_valid` check constraint, and again in the
/// public invoice page before a button is ever rendered. The app's copy is the
/// least trusted of the three; it exists so the person typing gets a sentence
/// they can act on instead of a policy refusal.
///
/// What is refused, and why:
/// - anything but `https` — a customer's payment page must not be plain http,
///   and `javascript:`, `data:` and `file:` are not addresses at all
/// - credentials in the URL (`https://user:pass@host/`) — never legitimate here
/// - a host with no dot — `localhost` and bare hostnames aren't public pages
/// - whitespace, and anything longer than 500 characters
nonisolated enum OnlinePaymentLink {
    static let maximumLength = 500

    nonisolated enum ValidationError: LocalizedError, Equatable {
        case notHTTPS
        case malformed
        case containsCredentials
        case tooLong

        var errorDescription: String? {
            switch self {
            case .notHTTPS:
                return "The link has to start with https:// so your customer's details stay encrypted."
            case .malformed:
                return "That doesn't look like a web address. Paste the payment page link from your payment provider."
            case .containsCredentials:
                return "Remove the username and password from the link — a payment page link should never contain them."
            case .tooLong:
                return "That link is too long. Paste the payment page link itself, not a redirect chain."
            }
        }
    }

    /// Trims and validates. Returns `nil` for empty input, which is how the
    /// link is cleared.
    static func normalise(_ raw: String) throws -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= maximumLength else { throw ValidationError.tooLong }
        guard !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw ValidationError.malformed
        }

        let lowered = trimmed.lowercased()
        guard lowered.hasPrefix("https://") else {
            throw ValidationError.notHTTPS
        }

        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host,
              !host.isEmpty else {
            throw ValidationError.malformed
        }

        guard components.user == nil, components.password == nil, !authority(of: trimmed).contains("@") else {
            throw ValidationError.containsCredentials
        }

        // A public payment page always has a dotted host.
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            throw ValidationError.malformed
        }

        let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_~")
        guard host.lowercased().unicodeScalars.allSatisfy({ hostCharacters.contains($0) }) else {
            throw ValidationError.malformed
        }

        return trimmed
    }

    /// True when the stored value is safe to put behind a button.
    static func isUsable(_ raw: String?) -> Bool {
        guard let raw else { return false }
        return (try? normalise(raw)) != nil
    }

    /// What the customer sees described on the invoice page ("buy.stripe.com").
    static func displayHost(_ raw: String?) -> String? {
        guard let raw, let host = URLComponents(string: raw)?.host else { return nil }
        return host
    }

    /// Everything between the scheme and the first `/`, which is where
    /// credentials would hide.
    private static func authority(of value: String) -> String {
        let withoutScheme = value.dropFirst("https://".count)
        guard let slash = withoutScheme.firstIndex(of: "/") else { return String(withoutScheme) }
        return String(withoutScheme[..<slash])
    }
}
