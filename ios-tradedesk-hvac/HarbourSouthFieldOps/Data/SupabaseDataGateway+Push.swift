import Foundation
import Supabase

/// A push attempt as the notifications policy is willing to return it.
private nonisolated struct PushNotificationRow: Decodable, Sendable {
    let id: UUID
    let template: String
    let title: String?
    let body: String?
    let status: NotificationStatus
    let jobID: UUID?
    let deepLink: String?
    let failureReason: String?
    let sentAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, template, title, body, status
        case jobID = "job_id"
        case deepLink = "deep_link"
        case failureReason = "failure_reason"
        case sentAt = "sent_at"
        case createdAt = "created_at"
    }

    static let columns = "id,template,title,body,status,job_id,deep_link,failure_reason,sent_at,created_at"
}

/// Push notification registration and history, against Supabase.
///
/// Two rules are worth stating plainly because they are enforced below the app
/// rather than by it:
///
/// * **Registration carries no tenancy.** `register_push_device` takes a token
///   and nothing else that matters; company and user come from `auth.uid()`
///   inside the function. There is no parameter this app could set to point a
///   device at another company.
///
/// * **The inbox is not a new authorisation system.** Reading push history is
///   an ordinary select against `notifications`, governed by the same policy as
///   every other row in that table. The policy lets you read a row that names
///   you as its target; the app adds a filter for precision, not for security.
extension SupabaseDataGateway {

    func registerPushDevice(session: TenantSession, registration: PushDeviceRegistration) async throws -> String {
        let id = try await performReturningID(
            "register_push_device",
            [
                "p_token": .string(registration.token),
                "p_environment": .string(registration.environment.rawValue),
                "p_bundle_id": .string(registration.bundleID),
                "p_app_version": .string(registration.appVersion),
                "p_device_model": .string(registration.deviceModel)
            ]
        )

        record(
            "push.register",
            session,
            allowed: true,
            "Device registered for job alerts — company and user taken from the session, never from this app"
        )
        return id
    }

    func unregisterPushDevice(session: TenantSession, token: String) async throws -> Bool {
        let response: PostgrestResponse<Void> = try await client
            .rpc("unregister_push_device", params: ["p_token": token])
            .execute()

        let removed = (try? SupabaseCoding.decoder.decode(Bool.self, from: response.data)) ?? false
        record(
            "push.unregister",
            session,
            allowed: true,
            removed
                ? "Device registration removed — this handset stops receiving job alerts"
                : "No live registration for this device"
        )
        return removed
    }

    func pushInbox(session: TenantSession, limit: Int) async throws -> [PushNotificationRecord] {
        let rows = try await fetch(
            PushNotificationRow.self,
            client.from("notifications")
                .select(PushNotificationRow.columns)
                .eq("channel", value: "push")
                .eq("target_user_id", value: session.userID)
                .order("created_at", ascending: false)
                .limit(max(1, min(limit, 100)))
        )

        record(
            "push.inbox",
            session,
            allowed: true,
            "\(rows.count) notification(s) addressed to this user; the policy returns none addressed to anyone else"
        )

        return rows.map { row in
            PushNotificationRecord(
                id: row.id.uuidString,
                event: row.template,
                title: row.title ?? PushEvent(rawValue: row.template)?.title ?? Brand.name,
                body: row.body ?? "",
                status: row.status,
                jobID: row.jobID?.uuidString,
                deepLink: row.deepLink,
                failureReason: row.failureReason,
                createdAt: row.createdAt,
                sentAt: row.sentAt
            )
        }
    }
}
