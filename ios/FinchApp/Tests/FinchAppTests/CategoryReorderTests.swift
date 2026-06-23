import XCTest
import FinchCore
@testable import FinchApp

final class CategoryReorderTests: XCTestCase {
    private func cat(_ id: String, parent: String? = nil, sortOrder: Int = 0) -> CategoryRow {
        CategoryRow(id: id, ledgerId: "l1", name: id, parentId: parent, kind: "expense", sortOrder: sortOrder)
    }

    func test_reparent_appends_after_destinations_existing_children() {
        // food's children have sparse sort_orders (3, 7); max+1 = 8, NOT count (2)
        let rows = [cat("food"), cat("g1", parent: "food", sortOrder: 3),
                    cat("g2", parent: "food", sortOrder: 7), cat("home", sortOrder: 12)]
        XCTAssertEqual(CategoryReorder.reparent("home", under: "food", in: rows),
                       CategoryMove(id: "home", parentId: "food", sortOrder: 8))
    }

    func test_reparent_to_empty_parent_appends_at_zero() {
        let rows = [cat("food", sortOrder: 5), cat("home", sortOrder: 10)]
        XCTAssertEqual(CategoryReorder.reparent("home", under: "food", in: rows),
                       CategoryMove(id: "home", parentId: "food", sortOrder: 0))
    }

    func test_reparent_to_top_level() {
        // top level has [food] at sortOrder 5; moving g1 to top → max+1 = 6, NOT count (1)
        let rows = [cat("food", sortOrder: 5), cat("g1", parent: "food", sortOrder: 2),
                    cat("g2", parent: "food", sortOrder: 4)]
        XCTAssertEqual(CategoryReorder.reparent("g1", under: nil, in: rows),
                       CategoryMove(id: "g1", parentId: nil, sortOrder: 6))
    }

    func test_reparent_excludes_source_from_count() {
        // g1 (sortOrder 3) already under food alongside g2 (sortOrder 9); excluding g1 → max+1 = 10, NOT count (2)
        let rows = [cat("food", sortOrder: 1), cat("g1", parent: "food", sortOrder: 3),
                    cat("g2", parent: "food", sortOrder: 9)]
        XCTAssertEqual(CategoryReorder.reparent("g1", under: "food", in: rows),
                       CategoryMove(id: "g1", parentId: "food", sortOrder: 10))
    }

    func test_reparent_onto_self_is_noop() {
        XCTAssertNil(CategoryReorder.reparent("food", under: "food", in: [cat("food")]))
    }
}
