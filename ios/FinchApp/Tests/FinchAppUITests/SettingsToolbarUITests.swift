import XCTest

/// Settings' privacy control exists and actually drives `store.privacyMode`.
///
/// It is a ROW now, not a toolbar button: the eye came off every iPhone screen
/// when hiding amounts moved to a long-press of the ledger button, and this row
/// is the visible home that keeps an invisible gesture discoverable.
///
/// **Written BEFORE the Settings root was converted to UIKit, and passing against the
/// hosted SwiftUI screen.** That ordering is the point: it proves the assertion can see
/// the affordance, so a green run after the conversion means it survived rather than
/// that the test was always vacuous.
///
/// **Scope, checked rather than assumed.** The Ledger control is NOT tested here,
/// because `TabChromeUITests.testEveryTabKeepsItsLedgerControl` already iterates all
/// five tabs — Settings included. That guard was added by `738cbb0c`, the fix for the
/// Scheduled tab losing its Ledger control, so the lesson was already banked. A second
/// copy would only cost suite time on a run CI already retries for flakiness.
///
/// What had no guard is the privacy toggle. `0898bb79` ("Scheduled lost its
/// hide-amounts button, and ignored privacy mode") was never turned into a test, and
/// `TabRootMechanicsUITests` only taps privacy on ACCOUNTS as a trigger for a selection
/// assertion — it says nothing about Settings having one.
///
/// It keys on accessibility, not layout, because that is the contract both
/// implementations already share: SwiftUI's `PrivacyToggleButton` sets label "Privacy
/// mode" + value on/off (`AdaptiveShell`), and the converted VCs set the identical pair
/// on their `UIBarButtonItem`. So one test spans both — which is what makes it a
/// characterization test rather than a description of the new code.
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

    func testSettingsPrivacyToggleExistsAndFlips() throws {
        XCTAssertTrue(app.staticTexts["Settings"].firstMatch.waitForExistence(timeout: 30),
                      "never reached Settings")

        // The toolbar EYE is gone on iPhone — hiding amounts moved to a
        // long-press of the ledger button, and this row is its visible home.
        // Asserted rather than assumed, because "the eye is still there" is the
        // way this change fails to actually reclaim the slot.
        XCTAssertFalse(app.buttons["Privacy mode"].firstMatch.exists,
                       "the privacy eye is still in Settings' toolbar on iPhone")

        let privacy = app.switches["Privacy mode"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 30),
                      "Settings has no privacy row")

        // The VALUE is the assertion that matters. A control that exists but does not
        // drive `store.privacyMode` is exactly the 0898bb79 defect — present, inert.
        let before = privacy.value as? String
        XCTAssertTrue(before == "0" || before == "1",
                      "privacy row reports no switch value; got \(before ?? "nil")")

        // A switch inside a cell takes the tap on its TRAILING edge; a centre tap
        // lands on the label and does nothing — the same trap the split toggles
        // in CategorySplitUITests documented.
        privacy.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

        let deadline = Date().addingTimeInterval(5)
        var after = app.switches["Privacy mode"].firstMatch.value as? String
        while after == before && Date() < deadline {
            usleep(100_000)
            after = app.switches["Privacy mode"].firstMatch.value as? String
        }
        XCTAssertNotEqual(after, before,
                          "privacy row did not change state — BEFORE \(before ?? "nil"), AFTER \(after ?? "nil")")

        // Put it back. `privacyMode` is STORE state, not view state: it outlives the
        // app termination in tearDown, and a later test in the same run then reads
        // masked amounts. That is not hypothetical — leaving it on failed
        // `CategorySplitUITests` with "allocated reads Allocated, •••• / ••••", a
        // failure whose message points nowhere near this file.
        app.switches["Privacy mode"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

        // ASSERT the restore landed. A coordinate tap that misses leaves privacy
        // ON for every later test in the run, and the failure surfaces somewhere
        // else entirely — masked amounts in CategorySplitUITests, per the note
        // above. Silent here, baffling there; so fail here instead.
        let restored = app.switches["Privacy mode"].firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        XCTAssertEqual(restored.value as? String, before,
                       "privacy was not restored — it leaks into every later test")
    }
}
