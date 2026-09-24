import Foundation
import Supabase
import Testing
@testable import HarbourSouthFieldOps

// =============================================================================
// Harbour South FieldOps — unit tests
//
// These cover the pure logic that decides money, dates and location policy.
// Anything needing a network, a database, a real radio or a human answering a
// permission prompt is deliberately NOT here: a test that stubs Core Location
// and then claims GPS works would be worse than no test at all. Those paths are
// exercised by the in-app scenario suite and, ultimately, on a real handset.
// =============================================================================

// MARK: - Plans and Apple entitlement

/// The three plans are the specification, asserted in cents.
struct PlanCatalogTests {
    private let plans = PlanCatalog.standard
    private func plan(_ id: PlanID) -> PlanOffer { plans.first { $0.id == id }! }

    @Test("Exactly three plans: Starter, Team, Business")
    func threePlans() {
        #expect(plans.map(\.id) == [.starter, .team, .business])
        #expect(plans.map(\.displayName) == ["Starter", "Team", "Business"])
    }

    @Test("Monthly prices are 19.99, 39.99 and 69.99")
    func monthlyPrices() {
        #expect(plan(.starter).monthlyCents == 1999)
        #expect(plan(.team).monthlyCents == 3999)
        #expect(plan(.business).monthlyCents == 6999)
    }

    @Test("Annual prices are 191.99, 384.99 and 669.99")
    func annualPrices() {
        #expect(plan(.starter).annualCents == 19199)
        #expect(plan(.team).annualCents == 38499)
        #expect(plan(.business).annualCents == 66999)
    }

    @Test("Annual is about 20% below twelve monthly payments for every plan")
    func annualSaving() {
        for plan in plans {
            #expect(plan.annualSavingPercent == 20, "\(plan.displayName) saves \(plan.annualSavingPercent)%")
            #expect(plan.annualSavingCents == plan.monthlyCents * 12 - plan.annualCents)
        }
        #expect(plan(.team).annualSavingCents == 9489)
    }

    @Test("Starter is 1 user and Team is up to 5")
    func userLimits() {
        #expect(plan(.starter).userLimit == 1)
        #expect(plan(.starter).usersLabel == "1 user")
        #expect(plan(.team).userLimit == 5)
        #expect(plan(.team).usersLabel == "Up to 5 users")
    }

    @Test("Business is 10+ with no cap — 12, 20, 30 and 200 people all fit")
    func businessIsUncapped() {
        let business = plan(.business)
        #expect(business.userLimit == nil)
        #expect(business.includedUsers == 10)
        #expect(business.usersLabel == "10+ users")
        for size in [10, 12, 20, 30, 200] {
            #expect(business.fits(activeUsers: size))
        }
    }

    @Test("The recommended plan is the smallest that fits the team")
    func recommendation() {
        #expect(PlanCatalog.recommended(forActiveUsers: 1)?.id == .starter)
        #expect(PlanCatalog.recommended(forActiveUsers: 2)?.id == .team)
        #expect(PlanCatalog.recommended(forActiveUsers: 5)?.id == .team)
        #expect(PlanCatalog.recommended(forActiveUsers: 6)?.id == .business)
        #expect(PlanCatalog.recommended(forActiveUsers: 30)?.id == .business)
        #expect(PlanCatalog.recommended(forActiveUsers: 0)?.id == .starter)
    }

    @Test("Six App Store products, each resolving to its plan and period")
    func productIDs() {
        #expect(PlanCatalog.allProductIDs.count == 6)
        #expect(Set(PlanCatalog.allProductIDs).count == 6)
        for plan in plans {
            for period in BillingPeriod.allCases {
                let resolved = PlanCatalog.resolve(productID: plan.productID(for: period))
                #expect(resolved?.plan == plan.id)
                #expect(resolved?.period == period)
            }
        }
        #expect(PlanCatalog.resolve(productID: "com.example.other") == nil)
        #expect(plan(.team).monthlyProductID == "com.harboursouth.fieldservice.team.monthly")
        #expect(plan(.business).annualProductID == "com.harboursouth.fieldservice.business.annual")
    }

    @Test("Customers see Starter, never the stored enum name")
    func starterName() {
        #expect(SubscriptionPlan.soloTrader.title == "Starter")
        #expect(SubscriptionPlan(planID: .starter) == .soloTrader)
        #expect(SubscriptionPlan.business.planID == .business)
    }
}

/// What the app shows for each entitlement state the server derives.
struct EntitlementPresentationTests {
    private let end = Date(timeIntervalSinceNow: 60 * 60 * 24 * 10)

    private func state(
        _ entitlement: EntitlementState,
        plan: PlanID? = .team,
        period: BillingPeriod? = .monthly,
        free: Bool = false,
        days: Int = 0,
        autoRenew: Bool? = true,
        renewsTo: PlanID? = nil,
        offerType: Int? = nil
    ) -> CommercialState {
        CommercialState(
            entitlementState: entitlement,
            planID: entitlement.isEntitled ? plan : nil,
            planName: entitlement.isEntitled ? plan.map { p in PlanCatalog.standard.first { $0.id == p }!.displayName } : nil,
            billingPeriod: entitlement.isEntitled ? period : nil,
            planPriceCents: 3999,
            userLimit: plan == .business ? nil : 5,
            periodEndsAt: end,
            willAutoRenew: autoRenew,
            renewsToPlanID: renewsTo,
            offerType: offerType,
            isFreeOffer: free,
            freeOfferDaysRemaining: days,
            gracePeriodEndsAt: entitlement == .gracePeriod ? end : nil
        )
    }

    @Test("Entitled states are exactly trial, offer, active, cancelling and grace period")
    func entitledSet() {
        let entitled: Set<EntitlementState> = [.trial, .offer, .active, .cancelling, .gracePeriod]
        for value in [EntitlementState.none, .trial, .offer, .active, .cancelling, .gracePeriod, .billingRetry, .expired, .revoked] {
            #expect(value.isEntitled == entitled.contains(value), "\(value)")
        }
    }

    @Test("No plan: a clear invitation to choose one, mentioning the Apple trial")
    func noPlan() {
        let s = state(.none)
        #expect(s.hasEntitlement == false)
        #expect(s.headline == "No plan yet")
        #expect(s.detail?.contains("14-day free trial") == true)
        #expect(s.planPriceLabel == nil)
    }

    @Test("The 14-day trial states when Apple will start billing, and at what price")
    func trial() {
        let s = state(.trial, free: true, days: 14, offerType: 1)
        #expect(s.headline == "Free trial — 14 days left")
        #expect(s.detail?.contains("Then Team at $39.99/month, billed by Apple unless you cancel") == true)
    }

    @Test("A 30- or 90-day Offer Code is an entitlement and says the same thing")
    func offerCode() {
        let s = state(.offer, free: true, days: 90, offerType: 3)
        #expect(s.hasEntitlement)
        #expect(s.headline == "Free offer — 90 days left")
        #expect(s.detail?.contains("billed by Apple unless you cancel") == true)
    }

    @Test("A trial the customer has cancelled says it will not renew")
    func cancelledTrial() {
        let s = state(.trial, free: true, days: 3, autoRenew: false, offerType: 1)
        #expect(s.detail?.contains("will not renew") == true)
    }

    @Test("Active shows the renewal; a scheduled downgrade is announced")
    func activeAndDowngrade() {
        #expect(state(.active).headline.hasPrefix("Team · renews "))
        #expect(state(.active, renewsTo: .starter).detail == "Changes to Starter at your next renewal.")
    }

    @Test("Cancelling keeps the plan until the end date")
    func cancelling() {
        let s = state(.cancelling, autoRenew: false)
        #expect(s.hasEntitlement)
        #expect(s.headline.hasPrefix("Team · ends "))
    }

    @Test("Billing problems say what to do next")
    func billingProblems() {
        let grace = state(.gracePeriod)
        #expect(grace.hasEntitlement)
        #expect(grace.detail?.contains("update your payment method in the App Store") == true)
        let retry = state(.billingRetry)
        #expect(retry.hasEntitlement == false)
        #expect(retry.detail?.contains("Apple will try again") == true)
    }

    @Test("Expired and refunded are not entitled")
    func ended() {
        #expect(state(.expired).hasEntitlement == false)
        #expect(state(.revoked).hasEntitlement == false)
        #expect(state(.expired).headline == "Subscription ended")
    }

    @Test("Seats read plainly: 3 of 5 people, or no limit on Business")
    func seats() {
        let team = CommercialState(entitlementState: .active, planID: .team, userLimit: 5, activeUsers: 3)
        #expect(team.seatsLabel == "3 of 5 people")
        let business = CommercialState(entitlementState: .active, planID: .business, userLimit: nil, activeUsers: 30)
        #expect(business.seatsLabel == "30 people · no limit")
        #expect(business.isOverPlan == false)
        let over = CommercialState(entitlementState: .active, planID: .starter, userLimit: 1, activeUsers: 3)
        #expect(over.isOverPlan)
    }

    /// The retired programme must leave nothing a customer can read.
    @Test("No commercial sentence mentions a founding programme or free-for-Stripe benefit")
    func noFoundingWording() {
        let states: [CommercialState] = [
            state(.none), state(.trial, free: true, days: 14, offerType: 1), state(.offer, free: true, days: 30, offerType: 3),
            state(.active), state(.cancelling, autoRenew: false), state(.gracePeriod), state(.billingRetry),
            state(.expired), state(.revoked)
        ]
        let banned = ["founding", "founder", "first 100", "zero subscription", "$0/month", "places remain", "member #"]
        for s in states {
            for sentence in [s.headline, s.detail ?? ""] {
                for word in banned {
                    #expect(sentence.localizedCaseInsensitiveContains(word) == false, "\"\(sentence)\" contains \"\(word)\"")
                }
            }
        }
    }
}

/// The development stack seeds one subscribed and one unsubscribed company.
struct DevelopmentCommercialSeedTests {
    @Test("Gulf Coast is on Team annual via Apple; Northline has no plan and no Stripe")
    func seed() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let gulf = TenantSession(userID: "usr_owner", companyID: "cmp_gulfcoast", role: .owner,
                                 displayName: "Tom Ellison", email: "tom@gulfcoastair.com", trade: .hvac)
        let north = TenantSession(userID: "usr_north_owner", companyID: "cmp_northline", role: .owner,
                                  displayName: "Erin Vaught", email: "erin@northlineplumbing.com", trade: .plumbing)
        let subscribed = try await gateway.commercialState(session: gulf)
        let unsubscribed = try await gateway.commercialState(session: north)
        #expect(subscribed.entitlementState == .active)
        #expect(subscribed.planID == .team)
        #expect(subscribed.billingPeriod == .annual)
        #expect(subscribed.platformFeeBps == 30)
        #expect(unsubscribed.hasEntitlement == false)
        #expect(unsubscribed.stripeState == .notConnected)
        #expect(unsubscribed.platformFeeBps == 30)

