import SwiftUI

/// "Communications" on a customer, and "Messages" on a job: the chronological
/// SMS history (sent and received) plus the one-tap operational actions.
struct CommunicationHistorySection: View {
    let title: String
    let customerID: String
    let customerName: String
    var jobID: String?
    var context: SmsMessageContext
    var quickActions: [SmsMessageKind] = []
    var hasPhone: Bool = true

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = CommunicationHistoryViewModel()
    @State private var composing: SmsMessageKind?

    private var session: TenantSession? { env.activeSession }
    private var canSend: Bool { session?.can(.smsCreditsConsume) == true && hasPhone && session?.canMutateWorkspace == true }
    private var canRead: Bool { session?.can(.smsCreditsConsume) == true || session?.can(.smsLedgerRead) == true }

    var body: some View {
        if canRead || canSend {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).sectionLabelStyle()
                    if let conversation = viewModel.messages.last?.conversationID {
                        NavigationLink(value: AppRoute.smsConversation(conversation)) {
                            Text("Open conversation").font(.caption.weight(.semibold))
                        }
                        .accessibilityIdentifier("history.openConversation")
                    }
                }

                if canSend {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            actionChip(context == .job ? "Message Customer" : "Send SMS", symbol: "message.fill", primary: true) {
                                composing = context == .job ? .generalJobUpdate : .generalCustomerMessage
                            }
                            .accessibilityIdentifier("history.sendSms")
                            ForEach(quickActions) { kind in
                                actionChip(kind.title, symbol: kind.symbolName, primary: false) { composing = kind }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    if viewModel.messages.isEmpty {
                        Text(viewModel.hasLoaded ? "No texts yet." : "Loading…")
                            .font(.footnote).foregroundStyle(Theme.meta)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    } else {
                        ForEach(Array(viewModel.messages.suffix(8).enumerated()), id: \.element.id) { index, message in
                            historyRow(message)
                            if index < min(viewModel.messages.count, 8) - 1 { Divider().padding(.leading, 50) }
                        }
                    }
                }
                .cardSurface()
            }
            .task(id: "\(customerID)-\(jobID ?? "")") { await reload() }
            .sheet(item: $composing, onDismiss: { Task { await reload() } }) { kind in
                SendSmsSheet(customerID: customerID, customerName: customerName, jobID: jobID,
                             context: kind.context == .customer ? .customer : context, initialKind: kind)
            }
        }
    }

    private func actionChip(_ title: String, symbol: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primary ? Color.white : Theme.primary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(primary ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.primaryTint))
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func historyRow(_ message: SmsThreadMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.direction == .inbound ? "arrow.down.left.circle.fill" : "arrow.up.right.circle.fill")
                .font(.title3)
                .foregroundStyle(message.direction == .inbound ? Theme.accent : Theme.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(message.kindTitle).font(.caption.weight(.semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text(Formatters.shortDayAndTime(message.at)).font(.caption2).foregroundStyle(Theme.meta)
                }
                Text(message.body).font(.footnote).foregroundStyle(Theme.secondary).lineLimit(3)
                if message.direction == .outbound {
                    Text(message.statusLabel).font(.caption2)
                        .foregroundStyle(message.statusTone == .danger ? Theme.red : Theme.meta)
                }
            }
        }
        .padding(12)
    }

    private func reload() async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session,
                             customerID: context == .job ? nil : customerID, jobID: context == .job ? jobID : nil)
    }
}

/// The quote / invoice "Text it" card.
struct DocumentSmsCard: View {
    let customerID: String
    let customerName: String
    var quoteID: String?
    var invoiceID: String?
    let kinds: [SmsMessageKind]

    @Environment(AppEnvironment.self) private var env
    @State private var composing: SmsMessageKind?

    var body: some View {
        if env.activeSession?.can(.smsCreditsConsume) == true, env.activeSession?.canMutateWorkspace == true {
            VStack(alignment: .leading, spacing: 8) {
                Text("Text the customer").sectionLabelStyle()
                VStack(spacing: 0) {
                    ForEach(Array(kinds.enumerated()), id: \.element.id) { index, kind in
                        Button { composing = kind } label: {
                            HStack(spacing: 12) {
                                Image(systemName: kind.symbolName)
                                    .font(.footnote).foregroundStyle(Theme.primary)
                                    .frame(width: 32, height: 32).background(Theme.primaryTint).clipShape(.rect(cornerRadius: 8))
                                Text(title(kind)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.meta)
                            }
                            .padding(.horizontal, 14)
                            .frame(minHeight: Theme.minTap)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("docsms.\(kind.rawValue)")
                        if index < kinds.count - 1 { Divider().padding(.leading, 58) }
                    }
                }
                .cardSurface()
            }
            .sheet(item: $composing) { kind in
                SendSmsSheet(customerID: customerID, customerName: customerName, quoteID: quoteID, invoiceID: invoiceID,
                             context: kind.context, initialKind: kind)
            }
        }
    }

    private func title(_ kind: SmsMessageKind) -> String {
        switch kind {
        case .quoteSent: return "Send Quote by SMS"
        case .invoiceSent: return "Send Invoice by SMS"
        default: return kind.title
        }
    }
}
