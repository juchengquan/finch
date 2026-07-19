import XCTest
@testable import FinchCore

final class CategoryTransactionsTests: XCTestCase {
    private func tx(_ id: String, category: String? = nil, date: String = "2026-05-01",
                    splits: [TxSplit]? = nil, pending: Bool = false, ledger: String = "l1") -> Tx {
        Tx(id: id, merchant: "m", category: category, amount: -5, account: "a1", date: date,
           pending: pending, ledgerId: ledger, splits: splits)
    }
    private func split(_ categoryId: String?, _ amount: Double = -5) -> TxSplit {
        TxSplit(id: nil, categoryId: categoryId, amount: amount, amountBase: amount, description: nil)
    }

    func test_matches_direct_category_newest_first() {
        let out = Selectors.categoryTransactions(
            [tx("a", category: "cFood", date: "2026-06-01"),
             tx("b", category: "cFood", date: "2026-06-03"),
             tx("c", category: "cOther", date: "2026-06-02")], "cFood", "l1")
        XCTAssertEqual(out.map(\.id), ["b", "a"])   // date-desc; cOther excluded
    }

    func test_matches_split_leg_category() {
        let out = Selectors.categoryTransactions(
            [tx("t1", splits: [split("cFood"), split("cFun")])], "cFood", "l1")
        XCTAssertEqual(out.map(\.id), ["t1"])
    }

    func test_splits_override_tx_category() {
        // when splits are present, tx.category is NOT matched (parity with categoryTxCounts)
        let out = Selectors.categoryTransactions(
            [tx("t1", category: "cFood", splits: [split("cFun")])], "cFood", "l1")
        XCTAssertTrue(out.isEmpty)
    }

    func test_excludes_pending_and_other_ledger() {
        let out = Selectors.categoryTransactions(
            [tx("t1", category: "cFood"),
             tx("t2", category: "cFood", pending: true),
             tx("t3", category: "cFood", ledger: "l2")], "cFood", "l1")
        XCTAssertEqual(out.map(\.id), ["t1"])
    }
}
