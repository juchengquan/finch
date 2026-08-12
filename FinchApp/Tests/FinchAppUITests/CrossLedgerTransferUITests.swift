import XCTest

/// The visible half of cross-ledger transfers (2026-08-12 design, D6): a
/// transfer's To picker offers accounts from OTHER books, grouped under each
/// ledger's name.
///
/// This is the only place the app deliberately looks outside the active ledger —
/// the store projects one ledger at a time — so it's worth a guard: if that read
/// ever regresses, the picker silently shows only this ledger's accounts and the
/// whole feature becomes unreachable without anything failing.
final class CrossLedgerTransferUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The simulator demo seed carries a second, EUR "Travel" ledger — which is
        // what makes a cross-ledger transfer expressible at all.
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES", "-openAdd", "YES"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testTransferToPickerOffersOtherLedgersAccounts() throws {
        // The type control is a segmented Picker of icons; each segment carries an
        // accessibilityLabel, which is how it's addressable at all.
        let transfer = app.buttons["Transfer"].firstMatch
        XCTAssertTrue(transfer.waitForExistence(timeout: 15), "no Transfer segment in the type control")
        transfer.tap()

        let toRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'To'")).firstMatch
        XCTAssertTrue(toRow.waitForExistence(timeout: 10), "transfer mode has no To row")
        toRow.tap()

        // The active ledger's own accounts are still there…
        XCTAssertTrue(app.buttons["picker.option.checking"].waitForExistence(timeout: 10),
                      "the To picker lost this ledger's accounts")
        // …and the other book appears under its own heading.
        XCTAssertTrue(app.staticTexts["Travel"].firstMatch.waitForExistence(timeout: 5),
                      "no 'Travel' section — the picker is not reading outside the active ledger")
    }
}
