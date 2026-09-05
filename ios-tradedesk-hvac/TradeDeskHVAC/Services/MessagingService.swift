import Foundation

nonisolated struct MessageReceipt: Hashable, Sendable {
    let providerReference: String
    let simulated: Bool
}

/// SMS delivery. Production will be a real SMS provider; credits are debited
/// through the SMS ledger, never a standalone balance field.
protocol SmsService: Sendable {
    var mode: ServiceMode { get }
    func send(to recipient: String, body: String) async throws -> MessageReceipt
}

/// DEVELOPMENT IMPLEMENTATION — nothing leaves the device.
struct MockSmsService: SmsService {
    let mode: ServiceMode = .simulated

    func send(to recipient: String, body: String) async throws -> MessageReceipt {
        try? await Task.sleep(for: .milliseconds(300))
        return MessageReceipt(providerReference: "SIMULATED-SM-\(Int.random(in: 1000...9999))", simulated: true)
    }
}

/// Email delivery. Production will be a transactional email provider.
protocol EmailService: Sendable {
    var mode: ServiceMode { get }
    func send(to recipient: String, subject: String, body: String) async throws -> MessageReceipt
}

/// DEVELOPMENT IMPLEMENTATION — nothing leaves the device.
struct MockEmailService: EmailService {
    let mode: ServiceMode = .simulated

    func send(to recipient: String, subject: String, body: String) async throws -> MessageReceipt {
        try? await Task.sleep(for: .milliseconds(300))
        return MessageReceipt(providerReference: "SIMULATED-EM-\(Int.random(in: 1000...9999))", simulated: true)
    }
}

// Push notifications live in `PushService.swift`: the contract grew past a
// single "did it register" boolean once permission state, token lifecycle and
// teardown became real, and it has no relationship to the customer messaging
// above beyond the word "send".
