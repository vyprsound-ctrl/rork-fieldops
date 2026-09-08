import Foundation
import Observation

/// Drives the recurring service list and its editor.
///
/// Generation itself is deliberately absent from this class. Recurring visits
/// are produced by a scheduled server function, so a contract does not depend
/// on somebody opening the app; this screen only sets the arrangement up and
/// shows what the server has produced.
@Observable
final class RecurringServiceViewModel {
    private(set) var state: LoadState<RecurringServiceBoard> = .idle
    private(set) var options: JobFormOptions?
    private(set) var isWorking: Bool = false
    var actionError: String?
    var confirmation: String?

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.recurringServices(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }

        // The editor needs customers and their sites. A failure here is not
        // fatal to the list, so it is kept separate.
        if session.can(.jobsManage) {
            options = try? await gateway.jobFormOptions(session: session)
        }
    }

    func save(gateway: DataGateway, session: TenantSession, draft: RecurringServiceDraft) async -> Bool {
        isWorking = true
        actionError = nil
        defer { isWorking = false }

        do {
            _ = try await gateway.saveRecurringService(session: session, draft: draft)
            await load(gateway: gateway, session: session, showLoading: false)
            confirmation = draft.id == nil
                ? "Recurring visit created. The first job will be booked automatically when it falls due."
                : "Recurring visit updated."
            return true
        } catch {
            actionError = DataError.wrap(error).errorDescription
            return false
        }
    }

    func delete(gateway: DataGateway, session: TenantSession, id: String) async {
        isWorking = true
        actionError = nil
        do {
            try await gateway.deleteRecurringService(session: session, id: id)
            await load(gateway: gateway, session: session, showLoading: false)
            confirmation = "Recurring visit removed. Jobs already booked from it are untouched."
        } catch {
            actionError = DataError.wrap(error).errorDescription
        }
        isWorking = false
    }
}
