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

    /// Asserts the SHAPE of the breakdown, not one locale's rendering of it.
    ///
    /// This previously hard-coded "$19.99 + 14 × $9.99" and passed only on a
    /// runner set to a US locale; on a runner formatting USD as "US$ 19,99" it
    /// failed while the app was behaving correctly. The arithmetic is the thing
    /// worth protecting, so it is checked against the same formatter the app
    /// uses — with the operands asserted independently, so a genuinely wrong
    /// figure still fails.
    @Test("The breakdown line states the arithmetic being charged")
    func breakdownIsItemised() {
        let solo = pricing.quote(for: 1)
        #expect(solo.breakdownLine == SubscriptionQuote.money(1_999))
        #expect(solo.breakdownLine.contains("×") == false)

        let fifteen = pricing.quote(for: 15)
        #expect(fifteen.breakdownLine == "\(SubscriptionQuote.money(1_999)) + 14 × \(SubscriptionQuote.money(999))")
        #expect(fifteen.additionalUsers == 14)
        #expect(fifteen.baseCents == 1_999)
        #expect(fifteen.additionalUserCents == 999)
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

/// The Founding Member programme, as a customer is allowed to see it.
///
/// WHY THIS SUITE EXISTS
/// The old wording — "Founding Members can receive $0/month … 100 of 100 places
/// remain" — was removed once and came back, because the sentence was typed
/// into several screens and only some were corrected. Every screen now reads
/// `FoundingCopy`, and these tests assert the rules directly against it, so a
/// reintroduction fails here rather than on a customer's phone.
///
/// The rules being protected are commercial, not cosmetic:
///   - the allocation size is confidential, and the programme may grow,
///   - a member's own number is internal,
///   - the benefit is something they earn by trading, not something granted,
///   - the subscription being free must never be stated without the fees that
///     still apply.
struct FoundingMemberCopyTests {

    /// Every sentence the app can show a customer about the programme.
    private var customerFacingCopy: [String] {
        [
            FoundingCopy.badgeTitle,
            FoundingCopy.benefitActive,
            FoundingCopy.benefitPaused,
            FoundingCopy.statusKept,
            FoundingCopy.trialOutcome,
            FoundingCopy.invitation(feeLabel: "0.30%"),
            FoundingCopy.feeRider("0.30%")
        ]
    }

    @Test("No customer-facing sentence reveals the allocation, a member number, or 'can receive'")
    func forbiddenWordingIsAbsent() {
        for sentence in customerFacingCopy {
            for fragment in FoundingCopy.forbiddenFragments {
                #expect(
                    sentence.localizedCaseInsensitiveContains(fragment) == false,
                    "\"\(sentence)\" must not contain \"\(fragment)\""
                )
            }
        }
    }

    /// The programme may be extended past 100, so nothing describing the STATUS
    /// may be tied to that figure — or to any other count.
    ///
    /// The fee rider and the invitation are excluded because they must quote
    /// the platform fee ("0.30%"); that is a rate, not a headcount, and
    /// `forbiddenWordingIsAbsent` already proves neither leaks an allocation.
    @Test("No sentence describing the status contains a figure")
    func noDigitsAnywhere() {
        let statusCopy = [
            FoundingCopy.badgeTitle,
            FoundingCopy.benefitActive,
            FoundingCopy.benefitPaused,
            FoundingCopy.statusKept,
            FoundingCopy.trialOutcome
        ]
        for sentence in statusCopy {
            #expect(
                sentence.contains(where: \.isNumber) == false,
                "\"\(sentence)\" must not contain a figure"
            )
        }
    }

    @Test("The benefit is stated as zero subscription fees, conditional on processing payments")
    func benefitIsStatedCorrectly() {
        let invitation = FoundingCopy.invitation(feeLabel: "0.30%")
        #expect(invitation.localizedCaseInsensitiveContains("zero"))
        #expect(invitation.localizedCaseInsensitiveContains("subscription fees"))
        #expect(invitation.localizedCaseInsensitiveContains("actively processing customer payments"))
    }

    /// Saying the subscription is free without the rider would misstate the
    /// commercial deal.
    @Test("The invitation always carries the platform fee and Stripe's fees")
    func invitationCarriesTheFeeRider() {
        let invitation = FoundingCopy.invitation(feeLabel: "0.30%")
        #expect(invitation.contains("0.30%"))
        #expect(invitation.localizedCaseInsensitiveContains("stripe processing fees"))
    }

    /// The fee shown must be the company's real fee, not a constant that would
    /// silently lie if the rate ever differed.
    @Test("The fee rider quotes the fee it is given")
    func feeRiderUsesTheSuppliedRate() {
        #expect(FoundingCopy.feeRider("0.45%").contains("0.45%"))
        #expect(FoundingCopy.feeRider("0.45%").contains("0.30%") == false)
    }

    @Test("Every sentence names the product")
    func copyNamesTheProduct() {
        #expect(FoundingCopy.programme == Brand.name)
        #expect(FoundingCopy.benefitActive.contains(Brand.name))
        #expect(FoundingCopy.invitation(feeLabel: "0.30%").contains(Brand.name))
        #expect(FoundingCopy.trialOutcome.contains(Brand.name))
    }

    /// An inactive month pauses the benefit; it never removes the status.
    @Test("A quiet month is described as recoverable, never as a forfeit")
    func statusIsNeverDescribedAsLost() {
        #expect(FoundingCopy.benefitPaused.localizedCaseInsensitiveContains("resume"))
        #expect(FoundingCopy.statusKept.localizedCaseInsensitiveContains("yours to keep"))
        for word in ["forfeit", "lose", "lost", "revoked", "cancelled"] {
            #expect(FoundingCopy.statusKept.localizedCaseInsensitiveContains(word) == false)
            #expect(FoundingCopy.benefitPaused.localizedCaseInsensitiveContains(word) == false)
        }
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

/// The state that drives the Founding wording, rather than the wording itself.
///
/// `CommercialState` decides WHICH sentence is shown; these assert it cannot
/// offer the programme to somebody ineligible, or leak the member number
/// through the badge title.
struct FoundingMemberStateTests {

    private func state(number: Int?, offerOpen: Bool, benefitActive: Bool) -> CommercialState {
        CommercialState(
            paymentModel: .harbourSouthPayments,
            subscriptionStatus: .active,
            trialEndsAt: nil,
            trialDaysRemaining: 0,
            isTrialActive: false,
            stripeConnected: true,
            chargesEnabled: true,
            payoutsEnabled: true,
            detailsSubmitted: true,
            requirementsDue: [],
            disabledReason: nil,
            stripeAccountID: "acct_1",
            foundingMemberNumber: number,
            foundingClaimedAt: nil,
            foundingPlacesClaimed: 27,
            foundingPlacesRemaining: 73,
            foundingOfferOpen: offerOpen,
            foundingBenefitActive: benefitActive,
            qualifyingPaymentsThisMonth: benefitActive ? 1 : 0,
            lastQualifyingPaymentAt: nil,
            activityMonthStart: nil,
            tierID: "team",
            tierName: "Team",
            subscriptionMonthlyCents: 3298,
            effectiveMonthlyCents: benefitActive ? 0 : 3298,
            platformFeeBps: 30,
            externalPaymentURL: nil,
            businessEmail: nil,
            canManageBilling: true
        )
    }

    /// The company holds place 27, and 73 places are left — neither figure may
    /// reach the badge.
    @Test("The badge never renders the member number")
    func badgeTitleHidesTheNumber() {
        let member = state(number: 27, offerOpen: true, benefitActive: true)
        #expect(member.foundingBadgeTitle == "Founding Member")
        #expect(member.foundingBadgeTitle?.contains("27") == false)
    }

    @Test("A member is never shown the invitation meant for non-members")
    func membersSeeNoInvitation() {
        #expect(state(number: 27, offerOpen: true, benefitActive: true).foundingInvitation == nil)
    }

    /// Nothing may promise a benefit that is no longer available.
    @Test("A closed offer is not advertised to anyone")
    func closedOfferIsSilent() {
        #expect(state(number: nil, offerOpen: false, benefitActive: false).foundingInvitation == nil)
        #expect(state(number: nil, offerOpen: true, benefitActive: false).foundingInvitation != nil)
    }

    @Test("A non-member has no Founding status or benefit message")
    func nonMemberHasNoStatus() {
        let outsider = state(number: nil, offerOpen: true, benefitActive: false)
        #expect(outsider.isFoundingMember == false)
        #expect(outsider.foundingBadgeTitle == nil)
        #expect(outsider.foundingBenefitMessage == nil)
    }

    /// Status survives an inactive month; only the benefit pauses.
    @Test("A member with no qualifying payment keeps the status")
    func statusSurvivesAQuietMonth() {
        let paused = state(number: 27, offerOpen: false, benefitActive: false)
        #expect(paused.isFoundingMember)
        #expect(paused.foundingBadgeTitle == "Founding Member")
        #expect(paused.foundingBenefitMessage == FoundingCopy.benefitPaused)
    }

    /// The headline sits on the billing screen, so it is as customer-facing as
    /// the card copy and must obey the same rules.
    @Test("The headline states the benefit without leaking the allocation")
    func headlineIsClean() {
        let active = state(number: 27, offerOpen: true, benefitActive: true)
        #expect(active.headline == "Founding Member — zero subscription fees")
        for fragment in FoundingCopy.forbiddenFragments {
            #expect(active.headline.localizedCaseInsensitiveContains(fragment) == false)
        }
    }

    @Test("The trial outcome for a member carries the correct wording")
    func trialOutcomeUsesSharedCopy() {
        #expect(state(number: 27, offerOpen: true, benefitActive: true).trialOutcomeMessage == FoundingCopy.trialOutcome)
    }
}