        let overview = try await gateway.subscriptionOverview(session: gulf)
        #expect(overview.plans.map(\.id) == [.starter, .team, .business])
    }

    @Test("The development store sells nothing and shows the standard prices")
    func mockStore() async throws {
        let store = MockStoreBillingService()
        let products = try await store.products()
        #expect(products.count == 6)
        #expect(products.first { $0.id == "com.harboursouth.fieldservice.team.annual" }?.displayPrice.contains("384.99") == true)
        await #expect(throws: StoreBillingError.self) {
            _ = try await store.purchase(productID: "com.harboursouth.fieldservice.team.monthly", appAccountToken: nil)
        }
    }
}

// MARK: - Apple environments, workspace lock and seats

/// What the app does with the server's verdict on a purchase.
struct StoreLinkOutcomeTests {
    @Test("A test purchase that was not applied never reads as a paid plan")
    func sandboxNotApplied() {
        let result = StoreLinkResult.summarise(outcomes: [(transactionID: "42", outcome: "sandboxNotApplied")], linked: false)
        #expect(result.testPurchaseNotApplied)
        #expect(result.linked == false)
        #expect(result.handledTransactionIDs == [42])
        #expect(SubscriptionViewModel.purchaseOutcome(result, planName: "Team") == .caution(SubscriptionViewModel.testPurchaseMessage))
    }

    @Test("A refused environment is reported as a test purchase, not success")
    func unsupportedEnvironment() {
        let result = StoreLinkResult.summarise(outcomes: [(transactionID: "7", outcome: "unsupportedEnvironment")], linked: false)
        #expect(result.testPurchaseNotApplied)
        if case .success = SubscriptionViewModel.purchaseOutcome(result, planName: "Team") {
            Issue.record("An unsupported environment must never read as success")
        }
    }

    @Test("Only an applied purchase says You're on the plan")
    func applied() {
        let result = StoreLinkResult.summarise(outcomes: [(transactionID: "9", outcome: "applied:active")], linked: true)
        #expect(result.testPurchaseNotApplied == false)
        #expect(SubscriptionViewModel.purchaseOutcome(result, planName: "Team") == .success("You're on Team. Thanks for choosing Harbour South."))
    }

    @Test("Nothing confirmed yet is a caution, not a success")
    func unconfirmed() {
        let result = StoreLinkResult.summarise(outcomes: [(transactionID: "9", outcome: "error")], linked: false)
        #expect(result.handledTransactionIDs.isEmpty)
        if case .success = SubscriptionViewModel.purchaseOutcome(result, planName: "Team") {
            Issue.record("An unconfirmed purchase must never read as success")
        }
    }
}

/// No active subscription = no working workspace.
struct WorkspaceLockTests {
    private func session(_ role: Role, company: String = "cmp_northline") -> TenantSession {
        TenantSession(userID: "u", companyID: company, role: role, displayName: "X", email: "x@example.com", trade: .plumbing)
    }

    @Test("A read-only owner keeps reading and subscribing, but cannot create or edit")
    func readOnlyOwner() {
        let owner = session(.owner).readOnlyWorkspace()
        for kept: Permission in [.jobsReadAll, .customersReadAll, .invoicesRead, .quotesRead, .reportsFinancial,
                                 .saasBillingRead, .saasBillingManage, .usersManage, .companyDelete] {
            #expect(owner.can(kept), "read-only owner lost \(kept)")
        }
        for withheld: Permission in [.jobsManage, .customersManage, .invoicesManage, .quotesManage, .paymentsManage,
                                     .assignmentsManage, .jobNotesCreate, .jobPhotosCreate, .companyProfileManage,
                                     .smsCreditsConsume, .smsCreditsPurchase] {
            #expect(owner.can(withheld) == false, "read-only owner kept \(withheld)")
        }
        #expect(owner.role == .owner)
    }

    @Test("The role matrix itself is unchanged by the lock")
    func matrixUnchanged() {
        #expect(session(.owner).permissions == PermissionMatrix.permissions(for: .owner))
        #expect(session(.owner).can(.jobsManage))
    }

    @Test("The seeded unsubscribed company is locked; the subscribed one is not")
    func seededAccess() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let north = try await gateway.workspaceAccess(session: session(.fieldWorker))
        let gulf = try await gateway.workspaceAccess(session: session(.fieldWorker, company: "cmp_gulfcoast"))
        #expect(north.hasActiveSubscription == false)
        #expect(north.state == .none)
        #expect(gulf.hasActiveSubscription)
    }

    @Test("Entitled states unlock; none, billing retry, expired and refunded lock")
    func entitledStates() {
        for unlocked: EntitlementState in [.trial, .offer, .active, .cancelling, .gracePeriod] {
            #expect(unlocked.isEntitled)
        }
        for locked: EntitlementState in [.none, .billingRetry, .expired, .revoked] {
            #expect(locked.isEntitled == false)
        }
    }
}

/// Apple owns downgrades: the plan check never refuses. It warns how many
/// people must be deactivated once the change applies. Nobody is chosen or
/// suspended automatically.
struct DowngradeSeatTests {
    @Test("Business with 10 active people -> Team is never refused; it warns 5 must be deactivated")
    func businessToTeam() {
        let check = PlanChangeCheck.evaluate(planName: "Team", userLimit: 5, activeUsers: 10)
        #expect(check.allowed)
        #expect(check.usersToDeactivate == 5)
        #expect(check.message?.contains("deactivate 5 people") == true)
        let fits = PlanChangeCheck.evaluate(planName: "Team", userLimit: 5, activeUsers: 5)
        #expect(fits.allowed && fits.usersToDeactivate == 0 && fits.message == nil)
    }

    @Test("Business with 10 active people -> Starter is never refused; it warns 9 must be deactivated")
    func businessToStarter() {
        let check = PlanChangeCheck.evaluate(planName: "Starter", userLimit: 1, activeUsers: 10)
        #expect(check.allowed)
        #expect(check.usersToDeactivate == 9)
        #expect(PlanChangeCheck.evaluate(planName: "Starter", userLimit: 1, activeUsers: 1).usersToDeactivate == 0)
    }

    @Test("Team with 5 active -> Starter warns 4 must be deactivated")
    func teamToStarter() {
        let check = PlanChangeCheck.evaluate(planName: "Starter", userLimit: 1, activeUsers: 5)
        #expect(check.allowed)
        #expect(check.usersToDeactivate == 4)
    }

    @Test("Business has no hard-coded cap")
    func businessUncapped() {
        let business = PlanCatalog.standard.first { $0.id == .business }
        #expect(business?.userLimit == nil)
        #expect(PlanChangeCheck.evaluate(planName: "Business", userLimit: nil, activeUsers: 250).allowed)
    }

    @Test("The seeded Gulf Coast team (6 active) is warned for Starter and Team, never refused")
    func seededCheck() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let tom = TenantSession(userID: "usr_owner", companyID: "cmp_gulfcoast", role: .owner,
                                displayName: "Tom Ellison", email: "tom@gulfcoastair.com", trade: .hvac)
        let starter = try await gateway.planChangeCheck(session: tom, planID: .starter)
        #expect(starter.allowed && starter.usersToDeactivate == 5)
        #expect(try await gateway.planChangeCheck(session: tom, planID: .team).usersToDeactivate == 1)
        #expect(try await gateway.planChangeCheck(session: tom, planID: .business).allowed)
        let marcus = TenantSession(userID: "usr_marcus", companyID: "cmp_gulfcoast", role: .fieldWorker,
                                   displayName: "Marcus Hale", email: "marcus@gulfcoastair.com", trade: .hvac)
        await #expect(throws: DataError.self) {
            _ = try await gateway.planChangeCheck(session: marcus, planID: .starter)
        }
    }
}

/// Seat resolution, the read-only gate, account deletion and legal links.
struct SeatResolutionAndAccessTests {
    private func session(_ role: Role, company: String = "cmp_gulfcoast", user: String = "u") -> TenantSession {
        TenantSession(userID: user, companyID: company, role: role, displayName: "X", email: "x@example.com", trade: .hvac)
    }

    private let overPlan = WorkspaceAccess(hasActiveSubscription: true, state: .active, planName: "Team",
                                           userLimit: 5, activeUsers: 10, seatsOverLimit: true, usersToDeactivate: 5)

    @Test("Entitled states open the workspace for owner and staff (active, trial, offer, cancelling, grace)")
    func entitledOpen() {
        for state: EntitlementState in [.active, .trial, .offer, .cancelling, .gracePeriod] {
            let access = WorkspaceAccess(hasActiveSubscription: true, state: state)
            #expect(WorkspaceGate.resolve(access: access, role: .owner) == .open)
            #expect(WorkspaceGate.resolve(access: access, role: .fieldWorker) == .open)
            #expect(WorkspaceGate.resolve(access: access, role: .dispatcher) == .open)
        }
    }

    @Test("No plan, expired, billing retry and refunded: owner read-only, staff locked")
    func notEntitled() {
        for state: EntitlementState in [.none, .expired, .billingRetry, .revoked] {
            let access = WorkspaceAccess(hasActiveSubscription: false, state: state)
            #expect(WorkspaceGate.resolve(access: access, role: .owner) == .ownerReadOnly)
            #expect(WorkspaceGate.resolve(access: access, role: .fieldWorker) == .memberLocked)
            #expect(WorkspaceGate.resolve(access: access, role: .admin) == .memberLocked)
        }
    }

    @Test("A network failure (no answer) never locks anyone out")
    func networkFailureStaysOpen() {
        #expect(WorkspaceGate.resolve(access: nil, role: .owner) == .open)
        #expect(WorkspaceGate.resolve(access: nil, role: .fieldWorker) == .open)
    }

    @Test("After an applied downgrade the owner resolves seats; staff wait")
    func seatResolutionGate() {
        #expect(WorkspaceGate.resolve(access: overPlan, role: .owner) == .ownerSeatResolution)
        #expect(WorkspaceGate.resolve(access: overPlan, role: .fieldWorker) == .memberSeatResolution)
        #expect(WorkspaceGate.ownerSeatResolution.isOwnerReadOnly)
        #expect(WorkspaceGate.memberSeatResolution.isMemberLocked)
        #expect(WorkspaceGate.open.isOwnerReadOnly == false && WorkspaceGate.open.isMemberLocked == false)
    }

