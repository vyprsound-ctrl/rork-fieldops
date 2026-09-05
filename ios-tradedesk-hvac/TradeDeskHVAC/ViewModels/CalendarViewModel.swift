import Foundation
import Observation

@Observable
final class CalendarViewModel {
    private(set) var state: LoadState<[CalendarDay]> = .idle
    var selectedDayID: String = "0"

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.calendarDays(session: session, dayCount: 14))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }
}
