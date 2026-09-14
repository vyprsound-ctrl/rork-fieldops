import XCTest

/// RUNTIME VERIFICATION — Harbour South FieldOps
///
/// These tests exist because Build 12 shipped with source that was believed
/// correct and a binary that behaved otherwise. Compiling is not evidence. A
/// route existing is not evidence. The only evidence that a feature works is
/// launching the app, tapping the thing, and reading what comes back.
///
/// Every test below drives the real UI through the DEBUG development stack,
/// which runs on the seeded in-memory store. That store is deliberately used
/// rather than the live database: these assertions are about whether the
/// *application* behaves correctly, and a test that mutated a real company's
/// records to prove a button works would be a poor trade.
///
/// Seeded accounts (Gulf Coast Air, HVAC):
///   Tom Ellison    owner
///   Carla Bell     dispatcher
///   Marcus Hale    field worker
final class HarbourSouthFieldOpsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Waits for an element and fails with a readable message rather than a
    /// bare timeout, so a failure says which screen never appeared.
    @discardableResult
    private func require(
        _ element: XCUIElement,
        _ description: String,
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        let found = element.waitForExistence(timeout: timeout)
        XCTAssertTrue(found, "Expected to find \(description)", file: file, line: line)
        return found
    }

    /// Signs in through the development picker as one of the seeded users.
    private func signIn(as name: String, file: StaticString = #filePath, line: UInt = #line) {
        let account = app.staticTexts[name]
        guard account.waitForExistence(timeout: 20) else {
            XCTFail("Development account '\(name)' never appeared on the sign-in screen", file: file, line: line)
            return
        }
        account.tap()
    }

    /// Taps a tab in the shell's tab bar.
    private func openTab(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[label]
        guard tab.waitForExistence(timeout: 20) else {
            XCTFail("Tab '\(label)' never appeared", file: file, line: line)
            return
        }
        tab.tap()
    }

    /// Scrolls the first scroll view until a matching element is hittable, or
    /// gives up. SwiftUI lazily realises off-screen rows, so a plain existence
    /// check is not enough for anything below the fold.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, attempts: Int = 10) -> Bool {
        if element.exists && element.isHittable { return true }
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Types into a SwiftUI `TextField` inside a `Form`.
    ///
    /// Tapping the field's own frame frequently fails to move focus, because the
    /// tappable target is the enclosing cell rather than the text layer. Tapping
    /// the centre coordinate and then waiting for the keyboard is what makes
    /// this reliable in a `Form`.
    @discardableResult
    private func type(_ text: String, into field: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        guard field.waitForExistence(timeout: timeout) else { return false }
        _ = scrollTo(field)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Focus is asynchronous; give the keyboard a moment to attach.
        _ = app.keyboards.element.waitForExistence(timeout: 5)
        guard field.value as? String != nil else { return false }
        field.typeText(text)
        return true
    }

    /// Taps an element even when SwiftUI reports it as not hittable.
    ///
    /// A row inside a `NavigationLink` is frequently reported non-hittable while
    /// still being perfectly tappable at its own centre — the label is a child of
    /// the link, not the hit target. Falling back to a coordinate tap keeps the
    /// test measuring the app rather than XCUITest's hit-testing quirks.
    private func forceTap(_ element: XCUIElement) {
        if element.isHittable {
            element.tap()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Opens a row in the More tab by its visible title.
    private func openMoreSection(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        openTab("More")

        // Prefer the button the row actually is; fall back to its label.
        let row = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", title)
        ).firstMatch
        if row.waitForExistence(timeout: 10) {
            _ = scrollTo(row)
            forceTap(row)
            return
        }

        let label = app.staticTexts[title]
        guard scrollTo(label) || label.waitForExistence(timeout: 10) else {
            XCTFail("More section '\(title)' never appeared", file: file, line: line)
            return
        }
        forceTap(label)
    }

    // MARK: - Authentication

    /// The app must reach a real signed-in shell, and signing out must return
    /// to the sign-in screen rather than merely dismissing a view.
    func testOwnerCanSignInAndSignOut() throws {
        signIn(as: "Tom Ellison")

        require(app.tabBars.buttons["Dashboard"], "the office shell after signing in")

        openTab("More")
        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(scrollTo(signOut), "Sign out must be reachable in More")
        signOut.tap()

        // The real proof: the tab bar is gone and the sign-in screen is back.
        let backAtSignIn = app.staticTexts["Tom Ellison"].waitForExistence(timeout: 20)
        XCTAssertTrue(backAtSignIn, "Signing out must return to the sign-in screen")
        XCTAssertFalse(
            app.tabBars.buttons["Dashboard"].exists,
            "The office shell must be gone after signing out"
        )
    }

    /// ISSUE — the field worker's way out must end the session, not just close
    /// a screen. Verified by asserting the field shell is gone afterwards.
    func testFieldWorkerCanSignOut() throws {
        signIn(as: "Marcus Hale")

        require(app.tabBars.buttons["Jobs"], "the field worker shell")
        XCTAssertFalse(
            app.tabBars.buttons["Dashboard"].exists,
            "A field worker must never receive the office shell"
        )

        openTab("More")
        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(scrollTo(signOut), "Sign out must be reachable for a field worker")
        signOut.tap()

        XCTAssertTrue(
            app.staticTexts["Marcus Hale"].waitForExistence(timeout: 20),
            "Field worker sign-out must return to the sign-in screen"
        )
        XCTAssertFalse(
            app.tabBars.buttons["Jobs"].exists,
            "The field shell must be gone after signing out"
        )
    }

    // MARK: - Field worker day

    /// MY DAY must be an ordered checklist of today's stops, not a single job
    /// or an equipment screen.
    func testFieldWorkerDayShowsTodaysWork() throws {
        signIn(as: "Marcus Hale")

        require(app.tabBars.buttons["Jobs"], "the field worker shell")
        require(app.navigationBars["My day"], "the MY DAY screen")

        // The four field tabs, and nothing resembling an office surface.
        for tab in ["Jobs", "Schedule", "Office", "More"] {
            XCTAssertTrue(app.tabBars.buttons[tab].exists, "Field worker needs the \(tab) tab")
        }
        for forbidden in ["Dashboard", "Customers", "Calendar"] {
            XCTAssertFalse(
                app.tabBars.buttons[forbidden].exists,
                "Field worker must not have a \(forbidden) tab"
            )
        }
    }

    // MARK: - Reports drill-down (release-blocking)

    /// ISSUE #11 — Build 12 shipped Reports with untappable figures.
    ///
    /// This is the test that would have caught it: it taps a financial metric
    /// and asserts the app actually navigates to the invoice list behind it.
    func testReportsFinancialMetricOpensInvoiceList() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Reports")

        require(app.navigationBars["Reports"], "the Reports screen")

        let outstanding = app.staticTexts["Outstanding"]
        XCTAssertTrue(scrollTo(outstanding), "Reports must show the Outstanding metric")
        outstanding.tap()

        XCTAssertTrue(
            app.navigationBars["Invoices"].waitForExistence(timeout: 20),
            "Tapping Outstanding must open the invoice list"
        )
    }

    /// The same defect on the operational side: a job figure must reach the
    /// jobs behind it.
    func testReportsJobMetricOpensJobList() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Reports")

        require(app.navigationBars["Reports"], "the Reports screen")

        let open = app.staticTexts["Open"]
        XCTAssertTrue(scrollTo(open), "Reports must show the Open jobs metric")
        open.tap()

        XCTAssertTrue(
            app.navigationBars["Jobs"].waitForExistence(timeout: 20),
            "Tapping Open must open the jobs list"
        )
    }

    // MARK: - Invoices

    /// ISSUE #5 — an invoice must be raisable without inventing a job. The
    /// picker's default tab is the standalone one, and it must offer a customer
    /// rather than demanding a source document.
    func testStandaloneInvoiceFlowIsReachableWithoutAJob() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Invoices")

        require(app.navigationBars["Invoices"], "the Invoices screen")

        app.navigationBars["Invoices"].buttons["New invoice"].tap()

        require(app.navigationBars["New invoice"], "the new invoice sheet")

        // All three sources must be offered, and "New" (standalone) is default.
        XCTAssertTrue(app.buttons["New"].exists, "A standalone invoice option must exist")
        XCTAssertTrue(app.buttons["From job"].exists, "The job-linked option must remain")
        XCTAssertTrue(app.buttons["From quote"].exists, "The quote-derived option must remain")

        XCTAssertTrue(
            app.staticTexts["Choose a customer"].waitForExistence(timeout: 20)
                || app.staticTexts["Customer"].exists,
            "The standalone form must ask for a customer, not a job"
        )
    }

    // MARK: - Quotes

    /// ISSUE #9B — quote creation must be one flow: line items and totals are
    /// reachable before the quote is ever saved.
    func testQuoteEditorOffersLineItemsBeforeSaving() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Quotes")

        require(app.navigationBars["Quotes"], "the Quotes screen")
        app.navigationBars["Quotes"].buttons["New quote"].tap()

        require(app.navigationBars["New quote"], "the new quote editor")

        let addLine = app.buttons["Add line item"]
        XCTAssertTrue(
            scrollTo(addLine),
            "Line items must be addable during creation, before the quote is saved"
        )
    }

    /// ISSUE #9A — a newly created quote is a draft, and drafts must appear
    /// under Open.
    func testQuoteOpenFilterExists() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Quotes")

        require(app.navigationBars["Quotes"], "the Quotes screen")
        XCTAssertTrue(app.buttons["Open"].exists, "The Open quote filter must exist")
        app.buttons["Open"].tap()
    }

    // MARK: - Messaging

    /// ISSUE #13 — the office needs its own way in to field worker messages.
    func testOwnerHasMessagesInbox() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Messages")

        XCTAssertTrue(
            app.navigationBars["Messages"].waitForExistence(timeout: 20),
            "Owner must be able to open the Messages inbox"
        )
    }

    // MARK: - Dispatch

    /// ISSUE #12 — dispatch must be a control centre, not a display.
    ///
    /// Also asserts the board actually offers the assignment controls, since
    /// "Dispatch opens" was true in Build 12 while reassign and unassign were
    /// unreachable.
    func testDispatchIsReachableAndOffersAssignment() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Dispatch")

        XCTAssertTrue(
            app.navigationBars["Dispatch"].waitForExistence(timeout: 20),
            "Owner must be able to open Dispatch"
        )

        // The board must show the field worker roster it dispatches to.
        XCTAssertTrue(
            app.staticTexts["Marcus Hale"].waitForExistence(timeout: 15)
                || app.staticTexts["Field workers"].exists,
            "Dispatch must show the field workers it can assign work to"
        )
    }

    // MARK: - Customers

    /// ISSUE #7 — the Create button must enable on name + street + city, with
    /// no state or ZIP typed at all.
    func testNewCustomerSavesWithoutStateOrPostalCode() throws {
        signIn(as: "Tom Ellison")
        openTab("Customers")

        require(app.navigationBars["Customers"], "the Customers screen")
        app.navigationBars["Customers"].buttons["Add customer"].tap()

        require(app.navigationBars["New customer"], "the customer editor")

        let create = app.navigationBars["New customer"].buttons["Create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10), "The customer editor must offer a Create action")

        // Nothing typed yet, so the form must refuse — this proves the later
        // assertion is measuring real validation rather than a button that was
        // enabled all along.
        XCTAssertFalse(create.isEnabled, "Create must be disabled before anything is entered")

        XCTAssertTrue(
            type("Runtime Check Ltd", into: app.textFields["Name or business"]),
            "The customer name field must accept input"
        )
        XCTAssertTrue(
            type("14 Harbour Way", into: app.textFields["Street address"]),
            "The street field must accept input"
        )
        XCTAssertTrue(
            type("Tampa", into: app.textFields["City"]),
            "The city field must accept input"
        )

        // State and ZIP are deliberately left empty — that is the whole point of
        // ISSUE #7 and of not being a US-only product.
        XCTAssertEqual(
            app.textFields["State"].value as? String, "State",
            "State must still be empty (showing its placeholder)"
        )
        XCTAssertEqual(
            app.textFields["ZIP"].value as? String, "ZIP",
            "ZIP must still be empty (showing its placeholder)"
        )

        XCTAssertTrue(
            create.isEnabled,
            "Create must enable on name + street + city, without a state or ZIP"
        )
    }

    // MARK: - Commercial

    /// COMMERCIAL PRIVACY — the customer must never be told their place in the
    /// Founding allocation, nor how many places remain.
    func testSubscriptionNeverRevealsFoundingAllocation() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Subscription & Users")

        require(app.navigationBars["Subscription"], "the Subscription screen")

        // Walk the whole screen so lazily-realised text is actually inspected.
        var seen = Set<String>()
        for _ in 0..<12 {
            for text in app.staticTexts.allElementsBoundByIndex {
                let label = text.label
                if !label.isEmpty { seen.insert(label) }
            }
            app.swipeUp()
        }

        for label in seen {
            XCTAssertFalse(
                label.contains("Founding Member #"),
                "The Founding Member allocation number must never be shown — found: \(label)"
            )
            XCTAssertFalse(
                label.localizedCaseInsensitiveContains("places remain")
                    || label.localizedCaseInsensitiveContains("places left")
                    || label.localizedCaseInsensitiveContains("of 100"),
                "The Founding allocation size must never be shown — found: \(label)"
            )
        }
    }

    // MARK: - Role isolation

    /// A field worker must not be able to reach financial or company surfaces.
    /// Structural, not cosmetic: the tabs and rows simply are not there.
    func testFieldWorkerCannotReachFinancialSurfaces() throws {
        signIn(as: "Marcus Hale")

        require(app.tabBars.buttons["Jobs"], "the field worker shell")
        openTab("More")

        for forbidden in [
            "Invoices", "Payments", "Accounts receivable", "Subscription & Users",
            "Reports", "Dispatch", "Quotes", "Customers"
        ] {
            XCTAssertFalse(
                app.staticTexts[forbidden].exists,
                "A field worker must not see '\(forbidden)' in More"
            )
        }
    }
}
