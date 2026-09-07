import Foundation
import Observation

@Observable
final class JobsViewModel {
    private(set) var state: LoadState<[JobRow]> = .idle
    private(set) var options: JobFormOptions = .empty
    var query: JobQuery = .today
    var searchText: String = ""

    /// The query actually sent to the gateway, search text included.
    private var resolvedQuery: JobQuery {
        var resolved = query
        resolved.searchText = searchText
        return resolved
    }

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.jobs(session: session, query: resolvedQuery))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func loadOptions(gateway: DataGateway, session: TenantSession) async {
        options = (try? await gateway.jobFormOptions(session: session)) ?? .empty
    }

    func workerName(_ id: String) -> String? {
        options.workers.first { $0.id == id }?.name
    }

    func customerName(_ id: String) -> String? {
        options.customers.first { $0.id == id }?.name
    }

    /// Human-readable chips describing the active refinements.
    func activeFilterLabels(_ terms: Terminology) -> [String] {
        var labels: [String] = []
        for status in query.statuses.sorted(by: { ($0.pipelineIndex ?? 99) < ($1.pipelineIndex ?? 99) }) {
            labels.append(status.title(terms))
        }
        if let workerID = query.fieldWorkerUserID {
            labels.append(workerName(workerID) ?? terms.Worker)
        }
        if let priority = query.priority {
            labels.append(priority.title)
        }
        if let customerID = query.customerID {
            labels.append(customerName(customerID) ?? "Customer")
        }
        return labels
    }
}
