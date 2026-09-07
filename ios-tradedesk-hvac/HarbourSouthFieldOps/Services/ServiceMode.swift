import Foundation

/// Marks whether a capability is backed by a real integration or a local
/// simulation. Nothing simulated is ever presented as production-ready.
nonisolated enum ServiceMode: String, Sendable {
    case simulated
    case production

    var isSimulated: Bool { self == .simulated }
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
        IntegrationStatus(id: "database", name: "Database", mode: .simulated, plannedProvider: "Supabase + RLS", detail: "In-memory store. Company isolation enforced in the gateway."),
        IntegrationStatus(
            id: "customerPayments",
            name: "Customer payments",
            mode: .production,
            plannedProvider: "The company's own payment provider",
            detail: "Not an integration and never will be. Payments received are recorded by hand, and a customer paying online is sent to the company's own payment link. TradeDesk never processes, routes, holds or reconciles a card payment."
        ),
        IntegrationStatus(
            id: "sms",
            name: "SMS",
            mode: .simulated,
            plannedProvider: "Twilio, server-side",
            detail: "Sending runs server-side, never from the device, and each attempt's real outcome is recorded against the invoice. With no provider credentials configured an attempt is recorded as failed — never as sent."
        ),
        IntegrationStatus(
            id: "email",
            name: "Email",
            mode: .simulated,
            plannedProvider: "Resend, server-side",
            detail: "Sending runs server-side, never from the device, and each attempt's real outcome is recorded against the invoice. With no provider credentials configured an attempt is recorded as failed — never as sent."
        ),
        IntegrationStatus(
            id: "location",
            name: "Field worker location",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "Core Location",
            detail: SupabaseClientProvider.isConfigured
                ? "Production captures real positions from Core Location at job workflow events only — start travel, arrive, complete. One reading each time, never a stream: no background updates, no significant-change monitoring and no timer. The development stack still uses fixtures."
                : "Fixed fixtures captured at job workflow events only. No live tracking and no background updates."
        ),
        IntegrationStatus(id: "routing", name: "ETA and travel time", mode: .simulated, plannedProvider: "MapKit Directions", detail: "Straight-line distance at an assumed speed. Knows nothing about roads or traffic."),
        IntegrationStatus(id: "maps", name: "Maps and navigation", mode: .simulated, plannedProvider: "MapKit", detail: "Prepares a destination hand-off to your maps app. No in-app routing or turn-by-turn."),
        IntegrationStatus(
            id: "push",
            name: "Push notifications",
            mode: SupabaseClientProvider.isConfigured ? .production : .simulated,
            plannedProvider: "APNs, server-side",
            detail: SupabaseClientProvider.isConfigured
                ? "Production registers this device with Apple once you sign in and turn alerts on, and the database raises a notification from the job event itself — an assignment written, a slot moved, a job cancelled. Delivery runs server-side; with no APNs key configured an alert stays queued and is never recorded as delivered. The development stack registers nothing and never prompts."
                : "No device token is registered and no permission is requested."
        ),
        IntegrationStatus(id: "storeBilling", name: "Subscription billing", mode: .simulated, plannedProvider: "Apple IAP and Google Play Billing", detail: "No purchase is made. Store references are placeholders.")
    ]

    static var simulatedCount: Int { all.filter { $0.mode.isSimulated }.count }
}
