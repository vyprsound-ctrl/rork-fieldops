import SwiftUI

/// Sends (or schedules) one operational SMS to one customer.
///
/// The server renders the chosen template with its own values, counts the
/// segments, checks the subscription, the company's SMS status and the
/// customer's opt-out, and only then spends credit — so this sheet shows the
/// real recipient, the exact message and its credit cost before anything is
/// sent. It holds no Twilio credential and cannot decide delivery.
struct SendSmsSheet: View {
    let customerID: String
    let customerName: String
    var jobID: String?
    var quoteID: String?
    var invoiceID: String?
    var context: SmsMessageContext = .customer
    var initialKind: SmsMessageKind?
    /// Kept for source compatibility with earlier call sites.
    var workerName: String?
    var whenLabel: String?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: SmsComposerViewModel
    @State private var finished: Bool = false

    init(customerID: String, customerName: String, jobID: String? = nil, quoteID: String? = nil,
         invoiceID: String? = nil, context: SmsMessageContext = .customer, initialKind: SmsMessageKind? = nil,
         workerName: String? = nil, whenLabel: String? = nil) {
        self.customerID = customerID
        self.customerName = customerName
        self.jobID = jobID
        self.quoteID = quoteID
        self.invoiceID = invoiceID
        self.context = context
        self.initialKind = initialKind
        self.workerName = workerName
        self.whenLabel = whenLabel
        let first = initialKind ?? SmsMessageKind.offered(for: context).first ?? .customMessage
        _viewModel = State(initialValue: SmsComposerViewModel(kind: first))
    }

    private var session: TenantSession? { env.activeSession }
    private var kinds: [SmsMessageKind] { SmsMessageKind.offered(for: context) }

    private var draft: SmsComposeDraft {
        viewModel.draft(customerID: customerID, jobID: jobID, quoteID: quoteID, invoiceID: invoiceID, phone: nil)
    }

    private var blocker: String? {
        if let setup = viewModel.setup, !setup.friendly.canSend {
            switch setup.friendly {
            case .notSetUp: return "SMS isn't set up yet. The owner can set it up in More → SMS & Messaging."
            case .settingUp, .waitingApproval: return "Your SMS number is waiting for approval. You can send as soon as it's approved."
            default: return setup.attention ?? "SMS isn't available right now."
            }
        }
        return viewModel.preview?.blockerMessage
    }

