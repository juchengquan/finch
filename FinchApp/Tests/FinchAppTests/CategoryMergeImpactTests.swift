import XCTest
@testable import FinchApp

final class CategoryMergeImpactTests: XCTestCase {
    func test_zero_returns_nil() {
        XCTAssertNil(mergeImpactMessage(txCount: 0))
    }
    func test_one_is_singular() {
        XCTAssertEqual(mergeImpactMessage(txCount: 1), "1 transaction will be combined")
    }
    func test_many_is_plural() {
        XCTAssertEqual(mergeImpactMessage(txCount: 8), "8 transactions will be combined")
    }
}
