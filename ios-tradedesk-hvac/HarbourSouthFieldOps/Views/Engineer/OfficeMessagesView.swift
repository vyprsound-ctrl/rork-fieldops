import SwiftUI

/// The engineer's conversations with the office.
///
/// Deliberately not a chat platform. There are no channels, no groups, no
/// reactions and no typing indicators — just the one thing a field engineer
/// actually needs on a cold morning: ask the office something, and see the
/// answer. Every conversation is company-scoped by the database, and an
/// engineer only ever sees their own.
struct OfficeMessagesView: View {
    @Bindable var viewModel: OfficeMessagesViewModel

    @Environment(AppEnvironment.self) private var env
    @State private var path = NavigationPath()
    @State private var isComposing: Bool = false

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle("Office")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: OfficeThreadRoute.self) { route in
                OfficeConversationView(threadID: route.threadID)
            }
            // A job-linked conversation offers to open that job. Without this
            // the "Open" button was a dead link: the button existed, the route
            // value was correct, but this stack had never been told what a
            // `FieldJobRoute` looks like, so SwiftUI had nothing to push.
            .navigationDestination(for: FieldJobRoute.self) { route in
                FieldWorkerJobView(jobID: route.jobID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isComposing = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .tint(Theme.primary)
                    .accessibilityLabel("New message to the office")
                }
            }
            .sheet(isPresented: $isComposing) {
                OfficeComposeSheet(jobID: nil, jobNumber: nil) { threadID in
                    Task {
                        await reload(showLoading: false)
                        path.append(OfficeThreadRoute(threadID: threadID))
                    }
                }
            }
        }
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading your messages")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let inbox):
            loaded(inbox)
        }
    }

    @ViewBuilder
    private func loaded(_ inbox: OfficeInbox) -> some View {
        if !inbox.isAvailable {
            ScrollView {
                EmptyStateView(
                    symbolName: "bubble.left.and.exclamationmark.bubble.right",
                    title: "Messaging isn't available here",
                    message: inbox.unavailableReason ?? "Sign in to your company account to message the office."
                )
                .cardSurface()
                .padding(Theme.margin)
            }
        } else if inbox.threads.isEmpty {
            ScrollView {
                VStack(spacing: 16) {
                    EmptyStateView(
                        symbolName: "bubble.left.and.bubble.right",
                        title: "No messages yet",
                        message: "Need a part, running late, or stuck on site? Tell the office here and they'll get an alert straight away.",
                        actionTitle: "New message",
                        action: { isComposing = true }
                    )
                    .cardSurface()
                }
                .padding(Theme.margin)
            }
            .refreshable { await reload(showLoading: false) }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if inbox.unreadCount > 0 {
                        Text(inbox.unreadCount == 1 ? "1 unread reply" : "\(inbox.unreadCount) unread replies")
                            .sectionLabelStyle()
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(inbox.threads.enumerated()), id: \.element.id) { index, thread in
                            NavigationLink(value: OfficeThreadRoute(threadID: thread.id)) {
                                threadRow(thread)
                            }
                            .buttonStyle(.plain)

                            if index < inbox.threads.count - 1 {
                                Divider().padding(.leading, 14)
                            }
                        }
                    }
                    .cardSurface()

                    Text("Messages stay inside your company. The office is alerted when you send, and you're alerted when they reply.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, Theme.margin)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .refreshable { await reload(showLoading: false) }
        }
    }

    private func threadRow(_ thread: OfficeThreadRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: thread.jobNumber == nil ? "bubble.left" : "wrench.adjustable")
                    .font(.footnote)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Theme.primaryTint)
                    .clipShape(.rect(cornerRadius: 9))

                if thread.isUnread {
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: 10, height: 10)
                        .offset(x: 3, y: -3)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(thread.subject)
                    .font(.subheadline.weight(thread.isUnread ? .bold : .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)

                Text(thread.preview)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text(thread.counterpartyName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.meta)
                    if let number = thread.jobNumber {
                        Text("· \(number)")
                            .font(.caption2)
                            .foregroundStyle(Theme.meta)
                    }
                    Spacer(minLength: 0)
                    Text(thread.timeLabel)
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(thread.subject). \(thread.preview). \(thread.isUnread ? "Unread." : "")"
        )
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

/// Route value for the office stack, kept separate from `AppRoute` so an
/// engineer's navigation can never resolve to an office-only screen.
nonisolated struct OfficeThreadRoute: Hashable, Sendable {
    let threadID: String
}

#Preview {
    OfficeMessagesView(viewModel: OfficeMessagesViewModel())
        .environment(AppEnvironment())
}
