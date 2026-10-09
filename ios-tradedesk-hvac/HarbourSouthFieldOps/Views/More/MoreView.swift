import SwiftUI

struct MoreView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var viewModel = MoreViewModel()
    @State private var path = NavigationPath()

    private var session: TenantSession? { env.activeSession }
    private var terms: Terminology { env.terms }

    /// Sections in the approved order, filtered by what the data layer will
    /// actually serve this role.
    private var visibleSections: [MoreSection] {
        guard let session else { return [] }
        // `.businessEmail` is deliberately at the top level rather than three
        // taps down in Settings → Business. It existed and was routed before,
        // but nothing surfaced it, so no owner ever found it and no invoice
        // ever carried the business's own reply address. A setting nobody can
        // find is a setting that does not exist.
        // ISSUE #13 — `.messages` sits high in the list, next to dispatch,
        // because it is operational: a field worker asking for a part or
        // reporting a delay is time-critical, and the database has always
        // delivered those threads to office roles with nowhere to read them.
        // `.payments_integration` is the "Connect Stripe" row: the existing
        // Payments screen, surfaced at the top level so an owner does not have
        // to know it lives under Settings → Integrations. Gated on
        // `saasBillingRead`, so only the owner is offered it.
        return [.communications, .dispatch, .messages, .smsMessaging, .payments_integration, .workerLocations, .fieldWorkers, .quotes, .invoices,
                .payments, .recurring, .reports, .smsCredits, .subscription, .businessEmail,
                .notifications, .settings, .dataAccess, .integrations, .legal]
            .filter { section in
                // Job alerts need a real device registration against a real
                // signed-in user, so the row is only offered where turning them
                // on actually does something.
                if section == .notifications, !env.isProductionSession { return false }
                // Customer conversations need every-customer visibility too.
                if section == .communications, !session.can(.customersReadAll) { return false }
                guard let permission = section.requiredPermission else { return true }
                return session.can(permission)
            }
    }

    /// Development-only tooling, kept in its own labelled group so it is easy to
    /// find and obviously not part of the customer-facing product surface.
    ///
    /// Empty for a production session: the acceptance suite runs against a
    /// freshly seeded in-memory store, so it is meaningless — and misleading —
    /// inside a real company's app.
    private var developmentSections: [MoreSection] {
        env.isDevelopmentSession ? [.developmentTests] : []
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.canvas.ignoresSafeArea()
                content
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: AppRoute.self) { route in
                RouteDestinationView(route: route)
            }
        }
        .task(id: session?.userID) { await reload() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading")
        case .failed(let error):
            ScrollView { ErrorStateView(error: error) { Task { await reload() } } }
        case .loaded(let overview):
            loaded(overview)
        }
    }

    private func loaded(_ overview: MoreOverview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityCard(overview)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sections")
                        .sectionLabelStyle()

                    VStack(spacing: 0) {
                        ForEach(Array(visibleSections.enumerated()), id: \.element.id) { index, section in
                            NavigationLink(value: AppRoute.more(section)) {
                                sectionRow(section, overview: overview)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("more.section.\(section.rawValue)")

                            if index < visibleSections.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .cardSurface()
                }

                if !developmentSections.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Development")
                            .sectionLabelStyle()

                        VStack(spacing: 0) {
                            ForEach(Array(developmentSections.enumerated()), id: \.element.id) { index, section in
                                NavigationLink(value: AppRoute.more(section)) {
                                    sectionRow(section, overview: overview)
                                }
                                .buttonStyle(.plain)

                                if index < developmentSections.count - 1 {
                                    Divider().padding(.leading, 58)
                                }
                            }
                        }
                        .cardSurface()

                        Text("Runs the full acceptance suite against a freshly seeded store. Development build only.")
                            .font(.caption)
                            .foregroundStyle(Theme.meta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Account")
                        .sectionLabelStyle()

                    NavigationLink {
                        DeleteAccountView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.xmark")
                                .font(.footnote)
                                .foregroundStyle(Theme.red)
                                .frame(width: 32, height: 32)
                                .background(Theme.red.opacity(0.1))
                                .clipShape(.rect(cornerRadius: 8))
                            Text("Delete account")
                                .font(.body)
                                .foregroundStyle(Theme.ink)
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.meta)
                        }
                        .padding(.horizontal, 13)
                        .frame(minHeight: Theme.minTap)
                        .contentShape(.rect)
                        .cardSurface()
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("more.deleteAccount")

                    VStack(spacing: 0) {
                        LegalWebRow(document: .accountDeletion)
                        Divider().padding(.leading, 58)
                        LegalWebRow(document: .privacyPolicy)
                    }
                    .cardSurface()

                    LegalLinksView(documents: [.privacyPolicy, .termsOfService, .smsTerms])
                        .padding(.horizontal, 4)
                }

                Button {
                    // One entry point for both stacks. The production path also
                    // removes this device's push registration before the session
                    // that owns it is discarded, which the development path has
                    // nothing to do.
                    Task { await env.signOutOfCurrentSession() }
                } label: {
                    Text("Sign out")
                        .font(.headline)
                        .foregroundStyle(Theme.red)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                        .cardSurface()
                }
                .buttonStyle(PressableTileStyle())

                if env.isDevelopmentSession {
                    SimulatedServicesBanner()
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 24)
        }
        .refreshable { await reload(showLoading: false) }
    }

    private func identityCard(_ overview: MoreOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(overview.companyName)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)

            HStack(spacing: 8) {
                Text(session?.displayName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondary)
                Text(overview.roleTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.primaryTint)
                    .clipShape(.rect(cornerRadius: 6))
                Text(overview.tradeTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.canvas)
                    .clipShape(.rect(cornerRadius: 6))
            }

            // The Apple subscription position, one line, for the owner only.
            if let commercial = viewModel.commercial {
                HStack(spacing: 8) {
                    Image(systemName: commercial.hasEntitlement ? "checkmark.seal.fill" : "sparkles")
                        .font(.caption)
                        .foregroundStyle(commercial.entitlementState.tone == .warning ? Theme.amber
                                         : commercial.hasEntitlement ? Theme.primary : Theme.accent)
                    Text(commercial.headline)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(commercial.entitlementState.tone == .warning ? Theme.amber : Theme.secondary)
                    Spacer(minLength: 0)
                }
            }

            if let subscription = overview.subscriptionSummary {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "creditcard")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                    Text(subscription)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                    if env.isDevelopmentSession {
                        SimulatedBadge()
                    }
                }
            }

            if let sms = overview.smsBalance {
                HStack(spacing: 8) {
                    Image(systemName: "message")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                    Text("\(sms) SMS credits")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .padding(.top, 4)
    }

    private func sectionRow(_ section: MoreSection, overview: MoreOverview) -> some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbolName)
                .font(.footnote)
                .foregroundStyle(needsAttention(section) ? Color.white : Theme.primary)
                .frame(width: 32, height: 32)
                .background(needsAttention(section) ? Theme.accent : Theme.primaryTint)
                .clipShape(.rect(cornerRadius: 8))

            Text(section.menuTitle(terms))
                .font(.body)
                .foregroundStyle(Theme.ink)

            Spacer(minLength: 4)

            if needsAttention(section) {
                Text("Not set")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.accentTint)
                    .clipShape(.capsule)
            } else if let detail = detailText(for: section, overview: overview) {
                Text(detail)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.meta)
            }

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.meta)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: Theme.minTap)
        .contentShape(.rect)
    }

    /// Rows that are waiting on the owner to do something.
    ///
    /// Only the business email qualifies today: until it is set, every invoice
    /// a customer receives has no return address that belongs to the business.
    /// The accent marks it so the gap is visible from the menu rather than
    /// discovered after an invoice has already gone out.
    private func needsAttention(_ section: MoreSection) -> Bool {
        section == .businessEmail && (viewModel.commercial?.businessEmail?.isEmpty ?? true)
    }

    private func detailText(for section: MoreSection, overview: MoreOverview) -> String? {
        switch section {
        // #13 — an unread count on the row itself, so a waiting message is
        // visible from the menu rather than only after opening it.
        case .messages:
            let unread = max(viewModel.unreadMessageCount, env.communications.unread.officeUnread)
            return unread > 0 ? "\(unread) unread" : nil
        case .communications:
            let unread = env.communications.unread.customerUnread
            return unread > 0 ? "\(unread) new" : nil
        case .fieldWorkers: return overview.workerCount.map(String.init)
        case .quotes: return overview.quoteCount.map(String.init)
        case .invoices: return overview.outstandingLabel
        case .payments: return overview.paymentCount.map(String.init)
        case .smsCredits: return overview.smsBalance.map(String.init)
        case .subscription:
            if let commercial = viewModel.commercial {
                return commercial.planName ?? commercial.entitlementState.pillText
            }
            return overview.subscriptionSummary
        case .payments_integration:
            return viewModel.commercial?.stripeState.shortLabel
        default: return nil
        }
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, session: session, showLoading: showLoading)
    }
}

#Preview {
    MoreView()
        .environment(AppEnvironment())
}
