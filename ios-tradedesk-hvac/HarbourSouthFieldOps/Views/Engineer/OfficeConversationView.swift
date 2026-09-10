import SwiftUI

/// One conversation with the office.
///
/// Two-way, company-scoped, and nothing more. The reply box is the whole
/// interface: no attachments panel, no formatting, no presence. An engineer
/// sends, the office is alerted, the office replies, the engineer is alerted.
struct OfficeConversationView: View {
    let threadID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = OfficeConversationViewModel()
    @FocusState private var isComposerFocused: Bool

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle(viewModel.state.value?.subject ?? "Message")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: threadID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading the conversation")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let conversation):
            loaded(conversation)
        }
    }

    private func loaded(_ conversation: OfficeConversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let number = conversation.jobNumber {
                        jobContext(number: number, jobID: conversation.jobID)
                    }

                    ForEach(conversation.messages) { message in
                        bubble(message).id(message.id)
                    }

                    if let error = viewModel.actionError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.red.opacity(0.08))
                            .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    }

                    Color.clear.frame(height: 4).id(Self.bottomAnchor)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom) { composer(conversation) }
            .onChange(of: conversation.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
            }
        }
    }

    private static let bottomAnchor = "conversation-bottom"

    private func jobContext(number: String, jobID: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wrench.adjustable")
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 30, height: 30)
                .background(Theme.primaryTint)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 1) {
                Text("About job \(number)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text("The office can see this job alongside your message.")
                    .font(.caption2)
                    .foregroundStyle(Theme.secondary)
            }

            Spacer(minLength: 0)

            if let jobID {
                NavigationLink(value: FieldJobRoute(jobID: jobID)) {
                    Text("Open")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.primaryTint)
                        .clipShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func bubble(_ message: OfficeMessageRow) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMine { Spacer(minLength: 40) }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 6) {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(message.isMine ? .white : Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !message.photoReferences.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.photoReferences, id: \.self) { reference in
                            JobPhotoThumbnail(reference: reference, size: 54)
                        }
                    }
                }

                Text("\(message.senderName) · \(message.timeLabel)")
                    .font(.caption2)
                    .foregroundStyle(message.isMine ? Color.white.opacity(0.75) : Theme.meta)
            }
            .padding(12)
            .background(message.isMine ? Theme.primary : Theme.surface)
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
            .overlay {
                if !message.isMine {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.border, lineWidth: 1)
                }
            }

            if !message.isMine { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.senderName), \(message.timeLabel). \(message.body)")
    }

    private func composer(_ conversation: OfficeConversation) -> some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message the office", text: $viewModel.draftBody, axis: .vertical)
                .font(.subheadline)
                .lineLimit(1...5)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Theme.border, lineWidth: 1)
                }
                .focused($isComposerFocused)

            Button {
                isComposerFocused = false
                guard let session else { return }
                Task {
                    await viewModel.send(gateway: env.gateway, session: session, threadID: threadID)
                }
            } label: {
                Group {
                    if viewModel.isSending {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(canSend ? Theme.primary : Theme.primary.opacity(0.35))
                .clipShape(.circle)
            }
            .buttonStyle(PressableTileStyle())
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var canSend: Bool {
        !viewModel.draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isSending
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(
            gateway: env.gateway,
            session: session,
            threadID: threadID,
            showLoading: showLoading
        )
    }
}

#Preview {
    NavigationStack {
        OfficeConversationView(threadID: "thread_1")
            .environment(AppEnvironment())
    }
}
