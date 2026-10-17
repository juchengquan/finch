import XCTest

/// Activity's review queue, end to end on the shipping UIKit feed: the chip opens it,
/// a swipe ticks one row off, "Mark all reviewed" clears the rest, and the queue then
/// says it is clear.
///
/// The demo seed reviews nothing, so every settled row starts in the queue — well
/// over `ReviewQueue.confirmationThreshold`, which is why "Mark all" must ask first.
final class ReviewQueueUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-initialTab", "accounts"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testSwipeTicksOneOffAndMarkAllClearsTheQueue() throws {
        // Activity has no bar slot on iPhone — it is hosted inside Accounts.
        let all = app.staticTexts["All Transactions"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 30), "no All Transactions row on Accounts")
        all.tap()

        let chip = app.buttons["reviewQueueChip"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 30), "no review chip on the feed")
        chip.tap()

        let before = try XCTUnwrap(queueCount(), "no \"N to review\" bar after opening the queue")
        XCTAssertGreaterThan(before, 1, "the seed should leave several rows to review")

        // Full swipe right on the first row: Reviewed is the leading edge's outer action.
        let bar = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " to review")).firstMatch
        let row = try XCTUnwrap(app.cells.allElementsBoundByIndex.first { $0.frame.minY > bar.frame.maxY + 20 },
                                "no row under the review bar")
        row.swipeRight(velocity: .fast)
        // A fast swipe can stop short of a full swipe and leave the button showing.
        let reviewed = app.buttons["Reviewed"].firstMatch
        if reviewed.waitForExistence(timeout: 1) { reviewed.tap() }

        // The engine stamps the whole purchase, so a split row can take a sibling with
        // it — fewer, never the same.
        let deadline = Date().addingTimeInterval(5)
        var after = queueCount()
        while (after ?? before) >= before && Date() < deadline {
            usleep(100_000)
            after = queueCount()
        }
        XCTAssertLessThan(after ?? before, before, "the swiped row did not leave the queue")

        let markAll = app.buttons["markAllReviewed"].firstMatch
        XCTAssertTrue(markAll.waitForExistence(timeout: 5), "no Mark all reviewed")
        markAll.tap()
        // Many rows ⇒ a confirmation, which says how many.
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "Mark all on a long queue did not ask first")
        alert.buttons["Mark all reviewed"].tap()

        XCTAssertTrue(app.staticTexts["All caught up"].waitForExistence(timeout: 10),
                      "the cleared queue shows no empty state")
        XCTAssertNil(queueCount(), "the count bar outlived the queue")
    }

    /// The bar's number, or nil when it is not on screen.
    private func queueCount() -> Int? {
        let bar = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " to review")).firstMatch
        guard bar.waitForExistence(timeout: 2) else { return nil }
        return Int(bar.label.split(separator: " ").first ?? "")
    }
}
