import XCTest

/// The add-transaction FAB must survive a tab root being converted to UIKit.
///
/// **Why this is a test and not a checklist line.** The chrome — the FAB and the
/// focused-tx sheet — comes from a SwiftUI `ViewModifier` applied to *hosted* tab
/// roots. A native `UINavigationController` root gets none of it, and nothing fails
/// loudly when that happens: the button is simply absent. It already happened once in
/// Phase 2, when `navigationTab` bypassed `TabRootHost` and every converted tab lost
/// its chrome at once, and it was found by eye rather than by anything red.
///
/// `TabChromeVC` is the fix. This is what stops it regressing as the remaining tab
/// roots convert — each one is an opportunity to forget the wrapper.
///
/// **The three tests are load-bearing as a set.** Budgets is the native root, so it is
/// the one under test. Accounts is a HOSTED root, so a build where the chrome broke
/// everywhere could not pass by accident. Settings must have NO FAB, so a button
/// rendered unconditionally cannot satisfy the other two. Drop any one of them and the
/// remaining assertions can go green on a broken build.
final class TabChromeUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // `-uikitActivity YES` is what routes Budgets to its native root. It is the
        // default now, so this is belt-and-braces rather than load-bearing — but it is
        // kept explicit so the test still says which implementation it is asserting,
        // and still targets it if the default ever moves again.
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES", "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Budgets is the first tab whose root is a native `UINavigationController` with a
    /// native list inside it — `BudgetsListVC`, no SwiftUI root view at all.
    func testFABIsPresentOnTheNativeBudgetsTab() throws {
        // The tab bar is the reliable way in. `idb`'s coordinate taps could not hit it
        // — the accessibility tree does not expose tab-bar items to that tool — which
        // is precisely why this check belongs in XCUITest.
        let tab = app.tabBars.buttons["Budgets"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Budgets tab")
        tab.tap()

        // Confirm we are on the converted screen before asserting anything about it, so
        // a navigation failure cannot masquerade as a missing FAB. The ⋯ overflow is
        // built by `BudgetsListVC.configureToolbar` and exists on no hosted root, so it
        // also proves the NATIVE list is what rendered.
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 15),
                      "Budgets tab did not open")
        XCTAssertTrue(app.buttons["More"].waitForExistence(timeout: 15),
                      "no ⋯ overflow — this is not the native BudgetsListVC")

        let fab = app.buttons["Add Transaction"]
        XCTAssertTrue(fab.waitForExistence(timeout: 15),
                      "no add-transaction FAB — the native root is missing its TabChromeVC wrapper")

        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "budgets-native-root"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A hosted tab root must keep its FAB too — otherwise this suite would pass on a
    /// build where the chrome broke everywhere except the one tab it checks.
    func testFABIsPresentOnAHostedTab() throws {
        let tab = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Accounts tab")
        tab.tap()
        XCTAssertTrue(app.buttons["Add Transaction"].waitForExistence(timeout: 15),
                      "no add-transaction FAB on the hosted Accounts tab")
    }

    /// Settings deliberately has none — asserting its ABSENCE keeps the two tests above
    /// honest, since a FAB rendered unconditionally would satisfy both.
    func testSettingsHasNoFAB() throws {
        let tab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Settings tab")
        tab.tap()
        XCTAssertTrue(app.buttons["Add Transaction"].waitForNonExistence(timeout: 10),
                      "Settings should not offer an add-transaction FAB")
    }

    /// EVERY tab keeps its Ledger corner control, converted or not.
    ///
    /// The ledger is reachable only from this button, so a tab that loses it loses the
    /// ledger entirely — silently, because a missing bar button crashes nothing and
    /// fails no test. That is what happened: `ScheduledListVC` shipped in #660 without
    /// one, and the Scheduled tab simply had no way to reach the ledger. The FAB tests
    /// above exist for the same reason and did not cover this item.
    ///
    /// Loops every slot rather than checking one, because the point is that no
    /// conversion can drop it — including conversions not written yet.
    func testEveryTabKeepsItsLedgerControl() throws {
        for tab in ["Accounts", "Budgets", "Scheduled", "Insights", "Settings"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 30), "no \(tab) tab")
            button.tap()
            XCTAssertTrue(app.buttons["Ledger"].waitForExistence(timeout: 15),
                          "\(tab) has no Ledger control — the ledger is unreachable from this tab")
        }
    }

}
