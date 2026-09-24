import SwiftUI

/// More → Communications (Owner / Admin / Dispatcher).
///
/// One simple place for every customer conversation and every operational
/// message: Inbox, Scheduled, Sent, Templates, Automations and SMS Usage.
/// Deliberately not a marketing tool — there is no bulk send, list or campaign.
struct CommunicationsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = CommunicationsHubViewModel()
    @State private var tab: Tab = .inbox
    @State private var editing: SmsTemplateEntry?

    enum Tab: String, CaseIterable, Identifiable {
        case inbox, scheduled, sent, templates, automations, usage
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inbox: return "Inbox"
            case .scheduled: return "Scheduled"
            case .sent: return "Sent"
            case .templates: return "Templates"
            case .automations: return "Automations"
            case .usage: return "SMS Usage"
            }
        }
        var symbol: String {
            switch self {
            case .inbox: return "tray.fill"
            case .scheduled: return "calendar.badge.clock"
            case .sent: return "paperplane.fill"
            case .templates: return "text.badge.plus"
            case .automations: return "bolt.fill"
            case .usage: return "chart.bar.fill"
            }
        }
    }

    private var session: TenantSession? { env.activeSession }
    private var canAdminister: Bool { session?.can(.usersManage) == true && session?.can(.smsCreditsConsume) == true }

    private var tabs: [Tab] {
        Tab.allCases.filter { tab in
            switch tab {
            case .usage: return session?.can(.smsLedgerRead) == true
            default: return true
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let status = viewModel.setup, !status.friendly.canSend, tab == .inbox {
                        setupBanner(status)
                    }
                    if let error = viewModel.actionError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Theme.red)
                    }
                    content
                }
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, 12)
            }
            .refreshable { await load(tab) }
        }
        .background(Theme.canvas)
        .navigationTitle("Communications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: tab) { await load(tab) }
        .onReceive(NotificationCenter.default.publisher(for: .communicationsPushReceived)) { _ in
            if tab == .inbox { Task { await load(.inbox) } }
        }
        .sheet(item: $editing) { entry in
            SmsTemplateEditorView(entry: entry, canEdit: canAdminister) {
                Task { await load(.templates) }
            }
        }
    }

    // MARK: Tabs

    /// All six sections visible at once (two rows), so nothing hides off-screen.
    private var tabStrip: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(tabs) { item in
                Button { withAnimation(.snappy) { tab = item } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.caption2)
                        Text(item.title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        if item == .inbox, env.communications.unread.total > 0 {
                            Text("\(env.communications.unread.total)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Theme.accent).clipShape(.capsule)
                        }
                    }
                    .foregroundStyle(tab == item ? Color.white : Theme.primary)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(tab == item ? AnyShapeStyle(Theme.primary) : AnyShapeStyle(Theme.primaryTint))
                    .clipShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("comms.tab.\(item.rawValue)")
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .sensoryFeedback(.selection, trigger: tab)
    }

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .inbox: inbox
        case .scheduled: scheduled
        case .sent: sent
        case .templates: templates
        case .automations: automations
        case .usage: usage
        }
    }

    // MARK: Inbox

    @ViewBuilder
    private var inbox: some View {
        if let team = viewModel.team, !team.threads.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Team").sectionLabelStyle()
                    if team.unreadCount > 0 {
                        Text("\(team.unreadCount) unread").font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(Array(team.threads.prefix(4).enumerated()), id: \.element.id) { index, thread in
                        NavigationLink(value: AppRoute.message(thread.id)) {
                            inboxRow(title: thread.counterpartyName, subtitle: thread.jobNumber.map { "Job \($0)" } ?? thread.subject,
                                     preview: thread.preview, time: thread.lastMessageAt, unread: thread.isUnread ? 1 : 0,
                                     symbol: "person.2.fill", tint: Theme.primary)
                        }
                        .buttonStyle(.plain)
                        if index < min(team.threads.count, 4) - 1 { Divider().padding(.leading, 62) }
                    }
                    if team.threads.count > 4 {
                        Divider()
                        NavigationLink(value: AppRoute.more(.messages)) {
                            Text("All team messages").font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                    }
                }
                .cardSurface()
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Customers").sectionLabelStyle()
            switch viewModel.conversations {
            case .idle, .loading: LoadingStateView(message: "Loading conversations")
            case .failed(let error): ErrorStateView(error: error) { Task { await load(.inbox) } }
            case .loaded(let rows):
                if rows.isEmpty {
                    EmptyStateView(symbolName: "bubble.left.and.text.bubble.right",
                                   title: "No customer messages yet",
                                   message: "Texts you send and customers' replies appear here.")
                        .cardSurface()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            NavigationLink(value: AppRoute.smsConversation(row.id)) {
                                inboxRow(title: row.displayName,
                                         subtitle: row.jobNumber.map { "Job \($0)" } ?? PhoneFormatting.pretty(row.phone),
                                         preview: (row.lastWasInbound ? "" : "You: ") + row.lastPreview,
                                         time: row.lastMessageAt, unread: row.unread,
                                         symbol: row.optedOut ? "hand.raised.fill" : "message.fill",
                                         tint: row.optedOut ? Theme.amber : Theme.accent)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("comms.conversation")
                            if index < rows.count - 1 { Divider().padding(.leading, 62) }
                        }
                    }
                    .cardSurface()
                }
            }
        }
    }

    private func inboxRow(title: String, subtitle: String, preview: String, time: Date, unread: Int,
                          symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.12))
                .clipShape(.circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title).font(.subheadline.weight(unread > 0 ? .bold : .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(Formatters.shortDayAndTime(time)).font(.caption2).foregroundStyle(Theme.meta)
                }
                Text(subtitle).font(.caption).foregroundStyle(Theme.secondary).lineLimit(1)
                Text(preview).font(.footnote).foregroundStyle(unread > 0 ? Theme.ink : Theme.meta).lineLimit(2)
            }
            if unread > 0 {
                Circle().fill(Theme.accent).frame(width: 10, height: 10).padding(.top, 4)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .contentShape(.rect)
    }

    private func setupBanner(_ status: MessagingSetupStatus) -> some View {
        NavigationLink(value: AppRoute.more(.smsMessaging)) {
            HStack(spacing: 12) {
                Image(systemName: status.friendly.symbolName).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.friendly.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(status.friendly == .notSetUp ? "Set up your business number to text customers."
                         : (status.attention ?? "You can text customers once your number is approved."))
                        .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.meta)
            }
            .padding(13)
            .background(Theme.accentTint)
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
        }
        .buttonStyle(.plain)
    }

    // MARK: Scheduled

    @ViewBuilder
    private var scheduled: some View {
        switch viewModel.scheduled {
        case .idle, .loading: LoadingStateView(message: "Loading scheduled messages")
        case .failed(let error): ErrorStateView(error: error) { Task { await load(.scheduled) } }
        case .loaded(let rows):
            if rows.isEmpty {
                EmptyStateView(symbolName: "calendar.badge.clock", title: "Nothing scheduled",
                               message: "Reminders and messages you schedule appear here until they send.")
                    .cardSurface()
            } else {
                VStack(spacing: 10) {
                    ForEach(rows) { row in scheduledRow(row) }
                }
            }
        }
    }

    private func scheduledRow(_ row: ScheduledMessageRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: row.kind.symbolName).foregroundStyle(Theme.primary)
                Text(row.kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
                StatusPill(badge: StatusBadge(text: row.statusLabel,
                                              tone: row.status == "scheduled" ? .info : row.status == "sent" ? .success : .neutral))
            }
            Text("\(row.customerName)\(row.jobNumber.map { " · Job \($0)" } ?? "")")
                .font(.caption).foregroundStyle(Theme.secondary)
            HStack {
                Label(Formatters.dayAndTime(row.scheduledFor), systemImage: "clock")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.secondary)
                Spacer()
                if row.isCancellable, session?.can(.smsCreditsConsume) == true {
                    Button("Cancel", role: .destructive) {
                        guard let session else { return }
                        Task { await viewModel.cancel(row, gateway: env.gateway, session: session) }
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("comms.scheduled.cancel")
                }
            }
            if let reason = row.failureReason, !row.isCancellable {
                Text(reason).font(.caption2).foregroundStyle(Theme.meta)
            }
        }
        .padding(13)
        .cardSurface()
    }

    // MARK: Sent

    @ViewBuilder
    private var sent: some View {
        switch viewModel.sent {
        case .idle, .loading: LoadingStateView(message: "Loading sent messages")
        case .failed(let error): ErrorStateView(error: error) { Task { await load(.sent) } }
        case .loaded(let rows):
            if rows.isEmpty {
                EmptyStateView(symbolName: "paperplane", title: "No messages sent yet",
                               message: "Every text your team sends appears here with its delivery status.")
                    .cardSurface()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(row.customerName ?? PhoneFormatting.pretty(row.recipient))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                StatusPill(badge: StatusBadge(text: row.state.title, tone: row.state.tone))
                            }
                            Text([row.kind?.title, row.jobNumber.map { "Job \($0)" }].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(Theme.secondary)
                            Text(row.body).font(.footnote).foregroundStyle(Theme.meta).lineLimit(2)
                            HStack(spacing: 6) {
                                Text(Formatters.shortDayAndTime(row.at))
                                if let segments = row.segments { Text("· \(segments) seg") }
                                if row.creditsRefunded > 0 { Text("· credit returned").foregroundStyle(Theme.green) }
                            }
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.meta)
                        }
                        .padding(13)
                        if index < rows.count - 1 { Divider().padding(.leading, 13) }
                    }
                }
                .cardSurface()
            }
        }
    }

    // MARK: Templates

    @ViewBuilder
    private var templates: some View {
        switch viewModel.templates {
        case .idle, .loading: LoadingStateView(message: "Loading templates")
        case .failed(let error): ErrorStateView(error: error) { Task { await load(.templates) } }
        case .loaded(let entries):
            ForEach(SmsMessageCategory.allCases) { category in
                let items = entries.filter { $0.kind.category == category }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.title).sectionLabelStyle()
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                                Button { editing = entry } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: entry.kind.symbolName)
                                            .font(.footnote).foregroundStyle(Theme.primary)
                                            .frame(width: 32, height: 32).background(Theme.primaryTint).clipShape(.rect(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(entry.kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                                if entry.isCustomised {
                                                    Text("Edited").font(.caption2.weight(.bold)).foregroundStyle(Theme.accentText)
                                                        .padding(.horizontal, 6).padding(.vertical, 2).background(Theme.accentTint).clipShape(.capsule)
                                                }
                                            }
                                            Text(entry.body.isEmpty ? "Write your own message." : entry.body)
                                                .font(.caption).foregroundStyle(Theme.meta).lineLimit(2)
                                        }
                                        Spacer(minLength: 4)
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.meta)
                                    }
                                    .padding(13)
                                    .contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("comms.template.\(entry.kind.rawValue)")
                                if index < items.count - 1 { Divider().padding(.leading, 57) }
                            }
                        }
                        .cardSurface()
                    }
                }
            }
        }
    }

    // MARK: Automations

    @ViewBuilder
    private var automations: some View {
        switch viewModel.templates {
        case .idle, .loading: LoadingStateView(message: "Loading automations")
        case .failed(let error): ErrorStateView(error: error) { Task { await load(.automations) } }
        case .loaded(let entries):
            Text("Automatic texts go to customers at key moments. Each uses its template and SMS credits, and never goes to anyone who replied STOP.")
                .font(.footnote).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
            if !canAdminister {
                Label("Only an owner or admin can change automations.", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(Theme.meta)
            }
            ForEach(SmsMessageCategory.allCases.filter { $0 != .general }) { category in
                let items = entries.filter { $0.kind.category == category && $0.isAutomatable }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(category.title).sectionLabelStyle()
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                                Toggle(isOn: Binding(
                                    get: { entry.automationEnabled },
                                    set: { newValue in
                                        guard let session else { return }
                                        Task { await viewModel.setAutomation(entry, enabled: newValue, gateway: env.gateway, session: session) }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.kind.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                        if let description = entry.automationDescription {
                                            Text(description).font(.caption).foregroundStyle(Theme.meta)
                                        }
                                    }
                                }
                                .tint(Theme.accent)
                                .disabled(!canAdminister)
                                .padding(.horizontal, 13)
                                .frame(minHeight: 60)
                                .accessibilityIdentifier("comms.automation.\(entry.kind.rawValue)")
                                if index < items.count - 1 { Divider().padding(.leading, 13) }
                            }
                        }
                        .cardSurface()
                    }
                }
            }
        }
    }

    // MARK: Usage

    @ViewBuilder
    private var usage: some View {
        switch viewModel.usage {
        case .idle, .loading: LoadingStateView(message: "Loading usage")
        case .failed(let error): ErrorStateView(error: error) { Task { await load(.usage) } }
        case .loaded(let summary):
            VStack(alignment: .leading, spacing: 6) {
                Text("Credits available").font(.caption).foregroundStyle(Theme.meta)
                Text("\(summary.balance)")
                    .font(.system(size: 48, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(summary.balance > 0 ? Theme.ink : Theme.amber)
                    .contentTransition(.numericText())
                Text("1 credit = 1 text segment").font(.caption).foregroundStyle(Theme.secondary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).cardSurface()

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("Purchased", summary.purchased, "cart.fill", Theme.primary)
                tile("Used", summary.used, "arrow.up.right", Theme.accent)
                tile("Returned", summary.refunded, "arrow.uturn.backward", Theme.green)
                tile("Number fees", summary.numberFees, "phone.fill", Theme.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Last 30 days").sectionLabelStyle()
                VStack(spacing: 0) {
                    usageRow("Texts sent", summary.sent30d)
                    Divider().padding(.leading, 14)
                    usageRow("Segments", summary.segments30d)
                    Divider().padding(.leading, 14)
                    usageRow("Not delivered", summary.failed30d)
                    Divider().padding(.leading, 14)
                    usageRow("Replies received", summary.received30d)
                }
                .cardSurface()
            }

            NavigationLink(value: AppRoute.more(.smsCredits)) {
                Label("Buy credits & full ledger", systemImage: "plus.circle.fill")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent.gradient).clipShape(.rect(cornerRadius: Theme.buttonRadius))
            }
            .buttonStyle(PressableTileStyle())
        }
    }

    private func tile(_ title: String, _ value: Int, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.footnote).foregroundStyle(tint)
            Text("\(value)").font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Theme.ink)
            Text(title).font(.caption).foregroundStyle(Theme.meta)
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .leading).cardSurface()
    }

    private func usageRow(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondary)
            Spacer()
            Text("\(value)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
        }
        .padding(.horizontal, 14).frame(minHeight: 46)
    }

    // MARK: Loading

    private func load(_ tab: Tab) async {
        guard let session else { return }
        switch tab {
        case .inbox:
            await viewModel.loadInbox(gateway: env.gateway, session: session)
            await env.communications.refresh(gateway: env.gateway, session: session, announce: false)
        case .scheduled: await viewModel.loadScheduled(gateway: env.gateway, session: session)
        case .sent: await viewModel.loadSent(gateway: env.gateway, session: session)
        case .templates, .automations: await viewModel.loadTemplates(gateway: env.gateway, session: session)
        case .usage: await viewModel.loadUsage(gateway: env.gateway, session: session)
        }
    }
}

