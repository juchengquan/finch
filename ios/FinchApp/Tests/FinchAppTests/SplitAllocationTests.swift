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

extension SplitAllocationTests {

    // Typing an amount pins that row; the others re-divide around it. This is the
    // rule that stops a later tick from wiping an amount the user chose.
    func test_typingAnAmountPinsThatRowAndTheOthersAbsorbTheRest() {
        var a = SplitAllocation(total: 58.20)
        a.tick("groceries"); a.tick("household"); a.tick("dining")
        a.setAmount("dining", 10)
        XCTAssertEqual(a.rows.map(\.amount), [24.10, 24.10, 10.00])
        XCTAssertEqual(a.rows.map(\.pinned), [false, false, true])
        XCTAssertEqual(a.allocated, 58.20, accuracy: 0.0001)
    }

    func test_unpinningLetsTheRowFloatAgain() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 80)
        XCTAssertEqual(a.rows.map(\.amount), [80, 20])
        a.setAmount("a", nil)
        XCTAssertEqual(a.rows.map(\.amount), [50, 50])
    }

    func test_untickingGivesTheMoneyBackToTheUnpinnedRows() {
        var a = SplitAllocation(total: 58.20)
        a.tick("groceries"); a.tick("household"); a.tick("dining")
        a.setAmount("dining", 10)
        a.untick("household")
        XCTAssertEqual(a.rows.map(\.id), ["groceries", "dining"])
        XCTAssertEqual(a.rows.map(\.amount), [48.20, 10.00])
    }

    // Changing the transaction's amount re-divides the unpinned rows. It must NOT
    // discard the split — AddTransactionSheet used to null pendingSplits outright on
    // any amount change, which silently threw the user's work away.
    func test_changingTheTotalRedividesTheUnpinnedRows() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 30)
        a.setTotal(200)
        XCTAssertEqual(a.rows.map(\.amount), [30, 170])
    }

    // Pinned rows are an explicit instruction, so they are never silently rescaled.
    // The unpinned rows go to zero and the imbalance is surfaced (see validation).
    func test_pinnedRowsExceedingTheTotalAreNotRescaled() {
        var a = SplitAllocation(total: 50)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 80)
        XCTAssertEqual(a.rows.map(\.amount), [80, 0])
    }

    // Every row pinned and one removed leaves a genuine shortfall. Nothing is
    // invented to cover it — the same as deleting a row in the old editor.
    func test_untickingWhenEveryRowIsPinnedLeavesAShortfall() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b"); a.tick("c")
        a.setAmount("a", 50); a.setAmount("b", 30); a.setAmount("c", 20)
        a.untick("b")
        XCTAssertEqual(a.allocated, 70, accuracy: 0.0001)
    }
}
