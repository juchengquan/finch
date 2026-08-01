import XCTest
@testable import FinchApp

/// The split's arithmetic, with no sheet involved. Every allocation rule lives in
/// `SplitAllocation` precisely so it can be tested here instead of by tapping.
final class SplitAllocationTests: XCTestCase {

    // The first ticked category takes the whole transaction — splitting one way is
    // just categorising, and it means the second tick has something to halve.
    func test_firstTickTakesTheWholeTotal() {
        var a = SplitAllocation(total: 58.20)
        a.tick("groceries")
        XCTAssertEqual(a.rows.map(\.id), ["groceries"])
        XCTAssertEqual(a.rows[0].amount, 58.20, accuracy: 0.001)
    }

    func test_secondTickSplitsItEvenly() {
        var a = SplitAllocation(total: 58.20)
        a.tick("groceries"); a.tick("household")
        XCTAssertEqual(a.rows.map(\.amount), [29.10, 29.10])
    }

    // 100 / 3 does not divide evenly. The last row absorbs the remainder, which is
    // what the engine itself does with the final leg (Transactions.swift:57-62), so
    // the rows always add up to exactly the total rather than to 99.99.
    func test_unevenDivisionPutsTheRemainderOnTheLastRow() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b"); a.tick("c")
        XCTAssertEqual(a.rows.map(\.amount), [33.33, 33.33, 33.34])
        XCTAssertEqual(a.allocated, 100, accuracy: 0.0001)
    }

    func test_rowsKeepTickOrder() {
        var a = SplitAllocation(total: 30)
        a.tick("c"); a.tick("a"); a.tick("b")
        XCTAssertEqual(a.rows.map(\.id), ["c", "a", "b"])
    }

    // "" is the Uncategorized row — a legal split leg (the engine takes a nil category).
    func test_uncategorisedIsATickableRow() {
        var a = SplitAllocation(total: 10)
        a.tick("groceries"); a.tick("")
        XCTAssertEqual(a.rows.map(\.id), ["groceries", ""])
        XCTAssertEqual(a.rows.map(\.amount), [5, 5])
    }

    func test_tickingTwiceIsIdempotent() {
        var a = SplitAllocation(total: 10)
        a.tick("groceries"); a.tick("groceries")
        XCTAssertEqual(a.rows.count, 1)
    }
}
