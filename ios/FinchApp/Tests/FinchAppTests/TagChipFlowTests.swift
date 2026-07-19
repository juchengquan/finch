import XCTest
@testable import FinchApp
import FinchCore

/// The tag field's chip selection is pure: the selected tags, in tag order, with
/// unknown ids ignored. All selected tags are shown (the row wraps them); no cap.
final class TagChipFlowTests: XCTestCase {
    private func tags(_ ids: [String]) -> [TagRow] { ids.map { TagRow(id: $0, name: $0, color: nil) } }

    func test_noneSelected_isEmpty() {
        XCTAssertTrue(TagField.selectedRows(tags: tags(["a","b","c"]), selected: []).isEmpty)
    }

    func test_showsAllSelectedInTagOrder() {
        let rows = TagField.selectedRows(tags: tags(["a","b","c","d"]), selected: ["d","b"])
        XCTAssertEqual(rows.map(\.id), ["b","d"])   // tag order, not selection order
    }

    func test_manySelected_areAllReturned() {
        let all = tags((1...12).map { "t\($0)" })
        let rows = TagField.selectedRows(tags: all, selected: Set(all.map(\.id)))
        XCTAssertEqual(rows.count, 12)              // no cap — the row wraps to hold all
        XCTAssertEqual(rows.first?.id, "t1")        // original order preserved
    }

    func test_ignoresUnknownSelectedIds() {
        let rows = TagField.selectedRows(tags: tags(["a","b"]), selected: ["a","ghost"])
        XCTAssertEqual(rows.map(\.id), ["a"])
    }
}
