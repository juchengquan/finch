import XCTest

/// The reconcile MODE's contract (2026-08-10 design): entering flips the account
/// screen in place; ticks stage with zero writes; Finish MATERIALIZES only at a
/// zero difference and seals in one batch; Cancel leaves the books untouched.
final class ReconcileModeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Happy path: enter → all rows start unticked (Finish absent on an
    /// unbalanced account) → tick everything → Finish appears → seal exits the
    /// mode and the normal chrome returns.
    func testTickAllThenFinishSeals() throws {
        enterReconcileOnCash()

        XCTAssertFalse(app.buttons["reconcile.finish"].exists,
                       "rows start UNTICKED, so an unbalanced account cannot offer Finish on entry")

        tickAllRows()
        let finish = app.buttons["reconcile.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 8),
                      "difference reached zero and Finish did not materialize")
        finish.tap()

        XCTAssertTrue(app.textFields["reconcile.statementBalance"].waitForNonExistence(timeout: 10),
                      "Finish should seal and exit the mode")
        XCTAssertTrue(app.buttons["account.more"].waitForExistence(timeout: 8),
                      "the normal chrome should return after sealing")
    }

    /// Cancel is honest: stage ticks, bail with ✕, re-enter — the staged work is
    /// gone and nothing was written (the account is exactly as unbalanced as
    /// before, so Finish is again absent).
    func testCancelDiscardsStagedTicks() throws {
        enterReconcileOnCash()
        tickAllRows()
        XCTAssertTrue(app.buttons["reconcile.finish"].waitForExistence(timeout: 8))

        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["account.more"].waitForExistence(timeout: 8),
                      "✕ should exit the mode")

        enterReconcile()
        XCTAssertTrue(app.textFields["reconcile.statementBalance"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["reconcile.finish"].exists,
                       "cancelled ticks must not survive — zero writes means the difference is back")
    }

    // MARK: Reaching the mode

    private func enterReconcileOnCash() {
        let accounts = app.buttons["Accounts"]
        if accounts.waitForExistence(timeout: 10) { accounts.tap() }
        let cash = app.staticTexts["Cash"].firstMatch
        XCTAssertTrue(cash.waitForExistence(timeout: 15), "no Cash account in the demo seed")
        cash.tap()
        enterReconcile()
    }

    private func enterReconcile() {
        let more = app.buttons["account.more"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 10), "account detail's ••• not found")
        more.tap()
        let reconcile = app.buttons["Reconcile"].firstMatch
        XCTAssertTrue(reconcile.waitForExistence(timeout: 5), "no Reconcile action in the menu")
        reconcile.tap()
        XCTAssertTrue(app.textFields["reconcile.statementBalance"].waitForExistence(timeout: 8),
                      "the reconcile header did not appear")
    }

    private func tickAllRows() {
        // The converted rows expose as combined BUTTONS, not Cells (the a11y tree
        // at failure showed 2 Cell elements total — a first draft tapped air).
        // Rows are the $-labelled buttons; "Add missing −$…" is excluded by prefix.
        let rows = app.buttons.matching(
            NSPredicate(format: "label CONTAINS '$' AND NOT (label BEGINSWITH 'Add missing')"))
        let count = rows.count
        XCTAssertGreaterThan(count, 0, "no transaction rows found to tick")
        for index in 0..<count {
            rows.element(boundBy: index).tap()
        }
    }
}
