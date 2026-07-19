import XCTest
@testable import FinchApp

final class DecimalInputTests: XCTestCase {
    // MARK: filter — decimal
    func test_keeps_plain_decimal() {
        XCTAssertEqual(DecimalInput.filter("12.34", allowsDecimal: true), "12.34")
    }
    func test_strips_letters_and_symbols() {
        XCTAssertEqual(DecimalInput.filter("1a2b.3c", allowsDecimal: true), "12.3")
        XCTAssertEqual(DecimalInput.filter("$1 234", allowsDecimal: true), "1234")
    }
    func test_comma_is_rejected() {
        // "," is not a decimal separator — stripped like any stray character.
        XCTAssertEqual(DecimalInput.filter("1,5", allowsDecimal: true), "15")
        XCTAssertEqual(DecimalInput.filter("1,234.50", allowsDecimal: true), "1234.50")
        XCTAssertEqual(DecimalInput.filter("5.4,5.4,5", allowsDecimal: true), "5.4545")
    }
    func test_keeps_first_separator_drops_later() {
        // Once a "." is present, later separators are ignored (their digits stay).
        XCTAssertEqual(DecimalInput.filter("1.2.3", allowsDecimal: true), "1.23")
        XCTAssertEqual(DecimalInput.filter("5.4.", allowsDecimal: true), "5.4")
        XCTAssertEqual(DecimalInput.filter("5.4.4.4", allowsDecimal: true), "5.444")
    }
    func test_leading_minus_kept_midstring_dropped() {
        XCTAssertEqual(DecimalInput.filter("-5.5", allowsDecimal: true), "-5.5")
        XCTAssertEqual(DecimalInput.filter("5-3", allowsDecimal: true), "53")
        XCTAssertEqual(DecimalInput.filter("--5", allowsDecimal: true), "-5")
    }
    func test_intermediate_states_preserved() {
        XCTAssertEqual(DecimalInput.filter("-", allowsDecimal: true), "-")
        XCTAssertEqual(DecimalInput.filter(".", allowsDecimal: true), ".")
        XCTAssertEqual(DecimalInput.filter("", allowsDecimal: true), "")
    }
    // MARK: filter — integer
    func test_integer_strips_separators() {
        XCTAssertEqual(DecimalInput.filter("12.5", allowsDecimal: false), "125")
        XCTAssertEqual(DecimalInput.filter("1,2a3", allowsDecimal: false), "123")
        XCTAssertEqual(DecimalInput.filter("-7", allowsDecimal: false), "-7")
    }
    // MARK: parse — plain "." decimals
    func test_parse_plain_decimals() {
        XCTAssertEqual(DecimalInput.parse("1.5"), 1.5)
        XCTAssertEqual(DecimalInput.parse("-5"), -5)
        XCTAssertEqual(DecimalInput.parse("1000"), 1000)
    }
    func test_parse_empty_and_junk_nil() {
        XCTAssertNil(DecimalInput.parse(""))
        XCTAssertNil(DecimalInput.parse("abc"))
    }
}
