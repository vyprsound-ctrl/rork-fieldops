import Foundation
import Observation

@Observable
final class MoreViewModel {
    private(set) var state: LoadState<MoreOverview> = .idle

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.moreOverview(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}
