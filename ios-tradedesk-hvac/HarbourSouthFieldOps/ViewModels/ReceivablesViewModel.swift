import Foundation
import Observation

@Observable
final class ReceivablesViewModel {
    private(set) var state: LoadState<ReceivablesSnapshot> = .idle
    var query: InvoiceQuery = InvoiceQuery(filter: .outstanding)

    var filter: InvoiceListFilter {
        get { query.filter }
        set { query.filter = newValue }
    }

    var dateScope: InvoiceDateScope {
        get { query.dateScope }
        set { query.dateScope = newValue }
    }

    var customerID: String? {
        get { query.customerID }
        set { query.customerID = newValue }
    }

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.receivables(session: session, query: query))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}
