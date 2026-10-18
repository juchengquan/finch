import XCTest

/// A transfer row does not carry the "part of one purchase" mark; a split purchase does.
///
/// The mark was shown on any row whose entry had more than one account leg, which is
/// also the shape of every transfer, so both halves of a transfer between your own
/// accounts showed it and VoiceOver read "Part of one purchase" on them.
/// `TransferIsNotASplitTests` pins the classification; this pins what VoiceOver reads.
final class TransferRowIsNotASplitUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Everyday holds both shapes in the demo seed: the Everyday → Savings transfer,
        // and the Costco split tender (credit card + Everyday), whose row's note reads
        // "Split across two accounts".
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-routeTo", "account:everyday"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// The row's one combined accessibility element (`TxRowCell`), found by a piece of
    /// its label, scrolling the list down until it is on screen.
    private func row(containing text: String) -> XCUIElement {
        let el = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
        let list = app.collectionViews.firstMatch
        for _ in 0..<12 where !(el.exists && el.isHittable) {
            list.swipeUp()
        }
        return el
    }

    func testATransferRowIsNotMarkedAsPartOfOnePurchase() throws {
        XCTAssertTrue(app.navigationBars["Everyday"].waitForExistence(timeout: 25),
                      "the deep link did not push the Everyday account")

        let split = row(containing: "Split across two accounts")
        XCTAssertTrue(split.exists, "no split-tender row on Everyday — the demo seed's Costco split moved")
        XCTAssertTrue(split.label.contains("Part of one purchase"),
                      "a genuine split purchase lost its mark: \(split.label)")

        let transfer = row(containing: "To Savings")
        XCTAssertTrue(transfer.exists, "no transfer row on Everyday — the demo seed's transfer moved")

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Everyday with a transfer row"
        shot.lifetime = .keepAlways
        add(shot)

        XCTAssertTrue(transfer.label.hasPrefix("Transfer"),
                      "the transfer row should open with its kind: \(transfer.label)")
        XCTAssertFalse(transfer.label.contains("Part of one purchase"),
                       "a transfer was read as part of one purchase: \(transfer.label)")
    }
}
