import XCTest

/// The ledger must be the SAME component as every other drill on a native tab — a
/// real `UINavigationController` push, not an imitation of one.
///
/// It used to be presented by `RightSlideModal`, a hand-rolled `.fullScreen`
/// transition. Two things went wrong with that, and only the first was obvious:
///
///  - Dismissing revealed a black hole. `.fullScreen` makes UIKit remove the
///    presenting view, and the dismiss animator never put it back. Covered by
///    `RightSlideModalTests`.
///  - Even fixed, it read WRONG next to its neighbours, because the drills on the
///    same tab are real pushes — Apple's curve, the leading-edge shadow, the dimming,
///    the interactive swipe-back. Hand-matching all of that is a losing game.
///
/// **The assertion is the tab bar.** A push keeps it; a `.fullScreen` presentation
/// covers it. That single observable says "this is a push" without depending on
/// animation timing, which no UI test can see.
///
/// Runs with `-uikitActivity YES`: the push needs a tab whose root is a
/// `UINavigationController`. With the flag off every tab is a hosted SwiftUI root
/// with no stack, and the modal is still the correct fallback — as it is for Insights.
final class LedgerNavigationUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testLedgerIsPushedOntoTheTabStack() throws {
        let ledgerButton = app.buttons["Ledger"]
        XCTAssertTrue(ledgerButton.waitForExistence(timeout: 30), "no Ledger corner control")

        // The tab bar before, so its presence after means something.
        XCTAssertTrue(app.tabBars.firstMatch.exists, "no tab bar on the tab root")
        ledgerButton.tap()

        XCTAssertTrue(app.staticTexts["Ledgers"].waitForExistence(timeout: 15),
                      "the ledger never opened")
        XCTAssertTrue(app.tabBars.firstMatch.exists,
                      "the tab bar is gone — the ledger is being PRESENTED over the tab, not pushed onto it")
    }

    func testLedgerPopsBackToTheTab() throws {
        let ledgerButton = app.buttons["Ledger"]
        XCTAssertTrue(ledgerButton.waitForExistence(timeout: 30), "no Ledger corner control")
        ledgerButton.tap()
        XCTAssertTrue(app.staticTexts["Ledgers"].waitForExistence(timeout: 15), "the ledger never opened")

        // A push labels its back item with the PREVIOUS screen's title, so it can only
        // be found positionally — the same trick `NavigationUITests` uses.
        app.navigationBars.buttons.element(boundBy: 0).tap()

        XCTAssertTrue(app.staticTexts["Ledgers"].waitForNonExistence(timeout: 15),
                      "the ledger did not close")
        // And the corner control still works afterwards: the shell must have cleared
        // `router.showLedger` on the pop, or a second tap does nothing at all.
        XCTAssertTrue(ledgerButton.waitForExistence(timeout: 15), "back on a tab, but no Ledger control")
        ledgerButton.tap()
        XCTAssertTrue(app.staticTexts["Ledgers"].waitForExistence(timeout: 15),
                      "the ledger would not reopen — the pop did not clear showLedger")
    }
}
