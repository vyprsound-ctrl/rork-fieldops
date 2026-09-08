import Foundation
import Observation

/// Drives the subscription screen.
///
/// It renders the price the database calculated. It does not compute a
/// company's bill locally — the only arithmetic here is the "what would it cost
/// at N people" preview, which runs over the same tier data the server used and
/// is clearly labelled as a projection rather than a charge.
@Observable
final class SubscriptionViewModel {
    private(set) var state: LoadState<SubscriptionOverview> = .idle
    private(set) var connectState: LoadState<ConnectAccountStatus> = .idle
    private(set) var isWorking: Bool = false
    var actionError: String?
    /// A Stripe onboarding or dashboard link ready to open in the browser.
    var pendingLink: URL?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.subscriptionOverview(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
        await loadConnect(gateway: gateway, session: session)
    }

    func loadConnect(gateway: DataGateway, session: TenantSession) async {
        guard session.can(.paymentsRead) || session.can(.saasBillingRead) else { return }
        do {
            connectState = .loaded(try await gateway.connectAccountStatus(session: session))
        } catch {
            connectState = .failed(DataError.wrap(error))
        }
    }

    func startOnboarding(gateway: DataGateway, session: TenantSession) async {
        isWorking = true
        actionError = nil
        do {
            pendingLink = try await gateway.beginConnectOnboarding(session: session)
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

    /// "What would N people cost?" — a projection over the published tiers, so
    /// an owner can see the effect of hiring before they hire.
    func projection(_ overview: SubscriptionOverview, users: Int) -> SubscriptionQuote {
        overview.pricing.quote(for: users)
    }
}
