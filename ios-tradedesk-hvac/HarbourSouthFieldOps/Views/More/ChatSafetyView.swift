import SwiftUI

/// More → Safety & reports.
///
/// Everyone sees the reports they've made and the people they've blocked
/// (with Unblock). Owners and Admins also see reports to review and can act on
/// them: remove the message, pause someone's chat, suspend the account, or
/// close the report. The database decides what each person can see and do —
/// nobody can see or act on a report about themselves, and reports about an
/// Owner go to Harbour South instead.
struct ChatSafetyView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var state: LoadState<ChatSafetyOverview> = .idle
    @State private var pending: PendingAction?
    @State private var workingReportID: String?
    @State private var actionError: String?
    @State private var notice: String?

    private var session: TenantSession? { env.activeSession }

    /// A moderation step waiting for confirmation.
    private struct PendingAction: Identifiable {
        let report: ModerationReportRow
        let action: ModerationAction
        let days: Int?
        var id: String { "\(report.id)-\(action.rawValue)-\(days ?? 0)" }

        var title: String {
            switch action {
            case .startReview: return "Start reviewing this report?"
            case .dismiss: return "Close this report with no action?"
            case .removeMessage: return "Remove this message for everyone?"
            case .restrictChat:
                return days.map { "Pause \(report.reportedName ?? "their") chat for \($0) days?" }
                    ?? "Pause \(report.reportedName ?? "their") chat until you lift it?"
            case .liftChatRestriction: return "Let \(report.reportedName ?? "them") chat again?"
            case .suspendAccount: return "Suspend \(report.reportedName ?? "this person")'s account?"
            }
        }

        var confirmTitle: String {
            switch action {
            case .startReview: return "Start review"
            case .dismiss: return "Close report"
            case .removeMessage: return "Remove message"
            case .restrictChat: return "Pause chat"
            case .liftChatRestriction: return "Lift pause"
            case .suspendAccount: return "Suspend account"
            }
        }

        var isDestructive: Bool {
            action == .removeMessage || action == .restrictChat || action == .suspendAccount
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch state {
                case .idle, .loading:
                    LoadingStateView(message: "Loading safety")
                case .failed(let error):
                    ErrorStateView(error: error) { Task { await reload() } }
                case .loaded(let overview):
                    loaded(overview)
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .navigationTitle("Safety & reports")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await reload(showLoading: false) }
        .task(id: session?.userID) { await reload() }
        .sensoryFeedback(.success, trigger: notice)
        .confirmationDialog(
            pending?.title ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { item in
            Button(item.confirmTitle, role: item.isDestructive ? .destructive : nil) {
                Task { await run(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if item.action == .suspendAccount {
                Text("They'll be signed out and can't use the app until an Owner reactivates them in Team.")
            } else if item.action == .removeMessage {
                Text("The message is replaced with \u{201C}Removed by a moderator\u{201D}. A copy is kept with the report.")
            }
        }
    }

    @ViewBuilder
    private func loaded(_ overview: ChatSafetyOverview) -> some View {
        header

        if let notice {
            banner(notice, symbol: "checkmark.shield.fill", tint: Theme.green)
        }
        if let actionError {
            banner(actionError, symbol: "exclamationmark.triangle.fill", tint: Theme.red)
        }

        if overview.canModerate {
            section("Reports to review", count: overview.reportsToReview.filter { !$0.status.isResolved }.count) {
                if overview.reportsToReview.isEmpty {
                    emptyRow("No reports to review. Reports about you go to Harbour South, not to you.")
                } else {
                    ForEach(overview.reportsToReview) { report in
                        reportCard(report, canModerate: true)
                    }
                }
            }
        }

        section("Your reports", count: nil) {
            if overview.myReports.isEmpty {
                emptyRow("You haven't reported anything. To report a message, press and hold it in a conversation.")
            } else {
                ForEach(overview.myReports) { report in
                    reportCard(report, canModerate: false)
                }
            }
        }

        section("People you've blocked", count: nil) {
            if overview.blocked.isEmpty {
                emptyRow("You haven't blocked anyone. Block someone from a conversation's shield menu or by pressing and holding their message.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(overview.blocked.enumerated()), id: \.element.id) { index, person in
                        blockedRow(person)
                        if index < overview.blocked.count - 1 {
                            Divider().padding(.leading, 56)
                        }
                    }
                }
                .cardSurface()
            }
        }

        contactFooter
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.shield.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.primary.gradient)
                .clipShape(.rect(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text("Keeping chat respectful")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Abusive, hateful or threatening messages aren't allowed. Messages with banned language are blocked before they send. Reports are reviewed within 24 hours, and anyone who breaks the rules can have messages removed, chat paused or their account suspended.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func section<Content: View>(_ title: String, count: Int?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).sectionLabelStyle()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.red)
                        .clipShape(.capsule)
                }
            }
            content()
        }
    }

    private func reportCard(_ report: ModerationReportRow, canModerate: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: report.isBlock ? "person.crop.circle.badge.xmark" : report.reason.symbolName)
                    .font(.footnote)
                    .foregroundStyle(Theme.red)
                    .frame(width: 30, height: 30)
                    .background(Theme.red.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 1) {
                    Text(report.isBlock ? "Blocked" : report.reason.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("\(report.sourceTitle) · \(Formatters.shortDayAndTime(report.createdAt))")
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                }
                Spacer(minLength: 0)
                statusPill(report)
            }

            if let excerpt = report.excerpt, !excerpt.isEmpty {
                Text("\u{201C}\(excerpt)\u{201D}")
                    .font(.footnote)
                    .foregroundStyle(Theme.ink)
                    .lineLimit(4)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.canvas)
                    .clipShape(.rect(cornerRadius: 10))
            }

            if canModerate {
                VStack(alignment: .leading, spacing: 2) {
                    if let name = report.reportedName { meta("About", name) }
                    if let name = report.reporterName { meta("Reported by", name) }
                    if let details = report.details, !details.isEmpty { meta("Note", details) }
                }
            } else if let name = report.reportedName, report.isBlock {
                meta("Person", name)
            }

            if canModerate {
                moderationControls(report)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .opacity(report.status.isResolved ? 0.75 : 1)
    }

    @ViewBuilder
    private func moderationControls(_ report: ModerationReportRow) -> some View {
        if report.isEscalated {
            Label("Being reviewed by Harbour South support", systemImage: "building.columns")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondary)
        } else if report.status.isResolved {
            if report.resolution == ModerationAction.restrictChat.rawValue {
                actionButton("Lift chat pause", symbol: "bubble.left.and.bubble.right") {
                    pending = PendingAction(report: report, action: .liftChatRestriction, days: nil)
                }
            }
        } else {
            Menu {
                if report.status == .open {
                    Button {
                        pending = PendingAction(report: report, action: .startReview, days: nil)
                    } label: { Label("Start review", systemImage: "eye") }
                }
                if report.canRemoveMessage {
                    Button(role: .destructive) {
                        pending = PendingAction(report: report, action: .removeMessage, days: nil)
                    } label: { Label("Remove message", systemImage: "trash") }
                }
                if report.canActOnPerson {
                    Button(role: .destructive) {
                        pending = PendingAction(report: report, action: .restrictChat, days: 7)
                    } label: { Label("Pause their chat for 7 days", systemImage: "pause.circle") }
                    Button(role: .destructive) {
                        pending = PendingAction(report: report, action: .restrictChat, days: nil)
                    } label: { Label("Pause their chat until lifted", systemImage: "pause.octagon") }
                    Button(role: .destructive) {
                        pending = PendingAction(report: report, action: .suspendAccount, days: nil)
                    } label: { Label("Suspend account", systemImage: "person.crop.circle.badge.minus") }
                }
                Divider()
                Button {
                    pending = PendingAction(report: report, action: .dismiss, days: nil)
                } label: { Label("Close with no action", systemImage: "checkmark.circle") }
            } label: {
                HStack {
                    if workingReportID == report.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "hammer.fill")
                    }
                    Text("Take action")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.primary.gradient)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .disabled(workingReportID != nil)
            .accessibilityIdentifier("safety.takeAction")
        }
    }

    private func actionButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: Theme.buttonRadius))
        }
        .buttonStyle(PressableTileStyle())
    }

    private func statusPill(_ report: ModerationReportRow) -> some View {
        let tint: Color = {
            if report.isEscalated && !report.status.isResolved { return Theme.primary }
            switch report.status.tone {
            case .warning: return Theme.amber
            case .success: return Theme.green
            case .info: return Theme.primary
            case .danger: return Theme.red
            case .neutral: return Theme.secondary
            }
        }()
        return Text(report.isEscalated && !report.status.isResolved ? "With support" : report.status.title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(.capsule)
    }

    private func meta(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(Theme.meta)
            Text(value).font(.caption).foregroundStyle(Theme.secondary).lineLimit(3)
        }
    }

    private func blockedRow(_ person: BlockedChatUser) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.xmark")
                .font(.title3)
                .foregroundStyle(Theme.secondary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("Blocked \(Formatters.shortDate(person.blockedAt))").font(.caption2).foregroundStyle(Theme.meta)
            }
            Spacer(minLength: 0)
            Button("Unblock") {
                Task { await unblock(person) }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(Theme.primary)
            .accessibilityIdentifier("safety.unblock")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
    }

    private func banner(_ text: String, symbol: String, tint: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(tint)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.08))
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private var contactFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Need help now?").sectionLabelStyle()
            Text(contactText)
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let email = Brand.legalContactEmail, let url = URL(string: "mailto:\(email)") {
                Link(destination: url) {
                    Label("Email Harbour South support", systemImage: "envelope.fill")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.primary)
            }
        }
    }

    private var contactText: String {
        "If someone is in immediate danger, call 911. For anything else about a report, contact Harbour South support"
            + (Brand.legalContactEmail == nil ? " using the support link on our App Store page." : ".")
    }

    // MARK: - Actions

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        if showLoading || state.value == nil { state = .loading }
        do {
            state = .loaded(try await env.gateway.chatSafetyOverview(session: session))
        } catch {
            if state.value == nil {
                state = .failed(DataError.wrap(error))
            } else {
                actionError = error.localizedDescription
            }
        }
    }

    private func run(_ item: PendingAction) async {
        guard let session else { return }
        workingReportID = item.report.id
        actionError = nil
        notice = nil
        defer { workingReportID = nil }
        do {
            try await env.gateway.moderateReport(
                session: session, reportID: item.report.id, action: item.action, note: nil, days: item.days
            )
            notice = "Done. The report has been updated."
            await reload(showLoading: false)
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func unblock(_ person: BlockedChatUser) async {
        guard let session else { return }
        actionError = nil
        do {
            try await env.gateway.unblockChatUser(session: session, userID: person.id)
            notice = "You unblocked \(person.name)."
            await reload(showLoading: false)
        } catch {
            actionError = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ChatSafetyView()
            .environment(AppEnvironment())
    }
}