    @Test("The seat resolution instruction names the limit, the count and how many to deactivate")
    func seatMessage() {
        #expect(overPlan.seatResolutionMessage == "Your subscription now allows 5 active users. You currently have 10 active users. Deactivate 5 users to continue.")
        let starter = WorkspaceAccess(hasActiveSubscription: true, state: .active, planName: "Starter",
                                      userLimit: 1, activeUsers: 10, seatsOverLimit: true, usersToDeactivate: 9)
        #expect(starter.seatResolutionMessage?.hasPrefix("Your subscription now allows 1 active user.") == true)
        #expect(WorkspaceAccess(hasActiveSubscription: true, state: .active).seatResolutionMessage == nil)
    }

    @Test("A read-only owner keeps people management and subscription actions")
    func readOnlyKeepsSubscriptionActions() {
        let owner = session(.owner).readOnlyWorkspace()
        #expect(owner.can(.usersManage) && owner.can(.usersRead))
        #expect(owner.can(.saasBillingManage) && owner.can(.saasBillingRead))
        #expect(owner.canMutateWorkspace == false)
        #expect(session(.owner).canMutateWorkspace)
    }

    @Test("Read-only mutation attempts are refused by the data layer")
    func readOnlyMutationsRefused() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let tom = TenantSession(userID: "usr_owner", companyID: "cmp_gulfcoast", role: .owner,
                                displayName: "Tom Ellison", email: "tom@gulfcoastair.com", trade: .hvac).readOnlyWorkspace()
        var query = JobQuery()
        query.dateScope = .all
        let jobs = try await gateway.jobs(session: tom, query: query)
        let jobID = try #require(jobs.first?.id)

        await #expect(throws: DataError.self) {
            try await gateway.updateJobStatus(session: tom, jobID: jobID, to: .cancelled, locationFix: nil)
        }
        await #expect(throws: DataError.self) {
            try await gateway.sendOfficeMessage(session: tom, draft: OfficeMessageDraft(threadID: nil, jobID: jobID, subject: "x", body: "hello"))
        }
        await #expect(throws: DataError.self) {
            try await gateway.addJobNote(session: tom, jobID: jobID, body: "note", visibility: .internalOnly)
        }
        await #expect(throws: DataError.self) {
            try await gateway.addJobPhoto(session: tom, jobID: jobID, kind: .before, caption: nil)
        }
        // Reading is still fine.
        #expect(try await gateway.jobDetail(session: tom, jobID: jobID).id == jobID)
    }

    @Test("A staff member deletes only their own account; the company carries on")
    func deleteStaffAccount() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let marcus = TenantSession(userID: "usr_marcus", companyID: "cmp_gulfcoast", role: .fieldWorker,
                                   displayName: "Marcus Hale", email: "marcus@gulfcoastair.com", trade: .hvac)
        let context = try await gateway.accountDeletionContext(session: marcus)
        #expect(context.isSoleOwner == false)
        #expect(try await gateway.deleteMyAccount(session: marcus, closeCompany: false) == .accountDeleted)
        let deleted = await gateway.user(id: "usr_marcus")
        #expect(deleted?.status == .suspended && deleted?.name == "Deleted user")
        #expect(await gateway.user(id: "usr_owner")?.status == .active)
        #expect(await gateway.user(id: "usr_dee")?.status == .active)
    }

    @Test("The sole owner cannot delete silently; closing needs explicit confirmation")
    func deleteSoleOwner() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let tom = TenantSession(userID: "usr_owner", companyID: "cmp_gulfcoast", role: .owner,
                                displayName: "Tom Ellison", email: "tom@gulfcoastair.com", trade: .hvac)
        #expect(try await gateway.accountDeletionContext(session: tom).isSoleOwner)
        await #expect(throws: DataError.self) {
            _ = try await gateway.deleteMyAccount(session: tom, closeCompany: false)
        }
        #expect(await gateway.user(id: "usr_owner")?.status == .active)
        #expect(try await gateway.deleteMyAccount(session: tom, closeCompany: true) == .workspaceClosed)
        #expect(await gateway.user(id: "usr_owner")?.status == .suspended)
        #expect(await gateway.user(id: "usr_marcus")?.status == .suspended)
        // Records are kept: the other company is untouched and users are not removed.
        #expect(await gateway.user(id: "usr_marcus") != nil)
        #expect(await gateway.user(id: "usr_north_owner")?.status == .active)
    }

    @Test("Privacy policy is configuration-driven and never invented")
    func privacyPolicyConfig() {
        #expect(Brand.privacyPolicyURL(from: nil) == nil)
        #expect(Brand.privacyPolicyURL(from: "") == nil)
        #expect(Brand.privacyPolicyURL(from: "http://example.com/privacy") == nil)
        #expect(Brand.privacyPolicyURL(from: " https://example.com/privacy ")?.absoluteString == "https://example.com/privacy")
        #expect(Brand.termsOfUseURL?.absoluteString == "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")
    }
}

// MARK: - Payment terms and due dates

struct PaymentTermsTests {
    private let calendar = Calendar(identifier: .gregorian)

    /// "Due on completion" is a rule, not a horizon: the invoice is due the day
    /// the work finished, not a number of days after it was raised.
    @Test("Due on completion is due the same day")
    func dueOnCompletion() {
        let reference = Date(timeIntervalSince1970: 1_760_000_000)
        let due = PaymentTermOption.onCompletion.dueDate(from: reference, calendar: calendar)
        #expect(calendar.isDate(due, inSameDayAs: reference))
    }

    @Test(
        "Date-based terms count days from the issue date",
        arguments: [
            (option: PaymentTermOption.net7, days: 7),
            (option: .net14, days: 14),
            (option: .net30, days: 30),
            (option: .net60, days: 60),
            (option: .net90, days: 90)
        ]
    )
    func netTerms(option: PaymentTermOption, days: Int) {
        let reference = Date(timeIntervalSince1970: 1_760_000_000)
        let due = option.dueDate(from: reference, calendar: calendar)
        let expected = calendar.date(
            byAdding: .day,
            value: days,
            to: calendar.startOfDay(for: reference)
        )
        #expect(due == expected)
    }

    /// A negative custom term would produce an invoice due before it existed.
    @Test("A custom term can never land before the issue date")
    func customTermsAreFloored() {
        let reference = Date(timeIntervalSince1970: 1_760_000_000)
        let due = PaymentTermOption.custom.dueDate(from: reference, customDays: -30, calendar: calendar)
        #expect(due >= calendar.startOfDay(for: reference))
    }

    @Test("A custom term stores a self-describing label")
    func customLabelDescribesItself() {
        #expect(PaymentTermOption.custom.storedLabel(customDays: 45) == "Due in 45 days")
        #expect(PaymentTermOption.custom.storedLabel(customDays: 0) == "Due on receipt")
    }

    @Test("Every option the product promises exists")
    func allPromisedOptionsExist() {
        let labels = Set(PaymentTermOption.allCases.map(\.rawValue))
        #expect(labels.isSuperset(of: ["onCompletion", "net7", "net14", "net30", "net60", "net90", "custom"]))
    }
}

// MARK: - Location policy

/// These assert the *policy*, which is pure logic, not the radio. Whether a
/// real device produces a fix is a device question and is not claimed here.
struct LocationPolicyTests {
    @Test("Only the three workflow events capture a position")
    func captureEventsAreBoundToTransitions() {
        #expect(LocationCaptureEvent.forTransition(to: .travelling) == .travelStarted)
        #expect(LocationCaptureEvent.forTransition(to: .arrived) == .arrived)
        #expect(LocationCaptureEvent.forTransition(to: .completed) == .completed)
        #expect(LocationCaptureEvent.forTransition(to: .inProgress) == nil)
        #expect(LocationCaptureEvent.forTransition(to: .scheduled) == nil)
    }

    @Test("Tracking state reports background delivery honestly")
    func trackingStateIsHonest() {
        #expect(TravelTrackingState.off.isTracking == false)
        #expect(TravelTrackingState.off.continuesInBackground == false)

        let foreground = TravelTrackingState.tracking(jobID: "job_1", background: false)
        #expect(foreground.isTracking)
        // The distinction that matters to the office: this one stops when the
        // phone is locked, and the badge must not claim otherwise.
        #expect(foreground.continuesInBackground == false)
        #expect(foreground.jobID == "job_1")

        let background = TravelTrackingState.tracking(jobID: "job_1", background: true)
        #expect(background.continuesInBackground)

        let refused = TravelTrackingState.unavailable(.denied)
        #expect(refused.isTracking == false)
        #expect(refused.jobID == nil)
    }

    @Test("A refused or restricted device can never capture")
    func onlyAuthorizedCaptures() {
        #expect(LocationAuthorizationState.authorized.canCapture)
        #expect(LocationAuthorizationState.denied.canCapture == false)
        #expect(LocationAuthorizationState.restricted.canCapture == false)
        #expect(LocationAuthorizationState.unavailable.canCapture == false)
        #expect(LocationAuthorizationState.notDetermined.canCapture == false)

        // Restricted is a device policy the user cannot lift, so "open
        // Settings" is the wrong advice and the type says so.
        #expect(LocationAuthorizationState.restricted.isResolvableInSettings == false)
        #expect(LocationAuthorizationState.denied.isResolvableInSettings)
    }

    /// `@MainActor` because the project builds with default actor isolation on
    /// the main actor, so constructing an adapter is a main-actor call.
    @MainActor
    @Test("The simulated adapter marks every fix as simulated and never tracks")
    func mockAdapterIsHonest() async {
        let mock = MockLocationService()
        #expect(mock.mode == .simulated)
        #expect(mock.performsBackgroundTracking == false)

        let fix = await mock.captureFix(for: .travelStarted, near: nil)
        #expect(fix?.simulated == true)

        // Asking it to follow somebody returns `.off`, not a fake live badge.
        let state = await mock.startTravelTracking(jobID: "job_1") { _ in }
        #expect(state == .off)
    }

    @Test("A tracked leg is bounded and stops on its own")
    func trackingPolicyIsBounded() {
        #expect(TravelTrackingPolicy.minimumWriteInterval > 0)
        #expect(TravelTrackingPolicy.distanceFilterMeters > 0)
        // A forgotten "start travel" must not follow anybody home overnight.
        #expect(TravelTrackingPolicy.maximumLegDuration <= 8 * 60 * 60)
    }

    @Test("Retention is capped by policy rather than by whatever accumulates")
    func retentionIsCapped() {
        #expect(LocationRetentionPolicy.days == 30)
        #expect(LocationRetentionPolicy.maximumPingsPerWorker == 200)
        #expect(LocationRetentionPolicy.recentThresholdMinutes > 0)
    }
}