    var body: some View {
        NavigationStack {
            Group {
                if finished, let outcome = viewModel.outcome {
                    confirmation(outcome)
                } else {
                    form
                }
            }
            .background(Theme.canvas)
            .navigationTitle(finished ? "Done" : "Text \(customerName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(finished ? "Close" : "Cancel") { dismiss() }
                }
            }
        }
        .task {
            guard let session else { return }
            await viewModel.load(gateway: env.gateway, session: session)
            await viewModel.refreshPreview(gateway: env.gateway, session: session, draft: draft)
        }
    }

    // MARK: Form

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                recipientCard
                if let blocker { notice(blocker, tone: Theme.amber, symbol: "exclamationmark.bubble.fill") }
                kindPicker
                editor
                if viewModel.kind.allowedVariables.contains(.eta) { etaField }
                scheduleCard
                previewCard
                if let error = viewModel.error { notice(error, tone: Theme.red, symbol: "xmark.octagon.fill") }
                sendButton
            }
            .padding(.horizontal, Theme.margin)
            .padding(.vertical, 14)
        }
    }

    private var recipientCard: some View {
        HStack(spacing: 12) {
            Text(String(customerName.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Theme.primary.gradient)
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(customerName).font(.headline).foregroundStyle(Theme.ink)
                Text(viewModel.preview.map { PhoneFormatting.pretty($0.recipient) } ?? "Their mobile number on file")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.secondary)
                    .accessibilityIdentifier("sms.compose.recipient")
            }
            Spacer()
            if let number = viewModel.setup?.displayNumber {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("From").font(.caption2).foregroundStyle(Theme.meta)
                    Text(number).font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(14)
        .cardSurface()
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Message").sectionLabelStyle()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(kinds) { kind in
                        Button {
                            viewModel.kind = kind
                            viewModel.applyTemplate()
                            refreshPreview()
                        } label: {
                            Label(kind.title, systemImage: kind.symbolName)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(viewModel.kind == kind ? Color.white : Theme.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(viewModel.kind == kind ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.primaryTint))
                                .clipShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sms.kind.\(kind.rawValue)")
                    }
                }
            }
            .contentMargins(.horizontal, 0)
            .sensoryFeedback(.selection, trigger: viewModel.kind)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $viewModel.body)
                .font(.body)
                .frame(minHeight: 120)
                .padding(10)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
                .accessibilityIdentifier("sms.compose.body")
                .onChange(of: viewModel.body) { _, _ in debouncePreview() }
            if !viewModel.kind.allowedVariables.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.kind.allowedVariables) { variable in
                            Button {
                                viewModel.body += (viewModel.body.hasSuffix(" ") || viewModel.body.isEmpty ? "" : " ") + variable.token
                            } label: {
                                Text("+ \(variable.label)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accentText)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(Theme.accentTint)
                                    .clipShape(.capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let problem = viewModel.localProblem {
                Text(problem).font(.caption).foregroundStyle(Theme.red)
            }
        }
    }

    private var etaField: some View {
        HStack {
            Image(systemName: "clock").foregroundStyle(Theme.primary)
            TextField("Arrival time, e.g. around 2:30 PM", text: $viewModel.eta)
                .onSubmit { refreshPreview() }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .cardSurface()
    }

    private var scheduleCard: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $viewModel.schedules.animation(.snappy)) {
                Label("Send later", systemImage: "calendar.badge.clock").font(.subheadline.weight(.semibold))
            }
            .tint(Theme.accent)
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            if viewModel.schedules {
                Divider()
                DatePicker("Send at", selection: $viewModel.scheduledFor,
                           in: Date().addingTimeInterval(120)...Date().addingTimeInterval(90 * 86_400))
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
            }
        }
        .cardSurface()
    }

    private var previewCard: some View {
        let segments = viewModel.preview?.segments ?? max(viewModel.estimate.segments, 1)
        let unicode = (viewModel.preview?.encoding ?? viewModel.estimate.encoding) == "UCS-2"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("What they'll receive").sectionLabelStyle()
                if viewModel.isPreviewing { ProgressView().controlSize(.mini) }
            }
            Text(viewModel.preview?.body ?? SmsTemplateValidator.estimate(viewModel.body))
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.primaryTint)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 4, bottomTrailingRadius: 16, topTrailingRadius: 16))
                .accessibilityIdentifier("sms.compose.preview")
            HStack(spacing: 8) {
                Label("\(segments) segment\(segments == 1 ? "" : "s")", systemImage: "square.stack.3d.up")
                Text("·")
                Text("\(segments) credit\(segments == 1 ? "" : "s")").fontWeight(.semibold)
                    .accessibilityIdentifier("sms.compose.credits")
                if unicode { Text("· emoji/special characters").foregroundStyle(Theme.amber) }
                Spacer()
                if let balance = viewModel.setup?.balance { Text("\(balance) left").foregroundStyle(Theme.meta) }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(segments > 1 ? Theme.amber : Theme.secondary)
            .contentTransition(.numericText())
            .animation(.snappy, value: segments)
        }
    }

    private var sendButton: some View {
        Button {
            guard let session else { return }
            Task {
                if await viewModel.send(gateway: env.gateway, session: session, draft: draft) {
                    withAnimation(.snappy) { finished = true }
                }
            }
        } label: {
            Group {
                if viewModel.isSending { ProgressView().tint(.white) }
                else { Label(viewModel.schedules ? "Schedule message" : "Send message", systemImage: viewModel.schedules ? "calendar.badge.plus" : "paperplane.fill").font(.headline) }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.accent.gradient)
            .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(PressableTileStyle())
        .disabled(viewModel.isSending || blocker != nil || viewModel.localProblem != nil
                  || viewModel.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        .opacity(blocker != nil ? 0.5 : 1)
        .sensoryFeedback(.success, trigger: finished)
        .accessibilityIdentifier("sms.compose.send")
    }

    private func notice(_ text: String, tone: Color, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tone)
            Text(text).font(.footnote).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tone.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: Confirmation

    private func confirmation(_ outcome: SmsDispatchOutcome) -> some View {
        VStack(spacing: 14) {
            Image(systemName: outcome.scheduled ? "calendar.badge.checkmark" : "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.green)
                .symbolEffect(.bounce, value: finished)
            Text(outcome.scheduled ? "Scheduled for \(customerName)" : "Sent to \(customerName)")
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
            Text(outcome.detail)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .multilineTextAlignment(.center)
            if outcome.sent {
                Text("\(outcome.creditsCharged) credit\(outcome.creditsCharged == 1 ? "" : "s") used\(outcome.balance.map { " · \($0) left" } ?? "")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.meta)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Preview refresh

    @State private var previewTask: Task<Void, Never>?

    private func refreshPreview() {
        guard let session else { return }
        previewTask?.cancel()
        previewTask = Task { await viewModel.refreshPreview(gateway: env.gateway, session: session, draft: draft) }
    }

    private func debouncePreview() {
        guard let session else { return }
        previewTask?.cancel()
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await viewModel.refreshPreview(gateway: env.gateway, session: session, draft: draft)
        }
    }
}
