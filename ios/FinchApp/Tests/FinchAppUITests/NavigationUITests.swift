import XCTest

/// UI regression net for the compact (iPhone) navigation model.
///
/// The compact drill-ins (Activity feed, account/budget detail) and the Ledger
/// corner button are presented as top-level right-slide COVERS (see
/// `Shell/RightSlideDrill.swift`) — NOT `NavigationStack` pushes — so a scrolled
/// root view never re-converges the iOS 26 glass into a resume shadow. Every cover
/// carries a leading chevron whose accessibility label is "Back" (`rsdBackToolbar`).
/// These tests exercise: tab → open a cover → confirm the "Back" chevron → dismiss.
///
/// Launch flags (both DEBUG-only, in `FinchApp.swift init()`):
///   `-resetStore YES` — wipes the live DB + App Group scratch before FinchStore
///   bootstraps, so each run starts from a fresh `SimulatorDemoSeed` and the UI-test
///   host process never clobbers a dev simulator's real data.
///   `-disableNotifications YES` — skips the permission prompt + `NotificationService`
///   refresh at launch; the demo seed dates transactions at `store.today`, so the
///   planner would otherwise fire a budget-alert banner that blocks the a11y tree.
final class NavigationUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Helpers

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 15), "\(name) tab should exist")
        tab.tap()
    }

    /// After some action opened a right-slide cover: confirm the "Back" chevron is
    /// present (cover opened), snapshot it, tap it, and confirm it's gone (cover
    /// dismissed). The chevron is the cleanest cross-cover signal — every cover has
    /// exactly one, and it disappears when the cover tears down.
    private func assertCoverOpensThenDismisses(_ label: String) {
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 15), "\(label): no 'Back' chevron — cover didn't open")

        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "\(label)-Cover"
        shot.lifetime = .keepAlways
        add(shot)

        back.tap()
        XCTAssertTrue(back.waitForNonExistence(timeout: 10), "\(label): 'Back' chevron still present — cover didn't dismiss")
    }

    // MARK: - Accounts → All Transactions cover

    func testAccountsDrillIntoActivityCover() throws {
        selectTab("Accounts")
        // "All Transactions" is a stable, always-present entry that opens the Activity
        // feed cover (a Button with a text Label, so its a11y label is exactly this).
        let allTransactions = app.buttons["All Transactions"]
        XCTAssertTrue(allTransactions.waitForExistence(timeout: 15), "All Transactions row should exist")
        allTransactions.tap()
        assertCoverOpensThenDismisses("Accounts→Activity")
    }

    // MARK: - Budgets → budget detail cover

    func testBudgetsDrillIntoDetailCover() throws {
        selectTab("Budgets")
        // Budget rows are plain Buttons wrapping BudgetRowView, so the button's a11y
        // label carries the budget name. "Health" is a top-level (ungrouped) budget in
        // the demo seed, so it's visible without expanding a group.
        let budgetRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Health")
        ).firstMatch
        XCTAssertTrue(budgetRow.waitForExistence(timeout: 15), "a 'Health' budget row should exist")
        budgetRow.tap()
        assertCoverOpensThenDismisses("Budgets→Detail")
    }

    // MARK: - Ledger corner button → ledger cover

    func testLedgerCornerButtonOpensCover() throws {
        selectTab("Accounts")
        // The top-left corner control (`LedgerBarButton`, a11y label "Ledger"),
        // compact-only, opens the ledger list as a cover.
        let ledger = app.buttons["Ledger"]
        XCTAssertTrue(ledger.waitForExistence(timeout: 15), "Ledger corner button should exist on iPhone")
        ledger.tap()
        assertCoverOpensThenDismisses("Ledger")
    }
}
