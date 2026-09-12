import SwiftUI

/// ISSUE #13 — the office side of the messaging system.
///
/// THE DEFECT: field workers could message the office, and the database already
/// delivered those threads to office roles — the `office_threads_select` policy
/// reads `(company_id = current_company_id()) AND (engineer_user_id = auth.uid()
/// OR is_office_user())`, so an owner or admin has always been able to read
/// every thread in their company. What was missing was any way to *reach* them:
/// the only inbox screen lived inside the field worker's own tab shell. Messages
/// arrived, push notifications fired, and the owner had nowhere to open them.
///
/// THE FIX: this screen, reachable from More. It is the same `officeInbox()`
/// call, the same `OfficeInbox` projection, the same `OfficeConversationView`
/// for replying, and the same `office_threads` tables. No second messaging
/// system, no new gateway method, no new database object.
///
/// WHY IT IS NOT `OfficeMessagesView`: that screen owns a `NavigationStack` and
/// its own private route type, because it is the root of a tab. This one is
/// pushed onto an existing stack, so it navigates with `AppRoute.message`,
/// which `RouteDestinationView` already resolves.
struct OfficeInboxView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = OfficeMessagesViewModel()

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.margin)
                .padding(.top, 4)
                .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await reload(showLoading: false) }
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading messages")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await reload() } }
        case .loaded(let inbox):
            loaded(inbox)
        }
    }

    @ViewBuilder
    private func loaded(_ inbox: OfficeInbox) -> some View {
        if !inbox.isAvailable {
            EmptyStateView(
                symbolName: "bubble.left.and.exclamationmark.bubble.right",
                title: "Messaging isn't available",
                message: inbox.unavailableReason
                    ?? "Sign in to your company account to see messages."
            )
            .cardSurface()
        } else if inbox.threads.isEmpty {
            EmptyStateView(
                symbolName: "bubble.left.and.bubble.right",
                title: "No messages yet",
                message: "When a \(terms.worker) messages the office — running late, needing a part, stuck on site — the conversation appears here."
            )
            .cardSurface()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if inbox.unreadCount > 0 {
                    Text(inbox.unreadCount == 1 ? "1 unread message" : "\(inbox.unreadCount) unread messages")
                        .sectionLabelStyle()
                }

                VStack(spacing: 0) {
                    ForEach(Array(inbox.threads.enumerated()), id: \.element.id) { index, thread in
                        NavigationLink(value: AppRoute.message(thread.id)) {
                            threadRow(thread)
                        }
                        .buttonStyle(.plain)

                        if index < inbox.threads.count - 1 {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .cardSurface()

                Text("Replies are delivered to the \(terms.worker) straight away, and to their phone if they have alerts switched on.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
    }

    private func threadRow(_ thread: OfficeThreadRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: thread.jobNumber == nil ? "bubble.left" : "wrench.adjustable")
                    .font(.footnote)
                    .foregroundStyle(thread.isUnread ? Theme.accent : Theme.primary)
                    .frame(width: 36, height: 36)
                    .background((thread.isUnread ? Theme.accent : Theme.primary).opacity(0.12))
                    .clipShape(.rect(cornerRadius: 9))

                if thread.isUnread {
                    Circle()
                        .fill(Theme.accent)
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
        .accessibilityLabel("\(thread.subject). \(thread.preview). \(thread.isUnread ? "Unread." : "")")
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    NavigationStack {
        OfficeInboxView()
            .environment(AppEnvironment())
    }
}
