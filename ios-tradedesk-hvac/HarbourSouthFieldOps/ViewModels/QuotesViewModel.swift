import Foundation
import Observation

@Observable
final class QuotesViewModel {
    private(set) var state: LoadState<[QuoteRow]> = .idle
    var filter: QuoteListFilter = .open
    var searchText: String = ""

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.quotes(session: session, filter: filter, query: searchText))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}
