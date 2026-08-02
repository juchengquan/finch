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

extension SplitAllocationTests {

    // Toggling split off keeps the largest leg. Not arbitrary: it is the same rule
    // Projection.swift:136-148 uses to decide which category a split DISPLAYS, so the
    // survivor is the category the row was already showing.
    func test_dominantCategoryIsTheLargestLeg() {
        var a = SplitAllocation(total: 66.20)
        a.tick("groceries"); a.tick("household"); a.tick("dining")
        a.setAmount("groceries", 40); a.setAmount("household", 18.20); a.setAmount("dining", 8)
        XCTAssertEqual(a.dominantId, "groceries")
    }

    // The web writes to the same ledger with free-form split rows, so a stored
    // transaction can repeat a category. Checkboxes cannot express that, so repeats
    // fold together. Lossless: the only field separating two same-category legs is
    // `description`, which the UI never writes and the projection reads back as nil.
    func test_mergingFoldsRepeatedCategoriesAndSumsThem() {
        let a = SplitAllocation.merging([
            (id: "groceries", amount: 10),
            (id: "groceries", amount: 20),
            (id: "household", amount: 28.20),
        ], total: 58.20)
        XCTAssertEqual(a.rows.map(\.id), ["groceries", "household"])
        XCTAssertEqual(a.rows.map(\.amount), [30.00, 28.20])
    }

    // Loaded rows are amounts the user set previously, so they arrive pinned and are
    // not re-divided the moment the sheet opens.
    func test_mergedRowsArrivePinned() {
        let a = SplitAllocation.merging([
            (id: "a", amount: 70), (id: "b", amount: 30),
        ], total: 100)
        XCTAssertEqual(a.rows.map(\.pinned), [true, true])
        XCTAssertEqual(a.rows.map(\.amount), [70, 30])
    }

    func test_mergingMapsNilCategoryToTheUncategorisedRow() {
        let a = SplitAllocation.merging([
            (id: nil, amount: 5), (id: "a", amount: 5),
        ], total: 10)
        XCTAssertEqual(a.rows.map(\.id), ["", "a"])
    }

    // Fewer than two ticked is a plain single-category transaction, which is legal —
    // and is what the engine demands, since it rejects a one-row split outright.
    func test_fewerThanTwoRowsIsLegal() {
        var a = SplitAllocation(total: 100)
        XCTAssertNil(a.problem)
        a.tick("a")
        XCTAssertNil(a.problem)
    }

    func test_twoRowsThatAddUpAreLegal() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        XCTAssertNil(a.problem)
    }

    // The toggle is usable before an amount is entered; this is what stops Confirm,
    // and the reason has to be sayable in the sheet.
    func test_noTotalYetIsReportedAsNeedsAmount() {
        var a = SplitAllocation(total: 0)
        a.tick("a"); a.tick("b")
        XCTAssertEqual(a.problem, .needsAmount)
    }

    func test_pinnedRowsThatDoNotAddUpAreReported() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 80); a.setAmount("b", 5)
        XCTAssertEqual(a.problem, .sumMismatch)
    }

    // Zero-amount rows drop out, so two ticks with only one funded is "needs two".
    func test_onlyOneFundedRowIsReportedAsNeedsTwo() {
        var a = SplitAllocation(total: 100)
        a.tick("a"); a.tick("b")
        a.setAmount("a", 100); a.setAmount("b", 0)
        XCTAssertEqual(a.problem, .needsTwo)
    }

    func test_payloadDropsZeroRowsAndMapsUncategorised() {
        var a = SplitAllocation(total: 100)
        a.tick(""); a.tick("b"); a.tick("c")
        a.setAmount("", 60); a.setAmount("b", 40); a.setAmount("c", 0)
        let p = a.payload
        XCTAssertEqual(p.count, 2)
        XCTAssertNil(p[0].id)
        XCTAssertEqual(p[1].id, "b")
    }
}

extension SplitAllocationTests {

