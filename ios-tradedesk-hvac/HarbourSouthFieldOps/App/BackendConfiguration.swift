import Foundation

/// Where the Supabase project's public coordinates come from.
///
/// The values live in `Config.swift`, which Rork generates at build time from the
/// project's public environment variables — the literals are empty in source
/// control and populated during the iOS build. Nothing here embeds a secret: the
/// anon key is a public, RLS-gated credential, and every rule that matters is
/// enforced by the policies in the database.
///
/// This type deliberately stops at configuration. No client, no session handling,
/// no queries — the app still runs on `MockDataGateway` until the production
/// adapter is written, and this is the seam that adapter will read from.
nonisolated enum BackendConfiguration {
    /// The project's REST/auth base URL, e.g. `https://<ref>.supabase.co`.
    static var url: URL? {
        let raw = Config.EXPO_PUBLIC_SUPABASE_URL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    /// The public anon key. Safe to ship; every table is protected by RLS.
    static var anonKey: String? {
        let raw = Config.EXPO_PUBLIC_SUPABASE_ANON_KEY.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : raw
    }

    /// True when the build was given both values.
    static var isConfigured: Bool { url != nil && anonKey != nil }

    /// The project's own backend host, which serves the customer invoice page.
    ///
    /// Deliberately not the Supabase functions host: that gateway rewrites every
    /// response to `text/plain` with a sandbox CSP, so an invoice served from
    /// there would reach the customer as raw markup.
    static var invoicePageBase: String? {
        let raw = Config.EXPO_PUBLIC_RORK_FUNCTIONS_URL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    /// The customer-facing invoice page, addressed by share token.
    ///
    /// The token is the whole address: no company, customer or invoice
    /// identifier is ever part of this URL.
    static func invoiceViewURL(token: String) -> String? {
        guard let base = invoicePageBase else { return nil }
        return "\(base)/i?t=\(token)"
    }

    /// Non-sensitive summary for the diagnostics screen. Never prints the key.
    static var summary: String {
        guard let url else { return "Not configured — no Supabase URL injected at build time" }
        guard let anonKey else { return "Incomplete — URL present, anon key missing" }
        return "\(url.host ?? url.absoluteString) · anon key present (\(anonKey.count) characters)"
    }
}
