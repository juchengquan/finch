import XCTest

/// A "To confirm (N)" header must follow the rows underneath it.
///
/// `TxListDetailVC` — the Category / Tag / Counterparty screens — built that header and
/// then applied its snapshot with no completion and no header refresh at all. A
/// diffable data source does not re-render a supplementary view when only the section's
/// ITEMS change, so the number did not lag, it was WRONG: it kept the old value until
/// the header happened to be re-created by scrolling. The feed and the account detail
/// already refreshed theirs; this screen was simply missed. See #702.
///
/// **Why the flow is "set pending" rather than "confirm".** With the demo seed each
/// category holds exactly one pending row, so confirming it empties the bucket and
/// diffable removes the whole section — taking the header with it, which looks correct
/// either way and proves nothing. The stale count only shows while the section
/// SURVIVES. Going 1 → 2 keeps it alive and is a single swipe.
final class PendingCountFollowsRowsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
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

    func testPendingCountUpdatesWhenARowJoinsTheBucket() throws {
        openGroceriesCategory()

        let before = pendingHeader()
        XCTAssertEqual(before, "To confirm (1)",
                       "expected the seed's single pending Groceries row; got \(before ?? "no header")")

        setFirstConfirmedRowPending()

        // Poll: the write is one runloop hop away by design — `txns` is `@Published`,
        // so the VC subscribes via `.receive(on: .main)`.
        let deadline = Date().addingTimeInterval(5)
        var after = pendingHeader()
        while after == before && Date() < deadline {
            usleep(100_000)
            after = pendingHeader()
        }

        XCTAssertEqual(after, "To confirm (2)",
                       "header BEFORE: \(before ?? "nil") | AFTER: \(after ?? "nil") — a row joined " +
                       "the bucket and the count did not follow")
    }

    // MARK: Reading the screen

    private func pendingHeader() -> String? {
        let header = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "To confirm")).firstMatch
        guard header.waitForExistence(timeout: 15) else { return nil }
        return header.label
    }

    // MARK: Driving it

    /// Settings → Categories → Groceries. Categories is a ledger-admin screen, reached
    /// from Settings rather than a tab of its own.
    private func openGroceriesCategory() {
        let settings = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30), "no Settings tab")
        settings.tap()

        let categories = app.buttons["Categories"].firstMatch
        XCTAssertTrue(categories.waitForExistence(timeout: 15), "no Categories row in Settings")
        categories.tap()

        let groceries = app.staticTexts["Groceries"].firstMatch
        XCTAssertTrue(groceries.waitForExistence(timeout: 15), "no Groceries category")
        groceries.tap()
    }

    /// Swipe a row in the "Transactions" section and tap "Set pending", moving it into
    /// the bucket so the count has to change while the section survives.
    private func setFirstConfirmedRowPending() {
        // TWO things on this screen say "Transactions": the summary row at the top
        // ("Transactions  37") and the section header below the pending bucket. Taking
        // firstMatch grabs the summary row, and swiping a value row reveals no actions
        // at all — which is how the first version of this test failed. Take the LOWEST
        // one on screen, which is the section header.
        let labelled = app.staticTexts.matching(identifier: "Transactions").allElementsBoundByIndex
        guard let header = labelled.max(by: { $0.frame.minY < $1.frame.minY }) else {
            return XCTFail("no Transactions section header")
        }

        // The first cell below that header is a confirmed row. Cells rather than a
        // label lookup, because merchant names are seed-dependent.
        let rows = app.cells.allElementsBoundByIndex
        guard let row = rows.first(where: { $0.frame.minY > header.frame.minY }) else {
            return XCTFail("no row under the Transactions header")
        }
        row.swipeLeft()

        let setPending = app.buttons["Set pending"].firstMatch
        XCTAssertTrue(setPending.waitForExistence(timeout: 10), "no Set pending swipe action")
        setPending.tap()
    }
}
