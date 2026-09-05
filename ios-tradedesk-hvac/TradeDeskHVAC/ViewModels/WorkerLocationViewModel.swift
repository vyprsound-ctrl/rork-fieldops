import Foundation
import Observation

@Observable
final class WorkerLocationViewModel {
    private(set) var state: LoadState<FieldWorkerLocationBoard> = .idle

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.fieldWorkerLocations(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}
