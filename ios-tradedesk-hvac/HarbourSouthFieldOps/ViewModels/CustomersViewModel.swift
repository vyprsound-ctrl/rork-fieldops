import Foundation
import Observation

@Observable
final class CustomersViewModel {
    private(set) var state: LoadState<[CustomerRow]> = .idle
    var query: String = ""

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.customers(session: session, query: query))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}
