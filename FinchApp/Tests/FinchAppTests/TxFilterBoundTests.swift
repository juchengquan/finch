import XCTest
@testable import FinchApp

/// Switching on the filter's From bound must not hide rows from earlier that day.
final class TxFilterBoundTests: XCTestCase {

    func test_aNewBoundTakesTheWholeDay() {
        let afternoon = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 14, minute: 37))!
        var f = TxFilter()
        f.from = TransactionFilterSheet.unsetBound(now: afternoon)
        f.to = TransactionFilterSheet.unsetBound(now: afternoon)
        XCTAssertEqual(f.fromYMD, "2026-11-24", "a bare date, not 2026-11-24 14:37")
        XCTAssertEqual(f.toYMD, "2026-11-24")
    }
}
