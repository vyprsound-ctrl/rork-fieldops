import Foundation
import UIKit
import UserNotifications

/// PRODUCTION IMPLEMENTATION — real APNs registration.
///
/// **This adapter starts no background work.** It asks for permission, asks
/// UIKit for a device token, and hands the token back. There is no silent-push
/// handler, no background refresh task and no `UIBackgroundModes` entry in the
/// build settings, so iOS itself will only ever wake this app for a
/// user-visible alert the person tapped.
///
/// It also knows nothing about the database or about tenancy. It produces a
/// `PushDeviceToken`; `PushRegistrationCoordinator` decides whether to ask for
/// one, and the `DataGateway` stores it under the tenant's RLS rules. That is
/// the same separation `CoreLocationService` follows.
@MainActor
final class ApplePushService: NSObject, PushService {
    let mode: ServiceMode = .production

    /// UIKit hands the device token to the app delegate, which is created by
    /// the system rather than by us. This shared instance is the meeting point
    /// between that callback and the async caller waiting for a token.
    static let shared = ApplePushService()

    /// APNs registration normally answers in well under a second. Giving up
    /// after this keeps a sign-in from hanging behind a token that is not
    /// coming — on a device with no network, or a build signed without the
    /// push entitlement.
    private static let tokenTimeout: Duration = .seconds(15)

    private var cachedToken: PushDeviceToken?
    private var tokenWaiters: [CheckedContinuation<PushRegistrationOutcome, Never>] = []
    private var isAwaitingToken: Bool = false
    private var requestGeneration: Int = 0

    private override init() {
        super.init()
    }

    // MARK: - Permission

    var authorizationState: PushAuthorizationState {
        get async {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return Self.state(from: settings.authorizationStatus)
        }
    }

    private static func state(from status: UNAuthorizationStatus) -> PushAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .authorized
        @unknown default: return .denied
        }
    }

    // MARK: - Registration

    func register() async -> PushRegistrationOutcome {
        let current = await authorizationState

        switch current {
        case .denied, .restricted:
            // Asking again is a no-op at this point; iOS will not re-prompt.
            return .refused(current)
        case .notDetermined:
            let granted: Bool
            do {
                granted = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                print("[push] permission request failed: \(error.localizedDescription)")
                return .refused(.denied)
            }
            guard granted else { return .refused(.denied) }
        case .authorized, .provisional:
            break
        }

        UNUserNotificationCenter.current().delegate = PushNotificationDelegate.shared
        return await requestTokenFromAPNs()
    }

    func refreshTokenIfAuthorized() async -> PushRegistrationOutcome? {
        let current = await authorizationState
        guard current.canReceive else { return nil }
        UNUserNotificationCenter.current().delegate = PushNotificationDelegate.shared
        return await requestTokenFromAPNs()
    }

    func unregister() async {
        cachedToken = nil
        UIApplication.shared.unregisterForRemoteNotifications()
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Asks UIKit to register and waits for whichever delegate callback fires.
    private func requestTokenFromAPNs() async -> PushRegistrationOutcome {
        if let cachedToken {
            return .registered(cachedToken)
        }

        requestGeneration += 1
        let generation = requestGeneration

        if !isAwaitingToken {
            isAwaitingToken = true
            UIApplication.shared.registerForRemoteNotifications()

            Task { [weak self] in
                try? await Task.sleep(for: Self.tokenTimeout)
                guard let self, self.requestGeneration == generation else { return }
                self.finish(
                    .tokenUnavailable("Apple didn't return a device token. Check the connection and try again.")
                )
            }
        }

        return await withCheckedContinuation { continuation in
            tokenWaiters.append(continuation)
        }
    }

    private func finish(_ outcome: PushRegistrationOutcome) {
        guard isAwaitingToken else { return }
        isAwaitingToken = false
        let waiters = tokenWaiters
        tokenWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: outcome) }
    }

    // MARK: - Delegate callbacks

    /// Called by the app delegate when APNs issues a token.
    func handleRegistration(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        let token = PushDeviceToken(value: hex, environment: PushEnvironment.current)
        cachedToken = token
        finish(.registered(token))
    }

    /// Called by the app delegate when APNs refuses to issue one. This is a
    /// failure and is reported as one — never as a silent success.
    func handleRegistrationFailure(_ error: Error) {
        print("[push] APNs registration failed: \(error.localizedDescription)")
        cachedToken = nil
        finish(.tokenUnavailable("This device could not be registered for notifications."))
    }
}

extension PushDeviceRegistration {
    /// Describes this handset. Deliberately coarse — the model name and the
    /// app version are enough to work out why a device stopped receiving
    /// alerts, and nothing here identifies the person holding it.
    @MainActor
    static func forThisDevice(token: PushDeviceToken) -> PushDeviceRegistration {
        PushDeviceRegistration(
            token: token.value,
            environment: token.environment,
            bundleID: Bundle.main.bundleIdentifier ?? "",
            appVersion: (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "",
            deviceModel: UIDevice.current.model
        )
    }
}

/// Receives the UIKit callbacks that have no async equivalent.
///
/// Deliberately minimal: token in, tap out. It holds no state and makes no
/// decisions, so there is nowhere for a background behaviour to hide.
final class PushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = PushNotificationDelegate.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            ApplePushService.shared.handleRegistration(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            ApplePushService.shared.handleRegistrationFailure(error)
        }
    }
}

/// Turns a tapped notification into an in-app destination.
final class PushNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationDelegate()

    /// A job alert is worth showing even while the app is open — the engineer
    /// may be looking at a different job than the one that just got cancelled.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Let the global message indicator refresh immediately, whichever
        // screen is open. The OS banner and sound are shown here, so the
        // in-app banner is not repeated for the same message.
        await MainActor.run {
            NotificationCenter.default.post(name: .communicationsPushReceived, object: nil)
        }
        return [.banner, .sound, .badge, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let route = PushDeepLink.route(from: userInfo)
        await MainActor.run {
            PushDeepLinkInbox.shared.receive(route)
        }
    }
}
