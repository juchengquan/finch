import XCTest
@testable import FinchApp

final class CategoryIconTests: XCTestCase {
    /// The original 12 web-shared names must remain present so packs authored on
    /// the web keep rendering — native-only icons EXTEND the set, never remove.
    func test_web_shared_names_present() {
        let webShared = ["fork", "home", "car", "bag", "film", "heart",
                         "sync", "tag", "coins", "wallet", "chart", "doc"]
        for n in webShared {
            XCTAssertTrue(CategoryIcon.names.contains(n), "missing web-shared icon \(n)")
        }
    }

    /// `names` is exactly the flat union of the themed groups, in order.
    func test_names_match_group_union() {
        XCTAssertEqual(CategoryIcon.names, CategoryIcon.groups.flatMap(\.names))
    }

    /// No short-name appears twice (a dupe would render/select ambiguously).
    func test_names_are_unique() {
        XCTAssertEqual(CategoryIcon.names.count, Set(CategoryIcon.names).count)
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

    /// Every icon has a non-empty friendly label (shown when tapped in the picker).
    func test_every_name_has_friendly_label() {
        for n in CategoryIcon.names {
            XCTAssertFalse(CategoryIcon.label(for: n).isEmpty, "missing label for \(n)")
        }
    }

    // MARK: Chinese

    /// The built app's Chinese table; nil when the key is missing or was never
    /// extracted.
    private func chinese(_ key: String) throws -> String? {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let missing = "\u{1}missing"
        let value = bundle.localizedString(forKey: key, value: missing, table: nil)
        return value == missing ? nil : value
    }

    /// The picker's section titles and icon names read in English on a Chinese
    /// phone: they were plain `String`s, never extracted.
    func test_everyGroupTitleAndIconNameHasChinese() throws {
        for g in CategoryIcon.groups {
            XCTAssertNotNil(try chinese(g.title), "group \"\(g.title)\" has no Chinese")
        }
        for n in CategoryIcon.names {
            let label = CategoryIcon.label(for: n)
            XCTAssertNotNil(try chinese(label), "\(n) → \"\(label)\" has no Chinese")
        }
        XCTAssertNotNil(try chinese("Tap an icon"))
    }

    /// Two icons that read differently in English read differently in Chinese,
    /// so the caption under the title still tells them apart.
    func test_chineseIconNamesStayDistinct() throws {
        var byChinese: [String: Set<String>] = [:]
        for n in CategoryIcon.names {
            let label = CategoryIcon.label(for: n)
            byChinese[try XCTUnwrap(try chinese(label)), default: []].insert(label)
        }
        let merged = byChinese.filter { $0.value.count > 1 }
        XCTAssertTrue(merged.isEmpty, "\(merged)")
    }
}
