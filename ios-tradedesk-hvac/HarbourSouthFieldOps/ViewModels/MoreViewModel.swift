import Foundation
import Observation

@Observable
final class MoreViewModel {
    private(set) var state: LoadState<MoreOverview> = .idle
    /// The company's commercial position, for the Founding Member badge and the
    /// trial line on the account card.
    ///
    /// Best-effort and optional on purpose: only a billing role can read it,
    /// and the More tab must work identically for every other role. A nil here
    /// means "nothing commercial to say", never an error state.
    private(set) var commercial: CommercialState?
    /// Set when a billing role asked for the commercial state and the request
    /// failed. The More tab still renders — this only explains the missing
    /// badge instead of leaving a silent gap where one should be.
    private(set) var commercialError: String?

    /// ISSUE #13 — unread field worker messages waiting for the office.
    ///
    /// Best-effort and defaulted to zero for exactly the same reason as
    /// `commercial`: a role without an office grant reads no threads, and a
    /// failure here must never turn the More tab into an error screen. Zero
    /// means "nothing to report", never "the request failed".
    private(set) var unreadMessageCount: Int = 0

    func load(gateway: DataGateway, session: TenantSession, showLoading: Bool = true) async {
        if showLoading { state = .loading }
        do {
            state = .loaded(try await gateway.moreOverview(session: session))
        } catch {
            state = .failed(DataError.wrap(error))
        }

        // #13 — asked only of a role the database would actually answer for.
        // `office_threads_select` admits a caller holding `assignmentsManage` or
        // `usersManage`, so anyone else would simply read an empty inbox.
        if session.can(.assignmentsManage) || session.can(.usersManage) {
            unreadMessageCount = (try? await gateway.officeInbox(session: session))?.unreadCount ?? 0
        } else {
            unreadMessageCount = 0
        }

        // Asked only of a role that could possibly be granted it, so a
        // dispatcher's More tab issues no refused request at all.
        guard session.can(.saasBillingRead) else {
            commercial = nil
            commercialError = nil
            return
        }
        do {
            commercial = try await gateway.commercialState(session: session)
            commercialError = nil
        } catch {
            commercial = nil
            commercialError = DataError.wrap(error).errorDescription
        }
    }
}
