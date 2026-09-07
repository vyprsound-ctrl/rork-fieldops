import Foundation

nonisolated enum NotificationChannel: String, Codable, Sendable {
    case sms
    case email
    case push

    var title: String {
        switch self {
        case .sms: return "SMS"
        case .email: return "Email"
        case .push: return "Push"
        }
    }
}

nonisolated enum NotificationStatus: String, Codable, Sendable {
    case queued
    case sent
    case delivered
    case failed

    var title: String {
        switch self {
        case .queued: return "Queued"
        case .sent: return "Sent"
        case .delivered: return "Delivered"
        case .failed: return "Failed"
        }
    }
}

/// One delivery attempt, whatever the channel.
///
/// SMS, email and push all live here. The push-only fields below are null on
/// every customer-facing SMS and email row, which is exactly how the database
/// models it — there is no second notification table anywhere in the system.
nonisolated struct AppNotification: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let companyID: String
    var channel: NotificationChannel
    var template: String
    var recipient: String
    var jobID: String?
    var customerID: String?
    var invoiceID: String?
    var status: NotificationStatus
    var providerReference: String?
    var sentAt: Date?
    var deliveredAt: Date?
    var failureReason: String?

    // MARK: Push only

    /// The staff member this notification is addressed to. Nil for customer
    /// SMS and email, which are addressed to a phone number or an address.
    var targetUserID: String?
    /// The device row this attempt was aimed at. Nil when the person had no
    /// registered device, in which case the attempt is recorded as failed.
    var pushDeviceID: String?
    var title: String?
    var body: String?
    /// Where a tap should land, e.g. `tradedesk://job/<id>`.
    var deepLink: String?
    var createdAt: Date = Date()
}
