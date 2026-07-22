import XCTest
@testable import FinchCore

/// Money.format moved to cached NumberFormatters (one per fraction-digit
/// count) — these pin the output so the cache can never drift from the
/// per-call formatter it replaced (mirrors `fmtNative`).
final class MoneyFormatTests: XCTestCase {

    func test_format_grouping_and_symbols() {
        XCTAssertEqual(Money.format(1234.5, currency: "USD"), "$1,234.50")
        XCTAssertEqual(Money.format(1234.5, currency: "SGD"), "S$1,234.50")
        XCTAssertEqual(Money.format(0, currency: "EUR"), "€0.00")
        // JPY formats with 0 decimals (NumberFormatter's half-even rounding,
        // same as the pre-cache per-call formatter).
        XCTAssertEqual(Money.format(1234.5, currency: "JPY"), "¥1,234")
        XCTAssertEqual(Money.format(1235.5, currency: "JPY"), "¥1,236")
        // Unknown currency → "CODE " prefix + 2 dp.
        XCTAssertEqual(Money.format(9.9, currency: "XXX"), "XXX 9.90")
    }

    func test_format_signs() {
        // Negative uses U+2212, positive is bare unless signed:.
        XCTAssertEqual(Money.format(-42, currency: "USD"), "\u{2212}$42.00")
        XCTAssertEqual(Money.format(42, currency: "USD", signed: true), "+$42.00")
    }

    func test_format_repeated_calls_are_stable() {
        // The cache returns the same formatter across calls — outputs must not
        // drift between the first (cache-miss) and later (cache-hit) calls.
        let first = Money.format(9876543.21, currency: "USD")
        for _ in 0..<100 {
            XCTAssertEqual(Money.format(9876543.21, currency: "USD"), first)
        }
        XCTAssertEqual(first, "$9,876,543.21")
    }
}
