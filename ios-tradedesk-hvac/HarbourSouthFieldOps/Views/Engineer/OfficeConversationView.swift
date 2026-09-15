import SwiftUI
import UIKit

/// One conversation with the office.
///
/// Two-way, company-scoped, and nothing more. No formatting, no presence, no
/// reactions. An engineer sends, the office is alerted, the office replies, the
/// engineer is alerted — plus photographs, because a picture of a corroded
/// condenser settles a question that three messages cannot.
///
/// PHOTOGRAPHS ARE JOB EVIDENCE FIRST
/// An attached image is stored as a `job_photos` row against the conversation's
/// job and then referenced by the message. That is deliberate: the photo a
/// worker sends the office becomes part of the job's permanent record without
/// anybody uploading it twice, and it inherits the job's company scoping rather
/// than needing a second security model. It also means attachments are only
/// offered on a job-linked thread — `job_photos.job_id` is NOT NULL, so there
/// is nowhere to legitimately put an image from a general enquiry.
struct OfficeConversationView: View {
    let threadID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = OfficeConversationViewModel()
    @State private var isAttachingPhotos: Bool = false
    @FocusState private var isComposerFocused: Bool

    private var session: TenantSession? { env.activeSession }

    /// Office roles open the full job record; a field worker opens their own
    /// job screen. Both are the real destination for the job in question.
    private var usesFieldShell: Bool { session?.role.usesFieldShell ?? false }

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

            // THE DEFECT THIS FIXES: this button always pushed a
            // `FieldJobRoute`, but neither stack that hosts this screen had a
            // `navigationDestination(for: FieldJobRoute.self)` — the field
            // worker's messages tab registered only its thread route, and the
            // office reaches this screen through More, which speaks `AppRoute`.
            // SwiftUI had nothing to push, so a correct job id produced a
            // button that did nothing at all in BOTH roles.
            //
            // Each shell now gets the route type it actually understands.
            if let jobID {
                if usesFieldShell {
                    NavigationLink(value: FieldJobRoute(jobID: jobID)) {
                        openLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open job \(number)")
                } else {
                    NavigationLink(value: AppRoute.job(jobID)) {
                        openLabel
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open job \(number)")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var openLabel: some View {
        Text("Open")
            .font(.caption.weight(.bold))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.primaryTint)
            .clipShape(.capsule)
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
        VStack(spacing: 8) {
            if !viewModel.pendingUploads.isEmpty {
                attachmentTray
            }

            if let progress = viewModel.sendProgress {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(progress)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                    Spacer(minLength: 0)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                // Only offered on a job-linked thread: an attachment is stored
                // as evidence against that job, and `job_photos.job_id` cannot
                // be null, so there is nowhere to file a photo from a general
                // enquiry. Hiding the control beats failing after the fact.
                if conversation.jobID != nil {
                    Button {
                        isComposerFocused = false
                        isAttachingPhotos = true
                    } label: {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.primary)
                            .frame(width: 44, height: 44)
                            .background(Theme.primaryTint)
                            .clipShape(.circle)
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(viewModel.isSending)
                    .accessibilityLabel("Attach photos")
                }

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
                        await viewModel.send(
                            gateway: env.gateway,
                            session: session,
                            threadID: threadID,
                            jobID: conversation.jobID
                        )
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
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
        .sheet(isPresented: $isAttachingPhotos) {
            AddPhotoSheet { uploads in
                viewModel.pendingUploads.append(contentsOf: uploads)
            }
        }
    }

    /// The images waiting to go, each removable before sending.
    private var attachmentTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(viewModel.pendingUploads) { upload in
                    ZStack(alignment: .topTrailing) {
                        if let image = UIImage(data: upload.data) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 10))
                        }

                        Button {
                            viewModel.pendingUploads.removeAll { $0.id == upload.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 17))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.black.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                        .accessibilityLabel("Remove \(upload.kind.title) photo")
                    }
                    .padding(.top, 5)
                    .padding(.trailing, 5)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(height: 68)
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