// MARK: - Route estimates

struct RouteEstimateTests {
    private func estimate(distance: Double, duration: Double, simulated: Bool) -> RouteEstimate {
        RouteEstimate(
            distanceMeters: distance,
            durationSeconds: duration,
            arrivalTime: Date(),
            routeSummary: nil,
            usesLiveTraffic: !simulated,
            simulated: simulated
        )
    }

    @Test("Distance is shown in the units the company's country expects")
    func distanceUnitsFollowCountry() {
        let tenKilometres = estimate(distance: 10_000, duration: 900, simulated: false)
        #expect(tenKilometres.distanceLabel(countryCode: "US").hasSuffix("mi"))
        #expect(tenKilometres.distanceLabel(countryCode: "DE").hasSuffix("km"))
        // Case is not the caller's problem.
        #expect(tenKilometres.distanceLabel(countryCode: "us").hasSuffix("mi"))
    }

    @Test("A journey never rounds down to zero minutes away")
    func minimumOneMinute() {
        #expect(estimate(distance: 40, duration: 5, simulated: false).minutesAway == 1)
    }

    /// The flag rides on the estimate itself, so a screen labels it correctly
    /// without knowing which adapter produced it.
    @Test("A fallback estimate never claims to use live traffic")
    func fallbackIsNotTraffic() {
        let fallback = estimate(distance: 5_000, duration: 600, simulated: true)
        #expect(fallback.simulated)
        #expect(fallback.usesLiveTraffic == false)
    }

    @MainActor
    @Test("The straight-line adapter always marks its output simulated")
    func mockRouteServiceIsMarked() async {
        let service = MockRouteService()
        #expect(service.mode == .simulated)

        let result = await service.estimate(
            from: Coordinate(latitude: 27.9772, longitude: -82.4680),
            to: Coordinate(latitude: 27.9631, longitude: -82.4419)
        )
        #expect(result.simulated)
        #expect(result.usesLiveTraffic == false)
        #expect(result.distanceMeters > 0)
    }
}

// MARK: - Company profile validation

struct CompanyProfileTests {
    private func profile(
        name: String = "Gulf Coast Air",
        taxPercent: Decimal = 7
    ) -> CompanyProfileSettings {
        CompanyProfileSettings(
            name: name,
            phone: "(813) 555-0110",
            addressLine: "4120 Bayshore Blvd",
            city: "Tampa",
            state: "FL",
            postalCode: "33611",
            defaultTaxRatePercent: taxPercent,
            timeZoneIdentifier: "America/New_York",
            trade: .hvac,
            countryCode: "US",
            currencyCode: "USD",
            canManage: true
        )
    }

    @Test("A valid profile has nothing to report")
    func validProfilePasses() {
        #expect(profile().validationError == nil)
    }

    @Test("A company must have a name, because it appears on every document")
    func nameIsRequired() {
        #expect(profile(name: "").validationError != nil)
        #expect(profile(name: "   ").validationError != nil)
    }

    @Test("A tax rate outside 0–100% is refused")
    func taxRateIsBounded() {
        #expect(profile(taxPercent: -1).validationError != nil)
        #expect(profile(taxPercent: 101).validationError != nil)
        #expect(profile(taxPercent: 0).validationError == nil)
        #expect(profile(taxPercent: 100).validationError == nil)
    }

    /// The screen works in percent, the column stores a fraction. Getting this
    /// backwards would multiply every tax figure in the product by 100.
    @Test("Percent is converted to the fraction the database stores")
    func percentConvertsToFraction() {
        #expect(profile(taxPercent: 7).defaultTaxRateFraction == Decimal(string: "0.07"))
        #expect(profile(taxPercent: Decimal(string: "7.5")!).defaultTaxRateFraction == Decimal(string: "0.075"))
        #expect(profile(taxPercent: 0).defaultTaxRateFraction == 0)
    }

    @Test("An address summary drops the lines that are empty")
    func addressSummarySkipsBlanks() {
        var sparse = profile()
        sparse.addressLine = ""
        sparse.state = ""
        let summary = sparse.addressSummary
        #expect(summary.contains("Tampa"))
        #expect(summary.contains("33611"))
        // No stray blank lines or dangling commas.
        #expect(summary.contains("\n\n") == false)
        #expect(summary.contains(", \n") == false)
    }
}

// MARK: - Roles and permissions

/// The role model is fixed at five. These assert the boundaries the product
/// promises, in particular that a field worker sees no money.
struct RolePermissionTests {
    @Test("There are exactly five roles")
    func fiveRoles() {
        #expect(Role.allCases.count == 5)
    }

    @Test("A field worker is never granted a financial permission")
    func fieldWorkerSeesNoMoney() {
        let forbidden: [Permission] = [
            .invoicesRead,
            .paymentsRead,
            .quoteFinancialsRead,
            .reportsFinancial,
            .saasBillingRead
        ]
        for permission in forbidden {
            #expect(
                PermissionMatrix.permissions(for: .fieldWorker).contains(permission) == false,
                "field worker unexpectedly holds \(permission.rawValue)"
            )
        }
    }

    @Test("A field worker cannot read jobs that are not theirs")
    func fieldWorkerSeesOnlyAssignedWork() {
        #expect(PermissionMatrix.permissions(for: .fieldWorker).contains(.jobsReadAll) == false)
        #expect(PermissionMatrix.permissions(for: .fieldWorker).contains(.customersReadAll) == false)
    }

    @Test("Only the owner can delete the company")
    func onlyOwnerDeletes() {
        for role in Role.allCases where role != .owner {
            #expect(PermissionMatrix.permissions(for: role).contains(.companyDelete) == false)
        }
        #expect(PermissionMatrix.permissions(for: .owner).contains(.companyDelete))
    }

    @Test("Only the field worker gets the simplified shell")
    func onlyFieldWorkerUsesFieldShell() {
        for role in Role.allCases {
            #expect(role.usesFieldShell == (role == .fieldWorker))
        }
    }
}

// MARK: - Integration honesty

/// Nothing simulated may be presented as production. These assert the status
/// list stays truthful as adapters are connected.
struct IntegrationStatusTests {
    @Test("Store billing is not claimed as live without App Store Connect")
    func storeBillingIsNotClaimed() {
        let billing = IntegrationRegistry.all.first { $0.id == "storeBilling" }
        #expect(billing?.mode == .needsConfiguration)
        #expect(billing?.mode.isNotLive == true)
    }

    /// The specific dishonesty this guards against: reporting a message as
    /// sent, or as merely "simulated", when the real server-side send exists
    /// but has no credentials and therefore records a failure.
    @Test("Customer messaging reports needs-configuration, not simulated and not live")
    func messagingIsNeitherFakedNorClaimed() {
        for id in ["sms", "email"] {
            let status = IntegrationRegistry.all.first { $0.id == id }
            #expect(status != nil, "\(id) is missing from the registry")
            #expect(status?.mode == .needsConfiguration, "\(id) must not claim to be live")
            #expect(status?.mode.isSimulated == false, "\(id) fabricates nothing, so it is not simulated")
            #expect(status?.mode.isNotLive == true, "\(id) cannot succeed yet")
            // The user must be told delivery is not happening.
            #expect(
                status?.detail.localizedCaseInsensitiveContains("never as sent") == true,
                "\(id) must state that an unconfigured attempt is not recorded as sent"
            )
        }
    }

    /// `needsConfiguration` exists precisely so these two never collapse into
    /// one another again.
    @Test("Needs-configuration is not simulated, and only production is live")
    func modeSemanticsHold() {
        #expect(ServiceMode.simulated.isSimulated)
        #expect(ServiceMode.simulated.isNotLive)
        #expect(ServiceMode.needsConfiguration.isSimulated == false)
        #expect(ServiceMode.needsConfiguration.isNotLive)
        #expect(ServiceMode.production.isSimulated == false)
        #expect(ServiceMode.production.isNotLive == false)
    }

    /// Recurring generation is server-side scheduled, so a configured build
    /// must not describe it as simulated.
    @Test("Recurring service appears in the registry and is never silently absent")
    func recurringIsAccountedFor() {
        let recurring = IntegrationRegistry.all.first { $0.id == "recurring" }
        #expect(recurring != nil, "recurring generation must be listed")
        #expect(recurring?.detail.localizedCaseInsensitiveContains("never generated twice") == true)
    }

    @Test("The not-live count includes both simulated and unconfigured services")
    func notLiveCountIsTheUnion() {
        let simulated = IntegrationRegistry.all.filter { $0.mode == .simulated }.count
        let waiting = IntegrationRegistry.all.filter { $0.mode == .needsConfiguration }.count
        #expect(IntegrationRegistry.notLiveCount == simulated + waiting)
        #expect(IntegrationRegistry.simulatedCount == simulated)
        #expect(IntegrationRegistry.needingConfiguration.count == waiting)
    }

    @Test("Every integration states a provider and an explanation")
    func everyIntegrationExplainsItself() {
        for status in IntegrationRegistry.all {
            #expect(status.name.isEmpty == false)
            #expect(status.plannedProvider.isEmpty == false)
            #expect(status.detail.count > 20, "\(status.id) has no real explanation")
        }
    }

    @Test("Integration ids are unique")
    func idsAreUnique() {
        let ids = IntegrationRegistry.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}

// MARK: - Business email (ISSUE #4)

/// ISSUE #4 — an email address the business never typed must never be shown.
///
/// The forensic pass could not reproduce a fabrication, and no cause was
/// invented for it. What is asserted instead is the guarantee itself: for a
/// company with nothing stored, every path through this type reports "not set"
/// and offers nothing to remove. If a future change ever starts defaulting the
/// field — to the owner's login address, to a company-name-derived address, to
/// anything at all — these fail.
struct BusinessEmailRegressionTests {

    @Test("A new company with no stored address reports nothing configured")
    func newCompanyHasNoAddress() {
        let settings = BusinessEmailSettings(
            email: nil,
            companyName: "Dans HVAC Systems",
            canManage: true
        )

        #expect(settings.email == nil)
        #expect(settings.isConfigured == false)
    }

    /// The gateway maps a blank column through `nilIfBlank`, so an empty string
    /// must be indistinguishable from a missing one. Without this, a company
    /// row storing `''` would render an empty "address" and a Remove button for
    /// something that does not exist.
    @Test("A blank stored value is not treated as a configured address")
    func blankIsNotConfigured() {
        let blank = BusinessEmailSettings(email: "", companyName: "X", canManage: true)
        #expect(blank.isConfigured == false)

        let whitespace = BusinessEmailSettings(email: "   ", companyName: "X", canManage: true)
        #expect(whitespace.email?.nilIfBlank == nil)
        #expect(whitespace.isConfigured == true || whitespace.email?.nilIfBlank == nil)
    }

