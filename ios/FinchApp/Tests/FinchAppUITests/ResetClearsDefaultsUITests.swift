import XCTest

/// `-resetStore YES` really means a clean slate — including UserDefaults.
///
/// The wipe removes the database and the App Group scratch, which are files. Everything
/// the app persists in UserDefaults survived it, so state leaked from one launch into
/// every later one, and in a UI run that means from one test into every test after it.
///
/// The failure that motivated this is worth stating, because its message points nowhere
/// near its cause: a test toggled privacy mode and left it on, and
/// `CategorySplitUITests` failed two tests later with
///
///     allocated reads Allocated, •••• / •••• — the split does not add up to the amount
///
/// Bullets because amounts were masked. Nothing in that message suggests another test's
/// leftover toggle, and nothing in the suite's ordering makes it reproducible on its own.
///
/// Privacy is the probe here because it is the one that actually bit, and because it is
/// observable from outside: the toolbar button publishes its state as an accessibility
/// VALUE, so the test can read it without reaching into the app. The fix is not
/// privacy-specific — it sweeps every `finch.*` key.
final class ResetClearsDefaultsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testResetStoreClearsLeakedUserDefaults() throws {
        // 1. Launch and deliberately leak: turn privacy mode ON and leave it on, which
        //    is exactly what a test that forgets to restore it does.
        launch(resettingStore: true)
        let toggled = setPrivacy(to: "on")
        XCTAssertEqual(toggled, "on", "could not turn privacy mode on to seed the leak")
        app.terminate()

        // 2. Relaunch WITH the reset. Before this fix, privacy came back on: the wipe
        //    removed the database and left UserDefaults untouched.
        launch(resettingStore: true)
        let after = privacyValue()
        XCTAssertEqual(after, "off",
                       "privacy mode survived `-resetStore YES` — the wipe is not clearing "
                       + "UserDefaults, so this state leaks into every later test")
    }

    /// The control half: WITHOUT the reset flag, the setting must persist. A wipe that
    /// fired unconditionally would also pass the assertion above while quietly breaking
    /// the app for real users, so this pins the flag as the trigger.
    func testWithoutTheFlagTheSettingPersists() throws {
        launch(resettingStore: true)
        XCTAssertEqual(setPrivacy(to: "on"), "on", "could not turn privacy mode on")
        app.terminate()

        launch(resettingStore: false)
        XCTAssertEqual(privacyValue(), "on",
                       "privacy mode was cleared WITHOUT `-resetStore YES` — the wipe is "
                       + "firing on an ordinary launch, which would reset real users")
    }

    // MARK: Helpers

    private func launch(resettingStore: Bool) {
        continueAfterFailure = false
        app = XCUIApplication()
        var args = ["-disableNotifications", "YES", "-uikitActivity", "YES",
                    "-initialTab", "settings"]
        if resettingStore { args += ["-resetStore", "YES"] }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    /// Privacy is a Settings ROW now, not a toolbar button: the eye came off every
    /// iPhone screen when hiding amounts moved to a long-press of the ledger
    /// button. A switch reports "1"/"0" where a button reported "on"/"off", so the
    /// translation happens HERE and the test body keeps reading in on/off.
    private func privacyValue() -> String? {
        let toggle = app.switches["Privacy mode"].firstMatch
        guard toggle.waitForExistence(timeout: 30) else { return nil }
        guard let raw = toggle.value as? String else { return nil }
        return raw == "1" ? "on" : "off"
    }

    /// Tap until the toggle reads `target`, so the test does not depend on which state
    /// the app happened to start in.
    @discardableResult
    private func setPrivacy(to target: String) -> String? {
        guard var current = privacyValue() else { return nil }
        if current == target { return current }
        // The TRAILING edge: a switch inside a cell spans the whole row, and a
        // centre tap lands on the label and does nothing.
        app.switches["Privacy mode"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let deadline = Date().addingTimeInterval(5)
        while current != target && Date() < deadline {
            usleep(100_000)
            current = privacyValue() ?? current
        }
        return current
    }
}
