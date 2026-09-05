import Foundation
import Observation

@Observable
final class ScheduleViewModel {
    private(set) var state: LoadState<CalendarBoard> = .idle
    private(set) var isWorking: Bool = false
    var query: CalendarQuery = CalendarQuery()
    var selectedDayID: String = "0"
    var actionError: String?

    /// A move the dispatcher has been warned about but not yet accepted.
    var pendingReschedule: PendingMove?

    struct PendingMove: Identifiable, Hashable {
        let id: String
        let jobID: String
        let jobNumber: String
        let input: RescheduleInput
        let check: SchedulingCheck
    }

    var span: CalendarSpan {
        get { query.span }
        set {
            query.span = newValue
            selectedDayID = "0"
        }
    }

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.calendarBoard(session: session, query: query))
        } catch {
            state = .failed(DataError.wrap(error))
        }
    }

    func shift(by days: Int) {
        query.anchorDate = Calendar.current.date(byAdding: .day, value: days, to: query.anchorDate) ?? query.anchorDate
        selectedDayID = "0"
    }

    func today() {
        query.anchorDate = Date()
        selectedDayID = "0"
    }

    /// First attempt at a move. An overlap is refused and returned for
    /// confirmation rather than being applied silently.
    func reschedule(
        gateway: DataGateway,
        session: TenantSession,
        jobID: String,
        jobNumber: String,
        start: Date?,
        end: Date?
    ) async {
        isWorking = true
        actionError = nil
        let input = RescheduleInput(scheduledStart: start, scheduledEnd: end, acknowledgesConflict: false)
        do {
            _ = try await gateway.rescheduleJob(session: session, jobID: jobID, input: input)
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            let check = (try? await gateway.checkReschedule(session: session, jobID: jobID, input: input)) ?? .clear
            if check.hasConflicts {
                pendingReschedule = PendingMove(
                    id: jobID,
                    jobID: jobID,
                    jobNumber: jobNumber,
                    input: input,
                    check: check
                )
            } else {
                actionError = DataError.wrap(error).errorDescription
            }
        }
        isWorking = false
    }

    func confirmPendingReschedule(gateway: DataGateway, session: TenantSession) async {
        guard let pending = pendingReschedule else { return }
        pendingReschedule = nil
        isWorking = true
        actionError = nil
        var input = pending.input
        input.acknowledgesConflict = true
        do {
            _ = try await gateway.rescheduleJob(session: session, jobID: pending.jobID, input: input)
            await load(gateway: gateway, session: session, showLoading: false)
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
