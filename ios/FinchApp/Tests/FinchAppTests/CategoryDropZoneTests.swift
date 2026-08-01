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

    // MARK: allowsNesting — an expanded parent offers no nest zone
    //
    // Its children are already on screen, so every position inside it is reachable
    // by dropping between them. Keeping a nest zone there would be a second, vaguer
    // route to the same result while taking half the row away from the precise one —
    // which is what made same-level reordering hard to hit.

    private func halved(_ y: CGFloat) -> CategoryDropZone {
        CategoryDropZone.at(pointY: y, cellMinY: 100, cellHeight: 44, allowsNesting: false)
    }

    func testWithoutNestingTheRowIsHalves() {
        XCTAssertEqual(halved(100), .before)       // top edge
        XCTAssertEqual(halved(121), .before)       // fraction 0.477 — just above centre
        XCTAssertEqual(halved(122), .after)        // fraction 0.5 exactly
        XCTAssertEqual(halved(143), .after)        // bottom edge
    }

    /// The whole point: the band that used to nest now reorders instead.
    func testWithoutNestingTheMiddleNeverNests() {
        for y in stride(from: CGFloat(100), through: 144, by: 1) {
            XCTAssertNotEqual(halved(y), .into,
                              "y=\(y) offered nesting on a row whose children are visible")
        }
    }

    /// Nesting stays the default so collapsed parents and leaves are unaffected —
    /// they have no visible children to drop among, so it is the only way in.
    func testNestingRemainsTheDefault() {
        XCTAssertEqual(CategoryDropZone.at(pointY: 122, cellMinY: 100, cellHeight: 44), .into)
    }

    /// Degenerate frame with nesting refused must not silently nest anyway.
    func testZeroHeightWithoutNestingFallsBackToBefore() {
        XCTAssertEqual(
            CategoryDropZone.at(pointY: 0, cellMinY: 0, cellHeight: 0, allowsNesting: false), .before)
    }
}
#endif
