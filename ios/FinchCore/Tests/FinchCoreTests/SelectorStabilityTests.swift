import XCTest
@testable import FinchCore

/// The list selectors must be STABLE for equal sort keys — Swift's `sort` isn't
/// stable by default, so equal-(date,time) rows could reorder run-to-run and
/// diverge from the web's stable Array.sort. (Selector parity fixtures only use
/// distinct keys, so this guards the tie path directly.)
final class SelectorStabilityTests: XCTestCase {
    func test_selectTransactions_preservesInputOrderForEqualDateTime() {
        let mk: (String) -> Tx = { id in
            Tx(id: id, merchant: id, amount: -1, account: "a1", date: "2026-05-01",
               pending: false, ledgerId: "l1", time: "10:00")
        }
        let input = ["t1", "t2", "t3", "t4", "t5"].map(mk)
        let out = Selectors.selectTransactions(input, ListOptions(ledgerId: "l1"))
        XCTAssertEqual(out.map(\.id), ["t1", "t2", "t3", "t4", "t5"])
    }

    func test_selectTransactions_dateThenTimeDescStillHolds() {
        let txs = [
            Tx(id: "older", merchant: "x", amount: -1, account: "a1", date: "2026-05-01", pending: false, ledgerId: "l1", time: "09:00"),
            Tx(id: "newest", merchant: "x", amount: -1, account: "a1", date: "2026-05-02", pending: false, ledgerId: "l1", time: "08:00"),
            Tx(id: "mid", merchant: "x", amount: -1, account: "a1", date: "2026-05-01", pending: false, ledgerId: "l1", time: "11:00"),
        ]
        let out = Selectors.selectTransactions(txs, ListOptions(ledgerId: "l1"))
        XCTAssertEqual(out.map(\.id), ["newest", "mid", "older"])  // date DESC, then time DESC
    }
}
