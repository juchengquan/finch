import XCTest
@testable import FinchApp

/// The privacy-mode day-cell decision: which presence dots a cell draws.
/// `MonthCashCalendar` is shared by Scheduled, Activity and Account detail,
/// so this one function is the guard for all three.
final class MonthCashCalendarMarksTests: XCTestCase {
    // Privacy OFF: the cell draws real amount lines, so it must never ask for
    // dots — not even on a busy day.
    func test_unmasked_isAlwaysEmpty() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 1850, expense: 42.10, masked: false), [])
        XCTAssertEqual(MonthCashCalendar.marks(income: 0, expense: 0, masked: false), [])
    }

    func test_masked_quietDayHasNoDots() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 0, expense: 0, masked: true), [])
    }

    func test_masked_incomeOnly() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 1850, expense: 0, masked: true), [.income])
    }

    func test_masked_expenseOnly() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 0, expense: 42.10, masked: true), [.expense])
    }

    // Order is fixed: income dot sits above the expense dot.
    func test_masked_bothKeepsIncomeFirst() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 1850, expense: 42.10, masked: true),
                       [.income, .expense])
    }

    // Presence ONLY. A one-cent day and a ten-thousand day must be
    // indistinguishable — magnitude is exactly what privacy mode hides.
    func test_masked_magnitudeNeverLeaks() {
        XCTAssertEqual(MonthCashCalendar.marks(income: 0.01, expense: 0, masked: true),
                       MonthCashCalendar.marks(income: 10_000, expense: 0, masked: true))
        XCTAssertEqual(MonthCashCalendar.marks(income: 0, expense: 0.01, masked: true),
                       MonthCashCalendar.marks(income: 0, expense: 10_000, masked: true))
    }
}
