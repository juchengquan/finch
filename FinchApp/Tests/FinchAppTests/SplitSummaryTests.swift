import XCTest
@testable import FinchApp

final class SplitSummaryTests: XCTestCase {
    func test_single_or_zero_is_nil() {
        XCTAssertNil(splitSummaryText(names: []))
        XCTAssertNil(splitSummaryText(names: ["Food"]))
    }
    func test_two_or_more_joins_names() {
        XCTAssertEqual(splitSummaryText(names: ["Groceries", "Household"]), "Groceries, Household")
        XCTAssertEqual(splitSummaryText(names: ["A", "B", "C"]), "A, B, C")
    }
    // The account picker's row summary reuses this same helper — proving it's
    // genuinely axis-agnostic rather than secretly category-shaped.
    func test_two_or_more_joins_account_names() {
        XCTAssertEqual(splitSummaryText(names: ["Checking", "Savings"]), "Checking, Savings")
    }
}