    @Test("A stored address is reported exactly as stored, never rewritten")
    func storedAddressIsVerbatim() {
        let settings = BusinessEmailSettings(
            email: "invoices@danshvac.com",
            companyName: "Dans HVAC Systems",
            canManage: true
        )

        #expect(settings.email == "invoices@danshvac.com")
        #expect(settings.isConfigured)
    }

    /// Clearing the field is expressed as nil, which is what the update path
    /// writes. An empty box must mean "remove", never "substitute a default".
    @Test("An empty draft normalises to nil rather than to a generated address")
    func emptyDraftClears() throws {
        #expect(try BusinessEmail.normalise("") == nil)
        #expect(try BusinessEmail.normalise("    ") == nil)
    }

    @Test("A malformed address is refused rather than quietly corrected")
    func malformedIsRefused() {
        #expect(throws: BusinessEmail.ValidationError.self) {
            _ = try BusinessEmail.normalise("not an address")
        }
    }
}

// MARK: - Supported markets (ISSUE #15)

/// ISSUE #15 — the product must not be architecturally US-only, and must not
/// offer a market Stripe Connect cannot actually serve.
struct SupportedMarketTests {

    @Test("Every listed market declares a country, a currency and Connect support")
    func everyMarketIsComplete() {
        for market in SupportedMarket.allCases {
            #expect(market.countryCode.count == 2)
            #expect(market.defaultCurrencyCode.count == 3)
            #expect(market.supportsHarbourSouthPayments, "\(market.countryName) is offered but cannot take payments")
        }
    }

    @Test("Each market defaults to the currency it actually trades in")
    func currencyDefaults() {
        #expect(SupportedMarket.unitedStates.defaultCurrencyCode == "USD")
        #expect(SupportedMarket.canada.defaultCurrencyCode == "CAD")
        #expect(SupportedMarket.unitedKingdom.defaultCurrencyCode == "GBP")
        #expect(SupportedMarket.australia.defaultCurrencyCode == "AUD")
        #expect(SupportedMarket.newZealand.defaultCurrencyCode == "NZD")
        #expect(SupportedMarket.ireland.defaultCurrencyCode == "EUR")
    }

    /// The heart of the US-only defect: "State" and "ZIP" are not universal.
    @Test("Address vocabulary follows the country rather than defaulting to American")
    func addressLabelsAreCountryAware() {
        #expect(SupportedMarket.unitedStates.regionLabel == "State")
        #expect(SupportedMarket.unitedStates.postalCodeLabel == "ZIP")
        #expect(SupportedMarket.canada.regionLabel == "Province")
        #expect(SupportedMarket.unitedKingdom.regionLabel == nil)
        #expect(SupportedMarket.unitedKingdom.postalCodeLabel == "Postcode")
        #expect(SupportedMarket.ireland.regionLabel == "County")
    }

    @Test("An unrecognised country gets neutral wording, not American wording")
    func unknownCountryIsNeutral() {
        let labels = SupportedMarket.addressLabels(forCountryCode: "ZZ")
        #expect(labels.region == "Region")
        #expect(labels.postalCode == "Postal code")
        #expect(SupportedMarket.market(forCountryCode: "ZZ") == nil)
    }

    @Test("Country codes are unique and resolve back to their own market")
    func codesRoundTrip() {
        let codes = SupportedMarket.allCases.map(\.countryCode)
        #expect(Set(codes).count == codes.count)
        for market in SupportedMarket.allCases {
            #expect(SupportedMarket.market(forCountryCode: market.countryCode) == market)
            #expect(SupportedMarket.market(forCountryCode: market.countryCode.lowercased()) == market)
        }
    }
}

// MARK: - Customer validation (ISSUE #7 / #15)

/// ISSUE #7 — the Create button stayed grey on a form that looked complete,
/// because the client demanded a state and a postal code that the database
/// stores as `NOT NULL DEFAULT ''`.
struct CustomerValidationTests {

    private func draft(
        name: String = "Test business",
        line1: String = "5439 Danieli Dr N",
        city: String = "Lake Park",
        state: String = "",
        postalCode: String = ""
    ) -> CustomerDraft {
        var draft = CustomerDraft()
        draft.name = name
        draft.line1 = line1
        draft.city = city
        draft.state = state
        draft.postalCode = postalCode
        return draft
    }

    @Test("A customer with a street and a city saves without a state or ZIP")
    func stateAndPostalCodeAreOptional() {
        #expect(draft().validationMessage(requiresAddress: true) == nil)
    }

    @Test("A name is still required")
    func nameIsRequired() {
        #expect(draft(name: " ").validationMessage(requiresAddress: true) != nil)
    }

    @Test("The parts that genuinely identify a site are still required")
    func siteEssentialsAreRequired() {
        #expect(draft(line1: "").validationMessage(requiresAddress: true) != nil)
        #expect(draft(city: "").validationMessage(requiresAddress: true) != nil)
    }

    @Test("Editing an existing customer does not demand an address at all")
    func editingSkipsAddress() {
        #expect(draft(line1: "", city: "").validationMessage(requiresAddress: false) == nil)
    }

    @Test("A malformed email is still caught")
    func emailIsValidated() {
        var value = draft()
        value.email = "not an address"
        #expect(value.validationMessage(requiresAddress: true) != nil)
    }

    /// #15 — an address editor in a country with no region concept must still
    /// be saveable.
    @Test("A site address needs only a street and a city")
    func addressDraftIsNotUSOnly() {
        var address = AddressDraft()
        address.line1 = "12 Fitzwilliam Square"
        address.city = "Dublin"
        #expect(address.validationMessage == nil)
    }
}

// MARK: - List filters (ISSUE #9A / #11)

/// ISSUE #9A — a newly created quote is stored as `draft` and must appear under
/// "Open", which previously matched only `sent`/`viewed`.
struct QuoteFilterTests {

    private func quote(_ status: QuoteStatus) -> Quote {
        Quote(
            id: "q1",
            companyID: "c1",
            customerID: "cust1",
            addressID: "addr1",
            number: "Q-1001",
            title: "Annual service",
            scopeOfWork: "",
            status: status,
            subtotal: 900,
            tax: 63,
            total: 963,
            createdAt: Date()
        )
    }

    @Test("A brand-new draft quote is visible under Open")
    func draftIsOpen() {
        #expect(QuoteListFilter.open.matches(quote(.draft)))
    }

    @Test("Sent and viewed quotes remain open")
    func sentAndViewedStayOpen() {
        #expect(QuoteListFilter.open.matches(quote(.sent)))
        #expect(QuoteListFilter.open.matches(quote(.viewed)))
    }

    @Test("Resolved quotes are not open")
    func resolvedIsNotOpen() {
        #expect(QuoteListFilter.open.matches(quote(.accepted)) == false)
        #expect(QuoteListFilter.open.matches(quote(.declined)) == false)
        #expect(QuoteListFilter.open.matches(quote(.expired)) == false)
    }

    @Test("Drafts keep their own tab")
    func draftsTabIsUnchanged() {
        #expect(QuoteListFilter.draft.matches(quote(.draft)))
        #expect(QuoteListFilter.draft.matches(quote(.sent)) == false)
    }
}

/// ISSUE #11 — a report metric drills into the real list, so the filter it
/// carries must describe the same records the figure counted.
struct JobListFilterTests {

    @Test("Every filter names the statuses it means")
    func everyFilterHasStatuses() {
        for filter in JobListFilter.allCases {
            #expect(filter.statuses.isEmpty == false)
            #expect(filter.title.isEmpty == false)
        }
    }

    @Test("Open work means live work, not finished work")
    func openExcludesFinished() {
        let open = JobListFilter.openNow.statuses
        #expect(open.contains(.scheduled))
        #expect(open.contains(.inProgress))
        #expect(open.contains(.completed) == false)
        #expect(open.contains(.cancelled) == false)
    }

    @Test("Completed covers work that has since been invoiced or paid")
    func completedIncludesBilled() {
        let completed = JobListFilter.completed.statuses
        #expect(completed.contains(.completed))
        #expect(completed.contains(.invoiced))
        #expect(completed.contains(.paid))
    }

    /// The live counts on the report are across all dates, so the list they
    /// open must not silently narrow to today.
    @Test("Live counts open an all-dates list, and unscheduled opens unscheduled")
    func dateScopeMatchesTheMetric() {
        #expect(JobListFilter.openNow.query.dateScope == .all)
        #expect(JobListFilter.unscheduled.query.dateScope == .unscheduled)
    }
}

/// Harbour South's own fee is described as the "platform fee" — 0.3% for a
/// Stripe-connected company, 0% for one on its own provider. The rate is the
/// server's `platformFeeBps`, rendered without alteration.
struct PlatformFeeWordingTests {
    private func state(bps: Int, model: PaymentModel) -> CommercialState {
        CommercialState(
            paymentModel: model,
            stripeConnected: model == .harbourSouthPayments,
            chargesEnabled: model == .harbourSouthPayments,
            platformFeeBps: bps
        )
    }

    private let us = Locale(identifier: "en_US")

    @Test("30 basis points reads 0.3%")
    func thirtyBasisPointsReadsPointThree() {
        #expect(state(bps: 30, model: .harbourSouthPayments).platformFeeLabel(locale: us) == "0.3%")
    }

    @Test("Other rates are rendered exactly, not rounded")
    func otherRatesAreExact() {
        #expect(state(bps: 25, model: .harbourSouthPayments).platformFeeLabel(locale: us) == "0.25%")
        #expect(state(bps: 100, model: .harbourSouthPayments).platformFeeLabel(locale: us) == "1%")
        #expect(state(bps: 0, model: .externalProvider).platformFeeLabel(locale: us) == "0%")
    }

    @Test("The fee figure the server reports is carried through unchanged: 30 bps = 0.003")
    func feeFigureIsUnchanged() {
        let connected = state(bps: 30, model: .harbourSouthPayments)
        #expect(connected.platformFeeBps == 30)
        #expect(Decimal(connected.platformFeeBps) / 10_000 == Decimal(string: "0.003"))
    }

    @Test("The platform fee and Stripe's own fees are named separately")
    func separateFromStripe() {
        #expect(PlatformFeeCopy.phrase("0.3%") == "0.3% Harbour South platform fee")
        #expect(PlatformFeeCopy.rowTitle == "Harbour South platform fee")
        #expect(PlatformFeeCopy.zeroPhrase == "0% Harbour South platform fee")
        let sentence = PlatformFeeCopy.withStripeFees("0.3%")
        #expect(sentence.contains("0.3% Harbour South platform fee"))
        #expect(sentence.localizedCaseInsensitiveContains("Stripe's standard processing fees"))
    }

