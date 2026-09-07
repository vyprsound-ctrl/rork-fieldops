import Foundation
import Observation

@Observable
final class DashboardViewModel {
    private(set) var state: LoadState<DashboardSnapshot> = .idle

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.dashboard(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}
