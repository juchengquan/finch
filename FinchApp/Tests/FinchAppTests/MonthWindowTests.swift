import XCTest
@testable import FinchApp

/// The month calendar's data window.
///
/// `MonthCashCalendar` draws the anchored month AND its neighbours, and asks its
/// caller for each page's totals separately — so a caller that expands only the
/// anchored month leaves the incoming page drawing bare day numbers under the
/// finger, with the figures appearing only after the swipe settles. That shipped:
/// `ScheduledCalendarView` had the window right and the UIKit port re-derived it a
/// month too narrow. Both now call these, so there is one definition to be right.
final class MonthWindowTests: XCTestCase {

    private func date(_ iso: String) -> Date {
        guard let d = AppDate.isoDay.date(from: iso) else {
            XCTFail("bad fixture date \(iso)"); return Date()
        }
        return d
    }

    // MARK: monthBounds

    func test_monthBounds_coversTheWholeMonth() {
        let (start, end) = MonthGrouping.monthBounds(date("2026-08-14"))
        XCTAssertEqual(start, "2026-08-01")
        XCTAssertEqual(end, "2026-08-31")
    }

    /// Any instant inside the month yields the same bounds — the first and last day
    /// included. An end-exclusive or off-by-one bound would drop a day's amounts from
    /// the grid's edge cells.
    func test_monthBounds_sameForEveryDayInTheMonth() {
        let expected = ("2026-08-01", "2026-08-31")
        for day in ["2026-08-01", "2026-08-02", "2026-08-30", "2026-08-31"] {
            let got = MonthGrouping.monthBounds(date(day))
            XCTAssertEqual(got.start, expected.0, "start wrong for \(day)")
            XCTAssertEqual(got.end, expected.1, "end wrong for \(day)")
        }
    }

    func test_monthBounds_shortMonths() {
        XCTAssertEqual(MonthGrouping.monthBounds(date("2026-09-15")).end, "2026-09-30")
        XCTAssertEqual(MonthGrouping.monthBounds(date("2026-02-10")).end, "2026-02-28")
    }

    /// 2028 is a leap year: February has to end on the 29th, not the 28th.
    func test_monthBounds_leapFebruary() {
        XCTAssertEqual(MonthGrouping.monthBounds(date("2028-02-10")).end, "2028-02-29")
    }

    // MARK: carouselWindow

    /// The whole point: one month either side of the anchor, so both neighbouring
    /// pages have data before the finger reaches them.
    func test_carouselWindow_spansPrevThroughNext() {
        let (start, end) = MonthGrouping.carouselWindow(date("2026-08-14"))
        XCTAssertEqual(start, "2026-07-01")
        XCTAssertEqual(end, "2026-09-30")
    }

    /// A window that stopped at the anchored month is the bug this guards.
    func test_carouselWindow_isStrictlyWiderThanTheAnchoredMonth() {
        let anchor = date("2026-08-14")
        let month = MonthGrouping.monthBounds(anchor)
        let wide = MonthGrouping.carouselWindow(anchor)
        XCTAssertLessThan(wide.start, month.start)
        XCTAssertGreaterThan(wide.end, month.end)
    }

    /// December rolls the year forward, January rolls it back — the two places a
    /// month ±1 computed by hand goes wrong.
    func test_carouselWindow_crossesTheYearBoundary() {
        let december = MonthGrouping.carouselWindow(date("2026-12-05"))
        XCTAssertEqual(december.start, "2026-11-01")
        XCTAssertEqual(december.end, "2027-01-31")

        let january = MonthGrouping.carouselWindow(date("2026-01-20"))
        XCTAssertEqual(january.start, "2025-12-01")
        XCTAssertEqual(january.end, "2026-02-28")   // 2026 is not a leap year
    }

    /// Landing on the 31st must not skid off a 30-day neighbour (a naive
    /// day-preserving shift from Mar 31 lands on "Feb 31" / "Apr 31").
    func test_carouselWindow_fromA31stWithShorterNeighbours() {
        let (start, end) = MonthGrouping.carouselWindow(date("2026-03-31"))
        XCTAssertEqual(start, "2026-02-01")
        XCTAssertEqual(end, "2026-04-30")
    }
}
