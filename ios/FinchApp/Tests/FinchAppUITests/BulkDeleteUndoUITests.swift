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

        let rent = row("Expense, Rent")
        XCTAssertTrue(rent.waitForExistence(timeout: 30), "the seed's Rent row is missing")

        app.buttons["Select"].firstMatch.tap()
        rent.tap()

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
        XCTAssertTrue(row("Expense, Rent").exists, "the row went before it was confirmed")
        confirm?.tap()

        let undo = app.buttons["undoDelete"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "no Undo banner after the delete")
        XCTAssertTrue(waitUntil(5) { !self.row("Expense, Rent").exists }, "the row was not deleted")
        XCTAssertTrue(waitUntil(5) { self.app.tabBars.firstMatch.isHittable },
                      "the tab bar did not come back when selection ended")

        undo.tap()
        XCTAssertTrue(row("Expense, Rent").waitForExistence(timeout: 5), "Undo did not bring the row back")
        XCTAssertTrue(waitUntil(5) { !undo.exists }, "the banner outlived its undo")
    }

    private func row(_ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
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