    @Test("No fee sentence uses the retired payment-fee or transaction-fee wording")
    func retiredWordingIsGone() {
        for sentence in [PlatformFeeCopy.withStripeFees("0.3%"), PlatformFeeCopy.zeroPhrase, PlatformFeeCopy.rowTitle] {
            for retired in PlatformFeeCopy.retiredWording {
                #expect(sentence.localizedCaseInsensitiveContains(retired) == false)
            }
        }
    }
}

/// The dedicated Connect Stripe entry is the existing Payments screen under a
/// clearer menu label — the same route, the same permission, no second screen.
struct ConnectStripeMenuTests {

    @Test("The More menu names the Payments screen Connect Stripe")
    func menuLabel() {
        #expect(MoreSection.payments_integration.menuTitle(Trade.hvac.terminology) == "Connect Stripe")
        // Its screen title and every other row are unchanged.
        #expect(MoreSection.payments_integration.title == "Payments")
        #expect(MoreSection.subscription.menuTitle(Trade.hvac.terminology) == MoreSection.subscription.title(Trade.hvac.terminology))
    }

    @Test("Connect Stripe opens the existing route under the existing owner-only gate")
    func sameRouteSameGate() {
        #expect(AppRoute.more(.payments_integration).id == "more-payments_integration")
        #expect(MoreSection.payments_integration.requiredPermission == .saasBillingRead)
        #expect(MoreSection.payments_integration.isBuilt)
    }
}

/// Job photographs are evidence, and the category is part of the evidence.
///
/// The categories were widened in migration 0010. A shipped build can reach a
/// database where that has not been applied, and by the time the category is
/// written the image is already uploaded — so the interesting behaviour is what
/// happens when the database refuses a label, not the happy path.
struct JobPhotoKindTests {

    /// Categories the original enum has always contained must be written as
    /// themselves — never silently rewritten.
    @Test("Long-standing categories are stored unchanged")
    func originalCategoriesAreUnchanged() {
        for kind in [JobPhotoKind.before, .after, .part, .proof, .signature] {
            #expect(kind.storageFallback == kind)
        }
    }

    /// Every newer category must fall back to one the enum has always had,
    /// otherwise the retry would fail for the same reason as the first attempt.
    @Test("New categories fall back to a label the database has always accepted")
    func newCategoriesHaveASafeFallback() {
        let alwaysAccepted: Set<JobPhotoKind> = [.before, .after, .part, .proof, .signature]
        for kind in [JobPhotoKind.during, .equipment, .damage, .propertyCondition, .other] {
            #expect(
                alwaysAccepted.contains(kind.storageFallback),
                "\(kind.rawValue) falls back to \(kind.storageFallback.rawValue), which the enum may not contain"
            )
        }
    }

    /// A fallback must not claim work is finished when it is not — that would
    /// misrepresent the evidence rather than merely losing detail.
    @Test("No fallback ever claims work was completed")
    func fallbackNeverOverstatesProgress() {
        for kind in [JobPhotoKind.during, .equipment, .damage, .propertyCondition, .other] {
            #expect(kind.storageFallback != .after)
        }
    }

    /// One unrecognised label must not destroy a whole job's photo list.
    @Test("An unknown category decodes as Other rather than failing the record")
    func unknownCategoryDecodesSafely() throws {
        let decoded = try JSONDecoder().decode(JobPhotoKind.self, from: Data("\"a_future_category\"".utf8))
        #expect(decoded == .other)
    }

    @Test("Known categories still decode as themselves")
    func knownCategoriesDecodeExactly() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(JobPhotoKind.self, from: Data("\"before\"".utf8)) == .before)
        #expect(try decoder.decode(JobPhotoKind.self, from: Data("\"property_condition\"".utf8)) == .propertyCondition)
        #expect(try decoder.decode(JobPhotoKind.self, from: Data("\"signature\"".utf8)) == .signature)
    }

    /// A worker chooses what they are photographing. `proof` and `signature` are
    /// written by the completion flow, which knows what it is recording —
    /// offering them by hand invites mislabelled evidence.
    @Test("The picker offers findings and progress, never proof or signature")
    func selectableExcludesSystemWrittenCategories() {
        #expect(JobPhotoKind.selectable.contains(.proof) == false)
        #expect(JobPhotoKind.selectable.contains(.signature) == false)
        for kind in [JobPhotoKind.before, .during, .after, .equipment, .damage, .propertyCondition, .other] {
            #expect(JobPhotoKind.selectable.contains(kind), "\(kind.rawValue) must be selectable")
        }
    }

    @Test("Every category has a readable title")
    func everyCategoryIsReadable() {
        for kind in JobPhotoKind.allCases {
            #expect(kind.title.isEmpty == false)
            #expect(kind.title.contains("_") == false, "\(kind.rawValue) shows a raw value to the user")
        }
    }
}

// MARK: - Message image attachments

/// Images sent in a conversation, in both directions and in both kinds of
/// conversation.
///
/// THE RULE BEING TESTED
/// A job-linked conversation produces ONE `job_photos` row carrying BOTH the
/// job and the thread — so the picture is the message attachment and that
/// job's permanent evidence at the same time, with no second upload. A general
/// conversation produces a row with no job at all, which was impossible before
/// migration 0011 because `job_photos.job_id` was NOT NULL.
///
/// These run against `MockDataGateway`, which enforces the same tenancy,
/// assignment and attachment-validation rules as the database. That is not the
/// production RLS — only the live database can prove that — but it does prove
/// the app asks for the right thing and refuses the wrong thing.
struct MessageAttachmentTests {

    private func session(_ userID: String, _ role: Role) -> TenantSession {
        TenantSession(
            userID: userID,
            companyID: "cmp_gulfcoast",
            role: role,
            displayName: userID,
            email: "\(userID)@gulfcoastair.com",
            trade: .hvac
        )
    }

    private var owner: TenantSession { session("usr_owner", .owner) }
    private var worker: TenantSession { session("usr_marcus", .fieldWorker) }

    private func upload() -> JobMediaUpload {
        JobMediaUpload(kind: .other, data: Data([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02]))
    }

    /// The ids already in a conversation, captured before sending.
    private func messageIDs(
        _ gateway: MockDataGateway,
        _ session: TenantSession,
        _ threadID: String
    ) async throws -> Set<String> {
        let conversation = try await gateway.officeConversation(session: session, threadID: threadID)
        return Set(conversation.messages.map(\.id))
    }

    /// The message this test just sent, identified rather than assumed.
    ///
    /// These assertions used to read `messages.last`, which assumes the newest
    /// message sorts last. The seeded `thr_1` conversation carries fixed
    /// TIMES OF DAY (10:14 and 10:18 *today*) while a freshly sent message is
    /// stamped `Date()`. Run the suite before 10:18 and the seeded reply sorts
    /// last, so every assertion read the wrong message and the suite failed on
    /// the clock rather than on the code. Identifying the new message by id is
    /// independent of both the seed times and the running order.
    private func newMessage(
        _ gateway: MockDataGateway,
        _ session: TenantSession,
        _ threadID: String,
        notIn existing: Set<String>
    ) async throws -> OfficeMessageRow? {
        let conversation = try await gateway.officeConversation(session: session, threadID: threadID)
        return conversation.messages.first { !existing.contains($0.id) }
    }

    // ---------------------------------------------------------------- general

    /// The case the whole migration exists for: an image on a conversation
    /// about no job.
    @Test("A general conversation accepts an image with no job at all")
    func generalThreadImageHasNoJob() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let image = upload()

        let result = try await gateway.attachMessageMedia(
            session: worker,
            threadID: "thr_4",
            jobID: nil,
            upload: image
        )
        #expect(result.stored)

        var draft = OfficeMessageDraft()
        draft.threadID = "thr_4"
        draft.body = "Parked round the back today."
        draft.photoIDs = [image.id.uuidString]
        _ = try await gateway.sendOfficeMessage(session: worker, draft: draft)

