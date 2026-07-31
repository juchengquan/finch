import XCTest

/// UI regression net for the compact (iPhone) navigation model.
///
/// **Runs twice.** The app has two navigation implementations behind a flag, and this
/// class is the base (`-uikitActivity` off, screens hosted from SwiftUI);
/// `NavigationUIKitUITests` below re-runs every test with it on, where Accounts,
/// Budgets and Settings drill into real `UIViewController`s. Testing only one of them
/// would pass while saying nothing about the other — which is what the original
/// version of this suite did, before the UIKit migration existed.
///
/// **Asserts the destination, not the chrome.** The two modes differ in ways that make
/// the obvious assertions mode-specific, and both traps were hit while writing this:
///
///  - The back affordance differs. A cover carries a custom chevron labelled "Back"
///    (`rsdBackToolbar`); a `UINavigationController` labels its back item with the
///    PREVIOUS screen's title. Asserting `buttons["Back"]` — as the first version of
///    this suite did — fails under UIKit for a reason unrelated to navigation working.
///  - "The tab root went away" is only true of a real push. A cover is presented
///    `.overFullScreen`, so the tab root stays in the accessibility tree underneath it,
///    visually hidden but findable. That assertion passed under UIKit and failed all
///    three cover tests.
///
/// What holds in both: drilling shows a marker that belongs to the DESTINATION, and
/// dismissing takes it away. The markers below are strings the two implementations
/// genuinely share (`Section("This cycle")` and `headers[.thisCycle]`, etc.), so they
/// cannot drift apart without one of the two screens actually changing.
///
/// **Launch flags** (both DEBUG-only, read in `LaunchSequence.run`):
///   `-resetStore YES` — wipes the live DB + App Group scratch BEFORE the store opens
///   it, so each run starts from a fresh `SimulatorDemoSeed`. Not optional: the UI-test
///   host process doesn't load `XCTestCase`, so `FinchStore`'s temp-dir guard is
///   inactive and without this the run mutates a development simulator's real data.
///   `-disableNotifications YES` — skips the permission prompt and the planner. The
///   demo seed dates transactions at `store.today`, so a budget alert fires
///   immediately and the system banner covers the accessibility tree.
class NavigationUITests: XCTestCase {

    var app: XCUIApplication!

    /// Overridden by `NavigationUIKitUITests`.
    var uikitActivity: Bool { false }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        var args = ["-resetStore", "YES", "-disableNotifications", "YES"]
        if uikitActivity { args += ["-uikitActivity", "YES"] }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    // MARK: - Helpers

    private var mode: String { uikitActivity ? "uikit" : "hosted" }

    private func selectTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 30), "[\(mode)] \(name) tab should exist")
        tab.tap()
    }

    /// The leading back affordance, whatever it is called in this mode.
    ///
    /// The cover's is labelled "Back"; a `UINavigationController`'s carries the
    /// previous screen's title, so it can only be found positionally.
    private func backAffordance() -> XCUIElement {
        let named = app.buttons["Back"]
        if named.exists { return named }
        return app.navigationBars.buttons.element(boundBy: 0)
    }

    /// Drill in from a tab root and come back.
    ///
    /// `destination` must be absent from the tab root and present on the drilled
    /// screen — that is what makes its appearance evidence of navigation, and its
    /// disappearance evidence that the back affordance actually dismissed rather than
    /// that something was merely tapped.
    private func assertDrillsAndReturns(open: XCUIElement,
                                        destination: XCUIElement,
                                        _ label: String) {
        XCTAssertTrue(open.waitForExistence(timeout: 30), "[\(mode)] \(label): no entry point to tap")
        XCTAssertFalse(destination.exists, "[\(mode)] \(label): destination marker already visible on the tab root — it cannot prove navigation")
        open.tap()

        XCTAssertTrue(destination.waitForExistence(timeout: 15),
                      "[\(mode)] \(label): destination never appeared — the drill didn't open")

        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        shot.name = "\(label)-\(mode)"
        shot.lifetime = .keepAlways
        add(shot)

        let back = backAffordance()
        XCTAssertTrue(back.waitForExistence(timeout: 15), "[\(mode)] \(label): no back affordance on the destination")
        back.tap()

        XCTAssertTrue(destination.waitForNonExistence(timeout: 15),
                      "[\(mode)] \(label): destination still showing — the drill didn't dismiss")
    }

    // MARK: - Accounts → All Transactions

    func testAccountsDrillIntoActivity() throws {
        selectTab("Accounts")
        assertDrillsAndReturns(
            // A stable, always-present row that opens the Activity feed.
            open: app.buttons["All Transactions"],
            // Both implementations title this screen "Activity"
            // (`ActivityTab.navigationTitle` / `ActivityFeedVC.title`).
            destination: app.navigationBars["Activity"],
            "Accounts→Activity")
    }

    // MARK: - Accounts → account detail

    func testAccountsDrillIntoAccountDetail() throws {
        selectTab("Accounts")
        assertDrillsAndReturns(
            // "Checking" is a leaf account in the demo seed, visible without expanding.
            open: app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Checking")).firstMatch,
            // The "Transactions" section header, present in both the empty and
            // populated branches of each implementation. Not the nav title: the UIKit
            // screen installs a custom `titleView`, so the bar's identity is less
            // predictable than the content's.
            destination: app.staticTexts["Transactions"],
            "Accounts→Detail")
    }

    // MARK: - Budgets → budget detail

    func testBudgetsDrillIntoDetail() throws {
        selectTab("Budgets")
        // "Health" is a top-level (ungrouped) budget in the demo seed, so it is visible
        // without expanding a group.
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Health")).firstMatch
        assertDrillsAndReturns(
            open: row,
            // `Section("This cycle")` in SwiftUI, `headers[.thisCycle]` in UIKit.
            destination: app.staticTexts["This cycle"],
            "Budgets→Detail")
    }
}

/// Every test above, re-run against the converted UIKit screens.
///
/// XCTest runs a superclass's tests in the subclass too, so this is the whole
/// parameterisation — it costs one flag and doubles the coverage.
final class NavigationUIKitUITests: NavigationUITests {
    override var uikitActivity: Bool { true }
}
