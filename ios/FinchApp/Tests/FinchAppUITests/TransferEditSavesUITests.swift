import XCTest

/// Editing a plain transfer saves from the first page.
///
/// A transfer is one entry with two account legs — the shape of a purchase paid
/// from two cards, if all you count is legs. The Edit sheet counted legs, so a
/// transfer opened as a split purchase: Save read "Next" and led to an
/// allocation page stuck at "Allocated $0.00 / $500.00" that could never
/// balance, so the transfer could not be saved at all. `TransferIsNotASplitTests`
/// pins the classification; this pins what the user actually meets.
final class TransferEditSavesUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // The demo seed posts one transfer, Everyday → Savings, and Savings holds
        // nothing else that reads as one.
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-routeTo", "account:savings"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testEditingATransferSavesWithACheckmark() throws {
        let row = app.cells.containing(NSPredicate(format: "label CONTAINS[c] %@", "Transfer")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20),
                      "no transfer row on Savings — the demo seed's transfer moved")
        // Right-of-center: the leading glyph toggles status instead of opening.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)).tap()

        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "tapping the transfer did not open the editor")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Edit transfer"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertFalse(app.buttons["Next"].exists,
                       "a transfer offered Next — it was classified as a split purchase")
        let save = app.buttons["Save"]
        XCTAssertTrue(save.exists, "the transfer editor has no Save button")
        save.tap()

        XCTAssertTrue(cancel.waitForNonExistence(timeout: 10),
                      "Save did not close the sheet")
    }
}
