import XCTest
@testable import FinchCore

/// What a category screen reports as spent on that category.
///
/// The screen's own doc says it answers "what did I spend on this". It builds
/// its list — and its count, total and average — from
/// `byPurchase(categoryTransactions(...))`, and sums each row's `amount`.
///
/// `amount` is the whole purchase. That is right for the merchant screen, which
/// asks what the shop cost. It is wrong here as soon as a purchase touches more
/// than one category, because the same money is then reported under each of
/// them.
final class CategoryShareTests: XCTestCase {

    private func tx(_ id: String, entry: String?, group: String? = nil,
                    amount: Double, splits: [TxSplit]?) -> Tx {
        Tx(id: id, merchant: "Market", amount: amount, account: "a1",
           date: "2026-06-01", ledgerId: "l1",
           entryId: entry, groupId: group, splits: splits)
    }

    /// One card, two categories — the shape that has shipped for a long time.
    /// Establishes whether the over-count is new with the grid or predates it.
    func test_anOrdinaryCategorySplit_reportsOnlyThatCategorysShare() {
        let t = tx("p1", entry: "e1", amount: -100, splits: [
            TxSplit(categoryId: "c1", amount: -70, amountBase: -70),
            TxSplit(categoryId: "c2", amount: -30, amountBase: -30),
        ])
        let groceries = Selectors.categoryPurchases([t], "c1", "l1")
        XCTAssertEqual(groceries.reduce(0) { $0 + $1.amount }, -70, accuracy: 0.001,
                       "70 of the 100 went on groceries")

        let household = Selectors.categoryPurchases([t], "c2", "l1")
        XCTAssertEqual(household.reduce(0) { $0 + $1.amount }, -30, accuracy: 0.001)
    }

    /// A 2x2 grid: two cards, two categories, one purchase. Each card is its own
    /// entry; the group is the purchase. Both entries carry BOTH categories, so
    /// both rows match either category screen and collapse into one — carrying
    /// the whole group's total.
    func test_aGridGroup_reportsOnlyThatCategorysShare() {
        let cardA = tx("p1", entry: "e1", group: "g1", amount: -60, splits: [
            TxSplit(categoryId: "c1", amount: -40, amountBase: -40),
            TxSplit(categoryId: "c2", amount: -20, amountBase: -20),
        ])
        let cardB = tx("p2", entry: "e2", group: "g1", amount: -40, splits: [
            TxSplit(categoryId: "c1", amount: -30, amountBase: -30),
            TxSplit(categoryId: "c2", amount: -10, amountBase: -10),
        ])
        let rows = [cardA, cardB]

        let groceries = Selectors.categoryPurchases(rows, "c1", "l1")
        XCTAssertEqual(groceries.count, 1, "one purchase, however many cards paid")
        XCTAssertEqual(groceries.reduce(0) { $0 + $1.amount }, -70, accuracy: 0.001,
                       "40 + 30 went on groceries — not the whole 100")

        let household = Selectors.categoryPurchases(rows, "c2", "l1")
        XCTAssertEqual(household.reduce(0) { $0 + $1.amount }, -30, accuracy: 0.001,
                       "20 + 10 — and the two screens must not add up to more than was spent")
    }
}
