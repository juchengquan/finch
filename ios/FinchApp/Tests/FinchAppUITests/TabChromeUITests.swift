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
final class TabChromeUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // `-uikitActivity YES` is what routes the converted tabs to their native
        // roots; without it this would test the hosted path and pass for free.
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES", "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Scheduled is the first tab whose root is a native `UINavigationController`.
    func testFABIsPresentOnTheNativeScheduledTab() throws {
        // The tab bar is the reliable way in. `idb`'s coordinate taps could not hit it
        // — the accessibility tree does not expose tab-bar items to that tool — which
        // is precisely why this check belongs in XCUITest.
        let tab = app.tabBars.buttons["Scheduled"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Scheduled tab")
        tab.tap()

        // Confirm we are on the converted screen before asserting anything about it,
        // so a navigation failure cannot masquerade as a missing FAB.
        XCTAssertTrue(app.staticTexts["Scheduled"].waitForExistence(timeout: 15),
                      "Scheduled tab did not open")

        let fab = app.buttons["Add Transaction"]
        XCTAssertTrue(fab.waitForExistence(timeout: 15),
                      "no add-transaction FAB — the native root is missing its TabChromeVC wrapper")

        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "scheduled-native-root"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// A hosted tab root must keep its FAB too — otherwise this suite would pass on a
    /// build where the chrome broke everywhere except the one tab it checks.
    func testFABIsPresentOnAHostedTab() throws {
        let tab = app.tabBars.buttons["Budgets"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Budgets tab")
        tab.tap()
        XCTAssertTrue(app.buttons["Add Transaction"].waitForExistence(timeout: 15),
                      "no add-transaction FAB on the hosted Budgets tab")
    }

    /// Settings deliberately has none — asserting its ABSENCE keeps the two tests
    /// above honest, since a FAB rendered unconditionally would satisfy both.
    func testSettingsHasNoFAB() throws {
        let tab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "no Settings tab")
        tab.tap()
        XCTAssertTrue(app.buttons["Add Transaction"].waitForNonExistence(timeout: 10),
                      "Settings should not offer an add-transaction FAB")
    }
}
