import XCTest
@testable import FinchApp

final class CategoryDeleteImpactTests: XCTestCase {
    func test_leaf_with_no_transactions_returns_nil() {
        XCTAssertNil(deleteImpactMessage(txCount: 0, subcatCount: 0))
    }

    func test_transactions_only_plural() {
        XCTAssertEqual(deleteImpactMessage(txCount: 5, subcatCount: 0),
                       "5 transactions will become uncategorized")
    }

    func test_transactions_only_singular() {
        XCTAssertEqual(deleteImpactMessage(txCount: 1, subcatCount: 0),
                       "1 transaction will become uncategorized")
    }

    func test_subcategories_only_plural() {
        XCTAssertEqual(deleteImpactMessage(txCount: 0, subcatCount: 3),
                       "3 subcategories move to top level")
    }

    func test_subcategories_only_singular() {
        XCTAssertEqual(deleteImpactMessage(txCount: 0, subcatCount: 1),
                       "1 subcategory moves to top level")
    }

    func test_both_clauses_joined_with_middot() {
        XCTAssertEqual(deleteImpactMessage(txCount: 2, subcatCount: 1),
                       "2 transactions will become uncategorized · 1 subcategory moves to top level")
    }
}
