import XCTest

/// Regular-width (iPad) selection: picking a row in the list column fills the detail
/// column. Skipped on compact width, so the suite stays valid on an iPhone destination.
///
/// **Why this exists.** `idb`'s synthetic taps do not drive SwiftUI `List(selection:)` —
/// verified against the SwiftUI shell itself, where the same tap left the placeholder
/// showing — so the simulator-driving tools used everywhere else in this project cannot
/// answer whether selection works. XCUITest sends real touches and can.
///
/// That matters beyond tidiness: Phase 3 is replacing the iPad shell with a
/// `UISplitViewController`, and "does picking a row still fill the detail column" is the
/// single behaviour most likely to break in a way nobody notices until they use an iPad.
/// This is written against the SwiftUI shell so it captures the behaviour BEFORE the
/// swap, which is the only way it can prove the swap preserved it.
final class SplitSelectionUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")

        // Regular width only. An iPhone destination has no detail column to fill, and
        // asserting one exists there would fail for the wrong reason.
        let width = app.windows.firstMatch.frame.width
        try XCTSkipUnless(width >= 700, "regular width only — got \(width)pt")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// A row in the list column, found by label across ANY element type.
    ///
    /// Deliberately not `.buttons` or `.cells`. In compact mode the rows are
    /// `NavigationLink`s and surface as buttons; in `List(selection:)` mode they are
    /// neither — a query for either type finds nothing, which is how the first version
    /// of this test failed while the app was working perfectly. Phase 3b will change
    /// the type again when the list column becomes a `UICollectionView`. The label is
    /// the stable thing across all three, so match on that.
    private func row(labelled prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix))
            .firstMatch
    }

    /// The whole contract in one test: the placeholder is up, a row is tapped, the
    /// detail column shows that account instead.
    func testSelectingAnAccountFillsTheDetailColumn() throws {
        // `DetailPlaceholder` — "Select an account" — is the empty state of the detail
        // column, so its presence proves the column exists and nothing is selected yet.
        let placeholder = app.staticTexts["Select an account"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 30),
                      "no detail placeholder — this doesn't look like the split shell")

        let cell = row(labelled: "Checking")
        XCTAssertTrue(cell.waitForExistence(timeout: 30), "no 'Checking' row in the list column")
        cell.tap()

        XCTAssertTrue(placeholder.waitForNonExistence(timeout: 15),
                      "placeholder still showing — the selection never reached the detail column")
        // And the column actually rendered the account, rather than merely going blank.
        XCTAssertTrue(app.staticTexts["Transactions"].waitForExistence(timeout: 15),
                      "detail column has no Transactions section — it cleared but didn't render the account")

        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "iPad-account-selected"
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// Switching section in the sidebar must not carry a stale detail across: Budgets
    /// should come up on its own placeholder, not the previously selected account.
    func testSwitchingSectionResetsTheDetailColumn() throws {
        let cell = row(labelled: "Checking")
        XCTAssertTrue(cell.waitForExistence(timeout: 30), "no 'Checking' row in the list column")
        cell.tap()
        XCTAssertTrue(app.staticTexts["Select an account"].waitForNonExistence(timeout: 15),
                      "selection never reached the detail column")

        // The sidebar may be an overlay in portrait; reveal it before reaching for a row.
        if !row(labelled: "Budgets").exists {
            let toggle = app.navigationBars.buttons.element(boundBy: 0)
            if toggle.exists { toggle.tap() }
        }
        let target = row(labelled: "Budgets")
        XCTAssertTrue(target.waitForExistence(timeout: 15), "no Budgets entry in the sidebar")
        target.tap()

        XCTAssertTrue(app.staticTexts["Select a budget"].waitForExistence(timeout: 15),
                      "Budgets didn't come up on its own placeholder — a stale detail carried across")
    }
}
