import SwiftUI

/// The company's people: who works here, what they can do, and who has been
/// invited but hasn't arrived yet.
///
/// Money never appears. `TeamMember` carries no monetary field at all, so there
/// is nothing on this screen to hide from a role that should not see it.
struct TeamView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = TeamViewModel()
    @State private var isInviting: Bool = false
    @State private var editingMember: TeamMember?

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("Team")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if viewModel.state.value?.canManage == true {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isInviting = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Invite somebody")
                }
            }
        }
        .task(id: session?.userID) { await load() }
        .sheet(isPresented: $isInviting) {
            TeamInviteSheet(terms: terms) { draft in
                guard let session else { return }
                Task { await viewModel.invite(gateway: env.gateway, session: session, draft: draft) }
            }
        }
        .sheet(item: $editingMember) { member in
            TeamMemberSheet(member: member, terms: terms) { name, phone, role, status in
                guard let session else { return }
                Task {
                    await viewModel.setDetails(
                        gateway: env.gateway,
                        session: session,
                        userID: member.id,
                        name: name,
                        phone: phone
                    )
                    if role != member.role {
                        await viewModel.setRole(gateway: env.gateway, session: session, userID: member.id, role: role)
                    }
                    if status != member.status {
                        await viewModel.setStatus(
                            gateway: env.gateway,
                            session: session,
                            userID: member.id,
                            status: status
                        )
                        // Deactivating people is how seat resolution ends;
                        // re-read the workspace so normal work resumes the
                        // moment the company is within its plan.
                        await env.refreshWorkspaceAccess()
                    }
                }
            }
        }
        .sheet(item: $viewModel.issuedInvite) { invite in
            TeamInviteCodeSheet(invite: invite)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading your team")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await load() } } }
        case .loaded(let roster):
            loaded(roster)
        }
    }

    private func loaded(_ roster: TeamRoster) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary(roster)

                if let error = viewModel.actionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.red.opacity(0.08))
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))
                }

                if roster.members.isEmpty && roster.invitations.isEmpty {
                    EmptyStateView(
                        symbolName: "person.2",
                        title: "Nobody here yet",
                        message: "Invite your \(terms.workerPlural) and office staff. They join with the code you send them.",
                        actionTitle: roster.canManage ? "Invite somebody" : nil,
                        action: roster.canManage ? { isInviting = true } : nil
                    )
                    .cardSurface()
                }

                if !roster.invitations.isEmpty { invitationsSection(roster) }
                if !roster.members.isEmpty { membersSection(roster) }

                Text("Only this company's people are listed. The database resolves your company from your sign-in, so another company's team is never returned.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .refreshable { await load(showLoading: false) }
    }

    private func summary(_ roster: TeamRoster) -> some View {
        HStack(spacing: 10) {
            tile(value: roster.activeCount, caption: "Active", symbol: "checkmark.circle.fill", tone: Theme.green)
            tile(
                value: roster.fieldWorkerCount,
                caption: terms.WorkerPlural,
                // A person, not a tool: this tile counts people, and the old
                // wrench-and-screwdriver was previous-identity branding.
                symbol: "person.fill.checkmark",
                tone: Theme.primary
            )
            tile(
                value: roster.inactiveCount,
                caption: "Not active",
                symbol: "pause.circle.fill",
                tone: roster.inactiveCount == 0 ? Theme.meta : Theme.amber
            )
        }
    }

    private func tile(value: Int, caption: String, symbol: String, tone: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(tone)
            Text("\(value)")
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func invitationsSection(_ roster: TeamRoster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invited").sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(roster.invitations.enumerated()), id: \.element.id) { index, invitation in
                    if index > 0 { Divider().padding(.leading, 14) }
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.fill")
                            .font(.footnote)
                            .foregroundStyle(invitation.isExpired ? Theme.meta : Theme.primary)
                            .frame(width: 36, height: 36)
                            .background((invitation.isExpired ? Theme.meta : Theme.primary).opacity(0.12))
                            .clipShape(.circle)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(invitation.email)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text("\(invitation.roleTitle) · \(invitation.expiresLabel)")
                                .font(.caption)
                                .foregroundStyle(invitation.isExpired ? Theme.amber : Theme.secondary)
                        }

                        Spacer(minLength: 4)

                        Button("Revoke") {
                            guard let session else { return }
                            Task {
                                await viewModel.revoke(
                                    gateway: env.gateway,
                                    session: session,
                                    invitationID: invitation.id
                                )
                            }
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.red)
                        .disabled(viewModel.isWorking)
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: Theme.minTap)
                }
            }
            .cardSurface()
        }
    }

    private func membersSection(_ roster: TeamRoster) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("People").sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(roster.members.enumerated()), id: \.element.id) { index, member in
                    if index > 0 { Divider().padding(.leading, 62) }
                    memberRow(member, canManage: roster.canManage)
                }
            }
            .cardSurface()
        }
    }

    private func memberRow(_ member: TeamMember, canManage: Bool) -> some View {
        Button {
            guard canManage, !member.isSelf else { return }
            editingMember = member
        } label: {
            HStack(spacing: 12) {
                Text(member.initials)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(member.isActive ? Theme.primary : Theme.meta)
                    .frame(width: 38, height: 38)
                    .background(member.isActive ? Theme.primaryTint : Theme.canvas)
                    .clipShape(.circle)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(member.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        if member.isSelf {
                            Text("You")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.canvas)
                                .clipShape(.rect(cornerRadius: 5))
                        }
                    }
                    Text([member.roleTitle, member.phone, member.email]
                        .compactMap { $0 }
                        .joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                StatusPill(badge: StatusBadge(text: member.statusTitle, tone: member.statusTone))

                if canManage, !member.isSelf {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.meta)
                }
            }
            .padding(.horizontal, 13)
            .frame(minHeight: Theme.minTap)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canManage || member.isSelf)
    }

    private func load(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    NavigationStack {
        TeamView()
            .environment(AppEnvironment())
    }
}
