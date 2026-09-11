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

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.moreOverview(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }

        // Asked only of a role that could possibly be granted it, so a
        // dispatcher's More tab issues no refused request at all.
        commercial = session.can(.saasBillingRead)
            ? try? await gateway.commercialState(session: session)
            : nil
    }
}
