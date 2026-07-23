import XCTest
@testable import FinchApp

final class SwipeResetTests: XCTestCase {
    func test_topVisibleID_returnsFirstOrderedIdThatIsVisible() {
        let order = ["a", "b", "c", "d", "e"]
        // c and d on screen → topmost in display order is c.
        XCTAssertEqual(SwipeReset.topVisibleID(order: order, visible: ["d", "c"]), "c")
    }

    func test_topVisibleID_respectsOrderNotSetIteration() {
        let order = ["z", "y", "x"]
        // Only y and x visible → first in order (z absent) is y.
        XCTAssertEqual(SwipeReset.topVisibleID(order: order, visible: ["x", "y"]), "y")
    }

    func test_topVisibleID_emptyVisible_isNil() {
        XCTAssertNil(SwipeReset.topVisibleID(order: ["a", "b"], visible: []))
    }

    func test_topVisibleID_ignoresStaleVisibleIdsNotInOrder() {
        // A visible id that is no longer part of the display order is ignored.
        XCTAssertEqual(SwipeReset.topVisibleID(order: ["a", "b"], visible: ["gone", "b"]), "b")
    }

    func test_topVisibleID_emptyOrder_isNil() {
        XCTAssertNil(SwipeReset.topVisibleID(order: [], visible: ["a"]))
    }

    func test_nextSavedAnchor_enabled_keepsCurrentTop() {
        XCTAssertEqual(SwipeReset.nextSavedAnchor(enabled: true, currentAnchor: "tx5"), "tx5")
    }

    func test_nextSavedAnchor_gated_dropsAnchor() {
        // Gated navigation (e.g. multi-select active): no rebuild → drop any anchor so no stale restore.
        XCTAssertNil(SwipeReset.nextSavedAnchor(enabled: false, currentAnchor: "tx9"))
    }

    func test_nextSavedAnchor_enabled_nilTop_isNil() {
        XCTAssertNil(SwipeReset.nextSavedAnchor(enabled: true, currentAnchor: nil))
    }
}
