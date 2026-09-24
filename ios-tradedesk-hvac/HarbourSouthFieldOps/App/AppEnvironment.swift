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
    /// Apple subscriptions. StoreKit for a production session, a stand-in that
    /// sells nothing for the development stack.
    private let developmentStoreBilling: StoreBillingService
    private let productionStoreBilling: StoreBillingService?
    /// Listens to `Transaction.updates` for the life of the app, so renewals,
    /// Offer Code redemptions and Ask to Buy approvals reach the server even
    /// when no purchase screen is open.
    private var storeUpdatesTask: Task<Void, Never>?
    // NO `sms` OR `email` ADAPTER HERE, DELIBERATELY. Customer messaging is not
    // a client capability: `sendInvoice` calls the `send-invoice` Edge
    // Function, which holds the provider credentials and writes the real
    // outcome to the notifications ledger. This class used to expose mock SMS
    // and email services that returned a fabricated "sent" receipt. Nothing
    // ever called them — but leaving them here implied the production app had a
    // device-side messaging path that could silently report a false success.
    // They have been deleted rather than re-wired.

    /// Routing and maps — straight-line fixtures for the development stack,
    /// Apple Maps for the production one. Split by the same condition as the
    /// gateway so a screen can never show a routed ETA against seeded data.
    private let developmentRoutes: RouteService
    private let productionRoutes: RouteService?
    private let developmentMaps: MapService
    private let productionMaps: MapService?

    /// The one travel leg an engineer can be on. Owned here rather than by a
    /// screen so it survives navigation, and stopped on sign-out so a signed-out
    /// handset never keeps reporting.
    let travelTracker = TravelTracker()

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
    /// Set when a recovery link has authenticated somebody who has not yet
    /// chosen a new password. Held here rather than published as the live
    /// session, so a half-finished reset never reaches the app shell.
    private(set) var pendingPasswordReset: TenantSession?
    private(set) var isCompletingPasswordReset: Bool = false
    var passwordResetError: String?
    /// Set when sign-up succeeded but the address still needs confirming. The
    /// company is founded automatically on the first sign-in after that.
    private(set) var signUpNotice: String?
    /// An invitation handed over by a tapped email link, waiting for the
    /// sign-in screen to pick it up.
    ///
    /// This is a PREFILL and nothing more. The code still has to match a live
    /// invitation inside the database, which is where the company and the role
    /// are decided — arriving by link grants nothing that typing the same code
    /// by hand would not.
    private(set) var pendingInvitationLink: InvitationLink.Payload?

    /// The address a confirmation email has just been sent to.
    ///
    /// Set when sign-up or a join succeeded but the address still needs
    /// confirming, and cleared the moment a session exists. The sign-in screen
    /// watches it to move itself to the Sign in form.
    ///
    /// This is why it exists: joining leaves the form sitting on Join, and Join
    /// is precisely the one thing that will *not* work after confirming — the
    /// invitation code is spent on the first authenticated session, so a second
    /// attempt to redeem it fails. Somebody returning from their inbox has to
    /// land on Sign in, or the app has quietly pointed them at a dead end.
    private(set) var pendingEmailConfirmation: String?

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
        self.developmentPush = MockPushService()
        self.developmentStoreBilling = MockStoreBillingService()
        self.developmentLocation = MockLocationService()
        self.developmentRoutes = MockRouteService()
        self.developmentMaps = MockMapService()

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
            // MapKit needs no credentials and no account, so these are real
            // from the first launch of a configured build.
            self.productionRoutes = MapKitRouteService()
            self.productionMaps = MapKitMapService()
            self.productionStoreBilling = StoreKitBillingService()
        } else {
            self.productionAuth = nil
            self.productionGateway = nil
            self.productionLocation = nil
            self.productionPush = nil
            self.productionRoutes = nil
            self.productionMaps = nil
            self.productionStoreBilling = nil
        }
    }

    /// The subscription store matching whichever session is signed in.
    var storeBilling: StoreBillingService {
        guard productionSession != nil else { return developmentStoreBilling }
        return productionStoreBilling ?? developmentStoreBilling
    }

    // MARK: - Apple subscription sync

    /// Starts the `Transaction.updates` listener once. Safe to call repeatedly.
    func startStoreListener() {
        guard storeUpdatesTask == nil, let store = productionStoreBilling else { return }
        storeUpdatesTask = Task { [weak self] in
            for await purchase in store.transactionUpdates() {
                await self?.linkStorePurchases([purchase])
            }
        }
    }

    /// Hands every current Apple subscription to the server. Called after a
    /// production session starts and after an Offer Code is redeemed, so a
    /// subscription bought or renewed while the app was closed is linked.
    /// Only the owner can link; for anyone else this does nothing.
    func syncStoreEntitlements() async {
        guard let session = productionSession, session.can(.saasBillingManage),
              let store = productionStoreBilling else { return }
        let purchases = await store.currentPurchases()
        guard !purchases.isEmpty else { return }
        await linkStorePurchases(purchases)
    }

    private func linkStorePurchases(_ purchases: [SignedStorePurchase]) async {
        guard let session = productionSession, session.can(.saasBillingManage),
              let store = productionStoreBilling else { return }
        do {
            let result = try await gateway.linkStorePurchases(session: session, purchases: purchases)
            for id in result.handledTransactionIDs { await store.finish(transactionID: id) }
        } catch {
            // Not fatal: App Store Server Notifications and the next sync
            // deliver the same facts. The transaction stays unfinished, so
            // StoreKit redelivers it.
            print("[store] subscription could not be linked yet: \(error.localizedDescription)")
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

    /// Travel time and distance, matched to the signed-in stack.
    var routes: RouteService {
        guard productionSession != nil else { return developmentRoutes }
        return productionRoutes ?? developmentRoutes
    }

    /// Map presentation and navigation hand-off, matched to the signed-in stack.
    var maps: MapService {
        guard productionSession != nil else { return developmentMaps }
        return productionMaps ?? developmentMaps
    }

    /// True while any user-facing capability is still backed by a local
    /// stand-in. Keyed off `simulatedCount`, not `notLiveCount`: a capability
    /// that is real but awaiting a credential is not a simulation, and saying
    /// so in a production build would be wrong.
    var hasSimulatedServices: Bool { IntegrationRegistry.simulatedCount > 0 }

    /// Capabilities that are implemented but cannot succeed until an external
    /// account is configured. Shown as configuration work, not as breakage.
    var servicesNeedingConfiguration: [IntegrationStatus] {
        IntegrationRegistry.needingConfiguration
    }

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
        pendingInvitationLink = nil
        pendingEmailConfirmation = nil
        // A development session cannot have started a real leg, but stopping is
        // cheap and leaves no path where sign-out keeps a tracker alive.
        Task { await travelTracker.stop() }
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
            // Whatever was still being waited on has now happened.
            pendingEmailConfirmation = nil
            pendingInvitationLink = nil
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
                pendingEmailConfirmation = nil

            case .confirmationSent(let address):
                // Not an error. The account exists and the company details are
                // held against it; signing in after confirming finishes setup.
                productionSession = nil
                authPhase = .signedOut
                pendingEmailConfirmation = address
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
                pendingEmailConfirmation = nil
                pendingInvitationLink = nil

            case .confirmationSent(let address):
                productionSession = nil
                authPhase = .signedOut
                // The code is now parked on the identity and will be redeemed
                // by the first authenticated session. Holding on to it here as
                // well would send the person back to Join on their return —
                // where redeeming it a second time fails — so it is released.
                pendingInvitationLink = nil
                pendingEmailConfirmation = address
                signUpNotice = "Check your email. We've sent a confirmation link to \(address). "
                    + "Confirm it, then sign in here with the same email and password — "
                    + "you'll join the company automatically."
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

        // The radio goes down before the session does. Signing out with a leg
        // still running would leave Core Location delivering fixes that no
        // longer have a session to be written against.
        await travelTracker.stop()

        // Clear locally first so the UI can never keep showing tenant context
        // while a network call is still in flight.
        productionSession = nil
        authPhase = .signedOut
        passwordResetNotice = nil
        signUpNotice = nil
        // Sign-out returns to a clean sign-in screen. A stale invitation or a
        // half-finished confirmation left over from an earlier attempt would
        // otherwise reopen the Join form for somebody who has just chosen to
        // leave, and send the next person on this handset there too.
        pendingInvitationLink = nil
        pendingEmailConfirmation = nil
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
    /// Everything the app is reopened by: Supabase email links, and the
    /// invitation hand-off from the join page.
    ///
    /// The invitation is checked first because it shares the registered scheme.
    /// It carries no Supabase code to exchange, so treating it as an auth
    /// callback would fail it with an "unusable link" message.
    func handleIncomingURL(_ url: URL) async {
        if let invitation = InvitationLink.payload(from: url) {
            acceptInvitationLink(invitation)
            return
        }
        await handleAuthCallback(url)
    }

    /// Parks an invitation from a tapped link for the sign-in screen.
    ///
    /// A signed-in session is deliberately left alone: somebody already working
    /// who taps an old invitation email must not be signed out of the company
    /// they are in. They are told what to do instead.
    private func acceptInvitationLink(_ payload: InvitationLink.Payload) {
        guard productionSession == nil else {
            signUpNotice = "You're already signed in. Sign out first if you're joining a different company with that invitation."
            return
        }
        pendingInvitationLink = payload
        passwordResetNotice = nil
        signUpNotice = "Invitation opened. Enter your email address and choose a password to finish setting up your account."
        if case .failed = authPhase { authPhase = .signedOut }
    }

    /// Called by the sign-in screen once it has copied the code into its form,
    /// so a later redraw doesn't overwrite what the person has since typed.
    func consumePendingInvitationLink() {
        pendingInvitationLink = nil
    }

    /// Called by the sign-in screen once it has moved itself to the Sign in
    /// form, so the move happens exactly once and the person can still switch
    /// tabs by hand afterwards.
    func consumePendingEmailConfirmation() {
        pendingEmailConfirmation = nil
    }

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

        // A recovery link is not a sign-in. It authenticates the user only so
        // they can choose a new password, so the app has to stop and ask for
        // one instead of dropping them into the shell — which is exactly the
        // dead end this flow used to have.
        let isRecovery = AuthCallback.isPasswordRecovery(url)

        do {
            let session = try await productionAuth.completeAuthCallback(url: url)
            if isRecovery {
                // Held back deliberately. The session exists, but nothing is
                // published to the UI until a new password has been set.
                pendingPasswordReset = session
                authPhase = .signedOut
            } else {
                productionSession = session
                authPhase = .signedIn
                // Confirmed and in. Both waiting states are spent.
                pendingEmailConfirmation = nil
                pendingInvitationLink = nil
            }
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
                // The link could not be exchanged — opened on another device,
                // or already spent. Signing in by hand still works and still
                // redeems what is parked on the identity, so the invitation is
                // released here too: leaving it set would drag the form back to
                // Join, which is the one flow that can no longer succeed.
                pendingInvitationLink = nil
            }
        }
    }

    /// Signs out of whichever stack is currently driving the app.
    ///
    /// Every sign-out control routes through here. The two stacks genuinely
    /// differ — only the production path holds a device registration and a
    /// server session to discard — and a screen that picked the wrong one
    /// looked interactive while doing nothing at all, which is exactly the
    /// fault this replaces.
    func signOutOfCurrentSession() async {
        if productionSession != nil {
            await signOutOfProduction()
        } else {
            signOut()
        }
    }

    /// Finishes a password reset.
    ///
    /// Only reachable while `pendingPasswordReset` is set, so it cannot be used
    /// to change the password of an ordinary signed-in session by accident.
    /// On success the held session is published and the user is simply in —
    /// no second sign-in, which is what makes this a complete flow rather than
    /// a detour.
    func completePasswordReset(newPassword: String) async -> Bool {
        guard let productionAuth, let session = pendingPasswordReset else {
            passwordResetError = AuthError.recoverySessionExpired.errorDescription
            return false
        }

        isCompletingPasswordReset = true
        passwordResetError = nil
        defer { isCompletingPasswordReset = false }

        do {
            try await productionAuth.updatePassword(newPassword)
            pendingPasswordReset = nil
            productionSession = session
            authPhase = .signedIn
            passwordResetNotice = "Your password has been changed."
            return true
        } catch {
            passwordResetError = Self.message(for: error)
            // An expired recovery session cannot be retried, so send the user
            // back to sign-in rather than leaving them on a form that will
            // never succeed.
            if case AuthError.recoverySessionExpired = error {
                pendingPasswordReset = nil
            }
            return false
        }
    }

    /// Abandons a reset without setting a password. The recovery session is
    /// discarded rather than left usable in the background.
    func cancelPasswordReset() async {
        pendingPasswordReset = nil
        passwordResetError = nil
        try? await productionAuth?.signOut()
        authPhase = .signedOut
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
