import XCTest
@testable import FinchApp

/// Absolute month index ↔ date, the calendar pager's page identity.
///
/// The pager no longer keeps a −1/0/+1 window around the anchored month; every page
/// simply IS its month, named by this index, and neighbours are `±1`. That makes the
/// conversion load-bearing in a way it wasn't when the index was only used to force
/// a view rebuild: an off-by-one here shifts every page by a month, silently.
final class MonthCashCalendarIndexTests: XCTestCase {

    private func date(_ year: Int, _ month: Int) -> Date {
        var c = DateComponents(); c.year = year; c.month = month; c.day = 1
        return AppDate.civil.date(from: c)!
    }

    func test_indexIsContiguousAcrossAYearBoundary() {
        // The whole point of an absolute index: December → January is +1, not −11.
        let dec = MonthCashCalendar.monthIndex(date(2026, 12))
        let jan = MonthCashCalendar.monthIndex(date(2027, 1))
        XCTAssertEqual(jan - dec, 1)
    }

    func test_roundTripsEveryMonthOfASpanningRange() {
        // Two full years either side of a year boundary — catches a January or
        // December off-by-one that a single mid-year sample would miss.
        for year in 2025...2027 {
            for month in 1...12 {
                let start = date(year, month)
                let index = MonthCashCalendar.monthIndex(start)
                XCTAssertEqual(MonthCashCalendar.date(fromMonthIndex: index), start,
                               "\(year)-\(month) did not survive the round trip")
            }
        }
    }

    func test_steppingTheIndexStepsTheMonth() {
        let july = MonthCashCalendar.monthIndex(date(2026, 7))
        XCTAssertEqual(MonthCashCalendar.date(fromMonthIndex: july + 1), date(2026, 8))
        XCTAssertEqual(MonthCashCalendar.date(fromMonthIndex: july - 1), date(2026, 6))
    }

    func test_indexIsAnchoredToTheFirstOfTheMonth() {
        // The grid pages by month, so any day inside a month must name the same page.
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 23
        let midMonth = AppDate.civil.date(from: c)!
        XCTAssertEqual(MonthCashCalendar.monthIndex(midMonth),
                       MonthCashCalendar.monthIndex(date(2026, 7)))
        XCTAssertEqual(MonthCashCalendar.date(fromMonthIndex: MonthCashCalendar.monthIndex(midMonth)),
                       date(2026, 7))
    }
}
