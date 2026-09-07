import Foundation
import Supabase

/// The single Supabase client for the whole app.
///
/// Native Supabase Auth owns the session, so there is deliberately no
/// `accessToken` closure here — the SDK stores, refreshes and attaches the JWT
/// itself, which is what makes session restoration on launch work.
///
/// Only the public URL and anon key are read, both from the build-time
/// `Config.swift` seam. The service-role key is never referenced, and must never
/// be added: every rule that matters is enforced by RLS in the database.
nonisolated enum SupabaseClientProvider {
    /// `nil` when the build was not given Supabase coordinates. Callers treat
    /// that as "production mode unavailable" rather than crashing.
    static let shared: SupabaseClient? = {
        guard let url = BackendConfiguration.url,
              let anonKey = BackendConfiguration.anonKey else {
            return nil
        }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    // Email links come back to the app rather than to the
                    // project's Site URL. Individual calls pass this explicitly
                    // too; setting it here means any future flow that needs a
                    // redirect gets the native one by default instead of
                    // silently falling back to localhost.
                    redirectToURL: AuthCallback.url,
                    // PKCE is already the SDK default, but the confirmation
                    // flow depends on it: the link returns an authorization
                    // code that is exchanged for a session using a verifier
                    // held only by this device.
                    flowType: .pkce
                )
            )
        )
    }()

    static var isConfigured: Bool { shared != nil }
}
