import XCTest
import FinchCore
@testable import FinchApp

final class CategoryForestTests: XCTestCase {
    private func cat(_ id: String, _ name: String, parent: String? = nil,
                     icon: String? = nil, color: String? = nil) -> CategoryRow {
        CategoryRow(id: id, ledgerId: "l1", name: name, parentId: parent, kind: "expense", icon: icon, color: color)
    }

    func test_builds_three_levels_preserving_order() {
        let rows = [cat("food", "Food"), cat("groc", "Groceries", parent: "food"),
                    cat("organic", "Organic", parent: "groc"), cat("home", "Home")]
        let forest = categoryForest(rows)
        XCTAssertEqual(forest.map(\.id), ["food", "home"])
        XCTAssertEqual(forest[0].children.map(\.id), ["groc"])
        XCTAssertEqual(forest[0].children[0].children.map(\.id), ["organic"])
    }

    func test_orphan_is_promoted_to_top() {
        let rows = [cat("a", "A", parent: "missing")]
        XCTAssertEqual(categoryForest(rows).map(\.id), ["a"])
    }

    func test_effective_color_inherits_then_defaults() {
        let rows = [cat("p", "P", color: "#31a773"), cat("c", "C", parent: "p")]
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(effectiveColor(rows[1], byId), "#31a773")           // inherited
        XCTAssertEqual(effectiveColor(cat("x", "X"), [:]), CategoryPalette.defaultHex)  // default
    }

    func test_effective_icon_inherits() {
        let rows = [cat("p", "P", icon: "fork"), cat("c", "C", parent: "p")]
        let byId = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertEqual(effectiveIcon(rows[1], byId), "fork")
        XCTAssertNil(effectiveIcon(cat("x", "X"), [:]))
    }

    func test_flatten_empty_search_respects_expanded() {
        let forest = categoryForest([cat("food", "Food"), cat("groc", "Groceries", parent: "food")])
        XCTAssertEqual(flattenCategories(forest, expanded: [], search: "").map(\.id), ["food"])
        XCTAssertEqual(flattenCategories(forest, expanded: ["food"], search: "").map(\.id), ["food", "groc"])
    }

    func test_flatten_search_force_expands_ancestors() {
        let forest = categoryForest([cat("food", "Food"), cat("groc", "Groceries", parent: "food"),
                                     cat("home", "Home")])
        // "groc" matches; its ancestor "food" is shown even though collapsed; "home" is hidden.
        XCTAssertEqual(flattenCategories(forest, expanded: [], search: "groc").map(\.id), ["food", "groc"])
    }

    func test_flatten_marks_hasChildren_and_depth() {
        let forest = categoryForest([cat("food", "Food"), cat("groc", "Groceries", parent: "food")])
        let flat = flattenCategories(forest, expanded: ["food"], search: "")
        XCTAssertTrue(flat[0].hasChildren); XCTAssertEqual(flat[0].depth, 0)
        XCTAssertFalse(flat[1].hasChildren); XCTAssertEqual(flat[1].depth, 1)
    }
}
