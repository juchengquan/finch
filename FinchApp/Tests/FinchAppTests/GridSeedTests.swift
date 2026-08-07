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

    /// The bug a user hit: two accounts and two categories, and page 2 showed
    /// nothing to fill in.
    ///
    /// The margins straight off page 1 carry NO amounts — the pickers select and
    /// nothing more — so seeding from `share × share ÷ total` gave every cell 0,
    /// and seeding from `payload` (funded rows) gave no cells at all.
    func test_aSelectionWithNoAmountsStillFillsTheGrid() {
        let cards: [(id: String?, amount: Double)] = [(id: "a1", amount: 0), (id: "a2", amount: 0)]
        let cats: [(id: String?, amount: Double)] = [(id: "c1", amount: 0), (id: "c2", amount: 0)]

        let g = PurchaseFlow.seedGrid(accounts: cards, categories: cats, total: 100)
        XCTAssertEqual(g.rows.count, 4, "two cards by two categories is four cells")
        XCTAssertEqual(g.allocated, 100, accuracy: 0.001, "divided evenly, and exactly")
        XCTAssertTrue(PurchaseFlow.isBalanced(g))
        for key in ["a1|c1", "a1|c2", "a2|c1", "a2|c2"] {
            XCTAssertEqual(amount(g, key), 25, accuracy: 0.001, "\(key) got no share")
        }
    }

    /// And the same through `reseedGrid`, which is what the sheet actually calls.
    func test_reseedingAnAmountlessSelectionFillsTheGrid() {
        let cards: [(id: String?, amount: Double)] = [(id: "a1", amount: 0), (id: "a2", amount: 0)]
        let cats: [(id: String?, amount: Double)] = [(id: "c1", amount: 0), (id: "c2", amount: 0)]

        let g = PurchaseFlow.reseedGrid(SplitAllocation(total: 0),
                                        accounts: cards, categories: cats, total: 100)
        XCTAssertEqual(g.rows.count, 4)
        XCTAssertEqual(g.allocated, 100, accuracy: 0.001)
    }

    /// `selection` is every ticked row; `payload` is only the funded ones. Feeding
    /// the shape decision from `payload` is what emptied the grid.
    func test_selectionCarriesTickedRowsThatPayloadDrops() {
        var a = SplitAllocation(total: 0)
        a.tick("a1"); a.tick("a2")
        XCTAssertTrue(a.payload.isEmpty, "nothing is funded")
        XCTAssertEqual(a.selection.count, 2, "but two things are selected")
    }

    // MARK: reopening a saved group

    private func gridRow(_ id: String, account: String, group: String,
                         cells: [(String?, Double)],
                         origCurrency: String? = nil) -> Tx {
        let total = cells.reduce(0) { $0 + $1.1 }
        return Tx(id: id, merchant: "Market", amount: -total, account: account,
                  date: "2026-06-01", ledgerId: "l1",
                  currency: origCurrency, nativeAmount: origCurrency == nil ? nil : -total,
                  entryId: "e-\(id)", groupId: group,
                  splits: cells.count < 2 ? nil : cells.map {
                      TxSplit(categoryId: $0.0, amount: -$0.1, amountBase: -$0.1,
                              origAmount: origCurrency == nil ? nil : -$0.1,
                              origCurrency: origCurrency)
                  })
    }

    /// The whole purchase comes back, not the row that was tapped.
    func test_aSavedGridReopensAsItsCells() {
        let rows = [
            gridRow("p1", account: "a1", group: "g1", cells: [("c1", 40), ("c2", 20)]),
            gridRow("p2", account: "a2", group: "g1", cells: [("c1", 30), ("c2", 10)]),
        ]
        let seed = PurchaseFlow.seedGrid(from: rows)
        XCTAssertEqual(seed.accountIds, ["a1", "a2"])
        XCTAssertEqual(seed.categoryIds.map { $0 ?? "" }, ["c1", "c2"])
        XCTAssertEqual(amount(seed.alloc, "a1|c1"), 40, accuracy: 0.001)
        XCTAssertEqual(amount(seed.alloc, "a2|c2"), 10, accuracy: 0.001)
        XCTAssertEqual(seed.alloc.total, 100, accuracy: 0.001, "the purchase, not the tapped card")
        XCTAssertTrue(PurchaseFlow.isBalanced(seed.alloc))
    }

    /// A foreign purchase reopens showing the figures the user TYPED. Falling
    /// back to the base amounts would show back-converted ones, which drift by a
    /// cent on awkward rates — and saving would bake the drift in as the truth.
    func test_aForeignGridReopensInThePurchaseCurrency() {
        let rows = [
            gridRow("p1", account: "a1", group: "g1", cells: [("c1", 40), ("c2", 20)], origCurrency: "EUR"),
            gridRow("p2", account: "a2", group: "g1", cells: [("c1", 30), ("c2", 10)], origCurrency: "EUR"),
        ]
        let seed = PurchaseFlow.seedGrid(from: rows)
        XCTAssertEqual(seed.currency, "EUR")
        XCTAssertEqual(amount(seed.alloc, "a1|c1"), 40, accuracy: 0.001, "€40 as typed")
    }

    /// A card that bought exactly one category has no `splits` array — the
    /// projection puts the category on the row itself. It is still a cell.
    func test_aCardWithOneCategoryStillContributesItsCell() {
        var single = gridRow("p2", account: "a2", group: "g1", cells: [("c1", 40)])
        single.category = "c1"
        let rows = [gridRow("p1", account: "a1", group: "g1", cells: [("c1", 40), ("c2", 20)]), single]
        let seed = PurchaseFlow.seedGrid(from: rows)
        XCTAssertEqual(amount(seed.alloc, "a2|c1"), 40, accuracy: 0.001)
        XCTAssertNil(seed.alloc.rows.first { $0.id == "a2|c2" }, "it bought nothing there")
        XCTAssertEqual(seed.alloc.total, 100, accuracy: 0.001)
    }

    /// Reopening must not renumber anything: seeded rows arrive pinned, so
    /// merely opening the sheet cannot re-divide the purchase.
    func test_reopeningDoesNotRedivideThePurchase() {
        let rows = [
            gridRow("p1", account: "a1", group: "g1", cells: [("c1", 99), ("c2", 1)]),
            gridRow("p2", account: "a2", group: "g1", cells: [("c1", 50), ("c2", 50)]),
        ]
        let seed = PurchaseFlow.seedGrid(from: rows)
        XCTAssertEqual(amount(seed.alloc, "a1|c2"), 1, accuracy: 0.001, "a lopsided cell stays lopsided")
        XCTAssertTrue(seed.alloc.rows.allSatisfy(\.pinned))
    }
}
