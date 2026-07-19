import XCTest
@testable import FinchApp
import FinchCore

final class TagChipFlowTests: XCTestCase {
    private func tags(_ ids: [String]) -> [TagRow] { ids.map { TagRow(id: $0, name: $0, color: nil) } }

    func test_underCap_showsAll() {
        let all = tags(["a","b","c"])
        let vis = TagChipFlow.collapsedVisible(tags: all, selected: [], cap: 10)
        XCTAssertEqual(vis.map(\.id), ["a","b","c"])
    }

    func test_overCap_truncatesToCap_preservingOrder() {
        let all = tags((1...15).map { "t\($0)" })
        let vis = TagChipFlow.collapsedVisible(tags: all, selected: [], cap: 10)
        XCTAssertEqual(vis.count, 10)
        XCTAssertEqual(vis.first?.id, "t1")
    }

    func test_selectedAlwaysVisible_evenBeyondCap() {
        let all = tags((1...15).map { "t\($0)" })
        // t14 is selected but sits past the cap — must still appear.
        let vis = TagChipFlow.collapsedVisible(tags: all, selected: ["t14"], cap: 10)
        XCTAssertTrue(vis.contains { $0.id == "t14" })
        XCTAssertLessThanOrEqual(vis.count, 11)   // cap unselected + the pulled-in selected
        // No duplicates.
        XCTAssertEqual(Set(vis.map(\.id)).count, vis.count)
    }

    func test_manySelected_allSelectedShown() {
        let all = tags((1...15).map { "t\($0)" })
        let sel = Set((11...15).map { "t\($0)" })
        let vis = TagChipFlow.collapsedVisible(tags: all, selected: sel, cap: 10)
        for id in sel { XCTAssertTrue(vis.contains { $0.id == id }, "\(id) missing") }
    }
}
