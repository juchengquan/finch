#if os(iOS)
import XCTest
@testable import FinchApp

/// The drop-zone thirds used by Categories' reorder-by-drag.
///
/// This exists because the gesture cannot be automated: `idb` offers only
/// press-move-release, which never triggers a UIKit drag lift, so a wrong
/// threshold here would otherwise reach a human as "reordering puts things in the
/// wrong place" rather than as a failing test.
final class CategoryDropZoneTests: XCTestCase {

    /// A 44pt row starting at y=100.
    private func zone(_ y: CGFloat) -> CategoryDropZone {
        CategoryDropZone.at(pointY: y, cellMinY: 100, cellHeight: 44)
    }

    func testTopQuarterInsertsBefore() {
        XCTAssertEqual(zone(100), .before)        // the very top edge
        XCTAssertEqual(zone(110), .before)        // fraction 0.227
    }

    func testBottomQuarterInsertsAfter() {
        XCTAssertEqual(zone(143), .after)         // fraction 0.977
        XCTAssertEqual(zone(134), .after)         // fraction 0.773
    }

    func testMiddleHalfNests() {
        XCTAssertEqual(zone(111), .into)          // fraction 0.25 exactly — not before
        XCTAssertEqual(zone(122), .into)          // dead centre
        XCTAssertEqual(zone(133), .into)          // fraction 0.75 exactly — not after
    }

    /// The boundaries are exclusive on both sides, so a drop exactly on 0.25 or 0.75
    /// nests rather than reordering. Asserted so the comparison operators cannot be
    /// loosened to <= / >= without a failure.
    func testBoundariesBelongToNesting() {
        XCTAssertEqual(CategoryDropZone.at(pointY: 25, cellMinY: 0, cellHeight: 100), .into)
        XCTAssertEqual(CategoryDropZone.at(pointY: 75, cellMinY: 0, cellHeight: 100), .into)
        XCTAssertEqual(CategoryDropZone.at(pointY: 24, cellMinY: 0, cellHeight: 100), .before)
        XCTAssertEqual(CategoryDropZone.at(pointY: 76, cellMinY: 0, cellHeight: 100), .after)
    }

    /// A missing cell frame yields height 0. Nesting is the safe reading: it is the
    /// one outcome the engine validates (cycles and depth > 3 are rejected), whereas
    /// a bogus sibling insert would silently renumber a group.
    func testZeroHeightNests() {
        XCTAssertEqual(CategoryDropZone.at(pointY: 0, cellMinY: 0, cellHeight: 0), .into)
        XCTAssertEqual(CategoryDropZone.at(pointY: 500, cellMinY: 0, cellHeight: 0), .into)
    }

    // MARK: nesting is gated on a sideways drag
    //
    // Same level is the default at every row. Two earlier attempts tried to infer
    // "I meant to go inside" from vertical position and both got it wrong — nesting
    // owned the middle half and beat same-level two-to-one, and narrowing it to rows
    // with hidden children still let folded categories swallow drops aimed past
    // them. Position cannot express that intent; only a second axis can.

    func testDraggingStraightDownNeverNests() {
        XCTAssertFalse(CategoryDropZone.allowsNesting(dragDX: 0))
        XCTAssertFalse(CategoryDropZone.allowsNesting(dragDX: 8))    // thumb wander
        XCTAssertFalse(CategoryDropZone.allowsNesting(dragDX: 31))   // just short
    }

    func testDraggingRightPastTheThresholdNests() {
        XCTAssertTrue(CategoryDropZone.allowsNesting(dragDX: 32))    // exactly on it
        XCTAssertTrue(CategoryDropZone.allowsNesting(dragDX: 80))
    }

    /// Leftward travel is not an un-nest gesture — the "Top level" drop row does
    /// that. A left drag must behave exactly like a straight one.
    func testDraggingLeftDoesNotNest() {
        XCTAssertFalse(CategoryDropZone.allowsNesting(dragDX: -40))
        XCTAssertFalse(CategoryDropZone.allowsNesting(dragDX: -200))
    }

    /// The threshold has to clear the tree's 14pt indent step by enough to read as
    /// deliberate; at one step it would fire on ordinary drag wobble.
    func testThresholdIsWellClearOfOneIndentStep() {
        XCTAssertGreaterThan(CategoryDropZone.nestingDragThreshold, 28)
    }

    // MARK: the halves layout used whenever nesting is refused

    private func halved(_ y: CGFloat) -> CategoryDropZone {
        CategoryDropZone.at(pointY: y, cellMinY: 100, cellHeight: 44, allowsNesting: false)
    }

    func testWithoutNestingTheRowIsHalves() {
        XCTAssertEqual(halved(100), .before)       // top edge
        XCTAssertEqual(halved(121), .before)       // fraction 0.477 — just above centre
        XCTAssertEqual(halved(122), .after)        // fraction 0.5 exactly
        XCTAssertEqual(halved(143), .after)        // bottom edge
    }

    /// The whole point: with nesting refused, NO point on the row can nest — so a
    /// drag that never went sideways cannot change a category's level by accident,
    /// wherever on the row it is released.
    func testWithoutNestingNoPointOnTheRowNests() {
        for y in stride(from: CGFloat(100), through: 144, by: 1) {
            XCTAssertNotEqual(halved(y), .into,
                              "y=\(y) nested on a drag that never moved sideways")
        }
    }

    /// Degenerate frame with nesting refused must not silently nest anyway.
    func testZeroHeightWithoutNestingFallsBackToBefore() {
        XCTAssertEqual(
            CategoryDropZone.at(pointY: 0, cellMinY: 0, cellHeight: 0, allowsNesting: false), .before)
    }
}
#endif
