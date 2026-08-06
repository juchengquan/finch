import XCTest
@testable import FinchApp

/// Typing a new amount over an existing split.
///
/// The rows of a reopened split arrive PINNED (`SplitAllocation.merging`) —
/// they are figures the user set before and must not be re-divided just by
/// opening the sheet. `redistribute()` therefore returns early when every row is
/// pinned, so `setTotal` moves the target without moving a single cell.
///
/// That is correct behaviour for the model and a silent data loss at the sheet:
/// `save()` sends `payload`, which still holds the old figures, so typing 120
/// over a 100 split saved 100 and said nothing. The model already computes the
/// right diagnosis; nothing consulted it.
final class SplitSaveGateTests: XCTestCase {

    /// A reopened two-card split of 100.
    private func reopened() -> SplitAllocation {
        SplitAllocation.merging([(id: Optional("a1"), amount: 60),
                                 (id: Optional("a2"), amount: 40)], total: 100)
    }

    func test_aReopenedSplitStartsAgreeingWithItsTotal() {
        XCTAssertNil(reopened().problem, "60 + 40 = 100, nothing to complain about")
    }

    /// The bug, stated as an assertion: raising the total leaves the cells alone,
    /// so what would be SAVED no longer matches what is on screen.
    func test_raisingTheTotalLeavesTheCellsBehind() {
        var alloc = reopened()
        alloc.setTotal(120)
        XCTAssertEqual(alloc.allocated, 100, accuracy: 0.001,
                       "every row is pinned, so redistribute cannot move them")
        XCTAssertEqual(alloc.problem, .sumMismatch,
                       "and the model says so — this is the signal the sheet must not ignore")
    }

    /// Correcting a cell clears it. This is the way out of the blocked state, so
    /// it has to actually work.
    func test_correctingACellClearsTheMismatch() {
        var alloc = reopened()
        alloc.setTotal(120)
        alloc.setAmount("a1", 80)
        XCTAssertEqual(alloc.allocated, 120, accuracy: 0.001)
        XCTAssertNil(alloc.problem)
    }

    /// Unpinning a row lets it absorb the difference instead — the other way out.
    func test_unpinningARowAbsorbsTheDifference() {
        var alloc = reopened()
        alloc.setTotal(120)
        alloc.setAmount("a2", nil)
        XCTAssertEqual(alloc.allocated, 120, accuracy: 0.001, "a2 floats and takes the rest")
        XCTAssertNil(alloc.problem)
    }

    /// A single row is not a split, and must never be blocked.
    func test_aSingleRowIsNeverBlocked() {
        var alloc = SplitAllocation.merging([(id: Optional("a1"), amount: 100)], total: 100)
        alloc.setTotal(120)
        XCTAssertNil(alloc.problem, "one row is a plain purchase, not a split")
    }

    /// The grid's own balance check, which gates the same save.
    func test_theGridBlocksUntilItsCellsReachTheTotal() {
        var grid = SplitAllocation(total: 100)
        for key in ["a1|c1", "a2|c1"] { grid.tick(key) }
        grid.setAmount("a1|c1", 60)
        grid.setAmount("a2|c1", 35)
        XCTAssertFalse(PurchaseFlow.isBalanced(grid), "5 unaccounted")
        grid.setAmount("a2|c1", 40)
        XCTAssertTrue(PurchaseFlow.isBalanced(grid))
    }
}
