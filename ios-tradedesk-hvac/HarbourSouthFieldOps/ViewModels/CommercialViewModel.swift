import Foundation
import Observation

/// Drives every commercial surface: the Payments screen, the Founding Member
/// badge, the trial banner and the subscription screen's commercial card.
///
/// It holds no commercial logic. `CommercialState` arrives fully decided from
/// `company_commercial_state()`, and this object only tracks load state and the
/// two actions a person can take — start or continue Stripe onboarding, and
/// choose to keep their own payment provider.
@Observable
final class CommercialViewModel {
    private(set) var state: LoadState<CommercialState> = .idle
    private(set) var isWorking: Bool = false
    var actionError: String?
    /// A Stripe onboarding or dashboard link ready for the browser.
    var pendingLink: URL?
    var confirmation: String?
    /// Sole trader or limited company, asked once before the Stripe account
    /// exists. A prefill only — Stripe verifies it either way.
    var businessType: ConnectBusinessType = .unspecified

    var commercial: CommercialState? {
        if case .loaded(let value) = state { return value }
        return nil
    }

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.commercialState(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    /// Starts Stripe onboarding, or reopens it where Stripe wants more.
    func startOnboarding(gateway: DataGateway, session: TenantSession) async {
        isWorking = true
        actionError = nil
        do {
            pendingLink = try await gateway.beginConnectOnboarding(
                session: session,
                businessType: businessType
            )
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }

    func openStripeDashboard(gateway: DataGateway, session: TenantSession) async {
        isWorking = true
        actionError = nil
        do {
            pendingLink = try await gateway.connectDashboardLink(session: session)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }

    /// Chooses MODEL B. The server refuses any attempt to select Harbour South
    /// Payments this way, so there is no call site for it here either.
    func chooseExternalProvider(gateway: DataGateway, session: TenantSession) async {
        isWorking = true
        actionError = nil
        confirmation = nil
        do {
            try await gateway.selectPaymentModel(session: session, model: .externalProvider)
            confirmation = "You'll keep using your own payment provider."
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}

/// Drives the business email identity screen.
@Observable
final class BusinessEmailViewModel {
    private(set) var state: LoadState<BusinessEmailSettings> = .idle
    private(set) var isWorking: Bool = false
    var draft: String = ""
    var actionError: String?
    var savedNotice: String?

    private var stored: String = ""

    // `tidied`, not `trimmed`: the latter also rewrites a comma as a decimal
    // point, which is right for a price field and wrong for an address.
    var isDirty: Bool { draft.tidied != stored }

    /// Why a save would be refused, before it is attempted.
    var draftProblem: String? {
        let trimmed = draft.tidied
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try BusinessEmail.normalise(trimmed)
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription
                ?? "That doesn't look like an email address."
        }
    }

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            let settings = try await gateway.businessEmailSettings(session: session)
            stored = settings.email ?? ""
            draft = stored
            state = .loaded(settings)
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func save(gateway: DataGateway, session: TenantSession) async {
        isWorking = true
        actionError = nil
        savedNotice = nil
        do {
            try await gateway.updateBusinessEmail(session: session, email: draft.tidied)
            savedNotice = draft.tidied.isEmpty
                ? "Removed. Invoice replies will have no return address until you add one."
                : "Saved. Customers will see this as your reply address."
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }

    func clear(gateway: DataGateway, session: TenantSession) async {
        draft = ""
        await save(gateway: gateway, session: session)
    }
}
