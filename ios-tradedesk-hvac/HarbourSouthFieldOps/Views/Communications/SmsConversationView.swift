import SwiftUI

/// One customer SMS conversation: the full two-way history and a reply box.
struct SmsConversationView: View {
    let conversationID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = SmsConversationViewModel()
    @State private var reportTarget: ReportTarget?

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView(message: "Loading conversation")
            case .failed(let error):
                ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
            case .loaded(let detail):
                loaded(detail)
            }
        }
        .background(Theme.canvas)
        .navigationTitle(viewModel.state.value?.recipientName ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: conversationID) { await reload() }
        .sheet(item: $reportTarget, onDismiss: {
            Task { await reload(showLoading: false) }
        }) { target in
            ReportMessageSheet(target: target)
        }
        .onReceive(NotificationCenter.default.publisher(for: .communicationsPushReceived)) { _ in
            Task { await reload(showLoading: false) }
        }
    }

    private func loaded(_ detail: SmsConversationDetail) -> some View {
        VStack(spacing: 0) {
            contextBar(detail.conversation)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if detail.messages.isEmpty {
                            EmptyStateView(symbolName: "message", title: "No messages yet",
                                           message: "Messages to and from this number appear here.")
                        }
                        if detail.messages.contains(where: { $0.direction == .inbound }) {
                            Label("Press and hold a customer's text to report it.", systemImage: "hand.raised")
                                .font(.caption2)
                                .foregroundStyle(Theme.meta)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        ForEach(detail.messages) { message in
                            if message.direction == .inbound {
                                SmsBubble(message: message)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            reportTarget = ReportTarget(
                                                messageID: message.id,
                                                kind: .sms,
                                                excerpt: message.body,
                                                senderUserID: nil,
                                                senderName: detail.recipientName
                                            )
                                        } label: {
                                            Label("Report message", systemImage: "flag")
                                        }
                                    }
                                    .id(message.id)
                            } else {
                                SmsBubble(message: message).id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.margin)
                    .padding(.vertical, 12)
                }
                .onAppear { proxy.scrollTo(detail.messages.last?.id, anchor: .bottom) }
                .onChange(of: detail.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(detail.messages.last?.id, anchor: .bottom) }
                }
            }
            .refreshable { await reload(showLoading: false) }
            composer(detail.conversation)
        }
    }

    private func contextBar(_ conversation: SmsConversationRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "phone.fill").font(.caption).foregroundStyle(Theme.primary)
            Text(PhoneFormatting.pretty(conversation.phone)).font(.footnote.monospacedDigit()).foregroundStyle(Theme.secondary)
            Spacer()
            if let customerID = conversation.customerID {
                NavigationLink(value: AppRoute.customer(customerID)) {
                    Label("Customer", systemImage: "person.fill").font(.caption.weight(.semibold))
                }
            }
            if let jobID = conversation.jobID, let number = conversation.jobNumber {
                NavigationLink(value: AppRoute.job(jobID)) {
                    Label(number, systemImage: "briefcase.fill").font(.caption.weight(.semibold))
                }
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }

    @ViewBuilder
    private func composer(_ conversation: SmsConversationRow) -> some View {
        VStack(spacing: 6) {
            if conversation.optedOut {
                Label("This customer replied STOP. They can't receive texts until they reply START.", systemImage: "hand.raised.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if conversation.customerID == nil {
                Label("This number isn't on a customer record. Add it to a customer to reply.", systemImage: "person.crop.circle.badge.questionmark")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if session?.can(.smsCreditsConsume) == true {
                if let error = viewModel.error {
                    Text(error).font(.caption).foregroundStyle(Theme.red).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Text message", text: $viewModel.reply, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Theme.surface)
                        .clipShape(.rect(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
                        .accessibilityIdentifier("sms.reply.field")
                    Button {
                        guard let session else { return }
                        Task { await viewModel.send(gateway: env.gateway, session: session) }
                    } label: {
                        Group {
                            if viewModel.isSending { ProgressView().tint(.white) } else { Image(systemName: "arrow.up") }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Theme.accent)
                        .clipShape(.circle)
                    }
                    .disabled(viewModel.isSending || viewModel.reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send")
                }
                if !viewModel.reply.isEmpty {
                    let count = viewModel.replySegments
                    Text("\(count.segments) segment\(count.segments == 1 ? "" : "s") · \(count.credits) credit\(count.credits == 1 ? "" : "s")")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(count.segments > 1 ? Theme.amber : Theme.meta)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, conversationID: conversationID, showLoading: showLoading)
    }
}

/// One SMS bubble. Inbound on the left, outbound on the right.
struct SmsBubble: View {
    let message: SmsThreadMessage

    private var outbound: Bool { message.direction == .outbound }

    var body: some View {
        HStack {
            if outbound { Spacer(minLength: 44) }
            VStack(alignment: outbound ? .trailing : .leading, spacing: 4) {
                Text(message.kindTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.meta)
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(outbound ? Color.white : Theme.ink)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(outbound ? AnyShapeStyle(Theme.primary.gradient) : AnyShapeStyle(Theme.surface))
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: outbound ? 18 : 5,
                                                      bottomTrailingRadius: outbound ? 5 : 18, topTrailingRadius: 18))
                    .overlay {
                        if !outbound {
                            UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 5, bottomTrailingRadius: 18, topTrailingRadius: 18)
                                .stroke(Theme.border, lineWidth: 1)
                        }
                    }
                HStack(spacing: 4) {
                    Text(Formatters.shortDayAndTime(message.at))
                    if outbound {
                        Text("·")
                        Text(message.statusLabel).foregroundStyle(message.statusTone == .danger ? Theme.red : Theme.meta)
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.meta)
            }
            if !outbound { Spacer(minLength: 44) }
        }
    }
}
