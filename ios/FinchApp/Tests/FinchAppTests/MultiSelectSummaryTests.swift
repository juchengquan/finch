import XCTest
@testable import FinchApp

final class MultiSelectSummaryTests: XCTestCase {
    func test_empty_uses_label() {
        XCTAssertEqual(multiSelectSummary(names: [], emptyLabel: "All accounts"), "All accounts")
    }
    func test_one_name() {
        XCTAssertEqual(multiSelectSummary(names: ["Checking"], emptyLabel: "All accounts"), "Checking")
    }
    func test_several_joined() {
        XCTAssertEqual(multiSelectSummary(names: ["Groceries", "Dining"], emptyLabel: "All categories"), "Groceries, Dining")
    }
}
