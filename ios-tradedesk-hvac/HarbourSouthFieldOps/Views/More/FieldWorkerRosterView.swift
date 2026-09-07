import SwiftUI

/// The company's field workers: who they are, their role and whether they can
/// take work today.
///
/// Deliberately a list and nothing more. There is no payroll here, no HR record
/// and no workforce planning — the roster answers "who works here and are they
/// available", which is what a small field-service company actually needs.
///
/// Money never appears: `RosterMember` carries no monetary field at all, so
/// there is nothing for this screen to hide from a role that should not see it.
struct FieldWorkerRosterView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var roster: FieldWorkerRoster?
    @State private var error: DataError?
    @State private var isLoading: Bool = true

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        ScrollView {
            content
        }
        .background(Theme.canvas)
        .navigationTitle(terms.WorkerPlural)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load(showLoading: false) }
        .task(id: session?.userID) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            LoadingStateView(message: "Loading \(terms.workerPlural)")
        } else if let error {
            ErrorStateView(error: error) { Task { await load() } }
        } else if let roster {
            if roster.isEmpty {
                EmptyStateView(
                    symbolName: "person.2",
                    title: "No \(terms.workerPlural) yet",
                    message: "\(terms.WorkerPlural) you add to the company will appear here, ready to be assigned to jobs."
                )
            } else {
                loaded(roster)
            }
        }
    }

    private func loaded(_ roster: FieldWorkerRoster) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            summary(roster)

            VStack(alignment: .leading, spacing: 8) {
                Text(terms.WorkerPlural)
                    .sectionLabelStyle()

                VStack(spacing: 0) {
                    ForEach(Array(roster.members.enumerated()), id: \.element.id) { index, member in
                        if index > 0 { Divider().padding(.leading, 62) }
                        row(member)
                    }
                }
                .cardSurface()
            }

            Text("Only this company's \(terms.workerPlural) are listed. The database resolves your company from your sign-in, so another company's people are never returned.")
                .font(.caption)
                .foregroundStyle(Theme.meta)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 4)
        .padding(.bottom, 24)
    }

    private func summary(_ roster: FieldWorkerRoster) -> some View {
        HStack(spacing: 10) {
            tile(
                value: roster.activeCount,
                caption: "Active",
                symbol: "checkmark.circle.fill",
                tone: Theme.green
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
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func row(_ member: RosterMember) -> some View {
        HStack(spacing: 12) {
            Text(member.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(member.isActive ? Theme.primary : Theme.meta)
                .frame(width: 38, height: 38)
                .background(member.isActive ? Theme.primaryTint : Theme.canvas)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 3) {
                Text(member.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.ink)

                HStack(spacing: 6) {
                    Text(member.roleTitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)

                    if let phone = member.phone, !phone.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                        Text(phone)
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                    }
                }
            }

            Spacer(minLength: 8)

            StatusPill(badge: StatusBadge(text: member.statusTitle, tone: member.statusTone))
        }
        .padding(.horizontal, 13)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    private func load(showLoading: Bool = true) async {
        guard let session else { return }
        if showLoading { isLoading = true }
        defer { isLoading = false }

        do {
            roster = try await env.gateway.fieldWorkerRoster(session: session)
            error = nil
        } catch let dataError as DataError {
            error = dataError
        } catch {
            self.error = .unexpected("The \(terms.workerPlural) list couldn't be loaded.")
        }
    }
}

#Preview {
    NavigationStack {
        FieldWorkerRosterView()
            .environment(AppEnvironment())
    }
}
