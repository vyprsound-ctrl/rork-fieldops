import Foundation
import Observation

/// Drives the SMS credits screen and the send sheet.
@Observable
final class SmsCreditsViewModel {
    private(set) var state: LoadState<SmsCreditOverview> = .idle
    private(set) var isWorking: Bool = false
    var actionError: String?
    /// Stripe checkout, opened in the browser. Credits are granted by the
    /// webhook once the money arrives — never when this URL is opened.
    var checkoutURL: URL?
    /// Set after a send so the screen can confirm what actually happened.
    var lastOutcome: SmsSendOutcome?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.smsCreditOverview(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func buy(gateway: DataGateway, session: TenantSession, bundle: SmsBundle) async {
        isWorking = true
        actionError = nil
        do {
            checkoutURL = try await gateway.purchaseSmsCredits(
                session: session,
                bundleID: bundle.id,
                credits: nil
            )
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }

    /// Sends one message and reports the real outcome.
    ///
    /// A refusal for want of credit is returned as an outcome, not thrown: the
    /// balance is untouched, nothing was sent, and the user is told to buy more
    /// rather than shown a failure they cannot interpret.
    @discardableResult
    func send(gateway: DataGateway, session: TenantSession, draft: SmsSendDraft) async -> Bool {
        isWorking = true
        actionError = nil
        lastOutcome = nil
        defer { isWorking = false }

        do {
            let outcome = try await gateway.sendCustomerSms(session: session, draft: draft)
            lastOutcome = outcome
            await load(gateway: gateway, session: session, showLoading: false)
            if !outcome.sent { actionError = outcome.detail }
            return outcome.sent
        } catch {
            actionError = DataError.wrap(error).errorDescription
            return false
        }
    }
}
