import XCTest
import SwiftUI
@testable import FinchApp

final class SplitVisibilityMappingTests: XCTestCase {
    func test_visibilityForCollapsed() {
        XCTAssertEqual(SplitVisibilityMapping.visibility(collapsed: true, columns: .three), .doubleColumn)
        XCTAssertEqual(SplitVisibilityMapping.visibility(collapsed: false, columns: .three), .all)
        XCTAssertEqual(SplitVisibilityMapping.visibility(collapsed: true, columns: .two), .detailOnly)
        XCTAssertEqual(SplitVisibilityMapping.visibility(collapsed: false, columns: .two), .doubleColumn)
    }

    func test_collapsedFromVisibility_definiteValues() {
        XCTAssertEqual(SplitVisibilityMapping.collapsed(from: .doubleColumn, columns: .three), true)
        XCTAssertEqual(SplitVisibilityMapping.collapsed(from: .all, columns: .three), false)
        XCTAssertEqual(SplitVisibilityMapping.collapsed(from: .detailOnly, columns: .two), true)
        XCTAssertEqual(SplitVisibilityMapping.collapsed(from: .doubleColumn, columns: .two), false)
    }

    func test_collapsedFromVisibility_transientValuesAreNil() {
        XCTAssertNil(SplitVisibilityMapping.collapsed(from: .automatic, columns: .three))
        XCTAssertNil(SplitVisibilityMapping.collapsed(from: .automatic, columns: .two))
        // .detailOnly on a THREE-column shell hides the list too — not a plain
        // "sidebar collapsed"; don't record it.
        XCTAssertNil(SplitVisibilityMapping.collapsed(from: .detailOnly, columns: .three))
        // .all on a TWO-column shell isn't one of its two states either.
        XCTAssertNil(SplitVisibilityMapping.collapsed(from: .all, columns: .two))
    }

    func test_roundTrip() {
        for columns in [SplitColumns.two, .three] {
            for collapsed in [true, false] {
                let v = SplitVisibilityMapping.visibility(collapsed: collapsed, columns: columns)
                XCTAssertEqual(SplitVisibilityMapping.collapsed(from: v, columns: columns), collapsed)
            }
        }
    }
}
