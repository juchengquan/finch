import XCTest
@testable import FinchApp

final class SplitSummaryTests: XCTestCase {
    func test_single_or_zero_is_nil() {
        XCTAssertNil(splitSummaryText(count: 0))
        XCTAssertNil(splitSummaryText(count: 1))
    }
    func test_two_or_more_summarizes() {
        XCTAssertEqual(splitSummaryText(count: 2), "Split across 2 categories")
        XCTAssertEqual(splitSummaryText(count: 3), "Split across 3 categories")
    }
}