    // `SplitAllocation` is shared by the account split (`SearchablePickerRow`'s
    // `splitting:`) as well as the category split — one allocation model, not a
    // fork. These use account-shaped ids to prove the arithmetic genuinely
    // doesn't depend on category semantics (no account ever ticks "", so that
    // leg of `payload`/`merging` is moot here, but everything else is identical).
    func test_splitAllocationWorksIdenticallyForAccountIds() {
        var a = SplitAllocation(total: 100)
        a.tick("acct-checking"); a.tick("acct-savings")
        XCTAssertEqual(a.rows.map(\.amount), [50, 50])
        a.setAmount("acct-checking", 30)
        XCTAssertEqual(a.rows.map(\.amount), [30, 70])
        XCTAssertNil(a.problem)
        XCTAssertEqual(a.payload.map(\.id), ["acct-checking", "acct-savings"])
        // The larger leg (savings, 70) survives an account-split collapse — the
        // same "keep the biggest" rule the category picker uses.
        XCTAssertEqual(a.dominantId, "acct-savings")
    }

    // One row is not a split for accounts either — `AddTransactionSheet.save()`
    // gates `args["accounts"]` on `payload.count >= 2`, so a single ticked account
    // must produce a one-row payload rather than being silently promoted.
    func test_oneAccountRowIsNotASplit() {
        var a = SplitAllocation(total: 100)
        a.tick("acct-checking")
        XCTAssertEqual(a.payload.count, 1)
        XCTAssertNil(a.problem)
    }

    // A three-way account split of an odd amount cannot land exactly on every leg
    // individually, but `redistribute()` puts the remainder on the last row so the
    // sum is always exact — the property that keeps `problem` (and so Save) from
    // ever blocking on a rounding cent.
    func test_threeWayAccountSplitOfAnOddAmountStillSumsExactly() {
        var a = SplitAllocation(total: 100)
        a.tick("acct-a"); a.tick("acct-b"); a.tick("acct-c")
        XCTAssertEqual(a.allocated, 100, accuracy: 0.0001)
        XCTAssertNil(a.problem)
    }
}

/// Ticking is per-category and never reaches a category's children.
///
/// Nothing in `SplitAllocation` could cascade today — `tick` appends exactly one row
/// — which is precisely why this is worth pinning down: the guarantee currently rests
/// on an implementation detail rather than on a stated rule, so a later "helpful"
/// change in the picker has nothing to fail against. A split is one categoryId, and a
/// parent tick that dragged its children in would silently manufacture a split per
/// child and re-divide amounts the user had set.
extension SplitAllocationTests {

    func test_tickingAParentAddsOnlyThatParent() {
        var a = SplitAllocation(total: 100)
        a.tick("dining")                       // a parent of coffee/restaurants
        XCTAssertEqual(a.rows.map(\.id), ["dining"])
        XCTAssertEqual(a.payload.count, 1)
        XCTAssertEqual(a.payload[0].id, "dining")
    }

    func test_tickingAParentAndAChildKeepsThemSeparate() {
        var a = SplitAllocation(total: 100)
        a.tick("dining")
        a.tick("dining.coffee")
        // Two independent legs, evenly divided — the child is not folded into the
        // parent, and the parent does not absorb the child.
        XCTAssertEqual(a.rows.map(\.id), ["dining", "dining.coffee"])
        XCTAssertEqual(a.rows.map(\.amount), [50, 50])
    }

    func test_untickingAParentLeavesItsChildTicked() {
        var a = SplitAllocation(total: 100)
        a.tick("dining"); a.tick("dining.coffee")
        a.untick("dining")
        XCTAssertEqual(a.rows.map(\.id), ["dining.coffee"])
        XCTAssertEqual(a.rows[0].amount, 100, accuracy: 0.001)
    }

    // The uncategorised leg, restored after the rewrite dropped it: the old split
    // editor let a row's category stay unset, and the engine takes a nil category.
    func test_uncategorisedTicksAndWritesANilCategory() {
        var a = SplitAllocation(total: 100)
        a.tick("groceries"); a.tick("")
        XCTAssertTrue(a.isTicked(""))
        XCTAssertEqual(a.payload.count, 2)
        XCTAssertNil(a.payload[1].id, "the uncategorised leg must write a nil category")
    }
}
