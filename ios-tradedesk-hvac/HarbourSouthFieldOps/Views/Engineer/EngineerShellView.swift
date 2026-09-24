import SwiftUI

/// The engineer's four-tab shell.
///
/// Deliberately not the office shell with things removed. An engineer's day is
/// a single question — what am I doing, where, and what do I need to tell the
/// office — so the tabs answer exactly that and nothing else:
///
///   Jobs      today's work, in order, with the workflow buttons on it
///   Schedule  what is coming, read-only
///   Office    the two-way conversation with dispatch
///   More      sites, equipment, my work, alerts, availability, sign out
///
/// There is no dashboard, no financial surface and no company-wide anything.
/// That is a structural decision, not a cosmetic one: the payload types behind
/// these screens carry no monetary field at all, so there is nothing to hide.
struct EngineerShellView: View {
    @Environment(AppEnvironment.self) private var env

    /// Unread office messages, shown on the tab itself so a reply from
    /// dispatch is noticed without opening anything.
    @State private var messages = OfficeMessagesViewModel()

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        TabView {
            Tab("Jobs", systemImage: "list.clipboard") {
                FieldWorkerDayView()
            }
            Tab("Schedule", systemImage: "calendar") {
                EngineerScheduleView()
            }
            Tab("Office", systemImage: "bubble.left.and.bubble.right") {
                OfficeMessagesView(viewModel: messages)
            }
            .badge(max(messages.unreadCount, env.communications.unread.officeUnread))
            Tab("More", systemImage: "ellipsis") {
                EngineerMoreView()
            }
        }
        .tint(Theme.primary)
        .task(id: session?.userID) {
            guard let session else { return }
            await messages.load(gateway: env.gateway, session: session)
        }
        // A new office message refreshes the inbox wherever the engineer is.
        .onChange(of: env.communications.unread.officeUnread) { _, _ in
            guard let session else { return }
            Task { await messages.load(gateway: env.gateway, session: session, showLoading: false) }
        }
    }
}

#Preview {
    EngineerShellView()
        .environment(AppEnvironment())
}
