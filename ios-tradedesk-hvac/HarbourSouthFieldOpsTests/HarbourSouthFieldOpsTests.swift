import Foundation
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

// MARK: - Subscription pricing

/// The pricing model is **non-progressive**: a company falls into exactly one
/// tier chosen by its total head count, and every seat after the first is
/// charged that tier's single rate. It is emphatically not "the first 10 at one
/// rate, the next 20 at another".
///
/// The published examples are the specification, so they are asserted verbatim
/// in cents. Comparing money as `Decimal`/cents rather than `Double` is the
/// point: a binary float would make several of these pass by rounding.
struct SubscriptionPricingTests {
    private let pricing = PlatformPricing.fallback

    @Test("One user is the base price and nothing else")
    func soloUser() {
        let quote = pricing.quote(for: 1)
        #expect(quote.monthlyPriceCents == 1_999)
        #expect(quote.additionalUsers == 0)
        #expect(quote.tierID == "solo")
    }

    @Test(
        "Published price points are exact",
        arguments: [
            (users: 1, cents: 1_999),     // $19.99
            (users: 5, cents: 7_195),     // $71.95   = 19.99 + 4 × 12.99
            (users: 10, cents: 13_690),   // $136.90  = 19.99 + 9 × 12.99
            (users: 11, cents: 11_989),   // $119.89  = 19.99 + 10 × 9.99
            (users: 15, cents: 15_985),   // $159.85  = 19.99 + 14 × 9.99
            (users: 30, cents: 30_970),   // $309.70  = 19.99 + 29 × 9.99
            (users: 31, cents: 25_969),   // $259.69  = 19.99 + 30 × 7.99
            (users: 35, cents: 29_165),   // $291.65  = 19.99 + 34 × 7.99
            (users: 100, cents: 81_100)   // $811.00  = 19.99 + 99 × 7.99
        ]
    )
    func publishedPricePoints(users: Int, cents: Int) {
        #expect(pricing.quote(for: users).monthlyPriceCents == cents)
    }

    /// The boundary that proves the model is not progressive: adding an
    /// eleventh person **reduces** the bill, because every seat reprices to the
    /// cheaper tier rather than only the new one.
    @Test("Crossing a tier boundary reprices every seat, not just the new one")
    func boundaryRepricesDownward() {
        let ten = pricing.quote(for: 10)
        let eleven = pricing.quote(for: 11)

        #expect(eleven.monthlyPriceCents < ten.monthlyPriceCents)
        #expect(eleven.additionalUserCents == 999)
        // A progressive model would charge 9 × 12.99 + 1 × 9.99 here. It does
        // not, and this is the assertion that would catch someone "fixing" it.
        #expect(eleven.monthlyPriceCents != 1_999 + (9 * 1_299) + 999)

        // And the marginal cost shown to the owner is honest about that: the
        // eleventh seat is negative, because the bill genuinely goes down.
        #expect((ten.nextUserCents ?? 0) < 0)
    }

    @Test("Every additional seat is charged the same rate inside a tier")
    func flatRateWithinTier() {
        for users in 2...10 {
            let quote = pricing.quote(for: users)
            #expect(quote.additionalUserCents == 1_299)
            #expect(quote.additionalUsers == users - 1)
            #expect(quote.monthlyPriceCents == 1_999 + ((users - 1) * 1_299))
        }
    }

    @Test("The ceiling is 100 paid users")
    func ceiling() {
        let full = pricing.quote(for: 100)
        #expect(full.isAtCapacity)
        #expect(full.isOverCapacity == false)
        // Nothing to quote for a 101st seat, so no marginal price is invented.
        #expect(full.nextUserCents == nil)

        let over = pricing.quote(for: 101)
        #expect(over.isOverCapacity)
    }

    @Test("A head count below one is treated as one rather than as free")
    func zeroUsersFloorsToOne() {
        #expect(pricing.quote(for: 0).monthlyPriceCents == 1_999)
        #expect(pricing.quote(for: -5).monthlyPriceCents == 1_999)
    }

    @Test("Tiers cover 1...100 with no gap and no overlap")
    func tiersAreContiguous() {
        for users in 1...100 {
            let matches = pricing.tiers.filter { $0.contains(users) }
            #expect(matches.count == 1, "\(users) users matched \(matches.count) tiers")
        }
    }

    @Test("The breakdown line states the arithmetic being charged")
    func breakdownIsItemised() {
        #expect(pricing.quote(for: 1).breakdownLine == "$19.99")
        #expect(pricing.quote(for: 15).breakdownLine == "$19.99 + 14 × $9.99")
    }

    /// The fallback price list is only ever shown with a caveat, and it says so
    /// in the type rather than relying on a screen to remember.
    @Test("The built-in price list is marked as not live")
    func fallbackIsLabelled() {
        #expect(PlatformPricing.fallback.isLive == false)
        #expect(PlatformPricing.fallback.maxUsers == 100)
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
        #expect(billing?.mode == .simulated)
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
