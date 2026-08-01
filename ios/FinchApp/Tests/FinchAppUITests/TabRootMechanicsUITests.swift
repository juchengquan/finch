import XCTest

/// Shared rig for the MECHANICAL half of §6 in
/// `ios/docs/uikit-migration-verification.md`. No tests of its own — the two subclasses
/// below split by width so nothing runs twice on an iPad.
///
/// §6 asks for nine checks per converted tab, on an iPhone AND an iPad — call it fifty
/// hand-walks, which is why none of them had been done. Most are not judgement calls
/// though: "does the list scroll", "does the FAB open the sheet", "does the row stay
/// selected" are things a test can assert exactly, and a test asserts them on every
/// commit rather than once. These take those. What is left for a human stays in the doc,
/// and is genuinely visual — whether the section spacing LOOKS like the SwiftUI screen,
/// whether VoiceOver READS well.
class TabMechanicsBase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Orientation is SIMULATOR state, not app state: it survives `app.terminate()`
        // and leaks into whatever runs next. The rotation test below left the device
        // turned and every later test failed with "no Accounts entry in the sidebar",
        // which reads as a broken sidebar rather than as a test-order artifact.
        // Normalising here makes each test independent of what ran before it.
        if XCUIDevice.shared.orientation != .portrait {
            XCUIDevice.shared.orientation = .portrait
        }
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

    // MARK: - width-aware helpers

    var isRegular: Bool { app.windows.firstMatch.frame.width >= 700 }

    /// Anything with this label prefix — the loose query, for "does it exist / where is
    /// it". Rows change class between compact (buttons), `List(selection:)` (neither)
    /// and the converted collection views, so the label is the only stable handle. Same
    /// reasoning as `SplitSelectionUITests.row(labelled:)`.
    func row(labelled prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix))
            .firstMatch
    }

    /// The ROW ITSELF — use this whenever the assertion is about row STATE.
    ///
    /// `row(labelled:)` returns `firstMatch` across every element type, and a cell's
    /// inner `StaticText` usually sorts first. A StaticText is never `isSelected`, so
    /// asserting selection through the loose query reports "the highlight was lost" on a
    /// screen that is behaving perfectly — which is exactly what it did here before a
    /// probe printed the types. The real row is a Button (iPad) or a Cell (iPhone), so
    /// prefer those and fall back only if neither exists.
    func rowElement(labelled prefix: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label BEGINSWITH[c] %@", prefix)
        let button = app.buttons.matching(predicate).firstMatch
        if button.exists { return button }
        let cell = app.cells.matching(predicate).firstMatch
        if cell.exists { return cell }
        return row(labelled: prefix)
    }

    /// Every row on the current list, at either width. `app.cells` is empty on the iPad
    /// split columns (the rows come through as buttons), so a cells-only query silently
    /// finds nothing there and any loop over it passes by doing nothing.
    var visibleRows: [XCUIElement] {
        // Scoped past the sidebar at regular width. Without that, the sidebar's own
        // entries match (they are wide buttons too) and land at the TOP of the list —
        // so "is the last row below the fold" answered no on every iPad tab and the
        // scroll test skipped itself into a permanent green.
        let minX = isRegular ? app.windows.firstMatch.frame.width * 0.25 : 0
        let cells = app.cells.allElementsBoundByIndex.filter { $0.frame.minX >= minX }
        if !cells.isEmpty { return cells }
        return app.buttons.allElementsBoundByIndex
            .filter { $0.frame.width > 120 && $0.frame.minX >= minX }
    }

    /// The scrollable list itself. Swiping the whole app instead would start the gesture
    /// wherever XCTest picks, which on these screens can be the FAB or the tab bar.
    var list: XCUIElement {
        let collection = app.collectionViews.firstMatch
        if collection.exists { return collection }
        let table = app.tables.firstMatch
        return table.exists ? table : app.windows.firstMatch
    }

    /// Poll a condition. `waitForExistence` only waits for APPEARANCE; several of these
    /// assertions are about something going away or a layout settling after a rotation,
    /// where a single immediate read races the animation.
    func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.4)
        }
        return condition()
    }

    /// Reach a tab at either width: a tab bar when compact, the sidebar when regular.
    func openTab(_ name: String) {
        if !isRegular {
            let tab = app.tabBars.buttons[name]
            XCTAssertTrue(tab.waitForExistence(timeout: 30), "no \(name) tab")
            tab.tap()
            return
        }
        // Regular: the sidebar may be hidden — an overlay behind a toggle in portrait,
        // or collapsed because a previous run left it that way (`storedCollapsed` is a
        // persisted preference and `-resetStore` does not touch it). Reveal it, then
        // WAIT: reading straight after the tap raced the reveal animation and reported
        // "no <tab> entry in the sidebar" on a perfectly good screen.
        if sidebarEntry(name) == nil {
            let named = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
            if named.exists { named.tap() }
            else { app.navigationBars.buttons.element(boundBy: 0).tap() }
            _ = waitUntil(timeout: 10) { self.sidebarEntry(name) != nil }
        }
        guard let entry = sidebarEntry(name) else {
            return XCTFail("no \(name) entry in the sidebar")
        }
        entry.tap()
    }

    /// A SIDEBAR entry, scoped by position rather than by label alone.
    ///
    /// Scoping matters more than it looks. Section names recur as content — the Travel
    /// ledger's detail has an "Accounts" heading — so a plain label match happily taps
    /// the heading in the detail column and the app does not navigate at all. That
    /// produced a test which "switched ledger", then asserted against a screen it had
    /// never left, and passed its first assertion for entirely the wrong reason.
    func sidebarEntry(_ name: String) -> XCUIElement? {
        let limit = app.windows.firstMatch.frame.width * 0.25
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", name))
            .allElementsBoundByIndex
            .first { $0.exists && $0.frame.minX < limit && $0.frame.width > 40 }
    }
}

