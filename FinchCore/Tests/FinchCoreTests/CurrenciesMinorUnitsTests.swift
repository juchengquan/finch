import XCTest
@testable import FinchCore

/// ISO 4217 minor units — the per-currency fraction-digit table behind amount
/// input regulation and native formatting. The table is checked in (never read
/// from platform ICU data, which drifts by OS version) and mirrored on the web
/// side; the fixture test pins the two mirrors together.
final class CurrenciesMinorUnitsTests: XCTestCase {

    func test_zero_decimal_currencies() {
        for code in ["JPY", "KRW", "VND", "CLP", "ISK", "UGX", "XOF"] {
            XCTAssertEqual(Currencies.minorUnits(for: code), 0, "\(code) is a 0-decimal currency")
        }
    }

    func test_three_decimal_currencies() {
        for code in ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"] {
            XCTAssertEqual(Currencies.minorUnits(for: code), 3, "\(code) is a 3-decimal dinar/rial")
        }
    }

    func test_default_is_two() {
        XCTAssertEqual(Currencies.minorUnits(for: "USD"), 2)
        XCTAssertEqual(Currencies.minorUnits(for: "EUR"), 2)
        // Unknown codes take the ISO default rather than crashing or hiding digits.
        XCTAssertEqual(Currencies.minorUnits(for: "ZZZ"), 2)
    }

    func test_every_exception_is_a_known_iso_code() {
        let iso = Set(Currencies.iso)
        for code in Currencies.minorUnitExceptions.keys {
            XCTAssertTrue(iso.contains(code), "\(code) is in the exceptions table but not in Currencies.iso")
        }
    }

    // The web-fixture comparison lives in ParityTests/CurrencyParityTests.swift —
    // FinchCoreTests has no resource bundle, and it IS a parity gate anyway.

    // MARK: Money.format follows the table (display half of the feature)

    func test_format_zero_decimal_fallback_shows_no_cents() {
        XCTAssertEqual(Money.format(1234, currency: "KRW"), "KRW 1,234")
    }

    func test_format_three_decimal_fallback_keeps_the_third_digit() {
        XCTAssertEqual(Money.format(1.234, currency: "BHD"), "BHD 1.234")
    }

    func test_format_known_symbols_unchanged() {
        XCTAssertEqual(Money.format(1234.5, currency: "USD"), "$1,234.50")
        XCTAssertEqual(Money.format(1234, currency: "JPY"), "¥1,234")
    }
}
