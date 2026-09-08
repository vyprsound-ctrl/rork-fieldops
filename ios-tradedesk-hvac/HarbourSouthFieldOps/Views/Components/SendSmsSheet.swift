import SwiftUI

/// Sends one SMS to one customer.
///
/// Nothing here fires automatically. A customer who receives six unprompted
/// texts about one visit stops reading all of them, so every message is chosen
/// by a person, previewed in full, and costs a visible credit.
///
/// The send itself is a server operation: this sheet has no Twilio credential,
/// does not know the company's balance rules, and cannot decide that a message
/// was delivered. It shows what the server reports.
struct SendSmsSheet: View {
    let customerID: String
    let customerName: String
    var jobID: String?
    var invoiceID: String?
    /// Prefill context, so the drafted message reads like a person wrote it.
    var workerName: String?
    var whenLabel: String?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SmsCreditsViewModel()
    @State private var template: SmsTemplate = .jobConfirmation
    /// Deliberately not called `body` — that name belongs to `View`.
    @State private var messageText: String = ""
    @State private var sent = false

    private var session: TenantSession? { env.activeSession }

    /// The sender line the customer will actually read, taken from the company
    /// record rather than from whichever screen opened this sheet.
    private var companyName: String {
        viewModel.state.value?.companyName.tidied ?? ""
    }

    private var characterCount: Int { messageText.count }
    /// A single SMS is 160 GSM-7 characters; beyond that the carrier bills more
    /// segments. The sender should know before they send, not after.
    private var segmentCount: Int { max(1, Int(ceil(Double(max(characterCount, 1)) / 160.0))) }

    var body: some View {
        NavigationStack {
            Group {
                if sent {
                    confirmation
                } else {
                    form
                }
            }
            .background(Theme.canvas)
            .navigationTitle(sent ? "Message sent" : "Send message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
                if !sent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { Task { await send() } }
                            .disabled(!canSend)
                    }
                }
            }
        }
        .task {
            await load()
            // Re-drafted once the company name is known, so the first template
            // the user sees carries the real sender rather than a placeholder.
            if !sent { applyTemplate(template) }
        }
    }

    private var canSend: Bool {
        guard !viewModel.isWorking else { return false }
        guard !messageText.tidied.isEmpty else { return false }
        guard let overview = viewModel.state.value else { return false }
        return overview.canSend && overview.balance > 0
    }

    // MARK: - Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recipientCard
                templatePicker
                messageEditor
                balanceNotice
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 16)
        }
    }

    private var recipientCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(customerName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("Goes to the mobile number on their record")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            }
            Spacer(minLength: 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message type")
                .sectionLabelStyle()

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                spacing: 8
            ) {
                ForEach(SmsTemplate.allCases, id: \.rawValue) { option in
                    Button {
                        template = option
                        applyTemplate(option)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.symbolName)
                                .font(.caption)
                            Text(option.title)
                                .font(.caption.weight(.medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(template == option ? Theme.primary : Theme.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(template == option ? Theme.primaryTint : Theme.surface)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(template == option ? Theme.primary.opacity(0.4) : Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var messageEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message")
                .sectionLabelStyle()

            TextEditor(text: $messageText)
                .font(.body)
                .foregroundStyle(Theme.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 130)
                .padding(10)
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )

            HStack {
                Text("\(characterCount) characters")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.meta)
                Spacer()
                Text(segmentCount == 1 ? "1 credit" : "\(segmentCount) parts")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(segmentCount > 1 ? Theme.amber : Theme.meta)
            }

            if segmentCount > 1 {
                Text("Longer messages are split by the carrier. Keep it under 160 characters to send as one.")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var balanceNotice: some View {
        if let overview = viewModel.state.value {
            if !overview.canSend {
                notice("Your role does not include sending messages.", tone: Theme.amber)
            } else if overview.balance <= 0 {
                notice("You have no SMS credits. Buy a bundle before sending.", tone: Theme.amber)
            } else {
                notice("\(overview.balance) credit\(overview.balance == 1 ? "" : "s") remaining.", tone: Theme.meta)
            }
        }

        if let error = viewModel.actionError {
            notice(error, tone: Theme.red)
        }
    }

    private func notice(_ text: String, tone: Color) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(tone)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Confirmation

    private var confirmation: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.green)

            Text("Message sent to \(customerName)")
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)

            // Deliberately not "delivered". The carrier has it; the handset may
            // not. Claiming delivery here would be a lie the app cannot back up.
            Text("The carrier has accepted it. Delivery is confirmed separately and shows in your message history.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let outcome = viewModel.lastOutcome {
                Text("\(outcome.creditsCharged) credit used · \(outcome.balance) remaining")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func applyTemplate(_ option: SmsTemplate) {
        let sender = companyName.tidied.isEmpty ? "We" : companyName.tidied
        messageText = option.draftBody(company: sender, worker: workerName, when: whenLabel)
    }

    private func load() async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session)
    }

    private func send() async {
        guard let session else { return }
        let draft = SmsSendDraft(
            customerID: customerID,
            jobID: jobID,
            invoiceID: invoiceID,
            template: template,
            body: messageText.tidied
        )
        let ok = await viewModel.send(gateway: env.gateway, session: session, draft: draft)
        if ok { withAnimation(.snappy) { sent = true } }
    }
}
