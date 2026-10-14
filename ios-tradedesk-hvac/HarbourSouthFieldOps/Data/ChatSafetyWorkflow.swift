import Foundation

/// Default (development) behaviour for chat safety. The development stack has
/// no moderation backend, so it says so plainly instead of pretending a report
/// went anywhere. The Supabase gateway overrides every member here.
extension DataGateway {
    private var safetyLiveOnly: DataError {
        .rejected("Reporting and blocking are only available on a live company account.")
    }

    @discardableResult
    func reportMessage(session: TenantSession, target: ReportTarget, reason: ReportReason, details: String?) async throws -> String {
        throw safetyLiveOnly
    }

    func blockChatUser(session: TenantSession, userID: String, reason: ReportReason, details: String?) async throws {
        throw safetyLiveOnly
    }

    func unblockChatUser(session: TenantSession, userID: String) async throws {
        throw safetyLiveOnly
    }

    func blockedChatUserIDs(session: TenantSession) async throws -> Set<String> { [] }

    func chatSafetyOverview(session: TenantSession) async throws -> ChatSafetyOverview {
        ChatSafetyOverview(reports: [], blocked: [], canModerate: session.can(.usersManage))
    }

    func moderateReport(session: TenantSession, reportID: String, action: ModerationAction, note: String?, days: Int?) async throws {
        throw safetyLiveOnly
    }
}