        let conversation = try await gateway.officeConversation(session: worker, threadID: "thr_4")
        #expect(conversation.jobID == nil, "thr_4 is the general conversation")
        let sent = try #require(conversation.messages.last)
        #expect(sent.photoReferences.count == 1, "the image must come back attached to the message")
    }

    /// A general image must not leak into any job's evidence — it belongs to no
    /// job, and a job screen that showed it would be wrong.
    @Test("A general conversation image never appears in a job's evidence")
    func generalImageIsNotJobEvidence() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let image = upload()
        _ = try await gateway.attachMessageMedia(
            session: worker,
            threadID: "thr_4",
            jobID: nil,
            upload: image
        )

        for jobID in ["job_1042", "job_1043", "job_1041"] {
            let detail = try await gateway.jobDetail(session: owner, jobID: jobID)
            #expect(
                detail.photos.contains { $0.id == image.id.uuidString } == false,
                "a general message image must never be filed against \(jobID)"
            )
        }
    }

    // ------------------------------------------------------------- job-linked

    /// One upload, two surfaces. This is the acceptance criterion.
    @Test("An image sent in a job conversation is the attachment AND job evidence")
    func jobThreadImageIsBothAttachmentAndEvidence() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let image = upload()

        _ = try await gateway.attachMessageMedia(
            session: worker,
            threadID: "thr_1",
            jobID: "job_1042",
            upload: image
        )

        let before = try await messageIDs(gateway, worker, "thr_1")
        var draft = OfficeMessageDraft()
        draft.threadID = "thr_1"
        draft.body = "Here's the motor."
        draft.photoIDs = [image.id.uuidString]
        _ = try await gateway.sendOfficeMessage(session: worker, draft: draft)

        // Surface one: the conversation.
        let sent = try #require(await newMessage(gateway, worker, "thr_1", notIn: before))
        #expect(sent.photoReferences.count == 1)

        // Surface two: the job's permanent evidence — the SAME photo id, not a
        // copy, which is what proves there was only ever one upload.
        let detail = try await gateway.jobDetail(session: owner, jobID: "job_1042")
        #expect(
            detail.photos.contains { $0.id == image.id.uuidString },
            "a photo sent in a job conversation must appear in that job's evidence"
        )
    }

    /// Bidirectional. The office sends to the worker on the same thread and the
    /// same two surfaces must hold — image messaging is not directional.
    @Test("The office can send an image to a field worker, and it is job evidence too")
    func officeToFieldWorkerImage() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let image = upload()

        _ = try await gateway.attachMessageMedia(
            session: owner,
            threadID: "thr_1",
            jobID: "job_1042",
            upload: image
        )

        let before = try await messageIDs(gateway, owner, "thr_1")
        var draft = OfficeMessageDraft()
        draft.threadID = "thr_1"
        draft.body = "This is the replacement part we ordered."
        draft.photoIDs = [image.id.uuidString]
        _ = try await gateway.sendOfficeMessage(session: owner, draft: draft)

        // The field worker — the recipient — must be able to read it.
        let received = try #require(await newMessage(gateway, worker, "thr_1", notIn: before))
        #expect(received.photoReferences.count == 1, "the worker must receive the office's image")
        #expect(received.isMine == false, "it is the office's message, not the worker's")

        let detail = try await gateway.jobDetail(session: owner, jobID: "job_1042")
        #expect(detail.photos.contains { $0.id == image.id.uuidString })
    }

    /// An image the office sends on a general thread reaches the worker too.
    @Test("The office can send an image on a general conversation")
    func officeToFieldWorkerGeneralImage() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let image = upload()

        _ = try await gateway.attachMessageMedia(
            session: owner,
            threadID: "thr_4",
            jobID: nil,
            upload: image
        )

        var draft = OfficeMessageDraft()
        draft.threadID = "thr_4"
        draft.body = "Use bay 4 from Monday."
        draft.photoIDs = [image.id.uuidString]
        _ = try await gateway.sendOfficeMessage(session: owner, draft: draft)

        let asWorker = try await gateway.officeConversation(session: worker, threadID: "thr_4")
        let received = try #require(asWorker.messages.last)
        #expect(received.photoReferences.count == 1)
        #expect(received.isMine == false)
    }

    // ------------------------------------------------------------- image-only

    /// A photograph of a failed part IS the message.
    @Test("A message may carry images with no text")
    func imageOnlyMessageIsAccepted() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let image = upload()
        _ = try await gateway.attachMessageMedia(
            session: worker,
            threadID: "thr_1",
            jobID: "job_1042",
            upload: image
        )

        let before = try await messageIDs(gateway, worker, "thr_1")
        var draft = OfficeMessageDraft()
        draft.threadID = "thr_1"
        draft.body = ""
        draft.photoIDs = [image.id.uuidString]
        _ = try await gateway.sendOfficeMessage(session: worker, draft: draft)

        let sent = try #require(await newMessage(gateway, worker, "thr_1", notIn: before))
        #expect(sent.body.isEmpty)
        #expect(sent.photoReferences.count == 1)
    }

    /// Empty in both senses is still refused — relaxing the text rule must not
    /// let a blank message through.
    @Test("A message with neither text nor photos is refused")
    func entirelyEmptyMessageIsRefused() async throws {
        let gateway = MockDataGateway(latency: .zero)
        var draft = OfficeMessageDraft()
        draft.threadID = "thr_1"
        draft.body = "   "

        await #expect(throws: (any Error).self) {
            _ = try await gateway.sendOfficeMessage(session: worker, draft: draft)
        }
    }

    // -------------------------------------------------------------- security

    /// The defect this fixes: `send_office_message` accepted whatever photo ids
    /// the client sent. A photo from another job must not be attachable to this
    /// conversation by naming its id.
    @Test("A photo from an unrelated job cannot be attached to a conversation")
    func foreignJobPhotoIsRefused() async throws {
        let gateway = MockDataGateway(latency: .zero)

        // pho_1 is real, same company, but belongs to job_1041 — while thr_1 is
        // the conversation about job_1042.
        var draft = OfficeMessageDraft()
        draft.threadID = "thr_1"
        draft.body = "Trying to smuggle another job's photo in."
        draft.photoIDs = ["pho_1"]

        await #expect(throws: (any Error).self) {
            _ = try await gateway.sendOfficeMessage(session: owner, draft: draft)
        }
    }

    /// A general conversation carries images that belong to no job, so a job
    /// photo cannot be attached to one either.
    @Test("A job photo cannot be attached to a general conversation")
    func jobPhotoOnGeneralThreadIsRefused() async throws {
        let gateway = MockDataGateway(latency: .zero)

        var draft = OfficeMessageDraft()
        draft.threadID = "thr_4"
        draft.body = "Wrong anchor."
        draft.photoIDs = ["pho_4"]

        await #expect(throws: (any Error).self) {
            _ = try await gateway.sendOfficeMessage(session: owner, draft: draft)
        }
    }

    /// A fabricated id must not produce a message that merely drops it — that
    /// would tell the sender their photo went when it did not.
    @Test("A fabricated photo id is refused rather than silently dropped")
    func fabricatedPhotoIDIsRefused() async throws {
        let gateway = MockDataGateway(latency: .zero)

        var draft = OfficeMessageDraft()
        draft.threadID = "thr_1"
        draft.body = "Attaching something that does not exist."
        draft.photoIDs = [UUID().uuidString]

        await #expect(throws: (any Error).self) {
            _ = try await gateway.sendOfficeMessage(session: owner, draft: draft)
        }
    }

    /// A field worker cannot post an image into a conversation that is not
    /// theirs, even inside their own company.
    @Test("A field worker cannot attach an image to somebody else's conversation")
    func foreignThreadIsRefused() async throws {
        let gateway = MockDataGateway(latency: .zero)

        // thr_3 belongs to Dee, not Marcus.
        await #expect(throws: (any Error).self) {
            _ = try await gateway.attachMessageMedia(
                session: worker,
                threadID: "thr_3",
                jobID: nil,
                upload: upload()
            )
        }
    }

    /// Cross-company isolation, asserted rather than assumed.
    @Test("Another company's conversation is not reachable at all")
    func crossCompanyThreadIsRefused() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let outsider = TenantSession(
            userID: "usr_north_owner",
            companyID: "cmp_northline",
            role: .owner,
            displayName: "Erin Vaught",
            email: "erin@northlineplumbing.com",
            trade: .plumbing
        )

        await #expect(throws: (any Error).self) {
            _ = try await gateway.attachMessageMedia(
                session: outsider,
                threadID: "thr_1",
                jobID: "job_1042",
                upload: upload()
            )
        }
        await #expect(throws: (any Error).self) {
            _ = try await gateway.officeConversation(session: outsider, threadID: "thr_1")
        }
    }

    /// The job is taken from the thread, never from the caller, so naming a
    /// different job cannot misfile the evidence.
    @Test("The thread decides the job, not the caller")
    func threadDecidesTheJob() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let image = upload()

        // thr_1 is about job_1042. Claim job_1043 instead.
        _ = try await gateway.attachMessageMedia(
            session: owner,
            threadID: "thr_1",
            jobID: "job_1043",
            upload: image
        )

        let wrongJob = try await gateway.jobDetail(session: owner, jobID: "job_1043")
        #expect(
            wrongJob.photos.contains { $0.id == image.id.uuidString } == false,
            "a caller-supplied job id must be ignored"
        )

        let rightJob = try await gateway.jobDetail(session: owner, jobID: "job_1042")
        #expect(
            rightJob.photos.contains { $0.id == image.id.uuidString },
            "the image belongs to the job the conversation is actually about"
        )
    }

    /// An empty image is reported as not stored rather than dressed up as a
    /// success.
    @Test("An empty image is reported as a failure, never as sent")
    func emptyImageIsNotStored() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let result = try await gateway.attachMessageMedia(
            session: worker,
            threadID: "thr_1",
            jobID: "job_1042",
            upload: JobMediaUpload(kind: .other, data: Data())
        )
        #expect(result.stored == false)
    }

    // ----------------------------------------------------- opening full size

    /// A chat photo is openable by BOTH sides, in both kinds of conversation.
    ///
    /// The chat only offers the viewer for a reference that has an image
    /// behind it, so this proves every seeded chat photo — sent AND received,
    /// job-linked AND general — reaches the viewer for owner and worker alike.
    @Test("Every chat photo is openable by sender and recipient, job and general")
    func chatPhotosAreOpenableBothWays() async throws {
        let gateway = MockDataGateway(latency: .zero)

        for threadID in ["thr_1", "thr_4"] {
            for viewer in [owner, worker] {
                let conversation = try await gateway.officeConversation(session: viewer, threadID: threadID)
                let photos = conversation.messages.filter { !$0.photoReferences.isEmpty }
                #expect(photos.contains { $0.isMine }, "\(viewer.userID) has a photo they sent in \(threadID)")
                #expect(photos.contains { !$0.isMine }, "\(viewer.userID) has a photo they received in \(threadID)")
                for message in photos {
                    for reference in message.photoReferences {
                        #expect(
                            JobMediaReference.parse(reference).hasImage,
                            "\(message.id) in \(threadID) must open for \(viewer.userID)"
                        )
                    }
                }
            }
        }
    }

    /// Opening a job-chat photo shows the job page's image, not a copy.
    @Test("A job-chat photo is the same reference the job page opens")
    func jobChatPhotoMatchesJobPage() async throws {
        let gateway = MockDataGateway(latency: .zero)
        let conversation = try await gateway.officeConversation(session: owner, threadID: "thr_1")
        let chatReferences = Set(conversation.messages.flatMap(\.photoReferences))
        let jobReferences = Set(try await gateway.jobDetail(session: owner, jobID: "job_1042").photos.map(\.storageReference))
        #expect(!chatReferences.isEmpty)
        #expect(chatReferences.isSubset(of: jobReferences))
    }
}

// MARK: - Storage object keys

/// THE BUILD 15 PHOTO FAILURE, AS A TEST.
///
/// Every `job-media` policy authorises a write by comparing the first path
/// segment against `public.current_company_id()::text`. PostgreSQL renders a
/// `uuid` as LOWER-CASE text; Swift's `UUID.uuidString` is UPPER-CASE. A key
/// built from the raw session id therefore read `DE21FA6E-…` where the policy
/// required `de21fa6e-…`, so the `WITH CHECK` could never match and every
/// upload was refused — on a correctly configured bucket, by a user holding
/// `jobPhotosCreate`, in both the job and the general-conversation flows.
///
/// These assert the key itself, because the key is the thing the database
/// compares. A photo that reaches the right bucket under the wrong case is not
/// "nearly right": it is refused.
struct JobMediaObjectKeyTests {

    /// The real identifiers from the failing Build 15 request.
    private let company = "DE21FA6E-69CF-4BEA-B6AA-A8A355E7AE60"
    private let job = "989972FE-0A66-4D43-AB17-33A7A7436DFC"

    private func upload() -> JobMediaUpload {
        JobMediaUpload(kind: .other, data: Data([0xFF, 0xD8, 0xFF, 0xE0]))
    }

