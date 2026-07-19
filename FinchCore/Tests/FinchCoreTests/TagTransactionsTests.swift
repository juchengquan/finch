import XCTest
@testable import FinchCore

final class TagTransactionsTests: XCTestCase {
    private func tx(_ id: String, tags: [String]? = nil, date: String = "2026-05-01",
                    pending: Bool = false, ledger: String = "l1") -> Tx {
        Tx(id: id, merchant: "m", amount: -5, account: "a1", date: date,
           pending: pending, ledgerId: ledger, tags: tags)
    }

    func test_matches_tagged_newest_first() {
        let out = Selectors.tagTransactions(
            [tx("a", tags: ["tagA"], date: "2026-06-01"),
             tx("b", tags: ["tagA"], date: "2026-06-03"),
             tx("c", tags: ["tagB"], date: "2026-06-02")], "tagA", "l1")
        XCTAssertEqual(out.map(\.id), ["b", "a"])   // date-desc; tagB excluded
    }

    func test_multi_tag_txn_matched() {
        let out = Selectors.tagTransactions([tx("t1", tags: ["tagA", "tagB"])], "tagB", "l1")
        XCTAssertEqual(out.map(\.id), ["t1"])
    }

    func test_excludes_pending_and_other_ledger() {
        let out = Selectors.tagTransactions(
            [tx("t1", tags: ["tagA"]),
             tx("t2", tags: ["tagA"], pending: true),
             tx("t3", tags: ["tagA"], ledger: "l2")], "tagA", "l1")
        XCTAssertEqual(out.map(\.id), ["t1"])
    }

    func test_untagged_absent() {
        XCTAssertTrue(Selectors.tagTransactions([tx("t1")], "tagA", "l1").isEmpty)
    }

    func test_agrees_with_tagTxCounts() {
        let txns = [tx("t1", tags: ["tagA"]), tx("t2", tags: ["tagA", "tagB"]),
                    tx("t3", tags: ["tagA"], pending: true), tx("t4", tags: ["tagB"], ledger: "l2")]
        let counts = Selectors.tagTxCounts(txns, "l1")
        XCTAssertEqual(Selectors.tagTransactions(txns, "tagA", "l1").count, counts["tagA"] ?? 0)
        XCTAssertEqual(Selectors.tagTransactions(txns, "tagB", "l1").count, counts["tagB"] ?? 0)
    }
}
