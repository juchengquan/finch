import XCTest
@testable import FinchApp

/// `LedgerReorder.reconciled` — what the in-flight reorder draft does when the set of
/// ledgers changes underneath it.
///
/// Both failure modes it guards against are silent: a dropped id names a row the data
/// source no longer has, and a missed id is invisible until ✓ and then absent from the
/// list ✓ writes. Neither shows up as a crash in the happy path, so they are asserted
/// directly.
final class LedgerReorderTests: XCTestCase {

    func testUntouchedDraftIsUnchanged() {
        XCTAssertEqual(LedgerReorder.reconciled(draft: ["c", "a", "b"], live: ["a", "b", "c"]),
                       ["c", "a", "b"], "the dragged order wins over the store's")
    }

    func testDeletedLedgerLeavesTheDraft() {
        XCTAssertEqual(LedgerReorder.reconciled(draft: ["c", "a", "b"], live: ["a", "c"]),
                       ["c", "a"])
    }

    /// A ledger that appears mid-drag joins at the end rather than going missing —
    /// the same "newcomers last" rule `LedgerOrder.sorted` applies to the saved order.
    func testNewLedgerJoinsAtTheEnd() {
        XCTAssertEqual(LedgerReorder.reconciled(draft: ["c", "a"], live: ["a", "c", "new"]),
                       ["c", "a", "new"])
    }

    func testSimultaneousAddAndRemove() {
        XCTAssertEqual(LedgerReorder.reconciled(draft: ["c", "a", "b"], live: ["a", "b", "x", "y"]),
                       ["a", "b", "x", "y"])
    }

    /// A duplicate would crash the diffable data source rather than merely look wrong.
    func testDuplicatesCollapse() {
        XCTAssertEqual(LedgerReorder.reconciled(draft: ["a", "a", "b"], live: ["a", "b"]),
                       ["a", "b"])
    }

    func testEmptyDraftTakesTheStoreOrder() {
        XCTAssertEqual(LedgerReorder.reconciled(draft: [], live: ["a", "b"]), ["a", "b"])
    }

    /// Runs on every republish, so a second pass must not shuffle what the first
    /// settled on.
    func testIsIdempotent() {
        let once = LedgerReorder.reconciled(draft: ["c", "a"], live: ["a", "c", "new"])
        XCTAssertEqual(LedgerReorder.reconciled(draft: once, live: ["a", "c", "new"]), once)
    }
}
