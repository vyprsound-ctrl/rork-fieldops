import XCTest

/// Launch verification.
///
/// The stock template attached a screenshot on every launch. Attachments are
/// disabled in the headless CI simulator, and `add(_:)` raises
/// `NSInternalInconsistencyException` there — so the template test failed for a
/// harness reason while telling us nothing about the app.
///
/// This asserts the thing that actually matters instead: the app launches and
/// reaches its first real screen rather than hanging on the restore state or
/// dying at startup.
final class HarbourSouthFieldOpsUITestsLaunchTests: XCTestCase {

    /// Deliberately false. The stock template ran this for every UI
    /// configuration purely to collect screenshots; without attachments that is
    /// repeated work with no extra signal.
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // The sign-in screen is the first thing a signed-out launch must reach.
        // The header renders `Brand.name`, which is "Harbour South FieldOps" —
        // matching on a prefix keeps this test from breaking on a future rename
        // while still proving real branded UI was rendered.
        let brand = app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH[c] %@", "Harbour South")
        ).firstMatch
        let signedOut = brand.waitForExistence(timeout: 30)

        // A restored session would land in a shell instead, which is equally a
        // successful launch — so accept either, and fail only if neither
        // appeared.
        let signedIn = app.tabBars.buttons["Dashboard"].exists
            || app.tabBars.buttons["Jobs"].exists

        XCTAssertTrue(
            signedOut || signedIn,
            "The app must reach either the sign-in screen or a signed-in shell after launching"
        )
    }
}