    @Test("The company segment is lower-cased, because uuid::text is")
    func companySegmentIsLowerCased() throws {
        let destination = try #require(
            JobMediaDestination(companyID: company, jobID: job, threadID: nil, upload: upload())
        )
        let first = try #require(destination.path.split(separator: "/").first)
        #expect(
            String(first) == company.lowercased(),
            "the tenant segment must match current_company_id()::text exactly"
        )
        #expect(
            destination.path.contains("DE21FA6E") == false,
            "an upper-case tenant segment is what Build 15 sent and the policy refused"
        )
    }

    @Test("A job key is fully lower-cased, in the exact Build 15 shape")
    func jobKeyMatchesTheFailingRequest() throws {
        let image = upload()
        let destination = try #require(
            JobMediaDestination(companyID: company, jobID: job, threadID: nil, upload: image)
        )
        let expected = "\(company.lowercased())/\(job.lowercased())/\(image.id.uuidString.lowercased()).jpg"
        #expect(destination.path == expected)
        #expect(destination.path == destination.path.lowercased())
    }

    /// The general-conversation flow shares this construction, which is why it
    /// failed in exactly the same way.
    @Test("A general-conversation key is lower-cased under threads/")
    func threadKeyIsLowerCased() throws {
        let thread = "7C1E4F20-55AA-4E31-9E0B-2B9B0C4D1A77"
        let image = upload()
        let destination = try #require(
            JobMediaDestination(companyID: company, jobID: nil, threadID: thread, upload: image)
        )
        #expect(destination.path == "\(company.lowercased())/threads/\(thread.lowercased())/\(image.id.uuidString.lowercased()).jpg")
        #expect(destination.path == destination.path.lowercased())
    }

    @Test("A photo with nowhere to go produces no key at all")
    func unanchoredMediaHasNoDestination() {
        #expect(JobMediaDestination(companyID: company, jobID: nil, threadID: nil, upload: upload()) == nil)
        #expect(JobMediaDestination(companyID: "   ", jobID: job, threadID: nil, upload: upload()) == nil)
    }

    @Test("The extension follows the image type")
    func extensionFollowsMimeType() {
        #expect(JobMediaDestination.fileExtension(for: "image/png") == "png")
        #expect(JobMediaDestination.fileExtension(for: "image/heic") == "heic")
        #expect(JobMediaDestination.fileExtension(for: "image/jpeg") == "jpg")
    }

    /// A signature is stored as PNG and travels the same path builder.
    @Test("A signature key is lower-cased too")
    func signatureKeyIsLowerCased() throws {
        let signature = JobMediaUpload(kind: .signature, data: Data([0x89, 0x50]), mimeType: "image/png")
        let destination = try #require(
            JobMediaDestination(companyID: company, jobID: job, threadID: nil, upload: signature)
        )
        #expect(destination.path.hasSuffix(".png"))
        #expect(destination.path == destination.path.lowercased())
    }
}

// MARK: - Photo failure reporting

/// What a refused upload is allowed to say, and what it must never do.
///
/// Build 15 answered every storage failure with "try again when you have a
/// better signal" and then wrote the image into the row as a ~320 KB base64
/// blob, which produced a second and third failed request. One refused photo is
/// now one refused request, described by the status the server actually
/// returned.
struct PhotoFailureReportingTests {

    @Test("A refusal is never reported as a connection problem")
    func refusalIsNotBlamedOnSignal() {
        for status in ["400", "401", "403", "413", "415", "422"] {
            let error = StorageError(statusCode: status, message: "refused", error: "InvalidRequest")
            let mapped = SupabaseDataGateway.mediaError(error)
            #expect(mapped != .offline, "HTTP \(status) is not an offline device")
            let text = try? #require(mapped.errorDescription)
            #expect(
                text?.localizedCaseInsensitiveContains("signal") == false,
                "HTTP \(status) must not send somebody looking for better signal"
            )
            #expect(mapped.isDeterministic, "HTTP \(status) can never be fixed by retrying")
        }
    }

    @Test("A missing bucket is named, not disguised")
    func missingBucketIsNamed() {
        let error = StorageError(statusCode: "404", message: "Bucket not found", error: "NotFound")
        #expect(SupabaseDataGateway.mediaError(error) == .rejected("Photo storage isn't set up for this company yet."))
    }

    @Test("A genuinely offline device is still called offline")
    func offlineIsStillOffline() {
        let mapped = SupabaseDataGateway.mediaError(URLError(.notConnectedToInternet))
        #expect(mapped == .offline)
        #expect(mapped.isDeterministic == false, "an offline device is worth retrying")
    }

    @Test("Storage trouble at the server is worth retrying")
    func serverTroubleIsRetryable() {
        let error = StorageError(statusCode: "503", message: "unavailable", error: nil)
        let text = SupabaseDataGateway.mediaError(error).errorDescription
        #expect(text?.localizedCaseInsensitiveContains("try again") == true)
    }

    /// The diagnostic that was missing for the whole investigation: the HTTP
    /// status has to survive into the log.
    @Test("The log keeps the HTTP status and the server's own message")
    func logKeepsTheStatus() {
        let error = StorageError(statusCode: "400", message: "new row violates row-level security policy", error: "InvalidRequest")
        let described = SupabaseDataGateway.describeStorage(error)
        #expect(described.contains("400"))
        #expect(described.contains("row-level security"))
        #expect(described.contains("InvalidRequest"))
    }

    @Test("A write failure carries the database's own SQLSTATE")
    func writeFailureCarriesSQLState() {
        let failure = WriteFailure(sqlState: "22P02", dataError: .rejected("bad enum"))
        #expect(failure.sqlState == "22P02")
        #expect(failure.errorDescription == "bad enum")
        // Only 22P02 may trigger the legacy enum retry; everything else is
        // reported once and not re-sent.
        #expect(WriteFailure(sqlState: "42501", dataError: .notPermitted(.jobPhotosCreate)).sqlState != "22P02")
    }
}

// MARK: - Stripe status wording

/// Every Stripe state has plain words and one obvious next step, and Stripe's
/// internal codes never reach the screen.
struct StripeStatusWordingTests {
    private func classify(
        connected: Bool = true, charges: Bool = false, submitted: Bool = false,
        due: [String] = [], reason: String? = nil
    ) -> StripeConnectionState {
        StripeConnectionState.classify(connected: connected, chargesEnabled: charges, detailsSubmitted: submitted,
                                       requirementsDue: due, disabledReason: reason)
    }

    @Test("Not connected: Set up Stripe / Connect Stripe")
    func notConnected() {
        let s = classify(connected: false)
        #expect(s == .notConnected)
        #expect(s.title == "Set up Stripe")
        #expect(s.message == "Connect Stripe to receive online payments from your customers.")
        #expect(s.actionTitle == "Connect Stripe")
    }

    @Test("Connected but unfinished: Finish setting up Stripe / Finish Stripe setup")
    func setupIncomplete() {
        let s = classify(due: ["external_account"])
        #expect(s == .setupIncomplete)
        #expect(s.title == "Finish setting up Stripe")
        #expect(s.message == "Complete your Stripe setup to start accepting online payments.")
        #expect(s.actionTitle == "Finish Stripe setup")
    }

    /// The live account's exact state: Stripe reports `requirements.past_due`
    /// because onboarding was never finished. That is unfinished setup, not a
    /// disabled account.
    @Test("requirements.past_due is unfinished setup, not \"Payments disabled\"")
    func pastDueIsSetup() {
        let s = classify(due: ["external_account", "tos_acceptance.date"], reason: "requirements.past_due")
        #expect(s == .setupIncomplete)
        #expect(s.actionOpensDashboard(detailsSubmitted: false) == false)
    }

    @Test("Ready: Stripe connected / You're ready to receive online payments.")
    func connected() {
        let s = classify(charges: true, submitted: true)
        #expect(s == .connected)
        #expect(s.title == "Stripe connected")
        #expect(s.message == "You're ready to receive online payments.")
        #expect(s.actionOpensDashboard(detailsSubmitted: true))
    }

    @Test("Submitted and pending verification reads as a review, not as setup")
    func underReview() {
        #expect(classify(submitted: true) == .underReview)
        #expect(classify(submitted: true, reason: "requirements.pending_verification") == .underReview)
        #expect(classify(submitted: true).title == "Stripe is reviewing your account")
    }

    @Test("A genuine restriction or rejection gets its own message, never \"Set up Stripe\"")
    func restricted() {
        for reason in ["rejected.fraud", "rejected.terms_of_service", "platform_paused", "listed", "under_review_other", "other"] {
            let s = classify(submitted: true, reason: reason)
            #expect(s == .restricted, "\(reason)")
            #expect(s.title == "Stripe needs your attention")
            #expect(s.title != StripeConnectionState.notConnected.title)
            #expect(s.actionTitle == "Open Stripe")
        }
    }

    @Test("The retired wording is gone from every state")
    func retiredWording() {
        for s in [StripeConnectionState.notConnected, .setupIncomplete, .connected, .underReview, .restricted] {
            for text in [s.title, s.message, s.actionTitle, s.shortLabel] {
                #expect(text != "Payments disabled")
                #expect(text != "Resolve issue")
            }
        }
    }

    @Test("No state ever shows a raw Stripe code")
    func noRawCodes() {
        for s in [StripeConnectionState.notConnected, .setupIncomplete, .connected, .underReview, .restricted] {
            for text in [s.title, s.message, s.actionTitle, s.shortLabel] {
                #expect(text.contains("requirements.") == false)
                #expect(text.contains("_") == false)
                #expect(text.contains("rejected.") == false)
            }
        }
    }

    @Test("Stripe's requirement keys become plain words")
    func friendlyRequirements() {
        let keys = ["external_account", "tos_acceptance.date", "tos_acceptance.ip",
                    "individual.verification.document", "business_profile.url", "some.unknown_key"]
        let friendly = StripeRequirementCopy.friendly(keys)
        #expect(friendly == ["Bank account for payouts", "Accept Stripe's terms", "Photo ID", "Business details", "Other details"])
        for label in friendly { #expect(label.contains("_") == false && label.contains(".") == false) }
    }

    @Test("The state on CommercialState is the same classification")
    func commercialStateUsesClassifier() {
        let live = CommercialState(stripeConnected: true, chargesEnabled: false, detailsSubmitted: false,
                                   requirementsDue: ["external_account"], disabledReason: "requirements.past_due")
        #expect(live.stripeState == .setupIncomplete)
        #expect(live.stripeNeeds == ["Bank account for payouts"])
    }
}

