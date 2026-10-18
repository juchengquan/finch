import XCTest

/// Entering an exchange rate by hand, end to end: Settings › Currencies › "+",
/// pick a currency with no rate, type it in either direction, save, and find it
/// again as an editable "manual" row in that currency's history.
///
/// This is the only way an offline user can book in a currency that has never had
/// a rate (`error.fx.noRate` refuses it), so the test drives the real screens rather
/// than the sheet alone. The arithmetic itself is pinned by `FxManualRateTests`.
final class ManualRateUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-initialTab", "settings"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testEnterARateByHandThenEditIt() throws {
        let currencies = app.staticTexts["Currencies"].firstMatch
        XCTAssertTrue(currencies.waitForExistence(timeout: 30), "Settings has no Currencies row")
        currencies.tap()

        let add = app.buttons["Add rate"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 10), "Currencies has no Add rate button")
        add.tap()

        // Pick KRW — a currency the demo data has no rate for.
        let currencyRow = app.buttons["manualRate.currency"].firstMatch
        XCTAssertTrue(currencyRow.waitForExistence(timeout: 10), "the rate sheet has no Currency row")
        currencyRow.tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the currency picker has no search field")
        search.tap()
        search.typeText("KRW")
        let krw = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'KRW'")).firstMatch
        XCTAssertTrue(krw.waitForExistence(timeout: 10), "KRW is not in the currency picker")
        krw.tap()

        // The question reads as a sentence against the ledger's base (USD here).
        let field = app.textFields["manualRate.rate"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no rate field after picking a currency")
        XCTAssertTrue(app.staticTexts["1 KRW ="].exists, "the rate row does not read '1 KRW = … USD'")
        field.tap()
        field.typeText("0.00073")
        // …and the footer reads it back the other way round.
        let inverse = app.staticTexts["manualRate.inverse"].firstMatch
        XCTAssertTrue(inverse.waitForExistence(timeout: 5))
        XCTAssertEqual(inverse.label, "1 USD = 1369.86 KRW")
        snapshot("add-rate")

        // Flipping keeps the meaning: the figure becomes its reciprocal.
        app.buttons["Swap direction"].firstMatch.tap()
        XCTAssertEqual(field.value as? String, "1369.86")
        XCTAssertTrue(app.staticTexts["1 USD ="].exists, "the flipped row does not read '1 USD = … KRW'")
        // The rounded reciprocal does not replace what was typed: the read-back (and
        // the save) still use 0.00073, not 1/1369.86 = 0.000730002.
        XCTAssertEqual(inverse.label, "1 KRW = 0.00073 USD")
        snapshot("add-rate-flipped")

        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(add.waitForExistence(timeout: 10), "the sheet did not close on save")

        // Find it in KRW's history, tagged manual.
        let listSearch = app.searchFields.firstMatch
        if !listSearch.exists { app.collectionViews.firstMatch.swipeDown() }
        XCTAssertTrue(listSearch.waitForExistence(timeout: 5), "Currencies has no search field")
        listSearch.tap()
        listSearch.typeText("KRW")
        let krwRow = app.cells.containing(NSPredicate(format: "label BEGINSWITH 'KRW'")).firstMatch
        XCTAssertTrue(krwRow.waitForExistence(timeout: 10), "KRW is not in the Currencies list")
        krwRow.tap()
        // `SourceBadge` speaks as "source manual".
        let manual = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'manual'")).firstMatch
        XCTAssertTrue(manual.waitForExistence(timeout: 10), "KRW's history has no manual row")
        snapshot("history")

        // A hand-entered row opens for editing, seeded with what was saved.
        manual.tap()
        let editField = app.textFields["manualRate.rate"].firstMatch
        XCTAssertTrue(editField.waitForExistence(timeout: 10), "the manual row did not open for editing")
        XCTAssertEqual(editField.value as? String, "0.00073")
        XCTAssertTrue(app.buttons["Delete Rate"].exists, "the edit sheet has no Delete Rate")
        snapshot("edit-rate")
    }
}
