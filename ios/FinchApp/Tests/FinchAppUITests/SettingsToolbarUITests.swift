import XCTest

/// The Settings toolbar keeps its Ledger control and its privacy toggle.
///
/// **Written BEFORE the Settings root was converted to UIKit, and passing against the
/// hosted SwiftUI screen.** That ordering is the point: it proves the test can actually
/// see these two affordances, so a green run after the conversion means they survived
/// rather than that the assertions were always vacuous.
///
/// The two tab-root conversions before this one each lost exactly these:
///
///   738cbb0c  fix(ios): the Scheduled tab lost its Ledger control when it went native
///   0898bb79  fix(ios): Scheduled lost its hide-amounts button, and ignored privacy mode
///
/// Both were found on a device after merging, not by the suite. This is the suite
/// catching it instead.
///
/// It keys on accessibility, not layout, because that is the one contract both
/// implementations already share: SwiftUI's `PrivacyToggleButton` sets label "Privacy
/// mode" + value on/off (`AdaptiveShell`), and `AccountsListVC` sets the identical pair
/// on its `UIBarButtonItem`. Same for "Ledger".
final class SettingsToolbarUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES", "-initialTab", "settings"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testSettingsKeepsItsLedgerControl() throws {
        XCTAssertTrue(app.staticTexts["Settings"].firstMatch.waitForExistence(timeout: 30),
                      "never reached Settings")
        XCTAssertTrue(app.buttons["Ledger"].firstMatch.waitForExistence(timeout: 15),
                      "Settings has no Ledger control — the corner button that opens the ledger")
    }

    func testSettingsPrivacyToggleExistsAndFlips() throws {
        let privacy = app.buttons["Privacy mode"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 30),
                      "Settings has no privacy toggle")

        // The VALUE is the assertion that matters. A button that exists but does not
        // drive `store.privacyMode` is exactly the 0898bb79 defect — present, inert.
        let before = privacy.value as? String
        XCTAssertTrue(before == "on" || before == "off",
                      "privacy toggle reports no on/off value; got \(before ?? "nil")")

        privacy.tap()

        let deadline = Date().addingTimeInterval(5)
        var after = app.buttons["Privacy mode"].firstMatch.value as? String
        while after == before && Date() < deadline {
            usleep(100_000)
            after = app.buttons["Privacy mode"].firstMatch.value as? String
        }
        XCTAssertNotEqual(after, before,
                          "privacy toggle did not change state — BEFORE \(before ?? "nil"), AFTER \(after ?? "nil")")
    }
}
