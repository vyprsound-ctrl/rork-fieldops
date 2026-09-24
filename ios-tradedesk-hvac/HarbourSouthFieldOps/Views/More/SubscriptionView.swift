import StoreKit
import SwiftUI

/// The company's Harbour South subscription.
///
/// Three plans, one decision: "Starter = me", "Team = my small team",
/// "Business = my business, 10+ people". Billed by Apple. The screen shows
/// where the company stands (decided by the server from Apple's verified
/// data), the three plans with a Monthly / Annual switch, and Restore.
///
/// Customer card payments (Stripe) are a separate concept with their own
/// screen, More → Connect Stripe. This screen links there and nothing more.
struct SubscriptionView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.openURL) private var openURL
    @State private var viewModel = SubscriptionViewModel()
    @State private var isRedeemingCode: Bool = false

    private var session: TenantSession? { env.activeSession }

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: session?.userID) { await reload() }
        .refreshable { await reload(showLoading: false) }
        .offerCodeRedemption(isPresented: $isRedeemingCode) { _ in
            Task {
                await env.syncStoreEntitlements()
                await reload(showLoading: false)
                await env.refreshWorkspaceAccess()
            }
        }
        .sensoryFeedback(.success, trigger: viewModel.notice)
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.actionError != nil },
                set: { if !$0 { viewModel.actionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.actionError = nil }
        } message: {
            Text(viewModel.actionError ?? "")
        }
        .alert(
            "Fewer seats on this plan",
            isPresented: Binding(
                get: { viewModel.pendingSeatWarning != nil },
                set: { if !$0 { viewModel.pendingSeatWarning = nil } }
            )
        ) {
            Button("Continue") {
                guard let plan = viewModel.pendingSeatWarning?.plan else { return }
                viewModel.pendingSeatWarning = nil
                Task { await buy(plan, acknowledgedSeats: true) }
            }
            Button("Cancel", role: .cancel) { viewModel.pendingSeatWarning = nil }
        } message: {
            Text(viewModel.pendingSeatWarning?.message ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            LoadingStateView(message: "Loading plans")
        case .failed(let error):
            ErrorStateView(error: error) { Task { await reload() } }
        case .loaded(let overview):
            loaded(overview)
        }
    }

    private func loaded(_ overview: SubscriptionOverview) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let notice = viewModel.notice {
                noticeBanner(notice)
            }
            if let caution = viewModel.caution {
                cautionBanner(caution)
            }

            if let commercial = viewModel.commercial {
                SubscriptionStatusCard(commercial: commercial)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if let problem = viewModel.commercialError {
                unavailableCard(problem)
            }

            plansSection(overview)

            peopleCard(overview)

            storeActions(overview)

            paymentsLink()

            legalFooter(overview)
        }
        .padding(.top, 4)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: viewModel.commercial)
    }

    // MARK: - Plans

    private func plansSection(_ overview: SubscriptionOverview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(viewModel.commercial?.hasEntitlement == true ? "Change plan" : "Choose your plan")
                    .sectionLabelStyle()
                Spacer()
            }

            PeriodSwitch(period: $viewModel.period, savingPercent: overview.plans.map(\.annualSavingPercent).max() ?? 20)

            VStack(spacing: 12) {
                ForEach(overview.plans) { plan in
                    PlanCard(
                        plan: plan,
                        period: viewModel.period,
                        priceLabel: viewModel.priceLabel(for: plan, period: viewModel.period),
                        freeTrialDays: viewModel.commercial?.hasEntitlement == true
                            ? nil : viewModel.freeTrialDays(for: plan, period: viewModel.period),
                        isCurrent: viewModel.isCurrent(plan),
                        isRecommended: !(viewModel.commercial?.hasEntitlement ?? false)
                            && PlanCatalog.recommended(forActiveUsers: overview.activeUsers, in: overview.plans)?.id == plan.id,
                        tooSmall: !plan.fits(activeUsers: activeUsers(overview)),
                        activeUsers: activeUsers(overview),
                        isWorking: viewModel.workingProductID == plan.productID(for: viewModel.period),
                        isDisabled: viewModel.isWorking || !overview.canManage || viewModel.isBilledToAnotherAppleID,
                        actionTitle: actionTitle(for: plan)
                    ) {
                        Task { await buy(plan) }
                    }
                }
            }

            if !overview.canManage {
                Text("Only the account owner can choose or change the plan.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
            } else if viewModel.isBilledToAnotherAppleID {
                Text(SubscriptionViewModel.billedElsewhereMessage)
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("subscription.billedElsewhere")
            }
            if !overview.pricesAreLive || viewModel.storeUnavailable {
                Text("Showing standard US prices. Your App Store price is confirmed by Apple before you pay.")
                    .font(.caption)
                    .foregroundStyle(Theme.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func activeUsers(_ overview: SubscriptionOverview) -> Int {
        viewModel.commercial?.activeUsers ?? overview.activeUsers
    }

    private func actionTitle(for plan: PlanOffer) -> String {
        guard let commercial = viewModel.commercial, commercial.hasEntitlement, let current = commercial.planID else {
            if let days = viewModel.freeTrialDays(for: plan, period: viewModel.period) {
                return "Start \(days)-day free trial"
            }
            return "Choose \(plan.displayName)"
        }
        if current == plan.id {
            return commercial.billingPeriod == viewModel.period ? "Current plan" : "Switch to \(viewModel.period.title.lowercased())"
        }
        let order = PlanID.allCases
        let isUpgrade = (order.firstIndex(of: plan.id) ?? 0) > (order.firstIndex(of: current) ?? 0)
        return isUpgrade ? "Upgrade to \(plan.displayName)" : "Move to \(plan.displayName)"
    }

    // MARK: - People

    private func peopleCard(_ overview: SubscriptionOverview) -> some View {
        let commercial = viewModel.commercial
        let limit = commercial?.userLimit
        let active = commercial?.activeUsers ?? overview.activeUsers
        return VStack(alignment: .leading, spacing: 8) {
            Text("People").sectionLabelStyle()
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(active)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text(limit.map { "of \($0) on your plan" } ?? (commercial?.hasEntitlement == true ? "active · no limit" : "active"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                }
                if let limit, limit > 0 {
                    SeatMeter(active: active, limit: limit)
                }
                if overview.invitedUsers > 0 || overview.suspendedUsers > 0 {
                    Text("\(overview.invitedUsers) invited · \(overview.suspendedUsers) suspended — neither counts until active.")
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
                if let commercial, commercial.isOverPlan, commercial.hasEntitlement, let limit {
                    let excess = max(active - limit, 0)
                    Text("Your plan allows \(limit) active \(limit == 1 ? "user" : "users"). Deactivate \(excess) \(excess == 1 ? "user" : "users") in Team to continue normal work — you choose who, and nobody is removed automatically.")
                        .font(.caption)
                        .foregroundStyle(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("subscription.overPlan")
                }
                if let commercial, commercial.hasEntitlement, let next = commercial.renewsToPlanID, next != commercial.planID,
                   let pending = PlanCatalog.standard.first(where: { $0.id == next }), let pendingLimit = pending.userLimit {
                    Text("Your plan changes to \(pending.displayName) at renewal, which allows \(pendingLimit) active \(pendingLimit == 1 ? "user" : "users"). Until then you can't add more people than that.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("subscription.pendingDowngrade")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
    }

    // MARK: - Store actions

    private func storeActions(_ overview: SubscriptionOverview) -> some View {
        VStack(spacing: 10) {
            if overview.canManage {
                HStack(spacing: 10) {
                    Button {
                        Task { await restore() }
                    } label: {
                        BrandOutlineLabel(
                            title: viewModel.isRestoring ? "Restoring…" : "Restore purchases",
                            symbol: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(viewModel.isWorking)

                    Button {
                        isRedeemingCode = true
                    } label: {
                        BrandOutlineLabel(title: "Redeem code", symbol: "ticket")
                    }
                    .buttonStyle(PressableTileStyle())
                    .disabled(viewModel.isWorking || !env.isProductionSession)
                }

                if viewModel.commercial?.billingStore == .apple {
                    Button {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") { openURL(url) }
                    } label: {
                        BrandOutlineLabel(title: "Manage in the App Store", symbol: "apple.logo", tint: Theme.secondary)
                    }
                    .buttonStyle(PressableTileStyle())
                }
            }
        }
    }

    // MARK: - Payments signpost

    /// Stripe is a separate thing: what the business's own customers pay
    /// them. It lives in More → Connect Stripe; this is only the way there.
    private func paymentsLink() -> some View {
        NavigationLink(value: AppRoute.more(.payments_integration)) {
            HStack(spacing: 12) {
                Image(systemName: "creditcard")
                    .font(.title3)
                    .foregroundStyle(Theme.primary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Taking customer payments?")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("That's Stripe, set up separately under Connect Stripe.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.meta)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
            .contentShape(.rect)
        }
        .buttonStyle(PressableTileStyle())
    }

    // MARK: - Legal

    private func legalFooter(_ overview: SubscriptionOverview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Subscriptions are billed by Apple to your Apple ID and renew automatically at the end of each period unless cancelled at least 24 hours before it ends. A free trial, where offered, turns into the paid plan you chose when it ends unless you cancel first. Manage or cancel any time in Settings → Apple ID → Subscriptions.")
            LegalLinksView()
        }
        .font(.caption2)
        .foregroundStyle(Theme.meta)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Small cards

    private func noticeBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.green)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Theme.green.opacity(0.10))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func cautionBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.primary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("subscription.caution")
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Theme.primaryTint)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    private func unavailableCard(_ problem: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Theme.amber)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your plan couldn't be loaded")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.amber.opacity(0.10))
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
    }

    // MARK: - Actions

    private func buy(_ plan: PlanOffer, acknowledgedSeats: Bool = false) async {
        guard let session else { return }
        await viewModel.buy(plan, gateway: env.gateway, store: env.storeBilling, session: session, acknowledgedSeats: acknowledgedSeats)
        await env.refreshWorkspaceAccess()
    }

    private func restore() async {
        guard let session else { return }
        await viewModel.restore(gateway: env.gateway, store: env.storeBilling, session: session)
        await env.refreshWorkspaceAccess()
    }

    private func reload(showLoading: Bool = true) async {
        guard let session else { return }
        await viewModel.load(gateway: env.gateway, store: env.storeBilling, session: session, showLoading: showLoading)
    }
}

// MARK: - Components

/// Where the company stands, in one card.
private struct SubscriptionStatusCard: View {
    let commercial: CommercialState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(tint.gradient)
                    .clipShape(.rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(commercial.planName ?? "No plan yet")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(commercial.headline)
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 0)
                StatusPill(badge: StatusBadge(text: commercial.entitlementState.pillText, tone: commercial.entitlementState.tone))
            }
            if let detail = commercial.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch commercial.entitlementState {
        case .trial, .offer: return "gift.fill"
        case .active, .cancelling: return "checkmark.seal.fill"
        case .gracePeriod, .billingRetry: return "exclamationmark.triangle.fill"
        case .none, .expired, .revoked: return "sparkles"
        }
    }

    private var tint: Color {
        switch commercial.entitlementState.tone {
        case .success: return Theme.green
        case .info: return Theme.primary
        case .warning: return Theme.amber
        case .danger: return Theme.red
        case .neutral: return Theme.accent
        }
    }
}

/// Monthly / Annual, with the saving stated on the switch itself.
private struct PeriodSwitch: View {
    @Binding var period: BillingPeriod
    let savingPercent: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(BillingPeriod.allCases) { option in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { period = option }
                } label: {
                    HStack(spacing: 6) {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                        if option == .annual {
                            Text("Save \(savingPercent)%")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(period == .annual ? Color.white.opacity(0.25) : Theme.accentTint)
                                .foregroundStyle(period == .annual ? Color.white : Theme.accentText)
                                .clipShape(.capsule)
                        }
                    }
                    .foregroundStyle(period == option ? Color.white : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if period == option {
                            RoundedRectangle(cornerRadius: 10).fill(Theme.primary)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(period == option ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.surfaceAlt)
        .clipShape(.rect(cornerRadius: 13))
        .sensoryFeedback(.selection, trigger: period)
    }
}

/// One plan: who it is for, the price, how many people, one button.
private struct PlanCard: View {
    let plan: PlanOffer
    let period: BillingPeriod
    let priceLabel: String
    let freeTrialDays: Int?
    let isCurrent: Bool
    let isRecommended: Bool
    let tooSmall: Bool
    let activeUsers: Int
    let isWorking: Bool
    let isDisabled: Bool
    let actionTitle: String
    let action: () -> Void

    private var symbol: String {
        switch plan.id {
        case .starter: return "person.fill"
        case .team: return "person.2.fill"
        case .business: return "person.3.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(isCurrent ? Color.white : Theme.primary)
                    .frame(width: 42, height: 42)
                    .background(isCurrent ? AnyShapeStyle(Theme.primary.gradient) : AnyShapeStyle(Theme.primaryTint))
                    .clipShape(.rect(cornerRadius: 11))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plan.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        if isCurrent {
                            tag("Current", fill: Theme.primaryTint, text: Theme.primary)
                        } else if isRecommended {
                            tag("Best fit", fill: Theme.accentTint, text: Theme.accentText)
                        }
                    }
                    Text(plan.tagline)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondary)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(priceLabel)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink)
                        .contentTransition(.numericText())
                    Text(period.perUnit)
                        .font(.caption)
                        .foregroundStyle(Theme.meta)
                }
            }

            HStack(spacing: 14) {
                Label(plan.usersLabel, systemImage: "person.crop.circle.badge.checkmark")
                if period == .annual {
                    Label("Save \(PriceLabel.usd(plan.annualSavingCents))/yr", systemImage: "tag.fill")
                        .foregroundStyle(Theme.green)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondary)

            if tooSmall, let limit = plan.userLimit {
                let excess = max(activeUsers - limit, 0)
                Text("You have \(activeUsers) active people — more than \(plan.displayName) includes. After the change you'll deactivate \(excess) \(excess == 1 ? "person" : "people") before normal work continues; you choose who, and they can be reactivated later.")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan-\(plan.id.rawValue)-seats")
            }

            if !isCurrent {
                Button(action: action) {
                    BrandButtonLabel(
                        title: actionTitle,
                        role: isRecommended ? .accent : .primary,
                        isEnabled: !isDisabled,
                        isWorking: isWorking
                    )
                }
                .buttonStyle(PressableTileStyle())
                .disabled(isDisabled)

                if let freeTrialDays {
                    Text("Free for \(freeTrialDays) days, then \(priceLabel)\(period.perUnit). Cancel any time before the trial ends.")
                        .font(.caption2)
                        .foregroundStyle(Theme.meta)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(.rect(cornerRadius: Theme.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(isCurrent ? Theme.primary : (isRecommended ? Theme.accent.opacity(0.55) : Theme.border),
                        lineWidth: isCurrent || isRecommended ? 1.5 : 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-\(plan.id.rawValue)")
    }

    private func tag(_ text: String, fill: Color, text textColor: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(fill)
            .clipShape(.capsule)
    }
}

/// Seats used against the plan, as a bar that fills.
private struct SeatMeter: View {
    let active: Int
    let limit: Int

    private var fraction: Double { min(Double(active) / Double(max(limit, 1)), 1) }
    private var tint: Color { active > limit ? Theme.amber : (active == limit ? Theme.accent : Theme.primary) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceAlt)
                Capsule().fill(tint.gradient)
                    .frame(width: max(proxy.size.width * fraction, 8))
            }
        }
        .frame(height: 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: fraction)
        .accessibilityLabel("\(active) of \(limit) people")
    }
}
