import XCTest
@testable import FinchApp
import FinchCore

/// Pure grouping/derivation helpers behind the Exchange rates pages.
final class FxDeriveTests: XCTestCase {
    private let rates = [
        ExchangeRate(date: "2026-07-16", currency: "EUR", rate: 1.14, source: "ECB"),
        ExchangeRate(date: "2026-07-17", currency: "EUR", rate: 1.15, source: "ECB"),
        ExchangeRate(date: "2026-07-17", currency: "CAD", rate: 0.71, source: nil),
        ExchangeRate(date: "2026-07-15", currency: "EUR", rate: 1.13, source: "manual"),
    ]

    func test_currencies_sortedDeduped() {
        XCTAssertEqual(fxCurrencies(rates), ["CAD", "EUR"])
        XCTAssertEqual(fxCurrencies([]), [])
    }

    func test_latest_picksMaxDate_nilWhenAbsent() {
        XCTAssertEqual(fxLatest(rates, "EUR")?.rate, 1.15)
        XCTAssertEqual(fxLatest(rates, "CAD")?.rate, 0.71)
        XCTAssertNil(fxLatest(rates, "JPY"))
    }

    func test_latest_equalDates_laterRowInListOrderWins() {
        let dup = rates + [ExchangeRate(date: "2026-07-17", currency: "EUR", rate: 9.99, source: "manual")]
        XCTAssertEqual(fxLatest(dup, "EUR")?.rate, 9.99)
    }

    func test_series_dateAscending() {
        XCTAssertEqual(fxSeries(rates, "EUR"), [1.13, 1.14, 1.15])
        XCTAssertEqual(fxSeries(rates, "JPY"), [])
    }

    func test_displayDay_formats_andFallsBack() {
        // en_US-style abbreviated month-day; assert on components to stay locale-tolerant.
        let s = fxDisplayDay("2026-07-17")
        XCTAssertTrue(s.contains("17"))
        XCTAssertFalse(s.contains("2026"))
        XCTAssertTrue(fxDisplayDay("2026-07-17", withYear: true).contains("2026"))
        XCTAssertEqual(fxDisplayDay("garbage"), "garbage")
    }

    func test_effectiveTracked_absentFallsBack_emptyIsRespected() {
        XCTAssertEqual(fxEffectiveTracked(stored: nil, fallback: ["CAD", "EUR"]), ["CAD", "EUR"])
        XCTAssertEqual(fxEffectiveTracked(stored: [], fallback: ["CAD", "EUR"]), [])   // user untracked everything
        XCTAssertEqual(fxEffectiveTracked(stored: ["JPY"], fallback: ["CAD", "EUR"]), ["JPY"])
    }
}
