import Foundation
import Observation

/// Which authentication stack the sign-in screen is driving.
///
/// Development is the seeded account picker over `MockDataGateway`; Production is
/// native Supabase Auth over the real database. They are deliberately separate
/// paths — a production identity is never handed to the mock data layer, because
/// that would present another company's simulated records as if they were the
/// signed-in user's own.
nonisolated enum AuthMode: String, CaseIterable, Sendable, Identifiable {
    case development
    case production

    var id: String { rawValue }

    var title: String {
        switch self {
        case .development: return "Development"
        case .production: return "Production"
        }
    }
}

/// Where the production authentication flow currently is.
nonisolated enum AuthPhase: Equatable, Sendable {
    case signedOut
    case restoring
    case working
    case signedIn
    case failed(String)

    var isBusy: Bool { self == .restoring || self == .working }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// Composition root. Swapping a mock for a production adapter happens here and
/// nowhere else — no screen constructs a service directly.
@Observable
final class AppEnvironment {
    /// Development data — the seeded in-memory store behind the account picker.
    private let developmentGateway: DataGateway
    /// Production data — Supabase over the authenticated session. `nil` when this
    /// build has no Supabase configuration.
    private let productionGateway: DataGateway?

    let auth: AuthService
    let sms: SmsService
    let email: EmailService
    let storeBilling: StoreBillingService
    let routes: RouteService
    let maps: MapService

    /// Positioning — fixtures for the development stack, Core Location for the
    /// production one. Paired with the gateway below so a real position is only
    /// ever taken when there is a real database to record it against.
    private let developmentLocation: LocationService
    private let productionLocation: LocationService?

    /// Notifications — the development stack never prompts and never registers,
    /// the production stack talks to APNs. Paired with the gateway for the same
    /// reason as positioning: a device token is only worth taking when there is
    /// a real database, and a real signed-in user, to record it against.
    private let developmentPush: PushService
    private let productionPush: PushService?

    /// Production authentication. `nil` when this build has no Supabase
    /// configuration, which is what makes production sign-in unavailable rather
    /// than crashing.
    let productionAuth: AuthService?

    // Development session — drives the mock-backed shells.
    private(set) var session: TenantSession?
    private(set) var isSigningIn: Bool = false
    private(set) var signInError: String?

    // Production session — resolved from the database, never from client input.
    private(set) var productionSession: TenantSession?
    private(set) var authPhase: AuthPhase = .signedOut
    private(set) var passwordResetNotice: String?
    /// Set when sign-up succeeded but the address still needs confirming. The
    /// company is founded automatically on the first sign-in after that.
    private(set) var signUpNotice: String?

    // MARK: Push notification state

    /// Current notification permission. Refreshed on demand — never by asking.
    private(set) var pushAuthorization: PushAuthorizationState = .notDetermined
    /// True once this device holds a live registration for the signed-in user.
    private(set) var isPushRegistered: Bool = false
    /// Plain-language account of the last registration attempt, including its
    /// failures. Shown to the user rather than swallowed.
    private(set) var pushStatusDetail: String?
    private(set) var isRegisteringForPush: Bool = false
    /// The token this device registered, kept so sign-out can remove exactly
    /// that registration and nothing else.
    private var registeredPushToken: String?

    /// The gateway that matches whichever session is signed in.
    ///
    /// A production identity is never served by the mock: the two adapters are
    /// constructed as a pair from the same Supabase client, so a production
    /// session always has a production gateway to read from. Without Supabase
    /// configuration there is no production session to serve in the first place.
    var gateway: DataGateway {
        guard productionSession != nil else { return developmentGateway }
        return productionGateway ?? developmentGateway
    }

    init() {
        let store = MockDataStore.seeded()
        // DEVELOPMENT WIRING. Production adapters replace these one for one.
        self.developmentGateway = MockDataGateway(store: store)
        self.auth = MockAuthService(store: store)
        self.sms = MockSmsService()
        self.email = MockEmailService()
        self.developmentPush = MockPushService()
        self.storeBilling = MockStoreBillingService()
        self.developmentLocation = MockLocationService()
        self.routes = MockRouteService()
        self.maps = MockMapService()

        // Authentication and data are wired together on purpose: a production
        // session can only exist when there is a production gateway to serve it.
        if let client = SupabaseClientProvider.shared {
            self.productionAuth = SupabaseAuthService(client: client)
            self.productionGateway = SupabaseDataGateway(client: client)
            // Constructing this does not prompt for anything. The permission
            // request happens the first time a workflow event needs a position.
            self.productionLocation = CoreLocationService()
            // Likewise: constructing this registers nothing and prompts for
            // nothing. Nothing happens until an authenticated user asks for it.
            self.productionPush = ApplePushService.shared
        } else {
            self.productionAuth = nil
            self.productionGateway = nil
            self.productionLocation = nil
            self.productionPush = nil
        }
    }

    /// The notification adapter matching whichever session is signed in.
    ///
    /// Mirrors `gateway` and `location` exactly. A development session gets the
    /// mock, which never shows a permission prompt for a capability that stack
    /// does not use; a production session gets APNs.
    var push: PushService {
        guard productionSession != nil else { return developmentPush }
        return productionPush ?? developmentPush
    }

    /// The positioning adapter matching whichever session is signed in.
    ///
    /// Mirrors `gateway` exactly: a development session gets fixtures and never
    /// triggers a permission prompt, a production session reads the device. The
    /// two are chosen by the same condition, so a real fix can never be written
    /// into the seeded in-memory store, and a fixture can never be written into
    /// the real database.
    var location: LocationService {
        guard productionSession != nil else { return developmentLocation }
        return productionLocation ?? developmentLocation
    }

    /// True while any user-facing capability is still simulated.
    var hasSimulatedServices: Bool { IntegrationRegistry.simulatedCount > 0 }

    /// Vocabulary for the signed-in company's trade. Neutral before sign-in.
    var terms: Terminology { activeSession?.terms ?? .generic }

    /// Whichever session is currently driving the UI.
    var activeSession: TenantSession? { productionSession ?? session }

    var isProductionAvailable: Bool { productionAuth != nil }

    /// True when the signed-in identity is a real one, authenticated against the
    /// live database.
    ///
    /// Keyed off exactly the same condition as `gateway`, `push` and `location`,
    /// so a screen can never disagree with the data layer about which stack it
    /// is running on.
    var isProductionSession: Bool { productionSession != nil }

    /// True when the seeded account picker is driving the app. Used to keep
    /// development-only tooling and simulated-service messaging out of a real
    /// user's app entirely, rather than merely restyling it.
    var isDevelopmentSession: Bool { productionSession == nil && session != nil }

    // MARK: - Development sign-in (unchanged behaviour)

    func signIn(accountID: String) async {
        isSigningIn = true
        signInError = nil
        do {
            session = try await auth.signIn(accountID: accountID)
        } catch {
            signInError = error.localizedDescription
        }
        isSigningIn = false
    }

    func signOut() {
        session = nil
        signInError = nil
    }

    // MARK: - Production authentication

    /// Restores a persisted Supabase session on launch.
    ///
    /// A missing or rejected token simply means "signed out" — the app returns
    /// to the sign-in screen rather than showing an error the user cannot act on.
    func restoreProductionSession() async {
        guard let productionAuth else { return }
        authPhase = .restoring
        do {
            if let restored = try await productionAuth.restoreSession() {
                productionSession = restored
                authPhase = .signedIn
            } else {
                productionSession = nil
                authPhase = .signedOut
            }
        } catch {
            productionSession = nil
            authPhase = .failed(Self.message(for: error))
        }
    }

    func signInToProduction(email: String, password: String) async {
        guard let productionAuth else {
            authPhase = .failed(AuthError.notConfigured.localizedDescription)
            return
        }
        authPhase = .working
        passwordResetNotice = nil
        signUpNotice = nil
        do {
            productionSession = try await productionAuth.signIn(email: email, password: password)
            authPhase = .signedIn
        } catch {
            productionSession = nil
            authPhase = .failed(Self.message(for: error))
        }
    }

    func signUpToProduction(_ registration: CompanyRegistration) async {
        guard let productionAuth else {
            authPhase = .failed(AuthError.notConfigured.localizedDescription)
            return
        }
        authPhase = .working
        passwordResetNotice = nil
        signUpNotice = nil
        do {
            switch try await productionAuth.signUp(registration) {
            case .signedIn(let session):
                productionSession = session
                authPhase = .signedIn

            case .confirmationSent(let address):
                // Not an error. The account exists and the company details are
                // held against it; signing in after confirming finishes setup.
                productionSession = nil
                authPhase = .signedOut
                signUpNotice = "Check your email. We've sent a confirmation link to \(address). "
                    + "Confirm it, then sign in here — your company is created automatically "
                    + "on your first sign-in."
            }
        } catch {
            productionSession = nil
            authPhase = .failed(Self.message(for: error))
        }
    }

    /// Joins a company that already exists, using an invitation code.
    ///
    /// The counterpart to `signUpToProduction`: one founds a company, the other
    /// joins one. Neither chooses a company id or a role — both come from the
    /// database.
    func joinCompany(_ redemption: InvitationRedemption) async {
        guard let productionAuth else {
            authPhase = .failed(AuthError.notConfigured.localizedDescription)
            return
        }
        authPhase = .working
        passwordResetNotice = nil
        signUpNotice = nil
        do {
            switch try await productionAuth.joinCompany(redemption) {
            case .joined(let session):
                productionSession = session
                authPhase = .signedIn

            case .confirmationSent(let address):
                productionSession = nil
                authPhase = .signedOut
                signUpNotice = "Check your email. We've sent a confirmation link to \(address). "
                    + "Confirm it, then sign in here — you'll join the company automatically."
            }
        } catch {
            productionSession = nil
            authPhase = .failed(Self.message(for: error))
        }
    }

    func signOutOfProduction() async {
        guard let productionAuth else { return }

        // The device registration goes first, while the session that owns it is
        // still valid. Removing it afterwards would be a write with no
        // authenticated caller, and the row would survive — meaning the next
        // person to hold this handset would receive the previous user's job
        // alerts. That is the whole reason this happens before the sign-out.
        await tearDownPushRegistration()

        // Clear locally first so the UI can never keep showing tenant context
        // while a network call is still in flight.
        productionSession = nil
        authPhase = .signedOut
        passwordResetNotice = nil
        signUpNotice = nil
        try? await productionAuth.signOut()
    }

    func requestPasswordReset(email: String) async {
        guard let productionAuth else {
            authPhase = .failed(AuthError.notConfigured.localizedDescription)
            return
        }
        passwordResetNotice = nil
        signUpNotice = nil
        do {
            try await productionAuth.requestPasswordReset(email: email)
            passwordResetNotice = "If that address has an account, a reset link is on its way."
        } catch {
            authPhase = .failed(Self.message(for: error))
        }
    }

    /// Completes a Supabase email link that reopened the app.
    ///
    /// Only production authentication is involved. The development picker has
    /// its own session and is deliberately left untouched — a real identity is
    /// never handed to the mock stack.
    func handleAuthCallback(_ url: URL) async {
        guard AuthCallback.matches(url) else { return }

        guard let productionAuth else {
            authPhase = .failed(AuthError.notConfigured.localizedDescription)
            return
        }

        // A signed-in user tapping an old link from their inbox must not lose
        // the session they already have, so nothing is cleared up front.
        let existingSession = productionSession

        authPhase = .working
        passwordResetNotice = nil
        signUpNotice = nil

        do {
            productionSession = try await productionAuth.completeAuthCallback(url: url)
            authPhase = .signedIn
        } catch {
            if let existingSession {
                // Restore exactly what was there before. An unusable link is
                // not a reason to sign anyone out.
                productionSession = existingSession
                authPhase = .signedIn
                print("[auth] ignoring an email link that could not be completed while signed in")
            } else {
                productionSession = nil
                authPhase = .failed(Self.message(for: error))
            }
        }
    }

    func clearAuthError() {
        if case .failed = authPhase { authPhase = .signedOut }
    }

    private static func message(for error: Error) -> String {
        (error as? AuthError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Push notifications

    /// Reads the current permission without prompting.
    ///
    /// Safe to call from `.task` on any screen: it shows no dialog, so a screen
    /// appearing can never be the thing that asks the user for notifications.
    func refreshPushAuthorization() async {
        pushAuthorization = await push.authorizationState
    }

    /// Turns on job alerts for this device.
    ///
    /// **This is the only place the system prompt is shown**, and it is only
    /// ever reached from a control the user deliberately tapped after being
    /// told what the alerts are for. Nothing calls it on launch.
    ///
    /// Requires a production session: a device token is meaningless without an
    /// authenticated user to attach it to, and the development stack has no
    /// database to record one in.
    @discardableResult
    func enablePushNotifications() async -> Bool {
        guard let session = productionSession else {
            pushStatusDetail = "Sign in before turning on job alerts."
            return false
        }

        isRegisteringForPush = true
        defer { isRegisteringForPush = false }

        let outcome = await push.register()
        pushAuthorization = await push.authorizationState

        switch outcome {
        case .refused(let state):
            isPushRegistered = false
            pushStatusDetail = state.explanation(worker: terms.worker)
            return false

        case .tokenUnavailable(let reason):
            // Permission without a token is not success and is not reported as
            // one. Nothing is registered, and the person is told why.
            isPushRegistered = false
            pushStatusDetail = reason
            return false

        case .registered(let token):
            return await store(token: token, for: session)
        }
    }

    /// Re-registers a device whose permission was granted in an earlier
    /// session, without prompting.
    ///
    /// iOS can reissue a device token — after a restore, an app reinstall, or
    /// at its own discretion — and the old one silently stops working. Calling
    /// this after a session is restored is what keeps a long-standing install
    /// reachable, and it never shows a dialog because it only runs when
    /// permission already exists.
    func restorePushRegistration() async {
        guard let session = productionSession else { return }

        pushAuthorization = await push.authorizationState
        guard pushAuthorization.canReceive else {
            isPushRegistered = false
            return
        }

        guard let outcome = await push.refreshTokenIfAuthorized() else { return }

        switch outcome {
        case .registered(let token):
            _ = await store(token: token, for: session)
        case .refused(let state):
            isPushRegistered = false
            pushStatusDetail = state.explanation(worker: terms.worker)
        case .tokenUnavailable(let reason):
            isPushRegistered = false
            pushStatusDetail = reason
        }
    }

    /// Records the token against the signed-in user.
    ///
    /// The registration carries no company and no user id: the database takes
    /// both from the authenticated session, so this app cannot register a
    /// device into another tenant even if it tried.
    private func store(token: PushDeviceToken, for session: TenantSession) async -> Bool {
        do {
            let registration = PushDeviceRegistration.forThisDevice(token: token)
            _ = try await gateway.registerPushDevice(session: session, registration: registration)
            registeredPushToken = token.value
            isPushRegistered = true
            pushStatusDetail = "This device will receive job alerts for \(session.displayName)."
            return true
        } catch {
            // A token Apple issued but the server would not store is not a
            // working registration, and is not displayed as one.
            isPushRegistered = false
            pushStatusDetail = (error as? DataError)?.errorDescription
                ?? "This device couldn't be registered for job alerts."
            return false
        }
    }

    /// Removes this device's registration on sign-out.
    ///
    /// Failure here is deliberately not allowed to block signing out — being
    /// unable to reach the server must never trap someone in a session — but it
    /// is also not silently ignored: remote notifications are switched off
    /// locally either way, so the handset stops presenting alerts immediately.
    private func tearDownPushRegistration() async {
        defer {
            registeredPushToken = nil
            isPushRegistered = false
            pushStatusDetail = nil
        }

        guard let session = productionSession, let token = registeredPushToken else {
            await push.unregister()
            return
        }

        do {
            _ = try await gateway.unregisterPushDevice(session: session, token: token)
        } catch {
            print("[push] the device registration could not be removed on the server: \(error.localizedDescription)")
        }

        await push.unregister()
    }
}
