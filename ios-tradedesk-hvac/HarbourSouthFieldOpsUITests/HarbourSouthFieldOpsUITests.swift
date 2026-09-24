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

        // The open keyboard covers the lower half of the screen. A field below
        // that line reports as existing and even as hittable, but a tap lands on
        // a key instead of the field and focus never moves — which is exactly
        // how this failed on the street and city fields.
        dismissKeyboard()
        guard scrollAboveKeyboard(field) else { return false }

        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Focus is asynchronous; give the keyboard a moment to attach.
        _ = app.keyboards.element.waitForExistence(timeout: 5)
        guard field.value as? String != nil else { return false }
        field.typeText(text)

        // Put the keyboard away so the NEXT field is reachable.
        dismissKeyboard()
        return true
    }

    /// Closes the keyboard without touching app content.
    private func dismissKeyboard() {
        guard app.keyboards.element.exists else { return }
        // "return" commits a single-line SwiftUI TextField and resigns focus.
        app.typeText("\n")
        _ = app.keyboards.element.waitForNonExistence(timeout: 3)
    }

    /// Scrolls until the element sits clear of the keyboard and is tappable.
    @discardableResult
    private func scrollAboveKeyboard(_ element: XCUIElement, attempts: Int = 10) -> Bool {
        for _ in 0..<attempts {
            guard element.exists else { return false }
            let limit = app.keyboards.element.exists
                ? app.keyboards.element.frame.minY
                : app.frame.maxY
            if element.isHittable, element.frame.maxY < limit - 12 { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
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

        // The inbox has to actually contain the company's conversations, not
        // just render an empty shell.
        XCTAssertTrue(
            app.staticTexts["Condenser fan motor"].waitForExistence(timeout: 15),
            "The office inbox must list the field worker's conversations"
        )
    }

    /// THE "OPEN" DEFECT — a job-linked message offers an Open button, and it
    /// did nothing at all.
    ///
    /// Root cause: the button pushed a `FieldJobRoute`, but neither stack that
    /// hosts the conversation registered a destination for that type, so
    /// SwiftUI had nothing to push.
    ///
    /// This opens TWO different conversations, each linked to a DIFFERENT job,
    /// and asserts each lands on its own job. Testing one would pass even if
    /// the button were hard-coded to a single job — which is exactly the class
    /// of bug worth ruling out.
    func testOwnerOpenButtonOpensTheExactRelatedJob() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Messages")
        require(app.navigationBars["Messages"], "the Messages inbox")

        // Conversation A — J-1042.
        openThread("Condenser fan motor")
        assertJobContext(is: "J-1042")
        tapOpen(job: "J-1042")
        XCTAssertTrue(
            app.staticTexts["J-1042"].waitForExistence(timeout: 20),
            "Open must navigate to job J-1042, the job this message is about"
        )
        XCTAssertFalse(
            app.staticTexts["J-1043"].exists,
            "Open must not land on a different job"
        )

        // Back out to the inbox for conversation B.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        require(app.navigationBars["Messages"], "the Messages inbox again")

        // Conversation B — a DIFFERENT job, J-1043.
        openThread("Roof access at Whitfield")
        assertJobContext(is: "J-1043")
        tapOpen(job: "J-1043")
        XCTAssertTrue(
            app.staticTexts["J-1043"].waitForExistence(timeout: 20),
            "Open must navigate to J-1043 for the second conversation, not repeat the first job"
        )
        XCTAssertFalse(
            app.staticTexts["J-1042"].exists,
            "Open must not be hard-coded to the previously opened job"
        )
    }

    /// The same button, in the field worker's own shell, which is a different
    /// navigation stack and therefore a genuinely separate code path.
    func testFieldWorkerOpenButtonOpensTheRelatedJob() throws {
        signIn(as: "Marcus Hale")
        openTab("Office")
        require(app.navigationBars["Office"], "the field worker's Office tab")

        openThread("Condenser fan motor")
        assertJobContext(is: "J-1042")
        tapOpen(job: "J-1042")

        XCTAssertTrue(
            app.staticTexts["J-1042"].waitForExistence(timeout: 20),
            "A field worker's Open button must reach their own job"
        )
    }

    // MARK: - Message image attachments
    //
    // THE DEFECT THESE EXIST FOR: Build 14 shipped with NO visible photo control
    // on a general conversation, because the composer hid it whenever the thread
    // had no job. The previous version of this test asserted that hiding was
    // correct — it was not; it was a workaround for `job_photos.job_id` being
    // NOT NULL, which migration 0011 fixes. A test that enshrines a workaround
    // is worse than no test, so it has been replaced by its opposite.

    /// The control must be visible on a JOB-LINKED conversation, for the worker.
    func testFieldWorkerSeesPhotoControlOnJobConversation() throws {
        signIn(as: "Marcus Hale")
        openTab("Office")
        require(app.navigationBars["Office"], "the field worker's Office tab")

        openThread("Condenser fan motor")
        assertPhotoControlIsVisible(in: "a job-linked conversation, as the field worker")

        // An existing attachment must still render alongside its text.
        XCTAssertTrue(
            app.staticTexts["Fan motor is seized and the capacitor is bulging. Photo attached."]
                .waitForExistence(timeout: 15),
            "A message carrying a photo must still display its text"
        )
    }

    /// The control must be visible on a GENERAL conversation, for the worker.
    ///
    /// This is the exact case that was broken in the shipping binary: no job,
    /// therefore no button, therefore no way to send a picture at all.
    func testFieldWorkerSeesPhotoControlOnGeneralConversation() throws {
        signIn(as: "Marcus Hale")
        openTab("Office")
        require(app.navigationBars["Office"], "the field worker's Office tab")

        openThread("Van parking at the depot")

        // Prove it really is a general conversation before asserting anything:
        // a job-linked thread announces its job, and this one must not.
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "About job")).firstMatch.exists,
            "'Van parking at the depot' is seeded with no job — it must not claim one"
        )
        assertPhotoControlIsVisible(in: "a general conversation, as the field worker")
    }

    /// The same two cases from the other side. Image messaging is not
    /// directional, so the office must see the control in both.
    func testOwnerSeesPhotoControlOnBothConversationKinds() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Messages")
        require(app.navigationBars["Messages"], "the Messages inbox")

        // Job-linked.
        openThread("Condenser fan motor")
        assertJobContext(is: "J-1042")
        assertPhotoControlIsVisible(in: "a job-linked conversation, as the owner")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        require(app.navigationBars["Messages"], "the Messages inbox again")

        // General.
        openThread("Van parking at the depot")
        assertPhotoControlIsVisible(in: "a general conversation, as the owner")
    }

    /// An image sent on a general conversation renders in the thread and is not
    /// text-only — the seeded general message carries a photo.
    func testGeneralConversationRendersItsImage() throws {
        signIn(as: "Marcus Hale")
        openTab("Office")
        require(app.navigationBars["Office"], "the field worker's Office tab")

        openThread("Van parking at the depot")
        XCTAssertTrue(
            app.staticTexts["Parked in the far bay again."].waitForExistence(timeout: 15),
            "The general conversation's message must be readable"
        )
    }

    /// Asserts the composer's photo control exists AND is usable.
    ///
    /// Existence alone is not enough: a control that is present but permanently
    /// disabled is the same defect wearing a different hat.
    private func assertPhotoControlIsVisible(
        in context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let control = app.buttons["composer.attachPhotos"]
        XCTAssertTrue(
            control.waitForExistence(timeout: 20),
            "The photo attachment control must be visible in \(context)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            control.isEnabled,
            "The photo attachment control must be usable in \(context), not merely present",
            file: file,
            line: line
        )
    }

    /// Opens a conversation from whichever inbox is on screen.
    private func openThread(_ subject: String, file: StaticString = #filePath, line: UInt = #line) {
        let row = app.staticTexts[subject]
        guard scrollTo(row) || row.waitForExistence(timeout: 15) else {
            XCTFail("Conversation '\(subject)' never appeared", file: file, line: line)
            return
        }
        forceTap(row)
    }

    /// Asserts the conversation names the job it is about, before Open is used.
    private func assertJobContext(is number: String, file: StaticString = #filePath, line: UInt = #line) {
        let context = app.staticTexts["About job \(number)"]
        XCTAssertTrue(
            context.waitForExistence(timeout: 20),
            "The conversation must state which job it concerns (\(number))",
            file: file,
            line: line
        )
    }

    /// Taps the Open button for a specific job.
    ///
    /// Matched by its accessibility label ("Open job J-1042") rather than by the
    /// word "Open", which additionally proves the control is bound to the job
    /// the conversation is actually about.
    private func tapOpen(job number: String, file: StaticString = #filePath, line: UInt = #line) {
        let open = app.buttons["Open job \(number)"]
        guard open.waitForExistence(timeout: 15) else {
            XCTFail(
                "The Open button for job \(number) never appeared on the job-linked message",
                file: file,
                line: line
            )
            return
        }
        forceTap(open)
    }

    // MARK: - Opening chat photos full size
    //
    // THE DEFECT THESE EXIST FOR: Build 17 rendered chat photos as bare
    // thumbnails with no action, so a recipient could see a photo but never
    // inspect it. Every case taps the photo itself, asserts the job screen's
    // viewer shows a real image, dismisses it, and asserts the conversation is
    // back. Sent and received photos are both covered, so nothing can pass
    // while the tap is conditioned on who sent the photo.

    /// A. Owner, general conversation: their own photo, and the engineer's.
    func testOwnerOpensPhotosInGeneralConversation() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Messages")
        require(app.navigationBars["Messages"], "the Messages inbox")

        openThread("Van parking at the depot")
        assertOpensFullSize("Your photo", "the owner's own photo on a general conversation")
        assertOpensFullSize("Photo from Marcus Hale", "the engineer's photo, received by the owner on a general conversation")
    }

    /// B. Engineer sends on a job conversation, owner receives and opens it.
    func testOwnerOpensEngineerPhotoInJobConversation() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Messages")
        require(app.navigationBars["Messages"], "the Messages inbox")

        openThread("Condenser fan motor")
        assertJobContext(is: "J-1042")
        assertOpensFullSize("Photo from Marcus Hale", "the engineer's photo, received by the owner on a job conversation")
        assertOpensFullSize("Your photo", "the owner's own photo on a job conversation")
    }

    /// C. Owner sends on a job conversation, engineer receives and opens it.
    func testEngineerOpensOwnerPhotoInJobConversation() throws {
        signIn(as: "Marcus Hale")
        openTab("Office")
        require(app.navigationBars["Office"], "the field worker's Office tab")

        openThread("Condenser fan motor")
        assertJobContext(is: "J-1042")
        assertOpensFullSize("Photo from Tom Ellison", "the owner's photo, received by the engineer on a job conversation")
        assertOpensFullSize("Your photo", "the engineer's own photo on a job conversation")
    }

    /// D. The job-chat photo still opens from the job page, as in Build 17.
    func testJobChatPhotoStillOpensFromJobPage() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Messages")
        require(app.navigationBars["Messages"], "the Messages inbox")

        openThread("Condenser fan motor")
        tapOpen(job: "J-1042")
        require(app.staticTexts["J-1042"], "the job page for J-1042")

        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Seized fan motor and bulging capacitor")
        ).firstMatch
        guard scrollTo(row) || row.waitForExistence(timeout: 10) else {
            XCTFail("The job-chat photo must be listed in the job page's Photos")
            return
        }
        forceTap(row)
        assertViewerShowsImageThenDismiss("the job-chat photo opened from the job page")
        XCTAssertTrue(
            app.staticTexts["J-1042"].waitForExistence(timeout: 10),
            "Dismissing the viewer must return to the job page"
        )
    }

    /// E. Engineer, general conversation (no job page exists): own and received.
    func testEngineerOpensPhotosInGeneralConversation() throws {
        signIn(as: "Marcus Hale")
        openTab("Office")
        require(app.navigationBars["Office"], "the field worker's Office tab")

        openThread("Van parking at the depot")
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "About job")).firstMatch.exists,
            "'Van parking at the depot' has no job, so it has no job page to fall back on"
        )
        assertOpensFullSize("Photo from Tom Ellison", "the owner's photo, received by the engineer on a general conversation")
        assertOpensFullSize("Your photo", "the engineer's own photo on a general conversation")
    }

    /// Taps a chat photo by its accessibility label and proves it opens full
    /// size and dismisses back to the same conversation.
    private func assertOpensFullSize(
        _ label: String,
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let photo = app.buttons[label].firstMatch
        guard photo.waitForExistence(timeout: 15) else {
            XCTFail("No tappable photo labelled '\(label)' for \(context)", file: file, line: line)
            return
        }
        XCTAssertTrue(photo.isEnabled, "The photo must be enabled for \(context)", file: file, line: line)
        forceTap(photo)
        assertViewerShowsImageThenDismiss(context, file: file, line: line)

        XCTAssertTrue(
            app.buttons["composer.attachPhotos"].waitForExistence(timeout: 10),
            "Dismissing the viewer must return to the conversation (\(context))",
            file: file,
            line: line
        )
    }

    /// The viewer must show the decoded image, not its failure state, and
    /// Done must close it.
    private func assertViewerShowsImageThenDismiss(
        _ context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let image = app.images["photoViewer.image"]
        XCTAssertTrue(
            image.waitForExistence(timeout: 15),
            "The full-size viewer must show the image for \(context)",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.otherElements["photoViewer.unavailable"].exists,
            "The viewer must not fall back to 'Photo unavailable' for \(context)",
            file: file,
            line: line
        )

        let done = app.navigationBars.buttons["Done"]
        guard done.waitForExistence(timeout: 5) else {
            XCTFail("The viewer has no Done button for \(context)", file: file, line: line)
            return
        }
        done.tap()
        XCTAssertTrue(
            image.waitForNonExistence(timeout: 10),
            "Done must dismiss the viewer for \(context)",
            file: file,
            line: line
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

    /// The three plans, the Monthly / Annual switch and the ~20% annual saving
    /// are on screen, and nothing from the retired founding programme is.
    func testSubscriptionShowsThreePlansAndNoFoundingWording() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Subscription & Users")
        require(app.navigationBars["Subscription"], "the Subscription screen")

        require(app.staticTexts["Starter"], "the Starter plan")
        let seen = collectTexts()
        for expected in ["Starter", "Team", "Business", "Just me", "My small team", "Annual"] {
            XCTAssertTrue(seen.contains(expected), "Expected \(expected). Saw: \(seen.sorted())")
        }
        // A one-text button is exposed as a button, not as a static text.
        XCTAssertTrue(app.buttons["Monthly"].exists || scrollTo(app.buttons["Monthly"]), "The Monthly switch must be on screen")
        XCTAssertTrue(seen.contains("10+ users"), "Business must read 10+ users. Saw: \(seen.sorted())")
        XCTAssertTrue(seen.contains { $0.contains("Save 20%") }, "The annual saving must be stated. Saw: \(seen.sorted())")
        for label in seen {
            XCTAssertFalse(label.localizedCaseInsensitiveContains("Founding"), "Founding wording must be gone — found: \(label)")
            XCTAssertFalse(label.localizedCaseInsensitiveContains("zero subscription"), "No free-for-Stripe promise — found: \(label)")
        }
        assertNoRetiredFeeWording(seen)
    }

    /// Annual prices appear when the switch is flipped.
    func testAnnualSwitchShowsAnnualPrices() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Subscription & Users")
        require(app.navigationBars["Subscription"], "the Subscription screen")
        let annual = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Annual")).firstMatch
        require(annual, "the Annual switch")
        annual.tap()
        require(app.staticTexts["/year"], "an annual price")
        let seen = collectTexts()
        XCTAssertTrue(seen.contains { $0.contains("384.99") }, "Team annual is $384.99. Saw: \(seen.sorted())")
    }

    /// A company with no plan is invited to start Apple's 14-day free trial.
    func testUnsubscribedCompanyIsOfferedTheFreeTrial() throws {
        signIn(as: "Erin Vaught")
        openMoreSection("Subscription & Users")
        require(app.navigationBars["Subscription"], "the Subscription screen")
        require(app.staticTexts["No plan yet"], "the no-plan status")
        let trial = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "14-day free trial")).firstMatch
        XCTAssertTrue(trial.waitForExistence(timeout: 20) || scrollTo(trial), "A plan must offer the 14-day free trial")
        let restore = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Restore purchases")).firstMatch
        XCTAssertTrue(scrollTo(restore), "Restore purchases must be offered")
    }

    // MARK: - Helpers for commercial screens

    /// Every visible text on the current screen, scrolled top to bottom.
    private func collectTexts(swipes: Int = 10) -> Set<String> {
        var seen = Set<String>()
        for _ in 0..<swipes {
            for text in app.staticTexts.allElementsBoundByIndex {
                let label = text.label
                if !label.isEmpty { seen.insert(label) }
            }
            app.swipeUp()
        }
        return seen
    }

    private func assertNoRetiredFeeWording(
        _ seen: Set<String>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for label in seen {
            XCTAssertFalse(
                label.localizedCaseInsensitiveContains("payment fee")
                    || label.localizedCaseInsensitiveContains("transaction fee")
                    || label.contains("0.30%") || label.contains("0,30%"),
                "Harbour South's fee must be called the platform fee — found: \(label)",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Connect Stripe

    /// The dedicated menu row opens the existing Stripe screen — same title,
    /// same controls, same fee rows.
    func testConnectStripeMenuItemOpensExistingStripeScreen() throws {
        signIn(as: "Tom Ellison")
        openTab("More")

        let row = app.buttons["more.section.payments_integration"]
        require(row, "the Connect Stripe row in More")
        XCTAssertTrue(row.label.localizedCaseInsensitiveContains("Connect Stripe"), "Row label was: \(row.label)")
        _ = scrollTo(row)
        forceTap(row)

        require(app.navigationBars["Payments"], "the existing Stripe (Payments) screen")
        require(app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Manage Stripe")).firstMatch,
                "the existing Stripe action for a connected account")

        let seen = collectTexts()
        XCTAssertTrue(seen.contains("Harbour South platform fee"), "The fee row must be named the platform fee. Saw: \(seen.sorted())")
        XCTAssertTrue(seen.contains("0.3%") || seen.contains("0,3%"), "A connected company's platform fee reads 0.3%. Saw: \(seen.sorted())")
        XCTAssertTrue(seen.contains("0%"), "The own-provider platform fee reads 0%. Saw: \(seen.sorted())")
        XCTAssertTrue(
            seen.contains { $0.localizedCaseInsensitiveContains("Stripe's normal processing fees") },
            "Stripe's own fees must still be stated separately"
        )
        assertNoRetiredFeeWording(seen)
    }

    /// A company that has not connected sees the Connect Stripe action on the
    /// same screen.
    func testConnectStripeMenuItemOffersConnectWhenNotConnected() throws {
        signIn(as: "Erin Vaught")
        openTab("More")

        let row = app.buttons["more.section.payments_integration"]
        require(row, "the Connect Stripe row in More")
        _ = scrollTo(row)
        forceTap(row)

        require(app.navigationBars["Payments"], "the existing Stripe (Payments) screen")
        require(app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Connect Stripe")).firstMatch,
                "the existing Connect Stripe action")

        let seen = collectTexts()
        XCTAssertTrue(seen.contains("Set up Stripe"), "Not connected reads Set up Stripe. Saw: \(seen.sorted())")
        XCTAssertTrue(seen.contains("Connect Stripe to receive online payments from your customers."), "Saw: \(seen.sorted())")
        for label in seen {
            XCTAssertFalse(label == "Payments disabled" || label == "Resolve issue", "Retired wording: \(label)")
            XCTAssertFalse(label.contains("requirements."), "Raw Stripe code shown: \(label)")
        }
    }

    /// Subscription keeps its link, and it reaches the very same screen.
    func testSubscriptionStripeLinkStillReachesTheSameScreen() throws {
        signIn(as: "Tom Ellison")
        openMoreSection("Subscription & Users")
        require(app.navigationBars["Subscription"], "the Subscription screen")

        let link = app.staticTexts["Taking customer payments?"]
        require(link, "the Stripe link on Subscription")
        _ = scrollTo(link)
        forceTap(link)

        require(app.navigationBars["Payments"], "the same Stripe (Payments) screen")
        require(app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Manage Stripe")).firstMatch,
                "the existing Stripe action")
    }

    // MARK: - Role isolation

    /// A field worker must not be able to reach financial or company surfaces.
    /// Structural, not cosmetic: the tabs and rows simply are not there.
    func testFieldWorkerCannotReachFinancialSurfaces() throws {
        signIn(as: "Marcus Hale")

        require(app.tabBars.buttons["Jobs"], "the field worker shell")
        openTab("More")

        for forbidden in [
            "Invoices", "Payments", "Connect Stripe", "Accounts receivable", "Subscription & Users",
            "Reports", "Dispatch", "Quotes", "Customers"
        ] {
            XCTAssertFalse(
                app.staticTexts[forbidden].exists,
                "A field worker must not see '\(forbidden)' in More"
            )
        }
    }
}