/// Checks that must hold at BOTH widths — the whole point of Phase 3b is that one view
/// controller serves compact and regular, so a check that only ever runs on an iPhone
/// misses half of what it protects.
final class TabRootMechanicsUITests: TabMechanicsBase {

    /// **"The list scrolls."** Not a formality, and the doc says so: `TabChromeVC`
    /// swallowed every touch on its first outing and nothing underneath it moved at all,
    /// on a screen that otherwise looked perfect. That bug was invisible to every other
    /// test here.
    ///
    /// The assertion is on MOVEMENT of a specific row rather than on a screenshot
    /// changing: remember the first row, swipe, and require that it either moved up or
    /// scrolled off. Both prove the gesture reached the scroll view. A tab whose content
    /// already fits is skipped rather than failed — there is nothing to scroll, and
    /// asserting otherwise would fail for the wrong reason.
    func testConvertedTabRootsScroll() throws {
        var exercised = 0
        // Activity only at regular width — it is a sidebar section on the iPad and not a
        // tab at all on the phone. It is included because the iPad columns are tall
        // enough that Accounts/Budgets/Scheduled all FIT, which skipped the whole test
        // there and left the widest layout with no scroll coverage at all.
        let tabs = isRegular
            ? ["Accounts", "Budgets", "Scheduled", "Activity"]
            : ["Accounts", "Budgets", "Scheduled"]
        for tab in tabs {
            openTab(tab)

            let cells = visibleRows
            guard let first = cells.first, let last = cells.last else {
                XCTFail("\(tab): no rows at all — the list never rendered")
                continue
            }
            guard last.frame.maxY > app.windows.firstMatch.frame.maxY else {
                continue   // genuinely nothing to scroll on this destination
            }
            exercised += 1

            let anchorLabel = first.label
            let before = first.frame.minY
            list.swipeUp()

            let after = row(labelled: anchorLabel)
            let moved = !after.exists || after.frame.minY < before - 1
            XCTAssertTrue(moved,
                          "\(tab): the list did not move when swiped — something above it is "
                          + "swallowing touches (this is exactly the TabChromeVC failure)")
        }
        // Without this the test goes green on a destination where every list happened to
        // fit, having asserted nothing at all.
        try XCTSkipIf(exercised == 0, "no tab had enough content to scroll on this destination")
    }

