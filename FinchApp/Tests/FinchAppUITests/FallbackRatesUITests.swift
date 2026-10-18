import XCTest

/// The 1.0 rates pre-#820 code saved by mistake: Currencies shows a notice only
/// while there are some, its review lists them with the entries each converted, and
/// they go only after a counted confirmation.
///
/// `-seedFallbackRates YES` writes them the old way (see
/// `FinchStore.seedPre820FallbackRatesForTesting`): KRW pinned at two dates with
/// one purchase each, THB pinned with none.
final class FallbackRatesUITests: XCTestCase {

    private var app: XCUIApplication!

    private func launch(seed: Bool) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-initialTab", "settings"]
        if seed { app.launchArguments += ["-seedFallbackRates", "YES"] }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    private func openCurrencies() {
        let row = app.cells.staticTexts["Currencies"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30), "Settings has no Currencies row")
        row.tap()
        XCTAssertTrue(app.staticTexts["Auto-update exchange rates"].waitForExistence(timeout: 10),
                      "never reached Currencies")
    }

    func testNoticeListsTheRatesAndRemovesThemOnlyAfterConfirming() throws {
        launch(seed: true)
        openCurrencies()

        let notice = app.staticTexts["3 rates were saved as 1:1 by mistake"]
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "no notice for the seeded 1:1 rates")
        notice.tap()

        XCTAssertTrue(app.staticTexts["2 entries were booked at 1:1"].waitForExistence(timeout: 10),
                      "the review does not count the entries booked 1:1")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label == %@", "1 entry")).count, 2,
                       "each KRW rate converted one purchase")
        XCTAssertTrue(app.staticTexts["Not used"].exists, "the THB rate converted nothing")

        // Opening the review removed nothing, and neither does dismissing the
        // confirmation. On iOS 26 it is a popover on the row with no Cancel button,
        // so it is dismissed by a tap outside it.
        app.cells["fallback-rates-remove"].tap()
        XCTAssertTrue(app.buttons["Remove 3 rates"].firstMatch.waitForExistence(timeout: 5),
                      "no confirmation before removing")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        XCTAssertTrue(app.staticTexts["Not used"].waitForExistence(timeout: 5), "dismissing removed the rates")

        app.cells["fallback-rates-remove"].tap()
        let confirm = app.buttons["Remove 3 rates"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "the confirmation does not name the count")
        confirm.tap()

        // Back on Currencies, with the notice gone.
        XCTAssertTrue(app.staticTexts["Auto-update exchange rates"].waitForExistence(timeout: 10),
                      "did not return to Currencies after removing")
        XCTAssertFalse(app.staticTexts["3 rates were saved as 1:1 by mistake"].exists,
                       "the notice outlived the rates")
    }

    func testNoNoticeWithoutSuspectRates() throws {
        launch(seed: false)
        openCurrencies()
        XCTAssertFalse(app.cells["fallback-rates-notice"].waitForExistence(timeout: 3),
                       "a notice with nothing to review")
    }
}
