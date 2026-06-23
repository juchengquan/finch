import XCTest
import FinchCore
@testable import FinchApp

final class CategoryReorderTests: XCTestCase {
    private func cat(_ id: String, parent: String? = nil) -> CategoryRow {
        CategoryRow(id: id, ledgerId: "l1", name: id, parentId: parent, kind: "expense")
    }

    func test_reparent_appends_after_destinations_existing_children() {
        let rows = [cat("food"), cat("g1", parent: "food"), cat("home")]
        // move "home" under "food": food already has [g1] (1 child) → append at index 1
        XCTAssertEqual(CategoryReorder.reparent("home", under: "food", in: rows),
                       CategoryMove(id: "home", parentId: "food", sortOrder: 1))
    }

    func test_reparent_to_empty_parent_appends_at_zero() {
        let rows = [cat("food"), cat("home")]
        XCTAssertEqual(CategoryReorder.reparent("home", under: "food", in: rows),
                       CategoryMove(id: "home", parentId: "food", sortOrder: 0))
    }

    func test_reparent_to_top_level() {
        let rows = [cat("food"), cat("g1", parent: "food"), cat("g2", parent: "food")]
        // top level currently has [food] (1) → moving g1 to top appends at index 1
        XCTAssertEqual(CategoryReorder.reparent("g1", under: nil, in: rows),
                       CategoryMove(id: "g1", parentId: nil, sortOrder: 1))
    }

    func test_reparent_excludes_source_from_count() {
        // moving g1 under food when g1 is already a child of food: other children = [g2] → index 1
        let rows = [cat("food"), cat("g1", parent: "food"), cat("g2", parent: "food")]
        XCTAssertEqual(CategoryReorder.reparent("g1", under: "food", in: rows),
                       CategoryMove(id: "g1", parentId: "food", sortOrder: 1))
    }

    func test_reparent_onto_self_is_noop() {
        XCTAssertNil(CategoryReorder.reparent("food", under: "food", in: [cat("food")]))
    }
}
