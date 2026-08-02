import XCTest

/// Confirming a pending row must move the row AND update the headers that count it.
///
/// Reported from a device as "the animation looks ugly" (#702). Four attempts missed,
/// because the visible defect was never the row's motion: the row relocated, and the
/// figures describing it — the pending bucket's count, the month's income/spent —
/// changed afterwards, in the snapshot apply's completion handler.
///
/// This guards the CORRECTNESS half of that, which is what a UI test can see. It
/// cannot see the timing half: XCUITest waits for quiescence, which is precisely the
/// state in which a late header has already caught up. The timing is verified by
/// frame analysis of a screen recording, and only that way — see #702 for the method
/// and for the four occasions sampling agreed with a claim that was false.
///
/// What it would have caught outright: `TxListDetailVC` shipped a `To confirm (N)`
/// header with no refresh at all, so its count was not late but wrong until the
/// header happened to be re-created by scrolling.
///
/// The assertions are "the text changed" rather than computed figures, so the test is
/// not a hostage to the demo seed's contents.
final class ConfirmHeaderFollowsRowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // `-uikitActivity YES` is the shipping default; naming it keeps the test
        // honest if the flag is ever flipped for an experiment.
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testConfirmUpdatesPendingCountAndMonthFigures() throws {
        openActivity()

        let bucketBefore = pendingBucketText()
        XCTAssertNotNil(bucketBefore,
                        "no \"To confirm\" bucket — the seed has no pending rows, so this test proves nothing")
        let monthBefore = monthCaptions()
        XCTAssertFalse(monthBefore.isEmpty, "no month header on screen — is the list grouped by month?")

        confirmFirstPendingRow()

        // The pending count is the tighter assertion of the two: it is a pure function
        // of the rows in the bucket the swipe emptied by one.
        let bucketAfter = waitForChange(from: bucketBefore, read: pendingBucketText)
        XCTAssertNotEqual(bucketAfter, bucketBefore,
                          "pending bucket BEFORE: \(bucketBefore ?? "nil") | AFTER: \(bucketAfter ?? "nil") " +
                          "— a row left the bucket and the count did not follow")

        let monthAfter = waitForChange(from: monthBefore, read: monthCaptions)
        XCTAssertNotEqual(monthAfter, monthBefore,
                          "month headers BEFORE: \(monthBefore) | AFTER: \(monthAfter) " +
                          "— a row moved into a month and that month's income/spent did not follow")
    }

    // MARK: Reading the screen

    /// "To confirm (N)" — the pending section's header.
    private func pendingBucketText() -> String? {
        let bucket = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "To confirm")).firstMatch
        guard bucket.waitForExistence(timeout: 20) else { return nil }
        return bucket.label
    }

    /// EVERY month header's "Income … · Spent …" caption, in screen order. Matched on
    /// "Spent" because the month label itself is a sibling static text.
    ///
    /// All of them, not the first: a pending row is only a few days old, so near the
    /// turn of a month it confirms into the month BELOW the one at the top of the
    /// screen. Reading `firstMatch` made this test fail on 2 August against a build
    /// that was working — the August header was correctly unchanged while July's
    /// figures moved.
    private func monthCaptions() -> [String] {
        let captions = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Spent"))
        guard captions.firstMatch.waitForExistence(timeout: 15) else { return [] }
        return captions.allElementsBoundByIndex.map(\.label)
    }

    /// Poll briefly rather than assert immediately: a flaky failure here would be
    /// indistinguishable from the defect, and the write is one runloop hop away by
    /// design (`@Published` fires in `willSet`, so the VCs subscribe via
    /// `.receive(on: .main)`).
    private func waitForChange<T: Equatable>(from before: T, read: () -> T) -> T {
        let deadline = Date().addingTimeInterval(5)
        var now = read()
        while now == before && Date() < deadline {
            usleep(100_000)
            now = read()
        }
        return now
    }

    // MARK: Driving it

    /// There is no Activity TAB — the tab bar is Accounts / Budgets / Scheduled /
    /// Insights / Settings. The feed is reached through "All Transactions" on the
    /// Accounts landing, which pushes `ActivityFeedVC`.
    private func openActivity() {
        let entry = app.buttons["All Transactions"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 30), "no All Transactions entry on Accounts")
        entry.tap()
    }

    private func confirmFirstPendingRow() {
        let bucket = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "To confirm")).firstMatch
        XCTAssertTrue(bucket.waitForExistence(timeout: 20), "no \"To confirm\" bucket")

        // The first cell BELOW the bucket header is a pending row. Cells are used
        // rather than a label lookup because merchant names are seed-dependent.
        let rows = app.cells.allElementsBoundByIndex
        guard let row = rows.first(where: { $0.frame.minY > bucket.frame.minY }) else {
            return XCTFail("no row under the \"To confirm\" header")
        }
        row.swipeLeft()
        let confirm = app.buttons["Confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "no Confirm swipe action")
        confirm.tap()
    }
}
