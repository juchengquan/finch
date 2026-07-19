import XCTest
@testable import FinchApp

final class SplitSummaryTests: XCTestCase {
    func test_single_or_zero_is_nil() {
        XCTAssertNil(splitSummaryText(categoryNames: []))
        XCTAssertNil(splitSummaryText(categoryNames: ["Food"]))
    }
    func test_two_or_more_joins_names() {
        XCTAssertEqual(splitSummaryText(categoryNames: ["Groceries", "Household"]), "Groceries, Household")
        XCTAssertEqual(splitSummaryText(categoryNames: ["A", "B", "C"]), "A, B, C")
    }
}
