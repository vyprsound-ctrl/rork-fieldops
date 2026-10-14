import Foundation
import Supabase

// MARK: - Wire records

private nonisolated struct MessageReportRecord: Decodable, Sendable {
    let id: UUID
    let source: String
    let reporterUserID: UUID?
    let reportedUserID: UUID?
    let reason: String
    let details: String?
    let snapshotBody: String?
    let status: String
    let escalatedToPlatform: Bool
    let createdAt: Date
    let resolution: String?

    enum CodingKeys: String, CodingKey {
        case id, source, reason, details, status, resolution
        case reporterUserID = "reporter_user_id", reportedUserID = "reported_user_id"
        case snapshotBody = "snapshot_body", escalatedToPlatform = "escalated_to_platform"
        case createdAt = "created_at"
    }

    static let columns = "id,source,reporter_user_id,reported_user_id,reason,details,snapshot_body,status,escalated_to_platform,created_at,resolution"
}

private nonisolated struct ChatBlockRecord: Decodable, Sendable {
    let blockedUserID: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case blockedUserID = "blocked_user_id", createdAt = "created_at"
    }

    static let columns = "blocked_user_id,created_at"
}

/// Reporting, blocking and moderation. Every rule lives in the database
/// functions from migration 0015 — this file only calls them and reads the
/// rows RLS lets the caller see.
extension SupabaseDataGateway {
    @discardableResult
    func reportMessage(session: TenantSession, target: ReportTarget, reason: ReportReason, details: String?) async throws -> String {
        guard UUID(uuidString: target.messageID) != nil else { throw DataError.notFound }
        let function: String
        switch target.kind {
        case .office: function = "report_office_message"
        case .sms: function = "report_sms_message"
        }
        let id = try await performReturningID(function, [
            "p_message": .string(target.messageID.lowercased()),
            "p_reason": .string(reason.rawValue),
            "p_details": Self.optionalText(details)
        ])
        record("safety.report", session, allowed: true, "Report filed; reviewers resolved server-side")
        return id
    }

    func blockChatUser(session: TenantSession, userID: String, reason: ReportReason, details: String?) async throws {
        guard UUID(uuidString: userID) != nil else { throw DataError.notFound }
        _ = try await performReturningID("block_chat_user", [
            "p_user": .string(userID.lowercased()),
            "p_reason": .string(reason.rawValue),
            "p_details": Self.optionalText(details)
        ])
        record("safety.block", session, allowed: true, "Blocked for this user only; moderators notified server-side")
    }

    func unblockChatUser(session: TenantSession, userID: String) async throws {
        guard UUID(uuidString: userID) != nil else { throw DataError.notFound }
        try await perform("unblock_chat_user", ["p_user": .string(userID.lowercased())])
        record("safety.unblock", session, allowed: true, "Block removed")
    }

    func blockedChatUserIDs(session: TenantSession) async throws -> Set<String> {
        let rows = try await fetch(
            ChatBlockRecord.self,
            client.from("chat_blocks").select(ChatBlockRecord.columns).limit(500)
        )
        return Set(rows.map { $0.blockedUserID.uuidString.lowercased() })
    }

    func chatSafetyOverview(session: TenantSession) async throws -> ChatSafetyOverview {
        let reports = try await fetch(
            MessageReportRecord.self,
            client.from("message_reports")
                .select(MessageReportRecord.columns)
                .order("created_at", ascending: false)
                .limit(200)
        )
        let blocks = try await fetch(
            ChatBlockRecord.self,
            client.from("chat_blocks")
                .select(ChatBlockRecord.columns)
                .order("created_at", ascending: false)
                .limit(500)
        )

        var ids = Set<String>()
        for report in reports {
            if let id = report.reporterUserID { ids.insert(id.uuidString) }
            if let id = report.reportedUserID { ids.insert(id.uuidString) }
        }
        for block in blocks { ids.insert(block.blockedUserID.uuidString) }
        // Names are a label only; a person this role can't read stays unnamed
        // rather than failing the whole screen.
        let people = (try? await users(ids: Array(ids))) ?? [:]
        let me = session.userID.lowercased()

        let rows = reports.map { report -> ModerationReportRow in
            ModerationReportRow(
                id: report.id.uuidString,
                reason: ReportReason(rawValue: report.reason) ?? .other,
                status: ModerationReportStatus(rawValue: report.status) ?? .open,
                createdAt: report.createdAt,
                isMine: report.reporterUserID?.uuidString.lowercased() == me,
                isEscalated: report.escalatedToPlatform,
                source: report.source,
                reporterName: report.reporterUserID.flatMap { people[$0.uuidString]?.name },
                reportedName: report.reportedUserID.flatMap { people[$0.uuidString]?.name },
                reportedUserID: report.reportedUserID?.uuidString,
                excerpt: report.snapshotBody,
                details: report.details,
                resolution: report.resolution
            )
        }
        let blocked = blocks.map { block in
            BlockedChatUser(
                id: block.blockedUserID.uuidString,
                name: people[block.blockedUserID.uuidString]?.name ?? "Team member",
                blockedAt: block.createdAt
            )
        }
        record("safety.overview", session, allowed: true, "\(rows.count) report(s) visible under RLS, \(blocked.count) block(s)")
        return ChatSafetyOverview(reports: rows, blocked: blocked, canModerate: session.can(.usersManage))
    }

    func moderateReport(session: TenantSession, reportID: String, action: ModerationAction, note: String?, days: Int?) async throws {
        guard UUID(uuidString: reportID) != nil else { throw DataError.notFound }
        try require(.usersManage, session, query: "safety.moderate")
        try await perform("moderate_message_report", [
            "p_report": .string(reportID.lowercased()),
            "p_action": .string(action.rawValue),
            "p_note": Self.optionalText(note),
            "p_days": days.map { .integer($0) } ?? .null
        ])
        record("safety.moderate", session, allowed: true, "Moderation action \(action.rawValue)")
    }

    private nonisolated static func optionalText(_ value: String?) -> AnyJSON {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .null : .string(String(trimmed.prefix(1000)))
    }
}
