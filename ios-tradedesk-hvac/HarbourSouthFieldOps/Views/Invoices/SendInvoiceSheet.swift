import SwiftUI

/// Sends an invoice to the customer by email, SMS or both.
///
/// The sheet promises nothing on the server's behalf. It shows who the message
/// would go to, sends, and then reports exactly what the server said happened —
/// including "nothing was delivered, no provider is configured", which is
/// reported as a failure rather than dressed up as a send.
struct SendInvoiceSheet: View {
    let invoiceNumber: String
    let sharing: InvoiceSharing
    let isSending: Bool
    let outcome: InvoiceSendOutcome?
    let onSend: (Set<NotificationChannel>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var wantsEmail: Bool = true
    @State private var wantsSMS: Bool = false

    private var hasEmail: Bool { (sharing.emailRecipient?.isEmpty == false) }
    private var hasSMS: Bool { (sharing.smsRecipient?.isEmpty == false) }

    private var channels: Set<NotificationChannel> {
        var selected: Set<NotificationChannel> = []
        if wantsEmail, hasEmail { selected.insert(.email) }
        if wantsSMS, hasSMS { selected.insert(.sms) }
        return selected
    }

    var body: some View {
        NavigationStack {
            Form {
                if let outcome {
                    resultSection(outcome)
                } else {
                    recipientSection
                    linkSection
                    paymentSection
                }
            }
            .navigationTitle(outcome == nil ? "Send \(invoiceNumber)" : "Send result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(outcome == nil ? "Cancel" : "Done") { dismiss() }
                }
                if outcome == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSending ? "Sending…" : "Send") {
                            onSend(channels)
                        }
                        .disabled(channels.isEmpty || isSending)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationContentInteraction(.scrolls)
        .onAppear {
            wantsEmail = hasEmail
            wantsSMS = hasEmail ? false : hasSMS
        }
    }

    // MARK: - Before sending

    private var recipientSection: some View {
        Section {
            Toggle(isOn: $wantsEmail) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Email", systemImage: "envelope.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(sharing.emailRecipient ?? "No email address on the billing contact")
                        .font(.caption)
                        .foregroundStyle(hasEmail ? Theme.secondary : Theme.red)
                }
            }
            .disabled(!hasEmail)

            Toggle(isOn: $wantsSMS) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("SMS", systemImage: "message.fill")
                        .font(.subheadline.weight(.semibold))
                    Text(sharing.smsRecipient ?? "No mobile number on the billing contact")
                        .font(.caption)
                        .foregroundStyle(hasSMS ? Theme.secondary : Theme.red)
                }
            }
            .disabled(!hasSMS)
        } header: {
            Text("Send to")
        } footer: {
            Text("Sending happens on the server, never from this device — no email or SMS credentials are shipped in the app. Every attempt is recorded against this invoice with its real outcome.")
        }
    }

    private var linkSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Your customer gets a private link to this invoice.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                Text("The link is a random code. It contains no account number, customer name or invoice reference, and you can revoke it at any time.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }
            .padding(.vertical, 2)
        } header: {
            Text("What they receive")
        }
    }

    @ViewBuilder
    private var paymentSection: some View {
        Section {
            if sharing.paymentLink.isConfigured {
                Label(
                    "They'll see a Pay online button through to \(sharing.paymentLink.displayHost ?? "your payment page").",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(Theme.green)
            } else {
                Label(
                    "No payment link is set, so no payment button is shown. They can still read the invoice and pay you as usual.",
                    systemImage: "info.circle.fill"
                )
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("Paying")
        } footer: {
            Text("Payment goes straight from your customer to your own provider. Harbour South isn't part of the transaction and won't know it happened — record the payment here once the money reaches you.")
        }
    }

    // MARK: - After sending

    private func resultSection(_ outcome: InvoiceSendOutcome) -> some View {
        Section {
            ForEach(outcome.results) { result in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: result.delivered ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(result.delivered ? Theme.green : Theme.red)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(result.channel.title) · \(result.recipient)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(result.delivered ? Theme.secondary : Theme.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(outcome.didDeliverAnything ? "Sent" : "Nothing was sent")
        } footer: {
            Text(
                outcome.missingProviders.isEmpty
                    ? "Each attempt above is recorded against this invoice."
                    : "No message was delivered. The delivery provider hasn't been configured for this project yet, so the attempt was recorded as failed rather than reported as sent."
            )
        }
    }
}

#Preview {
    SendInvoiceSheet(
        invoiceNumber: "INV-1176",
        sharing: InvoiceSharing(
            shareURL: nil,
            canShare: true,
            blockedReason: nil,
            canSend: true,
            emailRecipient: "billing@coastalproperties.example",
            smsRecipient: "(813) 555-0142",
            paymentLink: PaymentLinkSettings(url: nil, displayHost: nil, canManage: true),
            deliveries: [],
            isSimulated: true
        ),
        isSending: false,
        outcome: nil
    ) { _ in }
}
