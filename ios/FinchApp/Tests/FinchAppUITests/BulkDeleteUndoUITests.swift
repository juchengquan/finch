import XCTest

/// The iPhone feed's multi-select, end to end: the bulk actions are reachable, Delete
/// asks first, and the Undo banner puts the row back.
///
/// The first assertion is the regression this exists for. iOS 26's floating tab bar is
/// drawn OVER the navigation toolbar, so "Confirm N / Recategorize N / Delete N" sat
/// underneath it — and a tap on Recategorize landed on the Scheduled tab. Selecting now
/// hides the tab bar; `isHittable` is the property that was false before.
final class BulkDeleteUndoUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
        try XCTSkipIf(app.windows.firstMatch.frame.width >= 700,
                      "iPhone layout only — the iPad split has no bottom tab bar")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testBulkDeleteIsReachableConfirmedAndUndoable() throws {
        let all = app.buttons["All Transactions"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 30), "no All Transactions entry on Accounts")
        all.tap()

        let target = row()
        XCTAssertTrue(target.waitForExistence(timeout: 30), "the seed's Target groceries row is missing")

        app.buttons["Select"].firstMatch.tap()
        target.tap()

        let delete = app.buttons["Delete 1"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "no bulk Delete after ticking a row")
        XCTAssertTrue(waitUntil(5) { !self.app.tabBars.firstMatch.isHittable },
                      "the tab bar is still up while selecting — it covers the bulk actions")
        XCTAssertTrue(app.buttons["Recategorize 1"].firstMatch.isHittable, "Recategorize is covered")
        XCTAssertTrue(delete.isHittable, "Delete is covered")

        // Delete asks first — the confirmation carries its own "Delete 1".
        let toolbarFrame = delete.frame
        delete.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@", "Delete 1"))
            .allElementsBoundByIndex.first { $0.frame != toolbarFrame && $0.isHittable }
        XCTAssertNotNil(confirm, "no confirmation before the bulk delete")
        XCTAssertTrue(row().exists, "the row went before it was confirmed")
        confirm?.tap()

        let undo = app.buttons["undoDelete"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo banner after the delete")
        XCTAssertTrue(waitUntil(5) { !self.row().exists }, "the row was not deleted")
        XCTAssertTrue(waitUntil(5) { self.app.tabBars.firstMatch.isHittable },
                      "the tab bar did not come back when selection ended")

        undo.tap()
        XCTAssertTrue(row().waitForExistence(timeout: 5), "Undo did not bring the row back")
        XCTAssertTrue(waitUntil(5) { !undo.exists }, "the banner outlived its undo")
    }

    /// The seed's Target shop, two days back: near the top of the feed whatever the
    /// date, and the only Groceries row for $58.20, so once it is deleted no other row
    /// matches. It used to be "Expense, Rent", but rent is now posted from its
    /// scheduled template on the 1st, which late in the month is far enough down the
    /// feed that its cell is never loaded.
    private func row() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@",
                                         "Expense, Groceries", "58.20")).firstMatch
    }

    private func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.3)
        }
        return condition()
    }
}
