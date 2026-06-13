import XCTest
@testable import FinchApp

/// Phase 4 — the pure saved-search upsert logic.
final class SavedSearchesTests: XCTestCase {
    func test_upsertAddsAndReplacesByName() {
        var list: [SavedSearch] = []
        list = SavedSearches.upsert(list, name: "Coffee", query: "starbucks")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.query, "starbucks")
        // same name → replaced, not duplicated
        list = SavedSearches.upsert(list, name: "Coffee", query: "blue bottle")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.query, "blue bottle")
        // different name → appended
        list = SavedSearches.upsert(list, name: "Rent", query: "landlord")
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(Set(list.map(\.name)), ["Coffee", "Rent"])
    }
}
