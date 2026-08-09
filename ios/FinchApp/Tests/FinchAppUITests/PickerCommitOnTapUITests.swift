import XCTest

/// The picker sheets' one-tap contract (2026-08-09): in SINGLE-select mode a tap
/// commits the option and closes the sheet — no staging, no Confirm. The staged
/// multi-select (with Confirm and leading tick circles) exists only while
/// "Split across…" is ON.
///
/// Written RED against the old stage-then-Confirm behavior, where the first
/// assertion fails because the sheet stays open waiting for a Confirm tap.
final class PickerCommitOnTapUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-openAdd", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Single mode: tapping an account commits it and dismisses the picker in
    /// ONE tap, and the Account row shows the choice.
    func testSingleSelectCommitsOnTapAndDismisses() throws {
        openAccountPicker()

        // By identifier, not label: the Accounts screen BEHIND the sheet also
        // shows "Checking", and a label query can resolve to that (occluded,
        // not hittable) copy — it did, and cost a debugging cycle.
        app.buttons["picker.option.checking"].firstMatch.tap()

        XCTAssertTrue(app.buttons["account.splitToggle"].waitForNonExistence(timeout: 8),
                      "tapped an account and the picker stayed open — still waiting for Confirm")
        let row = app.buttons["addtx.account"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Checking"),
                      "picker dismissed but the Account row does not show the tapped choice")
    }

    /// Single mode shows NO Confirm; toggling split ON brings Confirm back and
    /// puts a tick circle on every option row.
    func testSplitModeBringsConfirmAndTickCircles() throws {
        openAccountPicker()

        XCTAssertFalse(app.buttons["Confirm"].exists,
                       "single-select mode should have no Confirm — a tap commits")

        let toggle = app.switches["account.splitToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no split toggle in the picker")
        // A plain tap on a switch can land without flipping it (same trap the
        // sim-driving notes record for idb). Tap, verify the VALUE, and retap
        // on the knob if the first one bounced.
        toggle.tap()
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        }
        XCTAssertTrue((toggle.value as? String) == "1" || app.buttons["Confirm"].waitForExistence(timeout: 3),
                      "the split toggle did not turn on")

        XCTAssertTrue(app.buttons["Confirm"].waitForExistence(timeout: 5),
                      "split mode must keep the staged Confirm flow")
        XCTAssertTrue(app.images["tick.off"].firstMatch.waitForExistence(timeout: 5),
                      "split mode should mark every row with a leading tick circle")

        app.buttons["picker.option.savings"].firstMatch.tap()
        XCTAssertTrue(app.images["tick.on"].firstMatch.waitForExistence(timeout: 5),
                      "ticking a row should fill its circle")
        // Still open: split mode stages rather than committing on tap.
        XCTAssertTrue(app.buttons["Confirm"].exists,
                      "split mode must not dismiss on a row tap")
    }

    // MARK: Reaching the Account picker (the Add sheet opens via -openAdd YES)

    private func openAccountPicker() {
        let accountRow = app.buttons["addtx.account"].firstMatch
        XCTAssertTrue(accountRow.waitForExistence(timeout: 15), "Add sheet's Account row not found")
        accountRow.tap()
        XCTAssertTrue(app.buttons["account.splitToggle"].waitForExistence(timeout: 8)
                        || app.switches["account.splitToggle"].waitForExistence(timeout: 2),
                      "Account picker sheet did not open")
    }
}
