import XCTest
@testable import FinchApp
import FinchCore

/// What page 2 shows when you arrive, and what it keeps when you come back.
final class GridSeedTests: XCTestCase {

    private func amount(_ a: SplitAllocation, _ key: String) -> Double {
        a.rows.first { $0.id == key }?.amount ?? .nan
    }

    private let cards: [(id: String?, amount: Double)] = [(id: "a1", amount: 60), (id: "a2", amount: 40)]
    private let cats: [(id: String?, amount: Double)] = [(id: "c1", amount: 70), (id: "c2", amount: 30)]

    /// Both sets of numbers the user already typed are honoured, so the grid
    /// opens balanced and ✓ is live at once. Starting empty would throw the
    /// margins away and demand four more entries for a 2×2 — twelve for a 3×4.
    func test_pageTwoOpensFilledFromBothMargins() {
        let g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 100)
        XCTAssertEqual(g.rows.count, 4)
        XCTAssertEqual(amount(g, "a1|c1"), 42, accuracy: 0.001)   // 60 × 70 / 100
        XCTAssertEqual(amount(g, "a1|c2"), 18, accuracy: 0.001)
        XCTAssertEqual(amount(g, "a2|c1"), 28, accuracy: 0.001)
        XCTAssertEqual(amount(g, "a2|c2"), 12, accuracy: 0.001)
        XCTAssertTrue(PurchaseFlow.isBalanced(g))
    }

    /// N independent roundings do not generally sum to the total, so the last
    /// cell absorbs the residue — the same trick `redistribute` uses on its final
    /// floating row and the engine on its final leg.
    func test_anAwkwardSplitStillSumsExactly() {
        let thirds: [(id: String?, amount: Double)] = [
            (id: "a1", amount: 33.33), (id: "a2", amount: 33.33), (id: "a3", amount: 33.34),
        ]
        let halves: [(id: String?, amount: Double)] = [(id: "c1", amount: 50), (id: "c2", amount: 50)]
        let g = PurchaseFlow.seedGrid(accounts: thirds, categories: halves, total: 100)
        XCTAssertEqual(g.rows.count, 6)
        XCTAssertEqual(g.allocated, 100, accuracy: 0.001)
        XCTAssertTrue(PurchaseFlow.isBalanced(g))
    }

    /// Uncategorised is a real column: a nil category is a nil leg, not an
    /// absent one, and its key must round-trip.
    func test_anUncategorisedColumnIsSeededLikeAnyOther() {
        let withNil: [(id: String?, amount: Double)] = [(id: "c1", amount: 70), (id: nil, amount: 30)]
        let g = PurchaseFlow.seedGrid(accounts: cards, categories: withNil, total: 100)
        XCTAssertEqual(amount(g, PurchaseFlow.cellKey(account: "a1", category: nil)), 18, accuracy: 0.001)
    }

    /// Going back to page 1 and adding a card must not disturb what was typed.
    /// The new cells float, so they take the remainder rather than fighting the
    /// figures the user set.
    func test_addingACardLeavesTypedCellsAlone() {
        var g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 100)
        g.setAmount("a1|c1", 50)          // the user corrects one cell
        g.setAmount("a1|c2", 10)

        let three = cards + [(id: "a3", amount: 0)]
        let back = PurchaseFlow.reseedGrid(g, accounts: three, categories: cats, total: 100)

        XCTAssertEqual(amount(back, "a1|c1"), 50, accuracy: 0.001, "what the user typed still stands")
        XCTAssertEqual(amount(back, "a1|c2"), 10, accuracy: 0.001)
        XCTAssertEqual(back.rows.count, 6, "the new card brought two cells")
        XCTAssertEqual(back.allocated, 100, accuracy: 0.001, "and they absorbed the rest")
    }

    /// Removing a category on page 1 takes its cells with it.
    func test_removingACategoryDropsItsCells() {
        let g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 100)
        let back = PurchaseFlow.reseedGrid(g, accounts: cards,
                                           categories: [(id: "c1", amount: 100)], total: 100)
        XCTAssertEqual(back.rows.count, 2)
        XCTAssertFalse(back.isTicked("a1|c2"))
    }

    /// An empty grid seeds from the margins rather than merging with nothing.
    func test_reseedingAnEmptyGridIsJustSeeding() {
        let back = PurchaseFlow.reseedGrid(SplitAllocation(total: 0),
                                           accounts: cards, categories: cats, total: 100)
        XCTAssertEqual(amount(back, "a1|c1"), 42, accuracy: 0.001)
        XCTAssertTrue(PurchaseFlow.isBalanced(back))
    }

    /// No amount yet means nothing to divide — seeding must not divide by zero.
    func test_seedingWithNoTotalProducesEmptyCells() {
        let g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 0)
        XCTAssertTrue(g.rows.isEmpty)
    }
}
