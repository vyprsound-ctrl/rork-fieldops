import Foundation

/// Which APNs host a device token is deliverable on.
///
/// A token minted under the `development` entitlement is only routable through
/// Apple's sandbox host, and one minted under `production` only through the
/// production host. Sending to the wrong host produces `BadDeviceToken`, so the
/// environment travels with the token rather than being assumed by the server.
nonisolated enum PushEnvironment: String, Codable, Sendable {
    case sandbox
    case production

    /// Taken from the entitlement this build was signed with, not guessed.
    static var current: PushEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
}

/// A registered address for one physical device.
nonisolated struct PushDeviceToken: Hashable, Sendable {
    /// 64 lowercase hex characters, exactly as APNs issued it.
    let value: String
    let environment: PushEnvironment

    /// Safe to show a person or write to a log. The full token never is.
    var masked: String { "•••• \(value.suffix(6))" }
}

/// Everything the server needs to record a device, none of it tenancy.
///
/// There is deliberately no company or user field: both are resolved from the
/// authenticated session inside the database, so a client cannot register a
/// device into somebody else's company.
nonisolated struct PushDeviceRegistration: Hashable, Sendable {
    let token: String
    let environment: PushEnvironment
    let bundleID: String
    let appVersion: String
    let deviceModel: String
}

/// Whether this device will deliver notifications, and why not when it won't.
///
/// Kept separate from `UNAuthorizationStatus` so the rest of the app never
/// imports UserNotifications, mirroring how `LocationAuthorizationState` keeps
/// Core Location out of the UI layer.
nonisolated enum PushAuthorizationState: String, Sendable, Hashable {
    /// Never asked. The system prompt has not been shown.
    case notDetermined
    case authorized
    /// Granted quietly — notifications arrive in the notification centre only.
    case provisional
    /// The person said no, or turned it off later.
    case denied
    /// Blocked by device policy, so the person cannot grant it themselves.
    case restricted

    var canReceive: Bool { self == .authorized || self == .provisional }

    /// Whether the person can change this themselves in Settings.
    var isResolvableInSettings: Bool { self == .denied }

    var title: String {
        switch self {
        case .notDetermined: return "Not asked yet"
        case .authorized: return "On"
        case .provisional: return "Quiet delivery"
        case .denied: return "Off"
        case .restricted: return "Restricted"
        }
    }

    /// What to tell this person, in their own terms.
    func explanation(worker: String) -> String {
        switch self {
        case .notDetermined:
            return "Get told the moment a job is assigned to you, moved, or cancelled — so you don't drive to a job that isn't happening."
        case .authorized:
            return "You'll be told when a job is assigned to you, moved or cancelled."
        case .provisional:
            return "Alerts are arriving quietly in your notification centre. Turn on sounds to hear them while you're driving."
        case .denied:
            return "Notifications are off for this app, so a cancelled or moved job won't reach you. You can turn them back on in Settings."
        case .restricted:
            return "Notifications are blocked by a restriction on this device. A device administrator controls this."
        }
    }
}

/// The outcome of trying to get this device ready to receive job alerts.
nonisolated enum PushRegistrationOutcome: Hashable, Sendable {
    case registered(PushDeviceToken)
    /// Permission was refused, so no token exists to register.
    case refused(PushAuthorizationState)
    /// Permitted, but APNs did not issue a token — no network, or a build with
    /// no push entitlement. Never treated as success.
    case tokenUnavailable(String)

    var token: PushDeviceToken? {
        if case .registered(let token) = self { return token }
        return nil
    }
}

/// Remote notifications.
///
/// The protocol exposes permission, token and teardown — and nothing that could
/// start a background service. There is no silent-push handler and no
/// background refresh hook, which is why this app declares no notification
/// background mode.
protocol PushService: Sendable {
    var mode: ServiceMode { get }

    /// Current permission, without prompting.
    var authorizationState: PushAuthorizationState { get async }

    /// Shows the system prompt if it has never been shown, then registers with
    /// APNs and waits for the token. Safe to call repeatedly: once permission
    /// exists this returns the cached token rather than re-prompting.
    func register() async -> PushRegistrationOutcome

    /// Registers with APNs *without* prompting. Used on relaunch, when
    /// permission was granted in an earlier session and the token may have
    /// been reissued by iOS.
    func refreshTokenIfAuthorized() async -> PushRegistrationOutcome?

    /// Stops remote notifications for this device.
    func unregister() async
}

/// DEVELOPMENT IMPLEMENTATION — never prompts, never registers with APNs and
/// never produces a token.
///
/// It reports `notDetermined` and refuses, which is the honest answer for a
/// build that has no push entitlement in play: the development stack must not
/// show a permission prompt for a capability it does not use.
struct MockPushService: PushService {
    let mode: ServiceMode = .simulated

    var authorizationState: PushAuthorizationState { get async { .notDetermined } }

    func register() async -> PushRegistrationOutcome {
        .tokenUnavailable("Development build — no device is registered for push notifications.")
    }

    func refreshTokenIfAuthorized() async -> PushRegistrationOutcome? { nil }

    func unregister() async {}
}
