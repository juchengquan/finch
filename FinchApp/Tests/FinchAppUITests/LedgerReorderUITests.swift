import XCTest

/// The ledger reorder mode, end to end: ⋯ → Reorder → drag → ✓, and the order that
/// survives it.
///
/// This is a UI test and not a unit test because the part that can break is the part
/// no unit test touches — the lift, the drop coordinate, and the diffable snapshot the
/// drop applies. `idb ui swipe` cannot drive it either: a drag needs the long-press
/// lift first, and a plain swipe just scrolls, so `press(forDuration:thenDragTo:)` is
/// the only thing that exercises this path.
final class LedgerReorderUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// The whole loop: the last ledger dragged to the top stays there after ✓.
    ///
    /// Asserted by NAME ORDER rather than "did the row move", because the bug this
    /// screen shipped with was an order that changed on its own.
    func testDraggingALedgerToTheTopPersists() throws {
        try openLedgers()
        let before = ledgerIDs()
        XCTAssertGreaterThan(before.count, 1, "need at least two ledgers to reorder")
        let last = try XCTUnwrap(before.last)

        try enterReorder()
        let source = try XCTUnwrap(ledgerRow(last), "the last ledger has no row")
        let target = try XCTUnwrap(ledgerRow(try XCTUnwrap(before.first)))
        // Drop ABOVE the first row's centre, or the drop lands after it.
        // Coordinate-to-coordinate: the element overload drops at the target's CENTRE,
        // which lands the row BELOW the first one — the opposite of what is asserted.
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0,
                   thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))

        app.buttons["Done"].firstMatch.tap()

        XCTAssertEqual(ledgerIDs().first, last, "the dragged ledger did not stay on top")
        XCTAssertEqual(Set(ledgerIDs()), Set(before), "reordering added or lost a ledger")
    }

    /// ✕ discards. The draft never reaches the DB, so the saved order is untouched.
    func testCancellingAReorderWritesNothing() throws {
        try openLedgers()
        let before = ledgerIDs()

        try enterReorder()
        let source = try XCTUnwrap(ledgerRow(try XCTUnwrap(before.last)))
        let target = try XCTUnwrap(ledgerRow(try XCTUnwrap(before.first)))
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 1.0,
                   thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        app.buttons["Cancel"].firstMatch.tap()

        XCTAssertEqual(ledgerIDs(), before, "✕ wrote the draft anyway")
    }

    /// Activating a ledger must leave the sequence alone — the reported bug, at the
    /// level a user meets it. The engine test covers the projection; this covers the
    /// screen, which is where the rearranging was actually seen.
    func testActivatingALedgerDoesNotMoveItsRow() throws {
        try openLedgers()
        let before = ledgerIDs()
        // Any INACTIVE row: the active one offers a status chip, not an action.
        let activeID = "personal"   // the demo seed activates Personal
        let name = try XCTUnwrap(before.first { $0 != "ledger.\(activeID)" }, "no inactive ledger")
        let row = try XCTUnwrap(ledgerRow(name))

        row.swipeRight()
        let activate = app.buttons["Make active"].firstMatch
        XCTAssertTrue(activate.waitForExistence(timeout: 5), "no Make active action")
        activate.tap()

        XCTAssertEqual(ledgerIDs(), before, "activating \(name) rearranged the list")
    }

    // MARK: Helpers

    private func openLedgers() throws {
        let corner = app.buttons["Ledger"].firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 15), "no ledger corner control")
        corner.tap()
        XCTAssertTrue(app.cells.staticTexts["Personal"].firstMatch.waitForExistence(timeout: 15),
                      "the ledger list did not appear")
    }

    private func enterReorder() throws {
        let more = app.buttons["More"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no ⋯ item on the ledger list")
        more.tap()
        let reorder = app.buttons["Reorder"].firstMatch
        XCTAssertTrue(reorder.waitForExistence(timeout: 5), "the ⋯ menu has no Reorder")
        reorder.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 5),
                      "reorder mode did not take over the toolbar")
    }

    /// The ledger list itself, by identifier.
    ///
    /// **Scoped deliberately.** The ledger flow is PUSHED over Accounts, and the
    /// account rows underneath stay in the accessibility hierarchy — an unscoped
    /// `app.cells` therefore returns both screens' rows, so `.last` is an account and
    /// every order assertion is meaningless. Cost two red tests to find.
    private var list: XCUIElement { app.collectionViews["ledgerList"] }

    /// The ledger ids in screen order, read from each row's identifier.
    ///
    /// **Not from the row's text.** A cell's `staticTexts` are not returned in visual
    /// order, so "the first one" is sometimes the name and sometimes the net worth —
    /// and reorder mode strips the net worth, so a string captured in one mode cannot
    /// be found in the other. That cost two red runs before the identifier existed.
    private func ledgerIDs() -> [String] {
        list.cells.allElementsBoundByIndex
            .map(\.identifier)
            .filter { $0.hasPrefix("ledger.") }
    }

    private func ledgerRow(_ id: String) -> XCUIElement? {
        let row = list.cells[id]
        return row.waitForExistence(timeout: 10) ? row : nil
    }
}
