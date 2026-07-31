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

    /// The floating add-`+` that is actually on screen.
    ///
    /// There can be TWO in the tree at once: a right-slide cover is presented
    /// `.overFullScreen`, so the tab root's FAB stays behind it, findable but not
    /// hittable. A bare query is therefore ambiguous ("Multiple matching elements
    /// found" — the tap fails outright), and `.firstMatch` picks whichever comes first,
    /// which was the buried one — the tap went nowhere and no sheet opened.
    private func floatingAddButton() -> XCUIElement {
        let all = app.buttons.matching(identifier: "fab.addTransaction")
        for i in 0..<all.count where all.element(boundBy: i).isHittable {
            return all.element(boundBy: i)
        }
        return all.firstMatch
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

    // MARK: - The floating add-+ on pushed screens (§2c)

    /// The button must survive a drill-in, and open a sheet SEEDED with that page.
    ///
    /// Both halves matter and they failed independently. The button was missing on
    /// converted pushed screens because the FAB is chrome on the tab ROOT, which a
    /// pushed view controller covers. Restoring it via `TabChromeVC` was not enough:
    /// the hosted FAB reads `AddTxContextKey` from its own (empty) tree, so it opened
    /// an UNSEEDED sheet where the SwiftUI path pre-fills the page's account and
    /// category. Asserting only existence would have passed on that broken state.
    ///
    /// Queries the identifier, not the label: the screen's own toolbar `+` carries the
    /// same "Add Transaction" label, so a label query passes with no floating button.
    private func assertFABSurvivesDrill(tab: String,
                                        open: XCUIElement,
                                        destination: XCUIElement,
                                        seededRow: String,
                                        _ label: String) {
        selectTab(tab)
        let fab = floatingAddButton()
        XCTAssertTrue(fab.waitForExistence(timeout: 30), "[\(mode)] \(label): no floating + on the tab root")

        XCTAssertTrue(open.waitForExistence(timeout: 30), "[\(mode)] \(label): no entry point to tap")
        open.tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 15), "[\(mode)] \(label): the drill never opened")

        XCTAssertTrue(fab.waitForExistence(timeout: 15),
                      "[\(mode)] \(label): the floating + vanished on the pushed screen")

        // The SEEDING half runs in uikit mode only.
        //
        // Not because hosted seeding is unverified — it was checked by hand on the
        // simulator (the cover's + opens the sheet reading "Account, Checking"). It is
        // that XCUITest cannot drive that cover's button: the tap resolves but no sheet
        // appears, with `.tap()` and with a coordinate tap. The uikit path is the one
        // this change alters, and it is asserted in full; the hosted path keeps its
        // existence assertions above, which is what would catch a regression there.
        guard uikitActivity else { return }

            // Tap the CENTRE by coordinate. `element.tap()` resolves the query again at tap
            // time and did not land here: the sheet never opened, though driving the same
            // button by hand did open it, seeded. A coordinate tap skips that resolution.
            fab.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            // Confirm the sheet is actually up before reading its rows.
            XCTAssertTrue(app.staticTexts["Expense"].waitForExistence(timeout: 15),
                          "[\(mode)] \(label): the Add sheet never opened from the +")
            // By IDENTIFIER: a label query matched the "Accounts" tab-bar button, and then
            // the budget detail's own Account row behind the sheet — both made this
            // assertion read an element that was never in the sheet.
            let seeded = app.buttons[seededRow].firstMatch
            XCTAssertTrue(seeded.waitForExistence(timeout: 10),
                          "[\(mode)] \(label): the seeded row is missing from the Add sheet")
            // "Account" alone is the empty state; seeded reads "Account, <name>".
            XCTAssertTrue(seeded.label.contains(","),
                          "[\(mode)] \(label): the + opened an UNSEEDED sheet — \(seeded.label)")
    }

    func testFloatingAddButtonSurvivesAccountDrill() throws {
        assertFABSurvivesDrill(
            tab: "Accounts",
            open: app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Checking")).firstMatch,
            destination: app.staticTexts["Transactions"],
            seededRow: "addtx.account",
            "Accounts→Detail")
    }

    func testFloatingAddButtonSurvivesBudgetDrill() throws {
        assertFABSurvivesDrill(
            tab: "Budgets",
            open: app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Health")).firstMatch,
            destination: app.staticTexts["This cycle"],
            // The demo's Health budget has a category and NO account, so the category
            // is what proves the seeding here.
            seededRow: "addtx.category",
            "Budgets→Detail")
    }

    // MARK: - The DEBUG navigation launch flag

    /// `-initialTab` is how a sim check reaches a non-default tab without tapping.
    ///
    /// It shipped BROKEN on iOS and nothing noticed: it was parsed in the SwiftUI
    /// `App.init`, and `FinchApp.swift` is excluded from the iOS target, so the flag
    /// worked on macOS and silently did nothing on the platform it exists to drive.
    /// It now parses in `LaunchSequence.run` with the other launch flags, which both
    /// entry points call — this test is what keeps it there.
    ///
    /// Asserts the tab's SELECTED state rather than a screen marker, so it says the
    /// same thing in both navigation modes.
    func testInitialTabLaunchFlagSelectsThatTab() throws {
        let defaultTab = app.tabBars.buttons["Accounts"]
        XCTAssertTrue(defaultTab.waitForExistence(timeout: 30), "[\(mode)] tab bar never appeared")
        XCTAssertTrue(defaultTab.isSelected, "[\(mode)] launch tab should be Accounts without the flag")

        app.terminate()
        var args = ["-resetStore", "YES", "-disableNotifications", "YES", "-initialTab", "budgets"]
        if uikitActivity { args += ["-uikitActivity", "YES"] }
        app.launchArguments = args
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "[\(mode)] app did not relaunch")

        let flagged = app.tabBars.buttons["Budgets"]
        XCTAssertTrue(flagged.waitForExistence(timeout: 30), "[\(mode)] tab bar never appeared after relaunch")
        XCTAssertTrue(flagged.isSelected, "[\(mode)] -initialTab budgets did not select the Budgets tab")
    }
}

/// Every test above, re-run against the converted UIKit screens.
///
/// XCTest runs a superclass's tests in the subclass too, so this is the whole
/// parameterisation — it costs one flag and doubles the coverage.
final class NavigationUIKitUITests: NavigationUITests {
    override var uikitActivity: Bool { true }
}
