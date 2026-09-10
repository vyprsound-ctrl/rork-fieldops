import Foundation

/// How a capability is currently backed.
///
/// There are three states rather than two, because "simulated" and "not
/// configured" are different promises to the user and conflating them was
/// actively misleading. SMS is the clearest case: no part of this app fakes an
/// SMS any more. The send runs server-side against Twilio, and with no
/// credentials configured the attempt is recorded as **failed** — so calling it
/// "simulated" implied a pretend success that does not exist, while calling it
/// "live" would imply messages are being delivered. It is neither: it is real
/// code awaiting a credential.
nonisolated enum ServiceMode: String, Sendable {
    /// A local stand-in produces the result. Nothing leaves the device.
    case simulated
    /// The real integration, connected and working.
    case production
    /// The real integration is implemented and wired, but a credential or
    /// external account is missing, so the capability cannot succeed yet.
    /// Attempts fail honestly rather than pretending to work.
    case needsConfiguration

    /// True only for a local stand-in. Deliberately false for
    /// `needsConfiguration`: that path fabricates nothing.
    var isSimulated: Bool { self == .simulated }

    /// True when the capability cannot currently succeed, for either reason.
    /// This — not `isSimulated` — is what "don't promise the user this works"
    /// should be keyed off.
    var isNotLive: Bool { self != .production }

    var label: String {
        switch self {
        case .simulated: return "Simulated"
        case .production: return "Live"
        case .needsConfiguration: return "Needs configuration"
        }
    }
}

/// One integration surface and its current backing.
nonisolated struct IntegrationStatus: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let mode: ServiceMode
    /// What the production implementation will be once connected.
    let plannedProvider: String
    let detail: String
}

/// Every integration this app will eventually depend on, with its honest
/// current state. Surfaced in Settings so simulated behaviour is never
/// mistaken for a live integration.
nonisolated enum IntegrationRegistry {
    static let all: [IntegrationStatus] = [
        IntegrationStatus(
            id: "auth",
            name: "Authentication",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "Supabase Auth",
            detail: SupabaseClientProvider.isConfigured
                ? "Production sign-in verifies credentials against Supabase Auth and resolves company and role from the database. The development account picker is still present and still verifies nothing."
                : "Local role switching only. No credentials are verified."
        ),
        IntegrationStatus(
            id: "database",
            name: "Database",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "Supabase + RLS",
            detail: SupabaseClientProvider.isConfigured
                ? "Production reads and writes the live Postgres database. Company isolation is enforced by row-level security in the database itself, not by this app — the client never sends a company id. The development account picker still runs on the in-memory store."
                : "In-memory store. Company isolation enforced in the gateway."
        ),
        IntegrationStatus(
            id: "customerPayments",
            name: "Customer payments",
            mode: .production,
            plannedProvider: "The company's own payment provider",
            detail: "Not an integration and never will be. Payments received are recorded by hand, and a customer paying online is sent to the company's own payment link. Harbour South never processes, routes, holds or reconciles a card payment."
        ),
        IntegrationStatus(
            id: "sms",
            name: "SMS",
            mode: .needsConfiguration,
            plannedProvider: "Twilio, server-side",
            detail: "Not simulated and not live: the send is real server-side code, but Twilio credentials have not been configured. Sending never runs from the device, and each attempt's real outcome is recorded against the invoice — with no credentials an attempt is recorded as failed, never as sent, and any SMS credit it reserved is returned."
        ),
        IntegrationStatus(
            id: "email",
            name: "Email",
            mode: .needsConfiguration,
            plannedProvider: "Resend, server-side",
            detail: "Not simulated and not live: the send is real server-side code, but email provider credentials have not been configured. Sending never runs from the device, and each attempt's real outcome is recorded against the invoice — with no credentials an attempt is recorded as failed, never as sent."
        ),
        IntegrationStatus(
            id: "location",
            name: "Field worker location",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "Core Location",
            detail: SupabaseClientProvider.isConfigured
                ? "Production captures real positions from Core Location. One reading at each job workflow event — start travel, arrive, complete — plus continuous updates for the drive itself, between Start Travel and Arrived and at no other time. \(TravelTrackingPolicy.summary). The development stack still uses fixtures and never tracks."
                : "Fixed fixtures captured at job workflow events only. No live tracking and no background updates."
        ),
        IntegrationStatus(
            id: "routing",
            name: "ETA and travel time",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "Apple Maps",
            detail: SupabaseClientProvider.isConfigured
                ? "Production asks Apple Maps for a driving ETA that follows roads and current traffic. It needs no account and no API key. When a route cannot be fetched the estimate falls back to straight-line distance and is labelled as an estimate rather than presented as a routed arrival time."
                : "Straight-line distance at an assumed speed. Knows nothing about roads or traffic."
        ),
        IntegrationStatus(
            id: "maps",
            name: "Maps and navigation",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "Apple Maps",
            detail: SupabaseClientProvider.isConfigured
                ? "Production draws a real Apple Maps route inside the app and hands the destination to Apple Maps for turn-by-turn. Harbour South does not give guidance itself, and does not use any third-party mapping service."
                : "Prepares a destination hand-off to your maps app. No in-app routing or turn-by-turn."
        ),
        IntegrationStatus(
            id: "push",
            name: "Push notifications",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "APNs, server-side",
            detail: SupabaseClientProvider.isConfigured
                ? "Production registers this device with Apple once you sign in and turn alerts on, and the database raises a notification from the job event itself — an assignment written, a slot moved, a job cancelled. Delivery runs server-side; with no APNs key configured an alert stays queued and is never recorded as delivered. The development stack registers nothing and never prompts."
                : "No device token is registered and no permission is requested."
        ),
        IntegrationStatus(
            id: "storeBilling",
            name: "Subscription billing",
            mode: .needsConfiguration,
            plannedProvider: "Apple In-App Purchase",
            detail: "Needs App Store Connect configuration. Seat counting and pricing are live and read from the database; the purchase itself is not, and no purchase is ever recorded as made. This is an iOS product — there is no Google Play billing path."
        ),
        IntegrationStatus(
            id: "recurring",
            name: "Recurring service",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "Scheduled in the database",
            detail: SupabaseClientProvider.isConfigured
                ? "Due service agreements generate their next visit from a schedule inside the database itself, so visits appear whether or not anybody opens this app. A visit already generated for a period is never generated twice. The development stack generates nothing."
                : "No schedule. Recurring agreements are listed but generate nothing."
        )
    ]

    /// How many capabilities are backed by a local stand-in.
    static var simulatedCount: Int { all.filter { $0.mode.isSimulated }.count }

    /// How many capabilities cannot currently succeed — simulated or awaiting a
    /// credential. Used wherever the user is being told what does not yet work.
    static var notLiveCount: Int { all.filter { $0.mode.isNotLive }.count }

    /// The capabilities that are real but awaiting an external credential.
    static var needingConfiguration: [IntegrationStatus] {
        all.filter { $0.mode == .needsConfiguration }
    }
}
