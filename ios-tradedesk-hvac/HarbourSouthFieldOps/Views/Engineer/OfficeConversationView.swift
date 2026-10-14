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
/// An attached image is stored as a `job_photos` row and then referenced by the
/// message. On a job-linked conversation that row carries the job too, so the
/// photo a worker sends the office becomes part of that job's permanent record
/// without anybody uploading it twice, and it inherits the job's company
/// scoping rather than needing a second security model.
///
/// GENERAL CONVERSATIONS CARRY IMAGES TOO
/// A conversation about no job anchors its images to the thread instead. The
/// attachment control is therefore offered on EVERY conversation — it is never
/// conditioned on the job, in either direction, for either role.
struct OfficeConversationView: View {
    let threadID: String

    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = OfficeConversationViewModel()
    @FocusState private var isComposerFocused: Bool
    /// The chat photo open full screen, if any.
    @State private var viewingPhoto: ViewedPhoto?
    /// The message being reported, if the report sheet is open.
    @State private var reportTarget: ReportTarget?
    /// Team members (lowercased ids) the signed-in person has blocked.
    @State private var blockedUserIDs: Set<String> = []
    /// Hidden messages the person chose to show anyway, one at a time.
    @State private var revealedMessageIDs: Set<String> = []
    @State private var blockCandidate: ChatPerson?
    @State private var safetyError: String?
    @State private var safetyNotice: String?

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
        .task(id: threadID) {
            await reload()
            await loadBlocks()
        }
        .toolbar {
            if let people = viewModel.state.value.map(otherPeople), !people.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    safetyMenu(people)
                }
            }
        }
        .sheet(item: $reportTarget) { target in
            ReportMessageSheet(target: target) { didBlock in
                if didBlock, let id = target.senderUserID {
                    blockedUserIDs.insert(id.lowercased())
                }
            }
        }
        .confirmationDialog(
            "Block \(blockCandidate?.name ?? "this person")?",
            isPresented: Binding(get: { blockCandidate != nil }, set: { if !$0 { blockCandidate = nil } }),
            titleVisibility: .visible,
            presenting: blockCandidate
        ) { person in
            Button("Block \(person.name)", role: .destructive) {
                Task { await block(person) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Their chat messages will be hidden from you and your company's admins will be told so they can review. Job assignments still reach you. You can unblock any time.")
        }
        .sensoryFeedback(.success, trigger: safetyNotice)
        // The SAME viewer the job screen uses — one implementation, one
        // loading path (`jobMediaURL`), so a job-chat photo opened here is
        // byte-for-byte the image the job page shows.
        .fullScreenCover(item: $viewingPhoto) { photo in
            JobPhotoViewer(
                reference: photo.reference,
                title: "Photo",
                subtitle: photo.subtitle
            )
        }
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

                    safetyHint

                    ForEach(conversation.messages) { message in
                        messageView(message).id(message.id)
                    }

                    if let notice = safetyNotice {
                        Label(notice, systemImage: "checkmark.shield.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.green)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.green.opacity(0.08))
                            .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    }

                    if let error = safetyError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(Theme.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.red.opacity(0.08))
                            .clipShape(.rect(cornerRadius: Theme.cardRadius))
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

    // MARK: - Safety (report / block)

    /// A person in this conversation other than the signed-in user.
    struct ChatPerson: Identifiable, Hashable {
        let id: String
        let name: String
    }

    private func otherPeople(_ conversation: OfficeConversation) -> [ChatPerson] {
        var seen = Set<String>()
        var people: [ChatPerson] = []
        for message in conversation.messages where !message.isMine {
            guard let id = message.senderUserID?.lowercased(), !seen.contains(id) else { continue }
            seen.insert(id)
            people.append(ChatPerson(id: id, name: message.senderName))
        }
        return people
    }

    private func isBlocked(_ message: OfficeMessageRow) -> Bool {
        guard !message.isMine, let id = message.senderUserID?.lowercased() else { return false }
        return blockedUserIDs.contains(id)
    }

    private var safetyHint: some View {
        Label("Press and hold a message to report it or block the sender.", systemImage: "hand.raised")
            .font(.caption2)
            .foregroundStyle(Theme.meta)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityIdentifier("chat.safetyHint")
    }

    private func safetyMenu(_ people: [ChatPerson]) -> some View {
        Menu {
            ForEach(people) { person in
                if blockedUserIDs.contains(person.id) {
                    Button {
                        Task { await unblock(person) }
                    } label: {
                        Label("Unblock \(person.name)", systemImage: "person.crop.circle.badge.checkmark")
                    }
                } else {
                    Button(role: .destructive) {
                        blockCandidate = person
                    } label: {
                        Label("Block \(person.name)", systemImage: "person.crop.circle.badge.xmark")
                    }
                }
            }
            Divider()
            Text("To report a message, press and hold it.")
        } label: {
            Image(systemName: "exclamationmark.shield")
        }
        .tint(Theme.primary)
        .accessibilityLabel("Report or block")
        .accessibilityIdentifier("chat.safetyMenu")
    }

    @ViewBuilder
    private func messageView(_ message: OfficeMessageRow) -> some View {
        if isBlocked(message) && !revealedMessageIDs.contains(message.id) {
            hiddenBubble(message)
        } else if message.isMine {
            bubble(message)
        } else {
            bubble(message)
                .contextMenu {
                    Button(role: .destructive) {
                        reportTarget = target(for: message)
                    } label: {
                        Label("Report message", systemImage: "flag")
                    }
                    if let id = message.senderUserID?.lowercased() {
                        let person = ChatPerson(id: id, name: message.senderName)
                        if blockedUserIDs.contains(id) {
                            Button {
                                Task { await unblock(person) }
                            } label: {
                                Label("Unblock \(message.senderName)", systemImage: "person.crop.circle.badge.checkmark")
                            }
                        } else {
                            Button(role: .destructive) {
                                blockCandidate = person
                            } label: {
                                Label("Block \(message.senderName)", systemImage: "person.crop.circle.badge.xmark")
                            }
                        }
                    }
                }
        }
    }

    private func hiddenBubble(_ message: OfficeMessageRow) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "eye.slash")
                .font(.footnote)
                .foregroundStyle(Theme.meta)
            VStack(alignment: .leading, spacing: 2) {
                Text("Message from someone you blocked")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                Text(message.timeLabel)
                    .font(.caption2)
                    .foregroundStyle(Theme.meta)
            }
            Spacer(minLength: 0)
            Button("Show") {
                withAnimation(.snappy) { _ = revealedMessageIDs.insert(message.id) }
            }
            .font(.caption.weight(.semibold))
            .tint(Theme.primary)
        }
        .padding(12)
        .background(Theme.canvas)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .padding(.trailing, 40)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.hiddenMessage")
    }

    private func target(for message: OfficeMessageRow) -> ReportTarget {
        ReportTarget(
            messageID: message.id,
            kind: .office,
            excerpt: message.body,
            senderUserID: message.senderUserID,
            senderName: message.senderName
        )
    }

    private func loadBlocks() async {
        guard let session else { return }
        blockedUserIDs = (try? await env.gateway.blockedChatUserIDs(session: session)) ?? []
    }

    private func block(_ person: ChatPerson) async {
        guard let session else { return }
        safetyError = nil
        do {
            try await env.gateway.blockChatUser(session: session, userID: person.id, reason: .other, details: nil)
            withAnimation(.snappy) {
                _ = blockedUserIDs.insert(person.id)
                safetyNotice = "You blocked \(person.name). Their chat messages are hidden from you."
            }
        } catch {
            safetyError = error.localizedDescription
        }
    }

    private func unblock(_ person: ChatPerson) async {
        guard let session else { return }
        safetyError = nil
        do {
            try await env.gateway.unblockChatUser(session: session, userID: person.id)
            withAnimation(.snappy) {
                _ = blockedUserIDs.remove(person.id)
                safetyNotice = "You unblocked \(person.name)."
            }
        } catch {
            safetyError = error.localizedDescription
        }
    }

    private func bubble(_ message: OfficeMessageRow) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMine { Spacer(minLength: 40) }

            VStack(alignment: message.isMine ? .trailing : .leading, spacing: 6) {
                // An image-only message has no text at all. Rendering an empty
                // `Text` would leave a blank line above the photo.
                if !message.body.isEmpty {
                    Text(message.body)
                        .font(.subheadline)
                        .foregroundStyle(message.isMine ? .white : Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !message.photoReferences.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(message.photoReferences, id: \.self) { reference in
                            photoButton(reference, in: message)
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
        // `.contain`, not `.combine`: combining folded the photos into one
        // static element, so neither VoiceOver nor a test could reach them as
        // the buttons they now are. Each photo announces itself instead.
        .accessibilityElement(children: .contain)
    }

    /// One chat photo, and the tap target for its full-size view.
    ///
    /// THE DEFECT THIS FIXES: the thumbnail used to be rendered bare, with no
    /// action and no viewer, so a photo in a conversation could be seen but
    /// never inspected. It is now a button onto the job screen's viewer.
    ///
    /// Deliberately NOT conditioned on who sent it, on the role, or on the
    /// thread having a job: the recipient needs to read a rating plate far
    /// more than the sender does. Only a reference with no file behind it is
    /// inert — the same rule the job page applies, so the viewer never opens
    /// onto nothing.
    private func photoButton(_ reference: String, in message: OfficeMessageRow) -> some View {
        let hasImage = JobMediaReference.parse(reference).hasImage
        return Button {
            guard hasImage else { return }
            viewingPhoto = ViewedPhoto(
                reference: reference,
                subtitle: "\(message.senderName) · \(message.timeLabel)"
            )
        } label: {
            JobPhotoThumbnail(reference: reference, size: 54)
                // The whole visible square is the target, and a filled image's
                // overflow can never steal a tap meant for its neighbour.
                .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(PressableTileStyle())
        .disabled(!hasImage)
        .accessibilityLabel(message.isMine ? "Your photo" : "Photo from \(message.senderName)")
        .accessibilityHint(hasImage ? "Opens the photo full size" : "No image file is attached")
        .accessibilityIdentifier("chat.photo")
    }

    /// What the full-screen viewer is showing.
    private struct ViewedPhoto: Identifiable {
        let reference: String
        let subtitle: String
        var id: String { reference }
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
                // Offered on EVERY conversation, job-linked or not, to both
                // sides. A general thread files its images against the thread;
                // a job thread files them against the job as well, so the same
                // single upload is the attachment and the job's evidence.
                MessagePhotoPicker(
                    onPicked: { uploads in
                        viewModel.pendingUploads.append(contentsOf: uploads)
                    },
                    isDisabled: viewModel.isSending
                )

                TextField(placeholder, text: $viewModel.draftBody, axis: .vertical)
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
                            // Taken from the conversation, so an image can never
                            // be filed against a job this thread is not about.
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
                    .background(viewModel.canSend ? Theme.primary : Theme.primary.opacity(0.35))
                    .clipShape(.circle)
                }
                .buttonStyle(PressableTileStyle())
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send message")
                .accessibilityIdentifier("composer.send")
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    /// Says what the box is for in the sender's own terms. An office user
    /// messaging an engineer is not "messaging the office".
    private var placeholder: String {
        usesFieldShell ? "Message the office" : "Message your engineer"
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
