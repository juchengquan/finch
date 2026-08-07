import XCTest

/// Tapping a transaction's leading glyph flips pending ⇄ confirmed.
///
/// **Written BEFORE the swipe's status action was removed, and passing while it still
/// exists.** The swipe was the only status path any UI test drove; this one has to be
/// green first, or the removal trades a tested affordance for an untested one.
///
/// **Why a coordinate tap.** The control is deliberately NOT a `Button` — wrapping the
/// glyph in one silently dropped the KIND from every row's VoiceOver label
/// ("Expense, Groceries, …" became "Groceries, …"), because `children: .combine` does
/// not merge an interactive child's label. It is a `simultaneousGesture` on an
/// 18pt image in a 22pt box at the leading edge, so `app.buttons[…]` cannot find it and
/// a normalised x-offset is the honest way in. Kept small (6%) so it lands on the glyph
/// rather than the title beside it.
///
/// **Scope, against `TxRowTapTargetsUITests`.** That file guards the two tap targets on
/// the compact Activity feed — row body opens the editor, glyph confirms — and its
/// row-body case is the one that fails on the commit before the overlay fix. This file
/// covers what it does not: the OTHER direction (a confirmed row tapped back INTO the
/// pending bucket) on a DIFFERENT screen (the account detail).
///
/// A second test here originally asserted the glyph tap does not also open the editor.
/// It was removed: it passed on the build where row selection was broken outright, so
/// it never detected the defect it appeared to be about. `TxRowTapTargetsUITests` holds
/// that ground properly.
final class StatusGlyphTapUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetStore", "YES", "-disableNotifications", "YES",
                               "-uikitActivity", "YES", "-routeTo", "account:credit"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30), "app did not reach foreground")
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testTappingTheGlyphMovesARowIntoThePendingBucket() throws {
        let header = pendingHeader()
        XCTAssertNotNil(header, "no \"To confirm\" bucket — the seed has no pending rows")

        tapGlyphOfFirstConfirmedRow()

        let after = waitForChange(from: header) { self.pendingHeader() }
        XCTAssertNotEqual(after, header,
                          "header BEFORE: \(header ?? "nil") | AFTER: \(after ?? "nil") — tapping "
                          + "the glyph did not move the row into the pending bucket")
    }

    // MARK: Reading the screen

    private func pendingHeader() -> String? {
        let h = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@", "To confirm")).firstMatch
        guard h.waitForExistence(timeout: 20) else { return nil }
        return h.label
    }

    private func waitForChange(from before: String?, read: () -> String?) -> String? {
        let deadline = Date().addingTimeInterval(5)
        var now = read()
        while now == before && Date() < deadline {
            usleep(100_000)
            now = read()
        }
        return now
    }

    // MARK: Driving it

    /// Tap the leading glyph of the first row under the "Transactions" section — a
    /// CONFIRMED row, so the tap moves it INTO the bucket and the count rises.
    ///
    /// Moving a row in rather than out matters: with this seed a category can hold a
    /// single pending row, and confirming the last one empties the section, which
    /// removes it and its header entirely. That looks correct however the code behaves.
    private func tapGlyphOfFirstConfirmedRow() {
        // The account detail groups by MONTH — there is no "Transactions" section header
        // here, that one belongs to the category/tag screens. Anchor on the first month
        // header and take the row under it: the pending bucket is pinned above every
        // month, so that row is confirmed, and it sits mid-screen.
        //
        // NOT the last row. `isHittable` is true for the row at the bottom of the list,
        // but the floating tab bar overlaps it, so the tap lands on the tab bar and
        // nothing happens — silently, because the count simply does not change.
        let months = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", "^[A-Za-z]+ [0-9]{4}$")).allElementsBoundByIndex
        guard let month = months.min(by: { $0.frame.minY < $1.frame.minY }) else {
            return XCTFail("no month header on the account detail")
        }
        let rows = app.cells.allElementsBoundByIndex.filter(\.isHittable)
        guard let row = rows.first(where: { $0.frame.minY > month.frame.minY }) else {
            return XCTFail("no confirmed row under the first month header")
        }
        // 10.5% from the leading edge. MEASURED, not estimated: the glyph's tinted
        // pixels span 8.2%–13.0% of the screen width on this row, because the cell
        // spans the full width and the inset-grouped card sits inside it. A first
        // attempt at 6% — reasoning from "22pt glyph in a 390pt row" — landed in the
        // margin, and the row-does-not-open-the-editor assertion PASSED anyway, because
        // a tap that hits nothing opens no sheet either. A miss is silent here.
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.105, dy: 0.5)).tap()
    }
}
