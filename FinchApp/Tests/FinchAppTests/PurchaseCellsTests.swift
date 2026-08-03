import XCTest
@testable import FinchApp
import FinchCore

/// The two-page flow's decisions and the payload it produces.
///
/// These are deliberately tested here rather than through the allocation model:
/// the predecessor plan shipped unsigned shares that made the engine reject every
/// expense split, and 407 green tests missed it because all of them exercised the
/// model — which was already correct. The bug was in what the sheet SENT.
final class PurchaseCellsTests: XCTestCase {

    // MARK: which page 2, if any

    func test_oneCardOneCategory_needsNoSecondPage() {
        XCTAssertEqual(PurchaseFlow.page2(accounts: 1, categories: 1), .notNeeded,
                       "nothing to divide, so the tick saves straight from page 1")
    }

    func test_oneAxisSplit_isAList() {
        XCTAssertEqual(PurchaseFlow.page2(accounts: 2, categories: 1), .list)
        XCTAssertEqual(PurchaseFlow.page2(accounts: 1, categories: 3), .list)
    }

    /// Previously unreachable by construction: the sheet made the two splits
    /// mutually exclusive on purpose, because the engine could not store the shape.
    /// It can now — as one transaction per card — so the combination routes to the
    /// grid instead of being blocked.
    func test_bothAxesSplit_isAGrid() {
        XCTAssertEqual(PurchaseFlow.page2(accounts: 2, categories: 2), .grid)
        XCTAssertEqual(PurchaseFlow.page2(accounts: 3, categories: 4), .grid)
    }

    // MARK: the payload

    private func alloc(total: Double, _ cells: [(String, String?, Double)]) -> SplitAllocation {
        var a = SplitAllocation(total: total)
        for (acct, cat, amount) in cells {
            let key = PurchaseFlow.cellKey(account: acct, category: cat)
            a.tick(key)
            a.setAmount(key, amount)
        }
        return a
    }

    /// A 2×2 grid is sent as FOUR cells. The engine derives the shape from the
    /// category count (Decision 15); the sheet does not pre-group by card.
    func test_aTwoByTwoGrid_issentAsFourCells() {
        let a = alloc(total: 100, [
            ("a1", "c1", 40), ("a1", "c2", 20), ("a2", "c1", 30), ("a2", "c2", 10),
        ])
        let cells = PurchaseFlow.cells(from: a, kind: .expense)
        XCTAssertEqual(cells.count, 4, "four cells, sent as four — the engine groups them")
    }

    /// The bug the predecessor shipped: unsigned shares. An expense's cells must be
    /// NEGATIVE, or the engine rejects the split.
    func test_anExpensesCellsAreNegative_andIncomesArePositive() {
        let a = alloc(total: 100, [("a1", "c1", 60), ("a2", "c1", 40)])

        let expense = PurchaseFlow.cells(from: a, kind: .expense).compactMap { cellAmount($0) }
        XCTAssertEqual(expense.sorted(), [-60, -40].sorted(), "an expense leaves the account")

        let income = PurchaseFlow.cells(from: a, kind: .income).compactMap { cellAmount($0) }
        XCTAssertEqual(income.sorted(), [40, 60], "income arrives")
    }

    /// An absent cell is absent — not a zero. A zero-amount cell would become a $0
    /// category leg on that transaction and pollute category counts.
    func test_aCrossedOutCellIsAbsent_notZero() {
        let a = alloc(total: 100, [("a1", "c1", 60), ("a2", "c2", 40)])
        let cells = PurchaseFlow.cells(from: a, kind: .expense)
        XCTAssertEqual(cells.count, 2, "only the two combinations that happened")
    }

    /// The composite key has to survive a round trip, including the
    /// uncategorized case, or a cell is silently reassigned.
    func test_theCellKeyRoundTrips() {
        let withCat = PurchaseFlow.cellKey(account: "a1", category: "c1")
        XCTAssertEqual(PurchaseFlow.splitCellKey(withCat).account, "a1")
        XCTAssertEqual(PurchaseFlow.splitCellKey(withCat).category, "c1")

        let noCat = PurchaseFlow.cellKey(account: "a1", category: nil)
        XCTAssertEqual(PurchaseFlow.splitCellKey(noCat).account, "a1")
        XCTAssertNil(PurchaseFlow.splitCellKey(noCat).category, "uncategorized stays uncategorized")
    }

    // MARK: the margins

    /// The cells drive the totals, and saving is refused until they reach the
    /// purchase amount. Reachable only when every cell is pinned — a single
    /// floating cell absorbs the difference, so a test that leaves one would never
    /// see the block.
    func test_savingIsRefusedWhileTheCellsDoNotReachTheTotal() {
        let short = alloc(total: 100, [("a1", "c1", 60), ("a2", "c1", 35)])
        XCTAssertFalse(PurchaseFlow.isBalanced(short), "$5 unaccounted")
        XCTAssertEqual(PurchaseFlow.unallocated(short), 5, accuracy: 0.001)

        let exact = alloc(total: 100, [("a1", "c1", 60), ("a2", "c1", 40)])
        XCTAssertTrue(PurchaseFlow.isBalanced(exact))
    }

    /// An amount that does not divide evenly must still sum exactly — the last
    /// floating cell takes the remainder, the same trick the engine uses on its
    /// final leg rather than leaving a residue.
    func test_anUnevenSplitStillSumsExactly() {
        var a = SplitAllocation(total: 100)
        for key in ["a1|c1", "a2|c1", "a3|c1"] { a.tick(key) }
        XCTAssertEqual(a.allocated, 100, accuracy: 0.001, "33.33 + 33.33 + 33.34")
    }

    /// Going back to page 1 and adding a card must not disturb what was already
    /// typed. This falls out of `redistribute` respecting `pinned`, so it should
    /// pass immediately — it is here because it is the behaviour a later refactor
    /// is most likely to break silently.
    func test_addingACardLeavesTypedCellsAlone() {
        var a = alloc(total: 100, [("a1", "c1", 60)])
        a.tick(PurchaseFlow.cellKey(account: "a2", category: "c1"))
        let typed = a.rows.first { $0.id == "a1|c1" }
        XCTAssertEqual(typed?.amount, 60, "what the user typed still stands")
        XCTAssertEqual(a.allocated, 100, accuracy: 0.001, "and the new cell took the rest")
    }

    private func cellAmount(_ v: JSONValue) -> Double? {
        guard case .object(let o) = v, case .double(let d)? = o["amount"] else { return nil }
        return d
    }
}
