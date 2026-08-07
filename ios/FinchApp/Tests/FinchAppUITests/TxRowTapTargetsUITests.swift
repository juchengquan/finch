import XCTest

/// The two tap targets a transaction row carries since the glyph became the
/// pending⇄confirmed control (#19f1d32a): the GLYPH toggles status, the row BODY
/// opens the editor (compact) or selects (iPad column).
///
/// This file exists because neither target had automated coverage, and the gap was
/// expensive: the glyph's first implementation — a `simultaneousGesture` on hosted
/// cell content — silently broke UICollectionView selection in the iPad Activity
/// column, shipped through three cancelled post-merge runs, and surfaced as the
/// first post-merge red (#744). `SplitMechanicsUITests` guards the iPad half; these
/// two guard the compact half so a future glyph redesign cannot break either tap
/// target unnoticed.
final class TxRowTapTargetsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
        try XCTSkipUnless(app.windows.firstMatch.frame.width < 700,
                          "compact-only: the iPad column half lives in SplitMechanicsUITests")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Tapping a row anywhere OUTSIDE the glyph opens the edit sheet. This is the
    /// tap the feed has always had — and the one nothing asserted while the glyph
    /// work rewired the row's touch handling.
    func testTappingTheRowBodyOpensTheEditor() throws {
        openActivityFeed()
        guard let row = firstTransactionRow() else {
            return XCTFail("no transaction rows in the feed")
        }
        // Right-of-center: far from the glyph column at the leading edge.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10)
                        || app.navigationBars["Edit Transaction"].waitForExistence(timeout: 2),
                      "tapping the row body did not open the editor — the glyph control " +
                      "is stealing the row's tap")
        // Leave the app where the next test expects it.
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
    }

    /// Tapping the GLYPH (leading edge) of a pending row confirms it: the
    /// "To confirm (N)" header must drop by one. The glyph column is ~16-48pt from
    /// the row's leading edge; dx 0.08 of a compact row lands inside it.
    func testTappingTheGlyphConfirmsAPendingRow() throws {
        openActivityFeed()
        guard let before = pendingCount() else {
            return XCTFail("no 'To confirm' header — the demo seed should provide pending rows")
        }
        guard let row = firstPendingRow() else {
            return XCTFail("a 'To confirm' header with no row under it")
        }
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()

        let deadline = Date().addingTimeInterval(5)
        var after = pendingCount()
        while after == before && Date() < deadline {
            usleep(100_000)
            after = pendingCount()
        }
        // The bucket may vanish entirely when its last row confirms — nil is a pass.
        XCTAssertTrue(after == nil || after == before - 1,
                      "tapped the glyph of a pending row; 'To confirm' went \(before) → " +
                      "\(after.map(String.init) ?? "nil") instead of \(before - 1)")
    }

    // MARK: Reaching the feed (compact: Accounts → All Transactions)

    private func openActivityFeed() {
        let accounts = app.buttons["Accounts"]
        if accounts.waitForExistence(timeout: 10) { accounts.tap() }
        let all = app.cells.staticTexts["All Transactions"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 15), "Accounts has no All Transactions row")
        all.tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 15),
                      "All Transactions did not push the Activity feed")
    }

    // MARK: Reading the screen

    private func pendingCount() -> Int? {
        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "To confirm")).firstMatch
        guard header.exists,
              let open = header.label.firstIndex(of: "("),
              let close = header.label.firstIndex(of: ")") else { return nil }
        return Int(header.label[header.label.index(after: open)..<close])
    }

    /// The first row UNDER the "To confirm" header — pending rows pin to the top,
    /// so this is the first transaction cell below that header's frame.
    private func firstPendingRow() -> XCUIElement? {
        let header = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "To confirm")).firstMatch
        guard header.exists else { return nil }
        return app.cells.allElementsBoundByIndex.first {
            $0.frame.minY >= header.frame.maxY && $0.frame.height > 30
        }
    }

    /// Any transaction cell — identified by an amount ($) somewhere in its
    /// descendants, which the mode picker / saved-search / calendar cells never
    /// carry. Two traps found the hard way, kept so nobody re-walks into them:
    /// a height/position filter matched the 52pt List|Calendar picker cell and
    /// "tapped a row" straight into calendar mode; and matching the CELL's own
    /// label finds nothing — the combined label lives on the hosted TxRow element
    /// INSIDE the cell, so it takes `containing(_:)`, not `matching(_:)`.
    private func firstTransactionRow() -> XCUIElement? {
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS %@", "$")).firstMatch
        return row.waitForExistence(timeout: 10) ? row : nil
    }
}
