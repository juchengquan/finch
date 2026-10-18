import XCTest

/// The 1.0 rates pre-#820 code saved by mistake: Currencies shows a notice only
/// while there are some, its review lists them with the entries each converted, and
/// they go only after a counted confirmation. The entries themselves are listed
/// from the review, and open in the Edit sheet.
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

        // The rates are gone, but the review stays on the entries booked with them:
        // once it closes, nothing else leads back to them.
        XCTAssertTrue(app.cells["fallback-rates-remove"].waitForNonExistence(timeout: 10),
                      "the rates outlived their removal")
        XCTAssertFalse(app.staticTexts["Not used"].exists, "a removed rate is still listed")
        XCTAssertTrue(app.staticTexts["2 entries were booked at 1:1"].exists,
                      "removing the rates lost the entries booked with them")

        // Back on Currencies, with the notice gone.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Auto-update exchange rates"].waitForExistence(timeout: 10),
                      "did not return to Currencies after removing")
        XCTAssertFalse(app.staticTexts["3 rates were saved as 1:1 by mistake"].exists,
                       "the notice outlived the rates")
    }

    /// The review leads to the entries it counts: a rate lists the ones it
    /// converted, the total lists them all, and each opens in the Edit sheet.
    func testTheCountedEntriesAreListedAndOpenForEditing() throws {
        launch(seed: true)
        openCurrencies()
        app.staticTexts["3 rates were saved as 1:1 by mistake"].firstMatch.tap()

        // One KRW rate → its one purchase.
        let oneEntry = app.staticTexts.matching(NSPredicate(format: "label == %@", "1 entry")).firstMatch
        XCTAssertTrue(oneEntry.waitForExistence(timeout: 10), "no rate row with its entry")
        oneEntry.tap()
        let purchase = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Seoul market"))
        XCTAssertTrue(purchase.firstMatch.waitForExistence(timeout: 10), "the rate does not list its entry")
        XCTAssertEqual(purchase.count, 1, "a rate lists only the entry it converted")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // The total → both, matching its count.
        let total = app.cells["fallback-rates-entries"]
        XCTAssertTrue(total.waitForExistence(timeout: 10), "no entries row")
        total.tap()
        XCTAssertTrue(app.navigationBars["Booked at 1:1"].waitForExistence(timeout: 10),
                      "the total does not open the list")
        XCTAssertTrue(purchase.firstMatch.waitForExistence(timeout: 10), "the list is empty")
        XCTAssertEqual(purchase.count, 2, "the list does not match \"2 entries were booked at 1:1\"")

        // Each opens in the ordinary Edit sheet, to be corrected.
        purchase.firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "edittx.category").firstMatch
                        .waitForExistence(timeout: 10),
                      "an entry does not open in the Edit sheet")
    }

    func testNoNoticeWithoutSuspectRates() throws {
        launch(seed: false)
        openCurrencies()
        XCTAssertFalse(app.cells["fallback-rates-notice"].waitForExistence(timeout: 3),
                       "a notice with nothing to review")
    }
}
