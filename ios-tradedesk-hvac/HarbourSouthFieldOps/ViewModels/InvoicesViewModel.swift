import Foundation
import Observation

@Observable
final class InvoicesViewModel {
    private(set) var state: LoadState<[InvoiceRow]> = .idle
    private(set) var sources: InvoiceSourceOptions = .empty
    var query: InvoiceQuery = .outstanding

    var searchText: String {
        get { query.searchText }
        set { query.searchText = newValue }
    }

    var filter: InvoiceListFilter {
        get { query.filter }
        set { query.filter = newValue }
    }

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.invoices(session: session, query: query))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func loadSources(gateway: DataGateway, session: TenantSession) async {
        sources = (try? await gateway.invoiceSources(session: session)) ?? .empty
    }
}