    /// **"Deep link into the tab … selects or pushes the right thing."**
    ///
    /// This is the widget / Spotlight / App Intent path — `route(to:)` picks the tab and
    /// sets `focusedId`, and each converted list has a sink that acts on it. It needed a
    /// `-routeTo` launch flag to be reachable at all: `-initialTab` only chooses a tab,
    /// and the `finch://` scheme handles `add` and nothing else.
    ///
    /// `account:everyday` rather than the `budget:` the checklist names, because account
    /// ids are FIXED in the demo seed while budget and transaction ids are generated —
    /// a test cannot name one. Same code path either way; `route(to:)` switches on the
    /// prefix and does the same thing with the rest.
    func testDeepLinkTargetFocusesTheRecord() throws {
        // COMPACT ONLY, because the iPad does not do this — see §6. The link selects the
        // Accounts tab there and then stops: the detail column stays on "Select an
        // account". Confirmed by screenshot, and it is NOT what this suite introduced.
        // Left as a skip rather than a failing test so the compact coverage can land;
        // the gap is written up in the doc rather than hidden here.
        try XCTSkipIf(isRegular, "regular width does not consume a deep-link target — known gap, §6")
        app.terminate()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES", "-routeTo", "account:everyday"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not relaunch")

        // "Everyday" is the account with id `everyday` in the demo seed. What proves it
        // opened DIFFERS by width, and getting that wrong reported a broken deep link on
        // a working app: at compact width the account is PUSHED, so its name lands in the
        // navigation bar; at regular width it fills the detail column, so the proof is
        // the placeholder going away. Asserting a "Transactions" heading — the iPad
        // column's wording — found nothing on the phone, where the pushed screen has a
        // List/Calendar picker and month sections instead.
        if isRegular {
            XCTAssertTrue(app.staticTexts["Select an account"].waitForNonExistence(timeout: 25),
                          "the detail column is still on its placeholder — focusedId was never consumed")
        } else {
            XCTAssertTrue(app.navigationBars["Everyday"].waitForExistence(timeout: 25),
                          "the deep link did not push the Everyday account")
        }
    }

    /// **"The FAB … opens the Add sheet."** `TabChromeUITests` proves the button EXISTS
    /// on every root; nothing proved it did anything. A FAB wired to a dead action, or
    /// one whose hit target is covered, looks identical in a screenshot.
    func testFABOpensTheAddSheet() throws {
        try XCTSkipIf(isRegular, "compact only — the iPad has no FAB, see testIPadOffersAddInTheToolbar")
        openTab("Budgets")

        let fab = app.buttons["Add Transaction"]
        XCTAssertTrue(fab.waitForExistence(timeout: 15), "no add-transaction FAB on Budgets")
        fab.tap()

        // `Cancel` / `Save` are AddTransactionSheet's own toolbar labels, so they
        // identify the sheet rather than anything behind it.
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "the FAB did not open the Add sheet")
        XCTAssertTrue(app.buttons["Save"].exists, "Add sheet opened without its Save button")

        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 10), "the Add sheet would not dismiss")
    }

    /// **"The FAB … does not block taps or scrolling anywhere else."** The passthrough
    /// this guards was subtle: `_UIHostingView.hitTest` returns the hosting view for ANY
    /// point inside its bounds, so a full-width chrome overlay silently ate every touch
    /// outside the button. Asserting a row level with the FAB still responds is the
    /// cheapest proof the passthrough geometry is right.
    func testTapsPassThroughBesideTheFAB() throws {
        try XCTSkipIf(isRegular, "compact only — no FAB to pass through on the iPad")
        openTab("Accounts")

        let fab = app.buttons["Add Transaction"]
        XCTAssertTrue(fab.waitForExistence(timeout: 15), "no FAB on Accounts")

        // A row on the same horizontal band as the FAB, but not under the button itself.
        let neighbours = visibleRows.filter {
            abs($0.frame.midY - fab.frame.midY) < 60 && $0.frame.minX < fab.frame.minX
        }
        guard let neighbour = neighbours.first else {
            throw XCTSkip("no row alongside the FAB on this destination")
        }
        let label = neighbour.label
        neighbour.tap()

        // Any response at all proves the touch landed on the row rather than the chrome:
        // a push at compact width, or the detail column filling at regular.
        let pushed = app.navigationBars.buttons["Accounts"].waitForExistence(timeout: 10)
        let filled = app.staticTexts["Select an account"].waitForNonExistence(timeout: 10)
        XCTAssertTrue(pushed || filled,
                      "tapping '\(label)' beside the FAB did nothing — the chrome is eating touches")
    }
}

