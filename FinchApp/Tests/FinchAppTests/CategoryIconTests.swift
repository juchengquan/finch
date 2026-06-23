import XCTest
@testable import FinchApp

final class CategoryIconTests: XCTestCase {
    func test_twelve_shared_names() {
        XCTAssertEqual(CategoryIcon.names,
            ["fork", "home", "car", "bag", "film", "heart", "sync", "tag", "coins", "wallet", "chart", "doc"])
    }

    func test_known_names_map_to_symbols() {
        XCTAssertEqual(CategoryIcon.symbol(for: "fork"), "fork.knife")
        XCTAssertEqual(CategoryIcon.symbol(for: "home"), "house.fill")
        XCTAssertEqual(CategoryIcon.symbol(for: "sync"), "arrow.triangle.2.circlepath")
    }

    func test_unknown_and_nil_default_to_tag() {
        XCTAssertEqual(CategoryIcon.symbol(for: nil), "tag.fill")
        XCTAssertEqual(CategoryIcon.symbol(for: ""), "tag.fill")
        XCTAssertEqual(CategoryIcon.symbol(for: "nope"), "tag.fill")
    }

    func test_every_name_maps_to_nonempty_symbol() {
        for n in CategoryIcon.names { XCTAssertFalse(CategoryIcon.symbol(for: n).isEmpty) }
    }
}
