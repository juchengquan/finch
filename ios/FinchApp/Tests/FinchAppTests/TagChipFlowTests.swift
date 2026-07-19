import XCTest
@testable import FinchApp
import FinchCore

/// The tag field's display-chip cap is pure: show selected tags (in order) up to
/// a cap, then a "+N" overflow count.
final class TagChipFlowTests: XCTestCase {
    private func tags(_ ids: [String]) -> [TagRow] { ids.map { TagRow(id: $0, name: $0, color: nil) } }

    func test_noneSelected_showsNothing() {
        let d = TagField.displayChips(tags: tags(["a","b","c"]), selected: [], cap: 8)
        XCTAssertTrue(d.shown.isEmpty)
        XCTAssertEqual(d.overflow, 0)
    }

    func test_underCap_showsAllSelectedInOrder() {
        let d = TagField.displayChips(tags: tags(["a","b","c","d"]), selected: ["b","d"], cap: 8)
        XCTAssertEqual(d.shown.map(\.id), ["b","d"])
        XCTAssertEqual(d.overflow, 0)
    }

    func test_overCap_capsAndCountsOverflow() {
        let all = tags((1...12).map { "t\($0)" })
        let sel = Set(all.map(\.id))   // all 12 selected
        let d = TagField.displayChips(tags: all, selected: sel, cap: 8)
        XCTAssertEqual(d.shown.count, 8)
        XCTAssertEqual(d.shown.first?.id, "t1")   // original order preserved
        XCTAssertEqual(d.overflow, 4)
    }

    func test_ignoresUnknownSelectedIds() {
        let d = TagField.displayChips(tags: tags(["a","b"]), selected: ["a","ghost"], cap: 8)
        XCTAssertEqual(d.shown.map(\.id), ["a"])
        XCTAssertEqual(d.overflow, 0)
    }
}
