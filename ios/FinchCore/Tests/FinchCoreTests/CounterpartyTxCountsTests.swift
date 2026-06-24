import XCTest
@testable import FinchCore

final class CounterpartyTxCountsTests: XCTestCase {
    private func cp(_ id: String, _ name: String) -> Counterparty {
        Counterparty(id: id, ledgerId: "l1", name: name)
    }
    private func tx(_ id: String, merchant: String = "", cp: String? = nil,
                    pending: Bool = false, ledger: String = "l1") -> Tx {
        Tx(id: id, merchant: merchant, amount: -5, account: "a1", date: "2026-05-01",
           pending: pending, ledgerId: ledger, counterpartyId: cp)
    }

    func test_counts_by_counterpartyId() {
        let r = Selectors.counterpartyTxCounts([tx("t1", cp: "cp1"), tx("t2", cp: "cp1")], [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 2])
    }

    func test_name_fallback_is_case_and_whitespace_insensitive() {
        let r = Selectors.counterpartyTxCounts(
            [tx("t1", merchant: "starbucks"), tx("t2", merchant: "  STARBUCKS ")],
            [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 2])
    }

    func test_unknown_counterpartyId_falls_back_to_name() {
        // counterpartyId points at an unknown id, but the merchant name matches
        let r = Selectors.counterpartyTxCounts([tx("t1", merchant: "Starbucks", cp: "ghost")], [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 1])
    }

    func test_excludes_pending() {
        let r = Selectors.counterpartyTxCounts([tx("t1", cp: "cp1"), tx("t2", cp: "cp1", pending: true)], [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 1])
    }

    func test_excludes_other_ledger() {
        let r = Selectors.counterpartyTxCounts([tx("t1", cp: "cp1"), tx("t2", cp: "cp1", ledger: "l2")], [cp("cp1", "Starbucks")], "l1")
        XCTAssertEqual(r, ["cp1": 1])
    }

    func test_unused_merchant_is_absent() {
        let r = Selectors.counterpartyTxCounts([tx("t1", cp: "cp1")], [cp("cp1", "Starbucks"), cp("cp2", "Shell")], "l1")
        XCTAssertEqual(r["cp1"], 1)
        XCTAssertNil(r["cp2"])
    }

    func test_unmatched_txn_is_uncounted() {
        // merchant name matches nothing, no counterpartyId → not counted
        let r = Selectors.counterpartyTxCounts([tx("t1", merchant: "Nowhere")], [cp("cp1", "Starbucks")], "l1")
        XCTAssertTrue(r.isEmpty)
    }
}
