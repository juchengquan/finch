import XCTest
@testable import FinchCore

final class TagCategoryCountsTests: XCTestCase {
    private func tx(_ id: String, category: String? = nil, tags: [String]? = nil,
                    splits: [TxSplit]? = nil, pending: Bool = false, ledger: String = "l1") -> Tx {
        Tx(id: id, merchant: "m", category: category, amount: -5, account: "a1", date: "2026-05-01",
           pending: pending, ledgerId: ledger, splits: splits, tags: tags)
    }
    private func split(_ categoryId: String?, _ amount: Double = -5) -> TxSplit {
        TxSplit(id: nil, categoryId: categoryId, amount: amount, amountBase: amount, description: nil)
    }

    // MARK: tagTxCounts

    func test_tag_counts_by_id() {
        let r = Selectors.tagTxCounts([tx("t1", tags: ["tagA"]), tx("t2", tags: ["tagA"])], "l1")
        XCTAssertEqual(r, ["tagA": 2])
    }

    func test_tag_multi_tag_txn_increments_each() {
        let r = Selectors.tagTxCounts([tx("t1", tags: ["tagA", "tagB"])], "l1")
        XCTAssertEqual(r, ["tagA": 1, "tagB": 1])
    }

    func test_tag_excludes_pending_and_other_ledger() {
        let r = Selectors.tagTxCounts(
            [tx("t1", tags: ["tagA"]), tx("t2", tags: ["tagA"], pending: true), tx("t3", tags: ["tagA"], ledger: "l2")], "l1")
        XCTAssertEqual(r, ["tagA": 1])
    }

    func test_tag_untagged_absent() {
        XCTAssertTrue(Selectors.tagTxCounts([tx("t1")], "l1").isEmpty)
    }

    // MARK: categoryTxCounts

    func test_category_direct_count() {
        let r = Selectors.categoryTxCounts([tx("t1", category: "cFood"), tx("t2", category: "cFood")], "l1")
        XCTAssertEqual(r, ["cFood": 2])
    }

    func test_category_split_legs_counted() {
        // a 2-leg txn across two categories increments both
        let r = Selectors.categoryTxCounts([tx("t1", splits: [split("cFood"), split("cFun")])], "l1")
        XCTAssertEqual(r, ["cFood": 1, "cFun": 1])
    }

    func test_category_splits_override_tx_category() {
        // when splits present, tx.category is NOT counted
        let r = Selectors.categoryTxCounts([tx("t1", category: "cIgnored", splits: [split("cFood")])], "l1")
        XCTAssertEqual(r, ["cFood": 1])
    }

    func test_category_same_category_twice_counts_once() {
        let r = Selectors.categoryTxCounts([tx("t1", splits: [split("cFood"), split("cFood")])], "l1")
        XCTAssertEqual(r, ["cFood": 1])
    }

    func test_category_excludes_pending_and_other_ledger() {
        let r = Selectors.categoryTxCounts(
            [tx("t1", category: "cFood"), tx("t2", category: "cFood", pending: true), tx("t3", category: "cFood", ledger: "l2")], "l1")
        XCTAssertEqual(r, ["cFood": 1])
    }

    func test_category_no_descendant_rollup() {
        // a child txn does NOT roll up to the parent id; only the child id is counted
        let r = Selectors.categoryTxCounts([tx("t1", category: "cChild")], "l1")
        XCTAssertEqual(r, ["cChild": 1])
        XCTAssertNil(r["cParent"])
    }
}
