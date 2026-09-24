import SwiftUI

/// The engineer's More tab: who I am, whether I'm available, the sites and kit
/// I work on, what I've finished, my alerts — and the way out.
///
/// Everything here is field work or the engineer's own account. There is no
/// company section, no financial section, no user administration and no
/// settings that reach past this one person, because a field role holds none of
/// the permissions those would need.
struct EngineerMoreView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = EngineerProfileViewModel()
    @State private var path = NavigationPath()
    @State private var isChoosingAvailability: Bool = false
    @State private var isSigningOut: Bool = false

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: EngineerSection.self) { section in
                switch section {
                case .sites: EngineerSitesView()
                case .workHistory: EngineerWorkHistoryView()
                case .alerts: NotificationsView()
                }
            }
            .navigationDestination(for: EngineerSiteRoute.self) { route in
                EngineerSiteDetailView(addressID: route.addressID)
            }
            .sheet(isPresented: $isChoosingAvailability) {
                if let profile = viewModel.state.value {
                    EngineerAvailabilitySheet(profile: profile) { state in
                        guard let session else { return }
                        Task { await viewModel.setDuty(gateway: env.gateway, session: session, to: state) }
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
            LoadingStateView(message: "Loading your profile")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let profile):
            loaded(profile)
        }
    }

    private func loaded(_ profile: EngineerProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityCard(profile)
                availabilityCard(profile)
                todayCard(profile)
                sectionsCard
                signOutButton

                NavigationLink {
                    DeleteAccountView()
                } label: {
                    Text("Delete account")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                }
                .accessibilityIdentifier("engineer.deleteAccount")

                LegalLinksView()

                if env.isDevelopmentSession { SimulatedServicesBanner() }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .refreshable { await reload(showLoading: false) }
    }

    // MARK: - Cards

    private func identityCard(_ profile: EngineerProfile) -> some View {
        HStack(spacing: 14) {
            Text(profile.initials)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.primary)
                .frame(width: 56, height: 56)
                .background(Theme.primaryTint)
                .clipShape(.circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)

                HStack(spacing: 6) {
                    Text(profile.roleTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.primaryTint)
                        .clipShape(.rect(cornerRadius: 6))
                    Text(profile.companyName)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }

                Text(profile.email)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .lineLimit(1)

                if let phone = profile.phone {
                    Text(phone)
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    /// Availability, with the honest caveat built in.
    ///
    /// When a job is live the shown status comes from that job, not from the
    /// picker — so the card says which one is speaking. Telling dispatch
    /// "Available" while somebody is mid-repair would be worse than useless.
    private func availabilityCard(_ profile: EngineerProfile) -> some View {
        Button {
            isChoosingAvailability = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: profile.availability.symbolName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tone(profile.availability.tone))
                        .frame(width: 40, height: 40)
                        .background(tone(profile.availability.tone).opacity(0.12))
                        .clipShape(.circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.availability.title)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text(statusDetail(profile))
                            .font(.caption)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    if viewModel.isUpdatingDuty {
                        ProgressView()
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.meta)
                    }
                }

                if let error = viewModel.actionError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(PressableTileStyle())
        .disabled(viewModel.isUpdatingDuty)
        .accessibilityLabel("Availability: \(profile.availability.title)")
        .accessibilityHint("Change your availability")
    }

    private func statusDetail(_ profile: EngineerProfile) -> String {
        if profile.availability.isDerivedFromJob {
            let number = profile.activeJobNumber.map { " on \($0)" } ?? ""
            return "From your live job\(number). Dispatch sees this until you finish."
        }
        if let changed = profile.dutyChangedLabel {
            return "\(profile.dutyState.detail) Set \(changed)."
        }
        return profile.dutyState.detail
    }

    private func todayCard(_ profile: EngineerProfile) -> some View {
        HStack(spacing: 0) {
            metric(value: profile.jobsToday, caption: "Today")
            Divider().frame(height: 34)
            metric(value: profile.completedToday, caption: "Done today")
            Divider().frame(height: 34)
            metric(value: profile.upcomingCount, caption: "Upcoming")
            Divider().frame(height: 34)
            metric(value: profile.completedAllTime, caption: "Completed")
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .cardSurface()
    }

    private func metric(value: Int, caption: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Theme.meta)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(caption)")
    }

    private var sectionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your work")
                .sectionLabelStyle()

            VStack(spacing: 0) {
                ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
                    NavigationLink(value: section) {
                        sectionRow(section)
                    }
                    .buttonStyle(.plain)

                    if index < visibleSections.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .cardSurface()
        }
    }

    /// Alerts need a real device registration against a real signed-in user, so
    /// the row is only offered where turning them on actually does something.
    private var visibleSections: [EngineerSection] {
        EngineerSection.allCases.filter { section in
            section != .alerts || env.isProductionSession
        }
    }

    private func sectionRow(_ section: EngineerSection) -> some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbolName)
                .font(.footnote)
                .foregroundStyle(Theme.primary)
                .frame(width: 32, height: 32)
                .background(Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text(section.title(terms))
                    .font(.body)
                    .foregroundStyle(Theme.ink)
                Text(section.detail(terms))
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    /// The way out.
    ///
    /// Routes through `signOutOfCurrentSession`, which picks the right stack —
    /// the production path also removes this device's push registration before
    /// discarding the session that owns it, so a shared handset stops receiving
    /// the previous engineer's job alerts.
    private var signOutButton: some View {
        Button {
            isSigningOut = true
            Task {
                await env.signOutOfCurrentSession()
                isSigningOut = false
            }
        } label: {
            HStack(spacing: 8) {
                if isSigningOut { ProgressView().tint(Theme.red) }
                Text("Sign out")
                    .font(.headline)
                    .foregroundStyle(Theme.red)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
            .cardSurface()
        }
        .buttonStyle(PressableTileStyle())
        .disabled(isSigningOut)
        .accessibilityLabel("Sign out")
        .accessibilityHint("Signs you out and returns to the sign-in screen. Your work and your account are not affected.")
    }

    private func tone(_ tone: StatusTone) -> Color {
        switch tone {
        case .neutral: return Theme.meta
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .success: return Theme.green
        case .danger: return Theme.red
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

/// Destinations inside the engineer's More tab.
///
/// Deliberately its own type rather than `MoreSection`: every case there is an
/// office surface gated on a permission a field role does not hold, so reusing
/// it would mean listing everything an engineer cannot have and filtering it
/// back out. These are the four things they can.
nonisolated enum EngineerSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case sites
    case workHistory
    case alerts

    var id: String { rawValue }

    func title(_ terms: Terminology) -> String {
        switch self {
        case .sites: return "Sites & \(terms.assetPlural)"
        case .workHistory: return "My work"
        case .alerts: return "Job alerts"
        }
    }

    func detail(_ terms: Terminology) -> String {
        switch self {
        case .sites: return "Customers, \(terms.assetPlural) and service history"
        case .workHistory: return "Jobs you've completed"
        case .alerts: return "Notifications on this device"
        }
    }

    var symbolName: String {
        switch self {
        case .sites: return "building.2"
        case .workHistory: return "checkmark.seal"
        case .alerts: return "bell"
        }
    }
}

#Preview {
    EngineerMoreView()
        .environment(AppEnvironment())
}