/// Edit one template with only its valid variables, validated as you type.
struct SmsTemplateEditorView: View {
    let entry: SmsTemplateEntry
    let canEdit: Bool
    let onSaved: () -> Void

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    @State private var error: String?
    @State private var isSaving: Bool = false

    private var problem: String? { SmsTemplateValidator.problem(kind: entry.kind, body: text) }
    private var estimate: SmsSegmentCounter.Result { SmsSegmentCounter.count(SmsTemplateValidator.estimate(text)) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .padding(10)
                        .scrollContentBackground(.hidden)
                        .background(Theme.surface)
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(problem == nil ? Theme.border : Theme.red, lineWidth: 1))
                        .disabled(!canEdit)
                        .accessibilityIdentifier("template.editor")
                    if canEdit {
                        Text("Tap to insert").sectionLabelStyle()
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 6)], spacing: 6) {
                            ForEach(entry.allowedVariables) { variable in
                                Button { text += (text.hasSuffix(" ") || text.isEmpty ? "" : " ") + variable.token } label: {
                                    Text(variable.label).font(.caption.weight(.semibold)).foregroundStyle(Theme.accentText)
                                        .frame(maxWidth: .infinity, minHeight: 32).background(Theme.accentTint).clipShape(.capsule)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    HStack {
                        Text("About \(estimate.segments) segment\(estimate.segments == 1 ? "" : "s") once filled in")
                        Spacer()
                        Text("\(text.count)/\(SmsTemplateValidator.maxCharacters)")
                    }
                    .font(.caption.monospacedDigit()).foregroundStyle(estimate.segments > 1 ? Theme.amber : Theme.meta)
                    if let message = problem ?? error {
                        Label(message, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Theme.red)
                            .accessibilityIdentifier("template.error")
                    }
                    Text("Your company name is added to the start of every text if it isn't already there, so customers always know who is messaging them.")
                        .font(.caption).foregroundStyle(Theme.meta).fixedSize(horizontal: false, vertical: true)
                    if canEdit, entry.isCustomised {
                        Button("Restore the default wording") { Task { await reset() } }
                            .font(.footnote.weight(.semibold))
                    }
                }
                .padding(Theme.margin)
            }
            .background(Theme.canvas)
            .navigationTitle(entry.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(canEdit ? "Cancel" : "Close") { dismiss() } }
                if canEdit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(problem != nil || isSaving || text == entry.body)
                    }
                }
            }
            .onAppear { text = entry.body }
        }
    }

    private func save() async {
        guard let session = env.activeSession else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await env.gateway.saveSmsTemplate(session: session, kind: entry.kind, body: text)
            onSaved()
            dismiss()
        } catch {
            self.error = DataError.wrap(error).errorDescription
        }
    }

    private func reset() async {
        guard let session = env.activeSession else { return }
        do {
            try await env.gateway.resetSmsTemplate(session: session, kind: entry.kind)
            onSaved()
            dismiss()
        } catch {
            self.error = DataError.wrap(error).errorDescription
        }
    }
}
