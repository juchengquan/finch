import XCTest

/// End-to-end cover for splitting from the Category subpage.
///
/// The allocation rules themselves are unit-tested in `SplitAllocationTests`; these
/// drive the WIRING — that ticking reaches the allocation, that the allocation reaches
/// the ledger, and that cancelling keeps it out of the ledger.
///
/// The sheets' own toolbar buttons are labelled Cancel/Save while the picker's are
/// Cancel/Confirm, so "Confirm" addresses the subpage unambiguously even though it is
/// presented on top of a sheet that also has a confirmation button.
final class CategorySplitUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        if let app, testRun?.hasSucceeded == false {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "failure"
            shot.lifetime = .keepAlways
            add(shot)
        }
        app?.terminate(); app = nil
    }

    // MARK: - Driving

    /// The floating add button, the same entry point `TabChromeUITests` uses.
    private func openAddSheet() {
        let fab = app.buttons["Add Transaction"]
        XCTAssertTrue(fab.waitForExistence(timeout: 30), "no add-transaction button")
        fab.tap()
    }

    private func enterAmount(_ text: String) {
        let field = app.textFields["addtx.amount"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "no amount field")
        field.tap()
        field.typeText(text)
    }

    private func openCategorySubpage(_ identifier: String = "addtx.category") {
        let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "no category row (\(identifier))")
        row.tap()
        // Assert the subpage actually came up. Without this the next step fails deep
        // inside a toggle query with "no matches for Switch", which says nothing about
        // the tap that did not land.
        XCTAssertTrue(splitToggle.waitForExistence(timeout: 15),
                      "tapping \(identifier) did not open the category subpage")
    }

    private var splitToggle: XCUIElement { app.switches["category.splitToggle"] }
    private var allocated: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "category.allocated").firstMatch
    }

    private func turnSplit(on: Bool) {
        XCTAssertTrue(splitToggle.waitForExistence(timeout: 15), "no split toggle")
        // Tap the TRAILING EDGE, not the element's centre. The accessibility element
        // spans the whole row, so a centre tap — and a held press — lands on the label
        // and silently does nothing; measured, `value` just stays at "0". The switch
        // itself sits at the trailing edge. The assertion below is what caught this;
        // without it the rest of the test would have run against single-select and
        // passed while proving nothing.
        splitToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(splitToggle.value as? String, on ? "1" : "0",
                       "the split toggle did not move to \(on ? "on" : "off")")
    }

    /// Ticks a category by name. Queried fresh each time: ticking the first one inserts
    /// the amounts section, which shifts every tree row down the screen.
    private func tickCategory(_ name: String) {
        let row = app.staticTexts[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no category named \(name)")
        row.tap()
    }

    private func confirmSubpage() {
        let confirm = app.buttons["Confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no Confirm in the subpage")
        confirm.tap()
    }

    /// Opens a real transaction for editing.
    ///
    /// Deliberately NOT `app.cells.firstMatch`: the Activity list's first cell is the
    /// List/Calendar mode picker, so that tapped the picker and never opened a sheet.
    /// Tapping the row's own text forwards to the cell and is unambiguous.
    private func openFirstGroceriesTransaction() {
        if app.buttons["All Transactions"].firstMatch.exists {
            app.buttons["All Transactions"].firstMatch.tap()
        }
        let row = app.staticTexts["Groceries"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "no Groceries transaction in the list")
        // Existing is not enough: reopening straight after a dismiss finds the row
        // still covered by the sheet sliding away, and the tap is rejected as not
        // hittable. Wait for it to actually be reachable.
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: row)],
             timeout: 30)

        // Tap, and tap AGAIN if the sheet did not come up.
        //
        // `isHittable` turning true is not the same as the tap landing: a sheet
        // that is still animating away keeps swallowing touches for a moment
        // after the row beneath it reports itself reachable. A longer timeout
        // cannot rescue that — the first tap never arrived, so nothing is coming.
        //
        // Measured, rather than guessed. On CI this failed after 107s having
        // already spent 49s reaching the Cancel tap; the re-run passed at 96s,
        // and locally the whole test is 33-40s. So the runner is ~3x slower AND
        // the tap is racy: the retry covers the swallowed tap, the longer waits
        // cover the slowness. A genuine regression still fails — just twice.
        let sheet = app.descendants(matching: .any).matching(identifier: "edittx.category").firstMatch
        row.tap()
        if !sheet.waitForExistence(timeout: 15) {
            row.tap()
            XCTAssertTrue(sheet.waitForExistence(timeout: 30),
                          "tapping the row did not open the edit sheet")
        }
    }

    private func categoryRowLabel(_ identifier: String = "addtx.category") -> String {
        let row = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "no category row (\(identifier))")
        return row.label
    }

    // MARK: - Tests

    // Two ticks divide the amount with no typing at all, and the split survives back
    // out to the form.
    func testTickingTwoCategoriesDividesTheAmountEvenly() throws {
        openAddSheet()
        enterAmount("100")
        openCategorySubpage()
        turnSplit(on: true)
        tickCategory("Groceries")
        tickCategory("Dining")

        XCTAssertTrue(allocated.waitForExistence(timeout: 10), "no allocated line")
        XCTAssertTrue(allocated.label.contains("100"),
                      "allocated reads \(allocated.label) — the split does not add up to the amount")

        confirmSubpage()

        let label = categoryRowLabel()
        XCTAssertTrue(label.contains("Groceries") && label.contains("Dining"),
                      "the category row does not name both splits: \(label)")
    }

    // Toggling split off keeps the largest leg — the same category the row was already
    // displaying, per Projection.swift's dominant-leg rule.
    //
    // 100 across three rows is 33.33 / 33.33 / 33.34: the LAST row takes the remainder
    // and is therefore the largest, with nothing typed. That keeps the assertion
    // deterministic without depending on the seed's amounts.
    func testTogglingSplitOffKeepsTheLargestCategory() throws {
        openAddSheet()
        enterAmount("100")
        openCategorySubpage()
        turnSplit(on: true)
        tickCategory("Groceries")
        tickCategory("Dining")
        tickCategory("Transport")

        turnSplit(on: false)
        confirmSubpage()

        let label = categoryRowLabel()
        XCTAssertTrue(label.contains("Transport"),
                      "collapse did not keep the largest leg — the row reads \(label)")
        XCTAssertFalse(label.contains("Groceries"),
                       "collapse left more than one category — the row reads \(label)")
    }

    // A transaction can legitimately have NO category, and the picker now offers it
    // in both modes. The write is the part that can lie: the edit sheet used to skip
    // the category patch whenever the id was empty, so choosing Uncategorized would
    // dismiss cleanly, save, and change nothing at all. The engine reads an explicit
    // null as "clear it"; omitting the key leaves the old leg in place.
    func testClearingACategoryActuallyClearsIt() throws {
        openFirstGroceriesTransaction()
        XCTAssertTrue(categoryRowLabel("edittx.category").contains("Groceries"),
                      "expected to start from a categorised transaction")

        openCategorySubpage("edittx.category")
        tickCategory("Uncategorized")
        confirmSubpage()
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "edittx.category")
                        .firstMatch.waitForNonExistence(timeout: 15),
                      "the edit sheet did not dismiss after saving")

        // Reopen the SAME row and read it back from the store, not from the sheet we
        // just closed — that is what makes this a write test rather than a UI one.
        let row = app.staticTexts["Uncategorized"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20),
                      "no uncategorised transaction in the list — the category was not cleared")
        wait(for: [expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: row)],
             timeout: 15)
        row.tap()
        // Asserts the category is GONE, not that the row reads "Uncategorized": an
        // empty field shows its own name as a placeholder, and it has to, because a
        // deliberately-uncategorised transaction and a never-categorised one are the
        // same nil category leg — the UI has nothing to tell them apart with.
        XCTAssertFalse(categoryRowLabel("edittx.category").contains("Groceries"),
                       "reopening still shows the old category — clearing it did not stick")
    }

    // Splits used to be written the moment the split editor was confirmed, so
    // cancelling the Edit sheet reverted your notes and date but silently KEPT your
    // splits. Staging them makes Cancel mean cancel.
    func testCancellingTheEditSheetDiscardsSplitChanges() throws {
        openFirstGroceriesTransaction()
        let before = categoryRowLabel("edittx.category")

        openCategorySubpage("edittx.category")
        // Turning the toggle on SEEDS from the category already chosen, so this
        // transaction's own category is ticked and holds the whole amount. Ticking it
        // again here would untick it — one more tick is all that is needed for a split.
        turnSplit(on: true)
        tickCategory("Dining")
        confirmSubpage()

        // Cancel the EDIT sheet — the split must never reach the ledger.
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "edittx.category")
                        .firstMatch.waitForNonExistence(timeout: 15),
                      "the edit sheet did not dismiss")

        // Reopen and assert the category is exactly what it was.
        openFirstGroceriesTransaction()
        XCTAssertEqual(categoryRowLabel("edittx.category"), before,
                       "cancelling the edit sheet still applied the split")
    }
}