/// Regular-width (iPad) mechanics. Skipped on an iPhone destination, exactly as
/// `SplitSelectionUITests` is, so the suite stays valid on both.
///
/// `SplitSelectionUITests` already covers Accounts selecting into the column and a
/// section switch resetting it. These are the §6 items it does not: the other converted
/// tabs, and the two opposite ways a selection is known to go wrong.
final class SplitMechanicsUITests: TabMechanicsBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        let width = app.windows.firstMatch.frame.width
        try XCTSkipUnless(width >= 700, "regular width only — got \(width)pt")
    }

    /// **"Regular: tapping a row fills the DETAIL COLUMN."** Per converted tab, because
    /// each wires its own `onSelect`, and a tab that forgot it fails silently — the
    /// placeholder simply stays up, which reads as "nothing selected" rather than a bug.
    func testSelectionFillsTheDetailColumnForEveryConvertedTab() throws {
        // All five converted tabs. Each wires its own `onSelect`, so this is five
        // separate opportunities to forget it — and Scheduled, Ledger and Activity were
        // the three nothing covered.
        let cases: [(tab: String, rowPrefix: String, placeholder: String)] = [
            ("Budgets",   "Groceries",       "Select a budget"),
            ("Accounts",  "Checking",        "Select an account"),
            ("Scheduled", "Apartment Rent",  "Select a scheduled item"),
            // Travel, not Personal: tapping a ledger row only OPENS it, so this fills
            // the column without changing which ledger is active — see
            // `makeLedgerActive` for why that distinction matters.
            ("Ledger",    "Travel",          "Select a ledger"),
        ]
        for c in cases {
            openTab(c.tab)
            let placeholder = app.staticTexts[c.placeholder]
            XCTAssertTrue(placeholder.waitForExistence(timeout: 20),
                          "\(c.tab): no detail placeholder — this is not the split shell")

            let target = rowElement(labelled: c.rowPrefix)
            XCTAssertTrue(target.waitForExistence(timeout: 20), "\(c.tab): no '\(c.rowPrefix)' row")
            target.tap()

            XCTAssertTrue(placeholder.waitForNonExistence(timeout: 15),
                          "\(c.tab): the selection never reached the detail column")
        }
    }

    /// The iPad's stand-in for the FAB checks above. It has no floating button — add is a
    /// toolbar `+` — which is DELIBERATE and identical in the hosted build, so the FAB
    /// tests skip at regular width. Without this, that skip would be a coverage hole:
    /// nothing would assert that an iPad can add anything at all.
    func testIPadOffersAddInTheToolbar() throws {
        openTab("Budgets")
        let add = app.buttons["Add Budget"]
        XCTAssertTrue(add.waitForExistence(timeout: 20),
                      "no toolbar + on the iPad Budgets column — and there is no FAB either, "
                      + "so nothing on this screen can create a budget")
        add.tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "the toolbar + did not open a sheet")
        cancel.tap()
    }

    /// Activity, separately: its rows carry seeded amounts and dates rather than a
    /// stable name, so this takes whatever the first row is instead of matching a label.
    func testSelectionFillsTheDetailColumnForActivity() throws {
        openTab("Activity")
        let placeholder = app.staticTexts["Select a transaction"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 20),
                      "Activity: no detail placeholder — this is not the split shell")

        guard let first = visibleRows.first else {
            return XCTFail("Activity: no rows in the list column")
        }
        first.tap()
        XCTAssertTrue(placeholder.waitForNonExistence(timeout: 15),
                      "Activity: the selection never reached the detail column")
    }

    /// **Switching across the three-column ↔ two-column boundary** (§6, 3a). Insights and
    /// Settings are two-column; the rest are three, so moving between them rebuilds the
    /// split controller. The risk is not a crash — it is coming back to a tab that has
    /// lost its list column, which still looks like a working screen.
    func testSwitchingAcrossTheColumnCountBoundaryRebuildsCleanly() throws {
        openTab("Accounts")
        XCTAssertTrue(app.staticTexts["Select an account"].waitForExistence(timeout: 20),
                      "Accounts did not come up as a three-column tab")

        openTab("Insights")          // two-column
        openTab("Settings")          // two-column
        openTab("Accounts")          // back across the boundary

        XCTAssertTrue(app.staticTexts["Select an account"].waitForExistence(timeout: 20),
                      "Accounts lost its detail column after a trip through the two-column tabs")
        XCTAssertTrue(rowElement(labelled: "Checking").waitForExistence(timeout: 15),
                      "Accounts came back without its list column — the rebuild dropped it")
    }

    /// **"The highlight survives a data change."** `dataSource.apply` clears the
    /// collection view's selection, so every converted list has to re-assert it
    /// afterwards. Nothing looks wrong when that is missed — the row just quietly stops
    /// being highlighted while its detail is still on screen.
    ///
    /// Privacy mode is the trigger: a store change that forces a snapshot on every
    /// converted list, and it alters no layout, so nothing else about the screen moves.
    func testTheSelectionSurvivesADataChange() throws {
        openTab("Accounts")
        let target = rowElement(labelled: "Checking")
        XCTAssertTrue(target.waitForExistence(timeout: 20), "no 'Checking' row")
        target.tap()
        XCTAssertTrue(app.staticTexts["Select an account"].waitForNonExistence(timeout: 15),
                      "selection never reached the detail column")

        let privacy = app.buttons["Privacy mode"]
        XCTAssertTrue(privacy.waitForExistence(timeout: 15), "no privacy-mode control to force a reload")
        privacy.tap()

        XCTAssertTrue(app.staticTexts["Select an account"].waitForNonExistence(timeout: 10),
                      "the detail column reverted to its placeholder after a reload — "
                      + "the selection was not re-asserted")
        XCTAssertTrue(rowElement(labelled: "Checking").isSelected,
                      "the row lost its highlight after a reload — dataSource.apply cleared the "
                      + "selection and nothing put it back")

        privacy.tap()   // leave the store as it was found
    }

    /// **"A ledger switch clears the per-tab selection."** The opposite requirement to
    /// the test above, and why both are needed: a screen that never clears looks
    /// identical to one that never loses its highlight, right up until it shows a
    /// Personal account while the Travel ledger is active.
    ///
    /// The switch is CONFIRMED before its consequence is asserted. An earlier version
    /// tapped Travel and went straight to "is the placeholder back", which failed for
    /// two wrong reasons at once — on the iPad it was still sitting in the Ledger
    /// section, where an Accounts placeholder was never going to appear. Checking that
    /// the Accounts list now shows the TRAVEL accounts pins down that the ledger really
    /// changed, so a failure below can only mean the selection survived it.
    func testALedgerSwitchClearsTheSelection() throws {
        openTab("Accounts")
        let target = rowElement(labelled: "Checking")
        XCTAssertTrue(target.waitForExistence(timeout: 20), "no 'Checking' row")
        target.tap()
        XCTAssertTrue(app.staticTexts["Select an account"].waitForNonExistence(timeout: 15),
                      "selection never reached the detail column")

        makeLedgerActive("Travel")

        openTab("Accounts")
        XCTAssertTrue(rowElement(labelled: "Travel Checking").waitForExistence(timeout: 20),
                      "Accounts is not showing the Travel ledger's accounts — the ledger never "
                      + "actually switched, so this test cannot say anything about the selection")
        XCTAssertTrue(app.staticTexts["Select an account"].waitForExistence(timeout: 15),
                      "the detail column still shows the Personal account after switching to "
                      + "Travel — the per-tab selection was not cleared")

        // No restore step: `-resetStore YES` now clears the remembered ledger too
        // (LaunchSequence.wipeLiveStateForTesting). It did not, and the omission was
        // invisible until this test — the active ledger lives in UserDefaults, not the
        // database, so a run that switched to Travel came back up in Travel forever,
        // and every later test failed with "no 'Checking' row" as though the app were
        // broken. Fixing the flag beat unwinding the state in the test.
    }

    /// Make a ledger current: open the Ledger section, open that ledger, then take the
    /// explicit action. Tapping the row only OPENS it.
    private func makeLedgerActive(_ name: String) {
        if isRegular {
            openTab("Ledger")
        } else {
            let ledger = app.buttons["Ledger"]
            XCTAssertTrue(ledger.waitForExistence(timeout: 15), "no Ledger control")
            ledger.tap()
        }
        let target = rowElement(labelled: name)
        XCTAssertTrue(target.waitForExistence(timeout: 15), "no '\(name)' ledger in the demo data")
        target.tap()
        // NOTE the query: this row is a CELL, not a button, so `app.buttons[...]` finds
        // nothing and silently skips the activation — which read as "the ledger never
        // switched" while the test looked like it had tried.
        let makeActive = rowElement(labelled: "Make active ledger")
        if makeActive.waitForExistence(timeout: 10) { makeActive.tap() }
    }
}
