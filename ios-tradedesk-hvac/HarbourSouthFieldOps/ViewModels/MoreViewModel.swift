import Foundation
import Observation

@Observable
final class MoreViewModel {
    private(set) var state: LoadState<MoreOverview> = .idle
    /// The company's commercial position, for the Founding Member badge and the
    /// trial line on the account card.
    ///
    /// Best-effort and optional on purpose: only a billing role can read it,
    /// and the More tab must work identically for every other role. A nil here
    /// means "nothing commercial to say", never an error state.
    private(set) var commercial: CommercialState?
    /// Set when a billing role asked for the commercial state and the request
    /// failed. The More tab still renders — this only explains the missing
    /// badge instead of leaving a silent gap where one should be.
    private(set) var commercialError: String?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.moreOverview(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }

        // Asked only of a role that could possibly be granted it, so a
        // dispatcher's More tab issues no refused request at all.
        guard session.can(.saasBillingRead) else {
            commercial = nil
            commercialError = nil
            return
        }
        do {
            commercial = try await gateway.commercialState(session: session)
            commercialError = nil
        } catch {
            commercial = nil
            commercialError = DataError.wrap(error).errorDescription
        }
    }
}
