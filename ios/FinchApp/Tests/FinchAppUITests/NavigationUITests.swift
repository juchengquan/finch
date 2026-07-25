import XCTest

/// UI test for navigation between tabs and detail views.
///
/// Covers the iPhone push stack that `AppDestination` makes reachable: tap a
/// tab, drill into the first row, confirm the back button appears, return.
/// Also exercises the top-left `LedgerBarButton` corner push onto the
/// current tab's stack.
///
/// Launch args:
///   `-resetStore YES` — DEBUG-only flag in `FinchApp.swift init()` wipes the
///   live DB and App Group scratch before FinchStore bootstraps, so each
///   test method starts from a fresh `SimulatorDemoSeed` and the host app
///   process doesn't clobber a developer simulator's real data.
///   `-disableNotifications YES` — DEBUG-only flag that skips the notification
///   permission prompt and `NotificationService.refresh()` at launch. The demo
///   seed stamps transactions dated `store.today` so the planner fires budget
///   alerts immediately; the system banner blocks the accessibility tree and
///   breaks UI tests.
final class NavigationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES"]
        app.launch()
    }

    override func tearDown() {
        app?.terminate()
        app = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Drill into the first cell of the current screen's table, confirm a
    /// back button appeared (push succeeded), then return to the list.
    /// SwiftUI's `List` on iOS 26 (Liquid Glass) exposes to XCUITest as either
/// `.table`, `.collectionView`, or `.other` depending on the contents/styling.
/// We don't care which — we just need *some* scrollable view whose children are
/// tappable rows. `app.cells` is the XCUITest query that traverses all three.
private func listCells() -> XCUIElementQuery { app.cells }

private func assertListExists(_ label: String, timeout: TimeInterval = 15) {
    let probe = listCells()
    XCTAssertTrue(probe.firstMatch.waitForExistence(timeout: timeout), "\(label): no rows in list")
    XCTAssertGreaterThan(probe.count, 0, "\(label): expected at least one row")
}

private func assertDrillAndBack(label: String) {
    assertListExists(label)

    listCells().firstMatch.tap()

    let backButton = app.navigationBars.buttons.element(boundBy: 0)
    XCTAssertTrue(backButton.waitForExistence(timeout: 15), "\(label): no back button after push")

    let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
    screenshot.name = "\(label)-Detail-View"
    add(screenshot)

    backButton.tap()
    assertListExists("\(label): did not return to list")
}

    // MARK: - Accounts Tab Navigation

    func testAccountsTabNavigation() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let accountsTab = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(accountsTab.waitForExistence(timeout: 15), "Accounts tab should exist")
        accountsTab.tap()

        assertDrillAndBack(label: "Accounts")
    }

    // MARK: - Budgets Tab Navigation

    func testBudgetsTabNavigation() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        let budgetsTab = app.tabBars.buttons["Budgets"]
        XCTAssertTrue(budgetsTab.waitForExistence(timeout: 15), "Budgets tab should exist")
        budgetsTab.tap()

        assertDrillAndBack(label: "Budgets")
    }

    // MARK: - Ledger Push Navigation (iPhone)

    func testLedgerPushNavigation() throws {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // Land on Accounts first so the Ledger bar-button is in scope.
        let accountsTab = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(accountsTab.waitForExistence(timeout: 5), "Accounts tab should exist")
        accountsTab.tap()
        assertListExists("Accounts list should appear")

        // The Ledger corner button is labeled "Ledger" via `.accessibilityLabel`
        // on `LedgerBarButton` — see `Shell/AdaptiveShell.swift`.
        let ledgerButton = app.navigationBars.buttons["Ledger"]
        XCTAssertTrue(ledgerButton.waitForExistence(timeout: 15), "Ledger bar-button should exist on iPhone")
        ledgerButton.tap()

        assertListExists("Ledger list should appear after push")

        let screenshot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        screenshot.name = "Ledger-Push-View"
        add(screenshot)

        // Back button title tracks the source tab ("Accounts") — pop returns us there.
        let backButton = app.navigationBars.buttons["Accounts"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 15), "Back button should show 'Accounts' title")
        backButton.tap()
        assertListExists("Should return to Accounts list")
    }
}