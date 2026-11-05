import XCTest

/// The ledger list's leading swipe and the detail's `⋯` menu.
///
/// The active row is asserted separately because its action is a status chip, not a
/// button — see `LedgersVC.leadingSwipeActions` for why "disabled" cannot be literal.
final class LedgerActionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Swiping an INACTIVE ledger right reveals Make active.
    func testTheLeadingSwipeOffersMakeActive() throws {
        try openLedgers()
        let row = try XCTUnwrap(ledgerRow("Business"), "no Business ledger to swipe")
        row.swipeRight()
        XCTAssertTrue(app.buttons["Make active"].firstMatch.waitForExistence(timeout: 5),
                      "leading swipe offered no Make active action")
    }

    /// The ACTIVE ledger never offers activation — only the status chip.
    func testTheActiveLedgerOffersNoActivation() throws {
        try openLedgers()
        let row = try XCTUnwrap(ledgerRow("Personal"), "no Personal ledger")
        row.swipeRight()
        XCTAssertFalse(app.buttons["Make active"].firstMatch.waitForExistence(timeout: 2),
                       "the active ledger offered Make active")
    }

    /// The detail's three actions are in the menu, and the row that showed the WRONG
    /// ledger's transactions is gone.
    func testTheDetailActionsAreInTheMenu() throws {
        try openLedgers()
        try XCTUnwrap(ledgerRow("Personal")).tap()
        XCTAssertTrue(app.staticTexts["Base currency"].waitForExistence(timeout: 10),
                      "ledger detail did not load")
        XCTAssertFalse(app.staticTexts["View all activity"].exists,
                       "View all activity is still on the UIKit detail screen")

        // The detail's own ⋯: the list's (Reorder) can still be in the hierarchy
        // while the detail pushes in, and "More" alone matches it first.
        let more = app.buttons["ledgerDetail.more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no ⋯ item on ledger detail")
        more.tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5),
                      "the menu has no Edit")
        XCTAssertTrue(app.buttons["Make active ledger"].exists)
        XCTAssertTrue(app.buttons["Delete"].exists)
    }

    /// A base change to a currency with no rate is refused — and the refusal offers
    /// the way out, as the transaction sheets do: enter that rate, then save again.
    func testABaseChangeRefusedForWantOfARateOffersToEnterIt() throws {
        try openLedgers()
        try XCTUnwrap(ledgerRow("Business")).tap()
        XCTAssertTrue(app.staticTexts["Base currency"].waitForExistence(timeout: 10),
                      "ledger detail did not load")
        app.buttons["ledgerDetail.more"].firstMatch.tap()
        let edit = app.buttons["Edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "the menu has no Edit")
        edit.tap()

        // KRW: a currency the demo data has no rate for.
        let base = app.buttons["editLedger.base"].firstMatch
        XCTAssertTrue(base.waitForExistence(timeout: 10), "Edit Ledger has no base currency row")
        base.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the currency picker has no search field")
        search.tap()
        search.typeText("KRW")
        let krw = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'KRW'")).firstMatch
        XCTAssertTrue(krw.waitForExistence(timeout: 10), "KRW is not in the currency picker")
        krw.tap()

        app.buttons["Save"].firstMatch.tap()
        let fix = app.buttons["Enter a KRW rate"].firstMatch
        XCTAssertTrue(fix.waitForExistence(timeout: 10), "the refused base change offers no way to enter the rate")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "base-change-refused"
        shot.lifetime = .keepAlways
        add(shot)

        fix.tap()
        let field = app.textFields["manualRate.rate"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "Enter a KRW rate did not open the rate sheet")
        field.tap()
        field.typeText("0.00073")
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(fix.waitForNonExistence(timeout: 10), "the offer outlived the rate it asked for")

        // With the rate in, the same change now goes through.
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(base.waitForNonExistence(timeout: 30), "the base change still did not save")
    }

    // MARK: Reaching the list

    /// The ledger flow is the top-left corner control, not a tab.
    private func openLedgers() throws {
        let corner = app.buttons["Ledger"].firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 15), "no ledger corner control")
        corner.tap()
        XCTAssertTrue(app.cells.staticTexts["Personal"].firstMatch.waitForExistence(timeout: 15),
                      "the ledger list did not appear")
    }

    private func ledgerRow(_ name: String) -> XCUIElement? {
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        return row.waitForExistence(timeout: 10) ? row : nil
    }
}
